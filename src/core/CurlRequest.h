#ifndef CURLREQUEST_H
#define CURLREQUEST_H

#include <QObject>
#include <QByteArray>
#include <QTimer>
#include <curl/curl.h>

class CurlRequest : public QObject
{
    Q_OBJECT
public:
    explicit CurlRequest(QObject *parent = nullptr);
    ~CurlRequest() override;

    void get(const QString &url, const QString &userAgent);

signals:
    void finished(bool success, const QByteArray &data,
                  const QString &errorString, int httpStatus);

private:
    static size_t writeCallback(char *ptr, size_t size, size_t nmemb, void *userdata);
    void onTimeout();

    CURLM *m_multi = nullptr;
    CURL *m_easy = nullptr;   // 当前进行中的请求句柄，析构时须手动清理（multi 不负责释放）
    QTimer m_timer;
    QByteArray m_response;
};

#endif // CURLREQUEST_H
