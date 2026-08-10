#include <QApplication>
#include <QIcon>
#include <QMetaObject>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStringList>
#include <QTimer>
#include <QStandardPaths>
#include <QResource>
#include <QSystemTrayIcon>
#include <QMenu>
#include <QLocalServer>
#include <QLocalSocket>
#include <QThread>
#include <QColor>
#include <QEasingCurve>
#include <QVariantAnimation>

#include "core/MusicManager.h"  // 提前包含：Q_OS_WIN 块内的 updateImmersiveTitleBar 需要完整类型

#ifdef Q_OS_WIN
#include <windows.h>
#include <dwmapi.h>
#include <dxgi.h>

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

// 解析 "#RRGGBB" → COLORREF，失败返回 false
static bool parseHexColor(const QString &hex, COLORREF *out) {
    if (hex.length() != 7 || !hex.startsWith(QLatin1Char('#'))) return false;
    bool okR = false, okG = false, okB = false;
    int r = hex.mid(1, 2).toInt(&okR, 16);
    int g = hex.mid(3, 2).toInt(&okG, 16);
    int b = hex.mid(5, 2).toInt(&okB, 16);
    if (!okR || !okG || !okB) return false;
    *out = RGB(r, g, b);
    return true;
}

// Win11 追加三色定制：一次性设置标题栏背景/文字/边框颜色
static void applyTitleBarColors(HWND hwnd, int r, int g, int b) {
    if (!isWindows11()) return;
    COLORREF caption = RGB(r, g, b);
    COLORREF text    = RGB(204, 204, 204);
    COLORREF border  = caption;            // 与背景同色（视觉无边框）
    DwmSetWindowAttribute(hwnd, DWMWA_CAPTION_COLOR, &caption, sizeof(caption));
    DwmSetWindowAttribute(hwnd, DWMWA_TEXT_COLOR,    &text,    sizeof(text));
    DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR,  &border,  sizeof(border));
}

// 深度自定义原生标题栏 — 强制暗黑模式，Win11 追加三色定制
// captionHex 为空时使用默认深色 RGB(30,30,30)
static void customizeTitleBar(HWND hwnd, const QString &captionHex = QString()) {
    BOOL darkMode = TRUE;
    // Win10 1809-2004 (属性 19) + Win10 2004+/Win11 (属性 20) 双保险
    DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &darkMode, sizeof(darkMode));
    DwmSetWindowAttribute(hwnd, 19, &darkMode, sizeof(darkMode));  // 旧版常量

    if (isWindows11()) {
        COLORREF parsed = 0;
        if (!captionHex.isEmpty() && parseHexColor(captionHex, &parsed))
            applyTitleBarColors(hwnd, GetRValue(parsed), GetGValue(parsed), GetBValue(parsed));
        else
            applyTitleBarColors(hwnd, 30, 30, 30);
    }
}

// ============================================================
// 标题栏颜色平滑过渡
// DWM 原生切换标题栏颜色是瞬时的，这里用 QVariantAnimation 逐帧插值，
// 让沉浸背景进入/退出/切歌时标题栏颜色平滑渐变。
// ★ 调整下面 kTitleBarColorAnimMs 即可控制变色快慢（毫秒）：
//   越大越慢（如 800），越小越快（如 150），设为 0 则瞬时变色。
// ============================================================
const int kTitleBarColorAnimMs = 350;  // 同步 PlayerDetailPage.qml openAnim 时长

static HWND   g_titleBarHwnd  = nullptr;        // 标题栏所属窗口句柄
static QColor g_titleBarColor(30, 30, 30);      // 当前已应用的颜色（作为下一轮动画起点）
static bool   g_prevDetailVisible = false;      // 上一次详情页可见状态，用于区分"进入详情页"和"详情页内切歌"

static void animateTitleBarColor(HWND hwnd, const QString &targetHex, int durationMs) {
    g_titleBarHwnd = hwnd;

    COLORREF target = 0;
    QColor targetColor = parseHexColor(targetHex, &target)
        ? QColor(GetRValue(target), GetGValue(target), GetBValue(target))
        : QColor(30, 30, 30);
    if (targetColor == g_titleBarColor) return;   // 颜色未变化，无需动画

    static QVariantAnimation *anim = nullptr;
    if (!anim) {
        anim = new QVariantAnimation;
        QObject::connect(anim, &QVariantAnimation::valueChanged, [](const QVariant &v) {
            QColor c = v.value<QColor>();
            g_titleBarColor = c;
            applyTitleBarColors(g_titleBarHwnd, c.red(), c.green(), c.blue());
        });
    }
    anim->stop();
    anim->setDuration(durationMs);
    anim->setEasingCurve(QEasingCurve::InOutQuad);
    anim->setStartValue(g_titleBarColor);
    anim->setEndValue(targetColor);
    anim->start();
}

// 沉浸背景联动：详情页沉浸背景显示且开启同步时，Win11 标题栏跟随封面主色调，否则恢复默认深色
// - 退出详情页：瞬时恢复（0ms）
// - 进入详情页：同步 kTitleBarColorAnimMs（350ms）
// - 详情页内切歌：同步详情页 ColorAnimation（600ms）
static void updateImmersiveTitleBar(HWND hwnd, MusicManager *mgr) {
    QString caption;
    bool immersive = mgr->playbackBackground() == 1 && mgr->playerDetailVisible() && mgr->titleBarImmersiveSync();
    if (immersive)
        caption = mgr->currentCoverColor();   // 无封面时为空串 → 默认深色

    int duration;
    if (!immersive && g_prevDetailVisible) {
        duration = 0;                          // 退出详情页：瞬时
    } else if (immersive && !g_prevDetailVisible) {
        duration = kTitleBarColorAnimMs;       // 进入详情页：200ms
    } else {
        duration = immersive ? 600 : 0;        // 切歌：600ms 同步详情页 / 非沉浸态：瞬时
    }
    g_prevDetailVisible = immersive;
    animateTitleBarColor(hwnd, caption, duration);
}
#endif

#include "version.h"
#include "core/SMTCManager.h"
#include "core/HotkeyManager.h"
#include "core/UpdateChecker.h"
#include "services/LyricServer.h"

// ============================================================
// 系统托盘：关闭窗口后最小化到任务栏
// ============================================================
static void setupSystemTray(QQuickWindow *window, MusicManager *mgr) {
    QSystemTrayIcon *tray = new QSystemTrayIcon(window);
    tray->setIcon(QIcon(":/qt/qml/JustSolo/data/image/logo.png"));
    tray->setToolTip("Just Solo");

    QMenu *menu = new QMenu();

    // ---- 播放控制 ----
    QAction *prevAction = menu->addAction("上一曲");
    QAction *playPauseAction = menu->addAction(mgr->isPlaying() ? "暂停" : "播放");
    QAction *nextAction = menu->addAction("下一曲");
    menu->addSeparator();

    QAction *showAction = menu->addAction("显示主窗口");
    QAction *hideAction = menu->addAction("退出至托盘");
    QAction *miniAction = menu->addAction("迷你模式");
    QAction *quitAction = menu->addAction("退出软件");

    tray->setContextMenu(menu);

    // 更新暂停/播放按钮文字
    QObject::connect(mgr, &MusicManager::playbackStateChanged, [playPauseAction, mgr]() {
        playPauseAction->setText(mgr->isPlaying() ? "暂停" : "播放");
    });

    // 上一曲
    QObject::connect(prevAction, &QAction::triggered, [mgr]() {
        mgr->previous();
    });

    // 暂停/播放
    QObject::connect(playPauseAction, &QAction::triggered, [mgr]() {
        if (mgr->currentIndex() < 0) return;
        if (mgr->isPlaying()) mgr->pause();
        else mgr->play();
    });

    // 下一曲
    QObject::connect(nextAction, &QAction::triggered, [mgr]() {
        mgr->next();
    });

    // 显示/恢复窗口（小窗模式下自动展开详情页）
    QObject::connect(showAction, &QAction::triggered, [window]() {
        QVariant miniWin = window->property("_miniWindow");
        if (miniWin.isValid() && !miniWin.isNull()) {
            window->setProperty("_pendingMiniExit", true);
        }
        window->show();
        window->raise();
        window->requestActivate();
    });

    // 迷你模式（小窗未激活时进入）
    QObject::connect(miniAction, &QAction::triggered, [window]() {
        QVariant miniWin = window->property("_miniWindow");
        if (!miniWin.isValid() || miniWin.isNull()) {
            QMetaObject::invokeMethod(window, "_enterMiniMode");
        }
    });

    // 退出至托盘：隐藏主窗口（音乐继续播放），由 QML 端 hideToTray() 处理
    // （同时记忆详情页状态、关闭 ShaderEffectSource 渲染）
    QObject::connect(hideAction, &QAction::triggered, [window]() {
        QMetaObject::invokeMethod(window, "hideToTray");
    });

    // 左键/双击托盘图标也恢复窗口（小窗模式同上去详情页）
    QObject::connect(tray, &QSystemTrayIcon::activated, [window](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::DoubleClick || reason == QSystemTrayIcon::Trigger) {
            QVariant miniWin = window->property("_miniWindow");
            if (miniWin.isValid() && !miniWin.isNull()) {
                window->setProperty("_pendingMiniExit", true);
            }
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
    // miniaudio 已替代 Qt Multimedia 作为音频引擎，无需设置媒体后端
#endif

    QApplication app(argc, argv);
    app.setApplicationName("Just Solo");
    app.setApplicationDisplayName("Just Solo");

    // 注册内置字体二进制资源（data/font 字体较大，不嵌入 C++ 避免编译器堆不足）
    // 必须在 MusicManager 注册应用字体、QML FontLoader 加载字体之前完成
    const QString fontsRcc = QCoreApplication::applicationDirPath() + "/fonts.rcc";
    if (!QResource::registerResource(fontsRcc))
        qWarning("Failed to register fonts.rcc: %s", qPrintable(fontsRcc));

    // 设置应用程序图标（任务管理器、窗口图标）
    app.setWindowIcon(QIcon(":/qt/qml/JustSolo/data/image/logo.png"));

    // ---- 单实例检测 ----
    // 若已有实例在运行，通知其激活窗口后本进程立即退出
    if (tryActivateRunningInstance()) {
        return 0;
    }

    // ---- GPU 可用性探测（DXGI）----
    // 通过 DXGI 枚举显卡判断 GPU 是否可用；若不可用（无 GPU、驱动故障、远程桌面等），
    // 回退到软件（CPU）渲染，避免白屏或崩溃。
    // 注意：不能用 QOpenGLContext 探测——它会把 ~100MB 的 OpenGL 驱动
    // （如 AMD 的 atio6axx.dll/amdxx64.dll）永久加载进进程，白白推高内存。
#ifdef Q_OS_WIN
    {
        bool gpuOk = false;
        IDXGIFactory1 *factory = nullptr;
        if (SUCCEEDED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) {
            IDXGIAdapter1 *adapter = nullptr;
            for (UINT i = 0; factory->EnumAdapters1(i, &adapter) != DXGI_ERROR_NOT_FOUND; ++i) {
                DXGI_ADAPTER_DESC1 desc{};
                adapter->GetDesc1(&desc);
                adapter->Release();
                if (!(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
                    gpuOk = true;
                    break;
                }
            }
            factory->Release();
        }
        if (gpuOk) {
            // 显式指定 D3D11 渲染后端（Qt6 在 Windows 的默认 RHI 后端），确保不触碰 OpenGL
            QQuickWindow::setGraphicsApi(QSGRendererInterface::Direct3D11);
        } else {
            qWarning("GPU rendering unavailable, falling back to software (CPU) rendering");
            // Qt6 RHI 用 QSG_RHI_BACKEND（Qt5 的 QSG_RENDERER_BACKEND 已失效）
            qputenv("QSG_RHI_BACKEND", "software");
        }
    }
#endif

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

    // Just Solo LyricServer 协议（WebSocket ws://127.0.0.1:47290）
    LyricServer *lyricServer = new LyricServer(musicManager, &app);
    lyricServer->start(47290);
    engine.rootContext()->setContextProperty("lyricServer", lyricServer);
    engine.rootContext()->setContextProperty("LYRICSERVER_VERSION", LyricServer::protocolVersion());

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
    // 快进 / 快退：步长取自用户设置（seekStep 秒），自动夹到 [0, duration]
    QObject::connect(hotkeyManager, &HotkeyManager::fastForwardTriggered, musicManager, [musicManager]() {
        if (musicManager->currentIndex() < 0) return;
        qint64 step = static_cast<qint64>(musicManager->seekStep()) * 1000;
        qint64 target = musicManager->position() + step;
        qint64 dur = musicManager->duration();
        if (dur > 0 && target > dur) target = dur;
        musicManager->seek(target);
    });
    QObject::connect(hotkeyManager, &HotkeyManager::rewindTriggered, musicManager, [musicManager]() {
        if (musicManager->currentIndex() < 0) return;
        qint64 step = static_cast<qint64>(musicManager->seekStep()) * 1000;
        qint64 target = musicManager->position() - step;
        if (target < 0) target = 0;
        musicManager->seek(target);
    });
    engine.rootContext()->setContextProperty("hotkeyManager", hotkeyManager);

    // 软件更新检查器
    UpdateChecker *updateChecker = new UpdateChecker(QString(APP_VERSION_DISPLAY), &app);
    engine.rootContext()->setContextProperty("updateChecker", updateChecker);

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

                // 沉浸背景联动：标题栏颜色跟随封面主色调
                // （详情页可见 + 沉浸背景模式 → 使用封面色，否则恢复默认深色）
                auto refreshTitleBar = [hwnd, musicManager]() {
                    updateImmersiveTitleBar(hwnd, musicManager);
                };
                QObject::connect(musicManager, &MusicManager::playbackBackgroundChanged, win, refreshTitleBar);
                QObject::connect(musicManager, &MusicManager::currentCoverColorChanged, win, refreshTitleBar);
                QObject::connect(musicManager, &MusicManager::playerDetailVisibleChanged, win, refreshTitleBar);
                QObject::connect(musicManager, &MusicManager::titleBarImmersiveSyncChanged, win, refreshTitleBar);

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
