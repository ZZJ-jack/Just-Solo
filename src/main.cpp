#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStringList>
#include <QTimer>

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
#endif

    QGuiApplication app(argc, argv);
    app.setApplicationName("Just Solo");
    app.setApplicationDisplayName("Just Solo");

    // 设置应用程序图标（任务管理器、窗口图标）
    app.setWindowIcon(QIcon(":/qt/qml/JustSolo/data/image/logo.png"));

    QQmlApplicationEngine engine;
    QQuickStyle::setStyle("Basic");

    // 暴露编译版本号到 QML
    engine.rootContext()->setContextProperty("BUILD_VERSION", QString::fromWCharArray(BUILD_VERSION));
    engine.rootContext()->setContextProperty("APP_VERSION", QString(APP_VERSION_DISPLAY));
    engine.rootContext()->setContextProperty("DEVELOPER_MODE", args.contains("--develop"));
#ifdef Q_OS_WIN
    engine.rootContext()->setContextProperty("OS_VERSION", osVersionString());
#endif

    // 注册音乐管理器（非开发者模式启用本地缓存）
    MusicManager *musicManager = new MusicManager(&app);
    musicManager->setUseCache(!args.contains("--develop"));
    engine.rootContext()->setContextProperty("musicManager", musicManager);

    // 从 QML 模块加载主界面
    const QUrl url(QStringLiteral("qrc:/qt/qml/JustSolo/src/qml/main.qml"));
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection
    );

    // 关闭窗口时退出进程（--develop 模式同样生效）
    QObject::connect(&engine, &QQmlApplicationEngine::quit, &app, &QGuiApplication::quit);

    engine.load(url);

#ifdef Q_OS_WIN
    // 系统原生标题栏深度自定义 + SMTC 初始化 — 延迟确保窗口句柄就绪
    if (!engine.rootObjects().isEmpty()) {
        QQuickWindow *win = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
        if (win) {
            QTimer::singleShot(200, win, [win, musicManager]() {
                HWND hwnd = HWND(win->winId());
                customizeTitleBar(hwnd);

                // 初始化 Windows 系统媒体控件 (SMTC)
                new SMTCManager(musicManager, hwnd, musicManager);
            });
        }
    }
#endif

    return app.exec();
}
