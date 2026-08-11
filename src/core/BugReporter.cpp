#include "BugReporter.h"

#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QUrl>
#include <QDateTime>
#include <QDebug>
#include <QMetaObject>
#include <QCoreApplication>
#include <QtGlobal>

#include <exception>      // std::set_terminate
#include <cstdlib>        // abort

// 后端日志收集服务 Base URL
static const char *kBaseUrl = "https://justsolobug.zzjjack.us.kg";

// 服务端通过正则 `Pvz-Game/(\S+)` 从 User-Agent 中提取版本号；
// 虽然 JustSolo 不是 Pvz-Game，但为兼容服务端硬编码逻辑，UA 中需包含该前缀。
// APP_VERSION_DISPLAY 由 CMake target_compile_definitions 注入（如 "v1.2.3"）
static const char *kUserAgent = "Pvz-Game/" APP_VERSION_DISPLAY;

BugReporter *BugReporter::instance()
{
    static BugReporter *s_inst = nullptr;
    if (!s_inst) {
        // 必须在 QCoreApplication 存在后调用
        s_inst = new BugReporter(QCoreApplication::instance());
    }
    return s_inst;
}

BugReporter::BugReporter(QObject *parent)
    : QObject(parent)
{
    m_networkManager = new QNetworkAccessManager(this);
    m_userAgent = QString::fromLatin1(kUserAgent);
    qDebug() << "[BugReporter] initialized, UA =" << m_userAgent
             << "endpoint =" << kBaseUrl;
}

void BugReporter::submit(const QString &type, const QString &content,
                         const QString &traceback, bool notifyUser)
{
    // 通过 QueuedConnection 投递到主线程，确保 QNetworkAccessManager 在主线程使用
    QMetaObject::invokeMethod(
        instance(), [type, content, traceback, notifyUser]() {
            instance()->doSubmit(type, content, traceback, notifyUser);
        }, Qt::QueuedConnection);
}

void BugReporter::report(const QString &type, const QString &content,
                         const QString &traceback)
{
    doSubmit(type, content, traceback, true);
}

void BugReporter::doSubmit(const QString &type, const QString &content,
                           const QString &traceback, bool notifyUser)
{
    if (type.isEmpty() || content.isEmpty()) {
        qDebug() << "[BugReporter] skip: type or content is empty";
        return;
    }

    // 始终发射信号让 QML 弹窗（即使禁用上报，用户也应看到错误提示）
    if (notifyUser) {
        emit errorOccurred(type, content, traceback);
    }

    // 节流：相同 (type + content) 在 kThrottleMs 内只上报一次
    // （例如热插拔重试每秒都会失败，避免刷屏）
    const QString key = type + QStringLiteral("\x01") + content;
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    auto it = m_lastReportTime.constFind(key);
    if (it != m_lastReportTime.constEnd() && (now - it.value()) < kThrottleMs) {
        return;  // 节流期内，跳过后端上报
    }
    m_lastReportTime[key] = now;

    // 清理过期的节流记录（超过 5 分钟的条目），防止内存无限增长
    if (m_lastReportTime.size() > 100) {
        for (auto i = m_lastReportTime.begin(); i != m_lastReportTime.end();) {
            if ((now - i.value()) > 5 * 60 * 1000)
                i = m_lastReportTime.erase(i);
            else
                ++i;
        }
    }

    // 上报被禁用，仅弹窗不发送到后端
    if (!m_reportingEnabled) {
        return;
    }

    // 构造请求体：time 字段不传，由服务端自动填服务器当前时间
    QJsonObject body;
    body[QStringLiteral("type")] = type;
    body[QStringLiteral("content")] = content;
    if (!traceback.isEmpty())
        body[QStringLiteral("traceback")] = traceback;

    QJsonDocument doc(body);

    QNetworkRequest request(QUrl(QString::fromLatin1(kBaseUrl) + QStringLiteral("/submit")));
    request.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    request.setHeader(QNetworkRequest::UserAgentHeader, m_userAgent);
    request.setTransferTimeout(10000);  // 10 秒超时，避免阻塞网络栈

    QNetworkReply *reply = m_networkManager->post(request, doc.toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this, [reply]() {
        if (reply->error() != QNetworkReply::NoError) {
            qDebug() << "[BugReporter] submit failed:" << reply->errorString();
        } else {
            qDebug() << "[BugReporter] submit ok, response:" << reply->readAll();
        }
        reply->deleteLater();
    });
}

// ============================================================
// 全局错误拦截
// ============================================================

// 保存原消息处理器，避免完全覆盖 Qt 默认行为
static QtMessageHandler g_origMessageHandler = nullptr;

static void bugReporterMessageHandler(QtMsgType type, const QMessageLogContext &ctx, const QString &msg)
{
    // 先调用原处理器，保留 Qt 默认输出（控制台/调试输出）
    if (g_origMessageHandler)
        g_origMessageHandler(type, ctx, msg);

    // 只上报严重错误（代码问题），qWarning/qInfo/qDebug 不自动上报
    // （qWarning 多为预期失败如 WASAPI 独占被占用、文件不存在等，不视为代码 bug）
    if (type == QtCriticalMsg || type == QtFatalMsg) {
        QString typeStr;
        switch (type) {
        case QtCriticalMsg: typeStr = QStringLiteral("严重错误"); break;
        case QtFatalMsg:    typeStr = QStringLiteral("致命错误"); break;
        default: return;
        }
        QString content = msg;
        QString traceback;
        if (ctx.file) {
            traceback = QStringLiteral("%1:%2 (%3)")
                            .arg(QString::fromUtf8(ctx.file))
                            .arg(ctx.line)
                            .arg(QString::fromUtf8(ctx.function ? ctx.function : ""));
        }
        // 致命错误不弹窗（进程即将终止），仅静默上报
        BugReporter::submit(typeStr, content, traceback, /*notifyUser=*/type != QtFatalMsg);
    }
}

// 未捕获的 C++ 异常处理：进程即将终止，尽力上报
static void bugReporterTerminateHandler()
{
    try {
        if (auto ep = std::current_exception()) {
            std::rethrow_exception(ep);
        }
    } catch (const std::exception &e) {
        BugReporter::submit(QStringLiteral("未捕获异常"),
                            QStringLiteral("std::exception: %1").arg(QString::fromLocal8Bit(e.what())),
                            QString(), /*notifyUser=*/false);
    } catch (...) {
        BugReporter::submit(QStringLiteral("未捕获异常"),
                            QStringLiteral("未知类型的未捕获异常"),
                            QString(), /*notifyUser=*/false);
    }
    // 短暂等待异步上报投递（QueuedConnection 需要事件循环）
    if (auto app = qApp) {
        QCoreApplication::processEvents(QEventLoop::AllEvents, 500);
    }
    std::abort();
}

void BugReporter::installGlobalHandler()
{
    g_origMessageHandler = qInstallMessageHandler(bugReporterMessageHandler);
    std::set_terminate(bugReporterTerminateHandler);
    qDebug() << "[BugReporter] global error handlers installed "
                "(QtCriticalMsg/QtFatalMsg + std::terminate)";
}
