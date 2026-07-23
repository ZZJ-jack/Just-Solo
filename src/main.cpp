#include <QApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStringList>
#include <QTimer>
#include <QStandardPaths>
#include <QSystemTrayIcon>
#include <QMenu>
#include <QLocalServer>
#include <QLocalSocket>
#include <QThread>

#ifdef Q_OS_WIN
#include <windows.h>
#include <dwmapi.h>

// SetCurrentProcessExplicitAppUserModelID 在新 SDK 中声明位置不稳定，手动声明
extern "C" HRESULT WINAPI SetCurrentProcessExplicitAppUserModelID(PCWSTR AppID);
#include <io.h>
#include <fcntl.h>

// DWM 属性常量（旧 SDK 可能未定义）
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_TEXT_COLOR
#define DWMWA_TEXT_COLOR 36
#endif

// AllowSetForegroundWindow 的 -1 常量（允许任意进程获取前台窗口权限）
#ifndef ASFW_ANY
#define ASFW_ANY ((DWORD)-1)
#endif

// 检测是否为 Windows 11 (Build >= 22000)
static bool isWindows11() {
    // RtlGetVersion 获取真实版本号（不受应用程序兼容性清单影响）
    typedef LONG (WINAPI *RtlGetVersionPtr)(PRTL_OSVERSIONINFOW);
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    if (!ntdll) return false;
    auto RtlGetVersion = (RtlGetVersionPtr)GetProcAddress(ntdll, "RtlGetVersion");
    if (!RtlGetVersion) return false;

    RTL_OSVERSIONINFOW vi = { sizeof(vi) };
    if (RtlGetVersion(&vi) != 0) return false;
    return vi.dwMajorVersion == 10 && vi.dwBuildNumber >= 22000;
}

// 获取系统版本描述字符串（"Windows 11" 或 "Windows 10"）
static QString osVersionString() {
    return isWindows11() ? QStringLiteral("Windows 11") : QStringLiteral("Windows 10");
}

// 深度自定义原生标题栏 — 强制暗黑模式，Win11 追加三色定制
static void customizeTitleBar(HWND hwnd) {
    BOOL darkMode = TRUE;
    // Win10 1809-2004 (属性 19) + Win10 2004+/Win11 (属性 20) 双保险
    DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &darkMode, sizeof(darkMode));
    DwmSetWindowAttribute(hwnd, 19, &darkMode, sizeof(darkMode));  // 旧版常量

    // Win11+: 标题栏背景 #1e1e2e，文字 #cccccc，边框同背景（视觉无边框）
    // COLORREF = 0x00BBGGRR → RGB(0x1e, 0x1e, 0x2e) = 0x002e1e1e
    if (isWindows11()) {
        COLORREF caption = RGB(30, 30, 46);   // #1e1e2e
        COLORREF text    = RGB(204, 204, 204); // #cccccc
        COLORREF border  = caption;            // 与背景同色
        DwmSetWindowAttribute(hwnd, DWMWA_CAPTION_COLOR, &caption, sizeof(caption));
        DwmSetWindowAttribute(hwnd, DWMWA_TEXT_COLOR,    &text,    sizeof(text));
        DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR,  &border,  sizeof(border));
    }
}
#endif

#include "version.h"
#include "core/MusicManager.h"
#include "core/SMTCManager.h"
#include "core/HotkeyManager.h"
#include "services/LyricServer.h"

// ============================================================
// 系统托盘：关闭窗口后最小化到任务栏
// ============================================================
static void setupSystemTray(QQuickWindow *window, MusicManager *mgr) {
    QSystemTrayIcon *tray = new QSystemTrayIcon(window);
    tray->setIcon(QIcon(":/qt/qml/JustSolo/data/image/logo.png"));
    tray->setToolTip("Just Solo");

    QMenu *menu = new QMenu();

    QAction *showAction = menu->addAction("显示主窗口");
    QAction *quitAction = menu->addAction("退出");

    tray->setContextMenu(menu);

    // 显示/恢复窗口
    QObject::connect(showAction, &QAction::triggered, [window]() {
        window->show();
        window->raise();
        window->requestActivate();
    });

    // 左键/双击托盘图标也恢复窗口
    QObject::connect(tray, &QSystemTrayIcon::activated, [window](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::DoubleClick || reason == QSystemTrayIcon::Trigger) {
            window->show();
            window->raise();
            window->requestActivate();
        }
    });

    // 真正退出：清理播放状态后退出进程
    QObject::connect(quitAction, &QAction::triggered, [window, mgr]() {
        window->hide();
        mgr->stop();
        mgr->shutdown();
        QApplication::quit();
    });

    tray->show();
}

// ============================================================
// 单实例：已运行实例被再次启动时，激活其主窗口到前台
// ============================================================
static void activateMainWindow(QQuickWindow *window) {
    if (!window) return;

#ifdef Q_OS_WIN
    HWND hwnd = HWND(window->winId());
    // 恢复最小化窗口（SW_RESTORE 保留原尺寸，不强制最大化）
    if (::IsIconic(hwnd)) {
        ::ShowWindow(hwnd, SW_RESTORE);
    }
#endif
    // 从托盘隐藏状态恢复出来
    if (!window->isVisible()) {
        window->show();
    }
    // 清除最小化标志（跨平台保险）
    if (window->windowState() & Qt::WindowMinimized) {
        window->setWindowState(static_cast<Qt::WindowState>(window->windowState() & ~Qt::WindowMinimized));
    }
    window->raise();
    window->requestActivate();

#ifdef Q_OS_WIN
    // 加强前台激活（托盘唤醒场景下 requestActivate 偶尔无效）
    if (hwnd) {
        ::SetForegroundWindow(hwnd);
    }
#endif
}

// 单实例通信管道名（带版本号，升级后可强制走新通道）
static const QString kSingleInstanceName = QStringLiteral("JustSolo.SingleInstance.v1");

// 尝试连接已运行的实例并请求激活；成功返回 true（本进程应退出）
static bool tryActivateRunningInstance() {
    // 重试一次，防时序竞争（窗口隐藏后 server 可能短暂不可达）
    for (int attempt = 0; attempt < 2; ++attempt) {
        if (attempt > 0) QThread::msleep(200);

        QLocalSocket socket;
        socket.connectToServer(kSingleInstanceName);
        if (!socket.waitForConnected(300)) continue;

#ifdef Q_OS_WIN
        // 把本次启动获得的前台权限让渡给已运行实例，避免 SetForegroundWindow 被拒
        ::AllowSetForegroundWindow(ASFW_ANY);
#endif
        socket.write("activate\n");
        socket.flush();
        socket.waitForBytesWritten(300);
        socket.disconnectFromServer();
        if (socket.state() != QLocalSocket::UnconnectedState) {
            socket.waitForDisconnected(300);
        }
        return true;
    }
    return false;  // 两次都失败，确认没有实例在监听
}

// 本进程成为单实例：创建监听服务器，收到连接时激活主窗口
static void startSingleInstanceServer(QQuickWindow *window) {
    // 清理上次崩溃残留的 socket 文件
    QLocalServer::removeServer(kSingleInstanceName);
    QLocalServer *server = new QLocalServer(qApp);
    server->setSocketOptions(QLocalServer::UserAccessOption);
    if (!server->listen(kSingleInstanceName)) {
        // 监听失败通常意味着已有实例刚启动成功，为防双开直接退出
        qWarning("Single-instance: listen failed, another instance may be running.");
        QMetaObject::invokeMethod(qApp, "quit", Qt::QueuedConnection);
        return;
    }
    QObject::connect(server, &QLocalServer::newConnection, [window, server]() {
        // 取出并丢弃客户端数据，避免连接堆积
        if (QLocalSocket *client = server->nextPendingConnection()) {
            client->readAll();
            client->deleteLater();
        }
        activateMainWindow(window);
    });
}

// APP_VERSION_DISPLAY 由 CMake target_compile_definitions 传入
// BUILD_VERSION 由 cmake/GenerateVersion.ps1 生成（格式: ts-machineId-vX.Y.Z）

int main(int argc, char *argv[])
{
    // 解析命令行参数（跨平台，不依赖 QApplication）
    QStringList args;
    for (int i = 0; i < argc; i++)
        args << QString::fromLocal8Bit(argv[i]);

#ifdef Q_OS_WIN
    // --develop 参数：分配控制台用于调试日志
    if (args.contains("--develop")) {
        if (AttachConsole(ATTACH_PARENT_PROCESS) || AllocConsole()) {
            // 设置控制台为 UTF-8，避免 qDebug 中文乱码
            SetConsoleOutputCP(CP_UTF8);
            SetConsoleCP(CP_UTF8);
            FILE *dummy;
            freopen_s(&dummy, "CONOUT$", "w", stdout);
            freopen_s(&dummy, "CONOUT$", "w", stderr);
            printf("\nJust Solo --develop mode\n");
            printf("Build: %ls\n", BUILD_VERSION);
            fflush(stdout);
        }
    }
#endif

#ifdef Q_OS_WIN
    // SetCurrentProcessExplicitAppUserModelID 必须在创建任何窗口/UI 之前调用
    // 否则 SMTC 无法正确解析 DisplayName，始终显示"未知应用"
    SetCurrentProcessExplicitAppUserModelID(L"JustSolo.JustSolo");
    // 使用 Windows Media Foundation 后端，避免 FFmpeg 24-bit 重采样无声问题
    qputenv("QT_MEDIA_BACKEND", "windows");
#endif

    QApplication app(argc, argv);
    app.setApplicationName("Just Solo");
    app.setApplicationDisplayName("Just Solo");

    // 设置应用程序图标（任务管理器、窗口图标）
    app.setWindowIcon(QIcon(":/qt/qml/JustSolo/data/image/logo.png"));

    // ---- 单实例检测 ----
    // 若已有实例在运行，通知其激活窗口后本进程立即退出
    if (tryActivateRunningInstance()) {
        return 0;
    }

    QQmlApplicationEngine engine;
    QQuickStyle::setStyle("Basic");

    // 暴露编译版本号到 QML
    engine.rootContext()->setContextProperty("BUILD_VERSION", QString::fromWCharArray(BUILD_VERSION));
    engine.rootContext()->setContextProperty("APP_VERSION", QString(APP_VERSION_DISPLAY));
    engine.rootContext()->setContextProperty("DEVELOPER_MODE", args.contains("--develop"));
#ifdef Q_OS_WIN
    engine.rootContext()->setContextProperty("OS_VERSION", osVersionString());
#endif

    // 注册音乐管理器（始终启用本地缓存；--develop 仅开控制台日志，不再清空数据）
    MusicManager *musicManager = new MusicManager(&app);
    musicManager->setUseCache(true);

    // --clearUserData：显式清空用户配置和缓存数据（独立于 --develop）
    if (args.contains("--clearUserData"))
        musicManager->clearUserData();

    engine.rootContext()->setContextProperty("musicManager", musicManager);

    // 实时歌词推送服务（WebSocket ws://127.0.0.1:47290）
    LyricServer *lyricServer = new LyricServer(musicManager, &app);
    lyricServer->start(47290);

    // 全局快捷键
    QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    HotkeyManager *hotkeyManager = new HotkeyManager(cacheDir, &app);
    QObject::connect(hotkeyManager, &HotkeyManager::playPauseTriggered, musicManager, [musicManager]() {
        if (musicManager->currentIndex() < 0) return;
        if (musicManager->isPlaying()) musicManager->pause();
        else musicManager->play();
    });
    QObject::connect(hotkeyManager, &HotkeyManager::nextTriggered, musicManager, &MusicManager::next);
    QObject::connect(hotkeyManager, &HotkeyManager::previousTriggered, musicManager, &MusicManager::previous);
    engine.rootContext()->setContextProperty("hotkeyManager", hotkeyManager);

    // 从 QML 模块加载主界面
    const QUrl url(QStringLiteral("qrc:/qt/qml/JustSolo/src/qml/main.qml"));
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection
    );

    // 关闭窗口时退出进程 — 备注：关闭事件已被 QML onClosing 拦截（隐藏到托盘），
    // 此连接仅在系统托盘「退出」菜单或 Qt.quit() 调用时生效
    QObject::connect(&engine, &QQmlApplicationEngine::quit, &app, &QApplication::quit);

    engine.load(url);

#ifdef Q_OS_WIN
    // 系统原生标题栏深度自定义 + SMTC 初始化 — 延迟确保窗口句柄就绪
    if (!engine.rootObjects().isEmpty()) {
        QQuickWindow *win = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
        if (win) {
            // 系统托盘（跨平台，在引擎加载后立即设置）
            setupSystemTray(win, musicManager);

            // 单实例监听：后续启动会通过此通道请求激活窗口
            startSingleInstanceServer(win);

            QTimer::singleShot(200, win, [win, musicManager]() {
                HWND hwnd = HWND(win->winId());
                customizeTitleBar(hwnd);

                // 初始化 Windows 系统媒体控件 (SMTC)
                new SMTCManager(musicManager, hwnd, musicManager);
            });
        }
    }
#else
    // 非 Windows 平台：仅设置系统托盘
    if (!engine.rootObjects().isEmpty()) {
        QQuickWindow *win = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
        if (win) {
            setupSystemTray(win, musicManager);
            startSingleInstanceServer(win);
        }
    }
#endif

    return app.exec();
}
