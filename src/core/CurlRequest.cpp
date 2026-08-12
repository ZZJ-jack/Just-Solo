#include "CurlRequest.h"
#include <QDebug>
#include <QUrl>

// 回调：将 curl 响应数据追加到 m_response
size_t CurlRequest::writeCallback(char *ptr, size_t size, size_t nmemb, void *userdata)
{
    CurlRequest *self = static_cast<CurlRequest *>(userdata);
    size_t total = size * nmemb;
    self->m_response.append(ptr, total);
    return total;
}

CurlRequest::CurlRequest(QObject *parent)
    : QObject(parent)
{
    curl_global_init(CURL_GLOBAL_DEFAULT);
    m_multi = curl_multi_init();
    m_timer.setInterval(0); // 尽可能快地轮询
    connect(&m_timer, &QTimer::timeout, this, &CurlRequest::onTimeout);
}

CurlRequest::~CurlRequest()
{
    m_timer.stop();
    if (m_multi) {
        // curl_multi_cleanup 不会释放仍在队列中的 easy handle，须先手动清理，
        // 否则请求未完成时销毁对象（如退出时更新检查仍在进行）会泄漏句柄
        if (m_easy) {
            curl_multi_remove_handle(m_multi, m_easy);
            curl_easy_cleanup(m_easy);
            m_easy = nullptr;
        }
        curl_multi_cleanup(m_multi);
        m_multi = nullptr;
    }
    curl_global_cleanup();
}

void CurlRequest::get(const QString &url, const QString &userAgent)
{
    m_response.clear();

    // 防御：上一次请求尚未完成时（正常流程不会发生，调用方有重入保护），先释放旧句柄
    if (m_easy) {
        curl_multi_remove_handle(m_multi, m_easy);
        curl_easy_cleanup(m_easy);
        m_easy = nullptr;
    }

    CURL *easy = curl_easy_init();
    if (!easy) {
        emit finished(false, QByteArray(), "Failed to initialize curl easy handle", 0);
        return;
    }

    // 设置 URL
    QByteArray urlBytes = url.toUtf8();
    curl_easy_setopt(easy, CURLOPT_URL, urlBytes.constData());

    // User-Agent
    QByteArray uaBytes = userAgent.toUtf8();
    curl_easy_setopt(easy, CURLOPT_USERAGENT, uaBytes.constData());

    // 跟随重定向（对应 curl -L）
    curl_easy_setopt(easy, CURLOPT_FOLLOWLOCATION, 1L);

    // 禁用证书吊销检查（对应 curl --ssl-no-revoke）
    curl_easy_setopt(easy, CURLOPT_SSL_OPTIONS, CURLSSLOPT_NO_REVOKE);

    // 写回调
    curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, writeCallback);
    curl_easy_setopt(easy, CURLOPT_WRITEDATA, this);

    // 超时：总超时 30 秒
    curl_easy_setopt(easy, CURLOPT_TIMEOUT, 30L);
    // 连接超时 15 秒
    curl_easy_setopt(easy, CURLOPT_CONNECTTIMEOUT, 15L);

    curl_multi_add_handle(m_multi, easy);
    m_easy = easy;
    m_timer.start();
}

void CurlRequest::onTimeout()
{
    int running;
    CURLMcode mc = curl_multi_perform(m_multi, &running);
    if (mc != CURLM_OK) {
        m_timer.stop();
        // 释放失败请求的句柄，避免残留到析构
        if (m_easy) {
            curl_multi_remove_handle(m_multi, m_easy);
            curl_easy_cleanup(m_easy);
            m_easy = nullptr;
        }
        emit finished(false, QByteArray(),
                      QString::fromUtf8(curl_multi_strerror(mc)), 0);
        return;
    }

    if (running == 0) {
        m_timer.stop();

        CURLMsg *msg;
        int msgsLeft;
        bool success = false;
        QString errorStr;
        int httpStatus = 0;

        while ((msg = curl_multi_info_read(m_multi, &msgsLeft))) {
            if (msg->msg == CURLMSG_DONE) {
                CURL *easy = msg->easy_handle;
                CURLcode result = msg->data.result;

                long statusCode = 0;
                curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, &statusCode);
                httpStatus = static_cast<int>(statusCode);

                if (result == CURLE_OK) {
                    success = true;
                } else {
                    errorStr = QString::fromUtf8(curl_easy_strerror(result));
                    qDebug() << "[CurlRequest] error:" << result << errorStr
                             << "httpStatus:" << httpStatus;
                }

                curl_multi_remove_handle(m_multi, easy);
                curl_easy_cleanup(easy);
            }
        }
        m_easy = nullptr;  // 本次请求句柄已在循环中释放

        emit finished(success, m_response, errorStr, httpStatus);
    }
}
