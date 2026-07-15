#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QQuickWindow>
#include <QStringList>

#ifdef Q_OS_WIN
#include <windows.h>
#include <io.h>
#include <fcntl.h>
#endif

#include "version.h"
#include "core/MusicManager.h"

// 软件版本号: 大版本.中版本.小版本.预发布
#define APP_VERSION_MAJOR   0   // 大版本号
#define APP_VERSION_MINOR   0   // 中版本号
#define APP_VERSION_PATCH   2   // 小版本号
#define APP_VERSION_PRE     2   // 预发布号，0=正式版

// 格式化: 0.0.1-pre.2 → v0.0.1-beta.2
#define STRINGIFY(x) #x
#define TOSTR(x) STRINGIFY(x)

#if APP_VERSION_PRE > 0
  #define APP_VERSION_DISPLAY "v" TOSTR(APP_VERSION_MAJOR) "." TOSTR(APP_VERSION_MINOR) "." TOSTR(APP_VERSION_PATCH) "-beta." TOSTR(APP_VERSION_PRE)
#else
  #define APP_VERSION_DISPLAY "v" TOSTR(APP_VERSION_MAJOR) "." TOSTR(APP_VERSION_MINOR) "." TOSTR(APP_VERSION_PATCH)
#endif

int main(int argc, char *argv[])
{
#ifdef Q_OS_WIN
    // --develop 参数：分配控制台用于调试日志
    QStringList args;
    for (int i = 0; i < argc; i++)
        args << QString::fromLocal8Bit(argv[i]);

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

    // 注册音乐管理器
    MusicManager *musicManager = new MusicManager(&app);
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

    return app.exec();
}
