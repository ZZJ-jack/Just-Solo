#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStringList>

#ifdef Q_OS_WIN
#include <windows.h>
#include <dwmapi.h>
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

// 深度自定义原生标题栏：暗黑模式 + 边框/标题栏颜色与窗口背景 #1e1e2e 一致
static void customizeTitleBar(HWND hwnd) {
    BOOL darkMode = TRUE;
    DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &darkMode, sizeof(darkMode));

    COLORREF bg = 0x002e1e1e;  // #1e1e2e (ABGR → COLORREF)
    DwmSetWindowAttribute(hwnd, DWMWA_BORDER_COLOR,  &bg, sizeof(bg));
    DwmSetWindowAttribute(hwnd, DWMWA_CAPTION_COLOR, &bg, sizeof(bg));
}
#endif

#include "version.h"
#include "core/MusicManager.h"

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
            FILE *dummy;
            freopen_s(&dummy, "CONOUT$", "w", stdout);
            freopen_s(&dummy, "CONOUT$", "w", stderr);
            printf("\nJust Solo --develop mode\n");
            printf("Build: %ls\n", BUILD_VERSION);
            fflush(stdout);
        }
    }
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
    // 系统原生标题栏深度自定义：窗口创建后设置 DWM 暗黑模式 + 边框颜色
    if (!engine.rootObjects().isEmpty()) {
        QQuickWindow *win = qobject_cast<QQuickWindow*>(engine.rootObjects().first());
        if (win) {
            QObject::connect(win, &QQuickWindow::visibleChanged, [win](bool visible) {
                if (visible)
                    customizeTitleBar(HWND(win->winId()));
            });
        }
    }
#endif

    return app.exec();
}
