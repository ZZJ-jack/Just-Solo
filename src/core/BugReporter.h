#ifndef BUGREPORTER_H
#define BUGREPORTER_H

#include <QObject>
#include <QMap>

class QNetworkAccessManager;

/**
 * @brief 运行日志上报器
 *
 * 将播放器运行中的关键事件（代码异常、加载失败等）异步上报到后端日志收集服务。
 * - 单例：进程内全局可用，首次调用时懒初始化
 * - 异步非阻塞：通过 QNetworkAccessManager 发送 POST，失败仅打 qDebug
 * - 节流：相同 (type + content) 在 kThrottleMs 毫秒内只上报一次，防止刷屏
 * - 线程安全：静态 submit() 通过 QueuedConnection 投递到主线程执行
 * - 弹窗通知：上报后发射 errorOccurred 信号，QML 端可监听并弹出提示框
 * - 全局拦截：installGlobalHandler() 安装 Qt 消息处理器拦截 QtCriticalMsg/QtFatalMsg
 *
 * User-Agent 使用 "Pvz-Game/<版本号>" 前缀，匹配服务端版本提取正则
 * （服务端从 UA 中匹配 `Pvz-Game/(\S+)` 提取版本号）。
 */
class BugReporter : public QObject
{
    Q_OBJECT
public:
    static BugReporter *instance();

    // 静态便捷方法：任意线程可调用，自动切到主线程异步上报
    // notifyUser=true 时同时发射 errorOccurred 信号让 QML 弹窗
    static void submit(const QString &type, const QString &content,
                       const QString &traceback = QString(),
                       bool notifyUser = true);

    // 实例方法：可被 QML 通过 contextProperty 调用
    Q_INVOKABLE void report(const QString &type, const QString &content,
                            const QString &traceback = QString());

    // 安装全局错误拦截：Qt 消息处理器（QtCriticalMsg/QtFatalMsg）+ std::set_terminate
    // 必须在 QCoreApplication 创建后、其他代码运行前调用
    static void installGlobalHandler();

    // 启用/禁用上报（禁用时仍会发射 errorOccurred 信号供 QML 弹窗，只是不上报后端）
    void setReportingEnabled(bool enabled) { m_reportingEnabled = enabled; }
    bool reportingEnabled() const { return m_reportingEnabled; }

signals:
    // 错误发生信号：QML 端监听以弹出错误提示框
    void errorOccurred(const QString &type, const QString &content,
                       const QString &traceback);

private:
    explicit BugReporter(QObject *parent = nullptr);
    void doSubmit(const QString &type, const QString &content,
                  const QString &traceback, bool notifyUser);

    QNetworkAccessManager *m_networkManager = nullptr;
    QString m_userAgent;
    bool m_reportingEnabled = true;

    // 节流：key = type + "\x01" + content，value = 上次上报时间戳（ms）
    QMap<QString, qint64> m_lastReportTime;

    static constexpr qint64 kThrottleMs = 60 * 1000;  // 同类错误 60 秒内只上报一次
};

#endif // BUGREPORTER_H
