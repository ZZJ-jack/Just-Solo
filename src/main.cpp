#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "version.h"

// 软件版本号: 大版本.中版本.小版本.预发布
#define APP_VERSION_MAJOR   0
#define APP_VERSION_MINOR   0
#define APP_VERSION_PATCH   1
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
    QGuiApplication app(argc, argv);

    // 设置应用程序图标（任务管理器、窗口图标）
    app.setWindowIcon(QIcon(":/qt/qml/JustSolo/data/image/logo.png"));

    QQmlApplicationEngine engine;

    // 暴露编译版本号到 QML
    engine.rootContext()->setContextProperty("BUILD_VERSION", QString::fromWCharArray(BUILD_VERSION));
    engine.rootContext()->setContextProperty("APP_VERSION", QString(APP_VERSION_DISPLAY));

    // 从 QML 模块加载主界面
    const QUrl url(QStringLiteral("qrc:/qt/qml/JustSolo/src/qml/main.qml"));
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection
    );

    engine.load(url);

    return app.exec();
}
