#include "LyricServer.h"
#include "core/MusicManager.h"

#include <QWebSocketServer>
#include <QWebSocket>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QHostAddress>

// ============================================================
// 构造 / 析构
// ============================================================

LyricServer::LyricServer(MusicManager *mgr, bool devMode, QObject *parent)
    : QObject(parent)
    , m_mgr(mgr)
    , m_devMode(devMode)
    , m_server(new QWebSocketServer(QStringLiteral("Just Solo LyricServer"),
                                    QWebSocketServer::NonSecureMode, this))
    , m_progressTimer(new QTimer(this))
{
    // 推送间隔 300ms（可在 200~500 间调整）
    m_progressTimer->setInterval(LYRICSERVER_PROTOCOL_PRE_TIME);

    connect(m_server, &QWebSocketServer::newConnection,
            this, &LyricServer::onNewConnection);

    // 切歌 / 歌词异步加载完成 → 推 init
    connect(m_mgr, &MusicManager::currentLyricsChanged,
            this, &LyricServer::onLyricsChanged);

    // 播放状态变化 → 推 playback + 控制定时器
    connect(m_mgr, &MusicManager::playbackStateChanged,
            this, &LyricServer::onPlaybackChanged);

    connect(m_progressTimer, &QTimer::timeout,
            this, &LyricServer::onProgressTick);
}

LyricServer::~LyricServer()
{
    if (m_server->isListening())
        m_server->close();
    qDeleteAll(m_clients);
}

// ============================================================
// 启动监听
// ============================================================

bool LyricServer::start(quint16 port)
{
    // 只监听本地环回，不暴露到网卡
    if (!m_server->listen(QHostAddress::LocalHost, port)) {
        qWarning("JustSolo LyricServer: listen 失败 port=%u — %s",
                 port, qPrintable(m_server->errorString()));
        return false;
    }
    qDebug("JustSolo LyricServer: 监听 ws://127.0.0.1:%u", port);
    emit runningChanged();
    return true;
}

bool LyricServer::isRunning() const
{
    return m_server && m_server->isListening();
}

QString LyricServer::protocolVersion()
{
    return QStringLiteral(LYRICSERVER_PROTOCOL_VERSION);
}

// ============================================================
// 新客户端连接：立即补推 init + playback，不用等下一次切歌
// ============================================================

void LyricServer::onNewConnection()
{
    while (m_server->hasPendingConnections()) {
        QWebSocket *client = m_server->nextPendingConnection();
        m_clients.append(client);

        // 开发者模式（--develop）：输出客户端连接日志
        if (m_devMode)
            qDebug("JustSolo LyricServer: 客户端连接 %s:%u（当前 %d 个客户端）",
                   qPrintable(client->peerAddress().toString()),
                   client->peerPort(), m_clients.size());

        connect(client, &QWebSocket::disconnected,
                this, &LyricServer::onClientDisconnected);

        // v1.1.0: 监听客户端 hello 消息（声明客户端名称）
        connect(client, &QWebSocket::textMessageReceived,
                this, &LyricServer::onTextMessageReceived);

        // 记录客户端信息
        ClientInfo info;
        info.name = QStringLiteral("未知客户端");
        info.address = client->peerAddress().toString();
        info.port = client->peerPort();
        info.connectTime = QDateTime::currentDateTime();
        m_clientInfo[client] = info;
        emit connectedClientsChanged();

        // 超时定时器：500ms 内未收到 hello → 按未知客户端通知
        QTimer *helloTimer = new QTimer(client);
        helloTimer->setSingleShot(true);
        m_helloTimers[client] = helloTimer;
        connect(helloTimer, &QTimer::timeout, this, [this, client]() {
            m_helloTimers.remove(client);
            // 超时仍未收到 hello，断开监听
            disconnect(client, &QWebSocket::textMessageReceived,
                       this, &LyricServer::onTextMessageReceived);
            emit clientConnected(QStringLiteral("未知客户端"));
        });
        helloTimer->start(500);

        // 补推当前歌词
        client->sendTextMessage(QString::fromUtf8(buildInitPayload()));

        // 补推当前播放状态
        QJsonObject pb;
        pb["type"] = QStringLiteral("playback");
        pb["status"] = m_mgr->isPlaying() ? QStringLiteral("playing")
                                          : QStringLiteral("paused");
        client->sendTextMessage(QString::fromUtf8(
            QJsonDocument(pb).toJson(QJsonDocument::Compact)));

        // 补推当前进度（播放中才需要，让客户端立刻能定位歌词行）
        if (m_mgr->isPlaying()) {
            QJsonObject pg;
            pg["type"] = QStringLiteral("progress");
            pg["position"] = qint64(m_mgr->position());
            client->sendTextMessage(QString::fromUtf8(
                QJsonDocument(pg).toJson(QJsonDocument::Compact)));
        }
    }

    // 客户端连上后，若正在播放但定时器已停（之前因无客户端被 onProgressTick 停掉），
    // 必须重新启动，否则后续 progress 不会实时推送
    if (m_mgr->isPlaying() && !m_progressTimer->isActive())
        m_progressTimer->start();
}

void LyricServer::onClientDisconnected()
{
    QWebSocket *client = qobject_cast<QWebSocket *>(sender());
    if (client) {
        m_clients.removeAll(client);
        // 清理 hello 定时器
        if (m_helloTimers.contains(client)) {
            m_helloTimers[client]->stop();
            m_helloTimers.remove(client);
        }
        // 清理客户端信息
        m_clientInfo.remove(client);
        emit connectedClientsChanged();
        client->deleteLater();
    }
}

void LyricServer::onTextMessageReceived(const QString &message)
{
    QWebSocket *client = qobject_cast<QWebSocket *>(sender());
    if (!client) return;

    // 只处理第一条消息（hello），之后不再监听
    disconnect(client, &QWebSocket::textMessageReceived,
               this, &LyricServer::onTextMessageReceived);

    // 尝试解析 hello 消息: {"type":"hello","client":"客户端名称"}
    QJsonDocument doc = QJsonDocument::fromJson(message.toUtf8());
    QJsonObject obj = doc.object();
    if (obj.value("type").toString() == "hello") {
        QString name = obj.value("client").toString().trimmed();
        if (name.isEmpty()) name = QStringLiteral("未知客户端");

        // 更新客户端名称
        if (m_clientInfo.contains(client))
            m_clientInfo[client].name = name;

        // 取消超时定时器
        if (m_helloTimers.contains(client)) {
            m_helloTimers[client]->stop();
            m_helloTimers.remove(client);
        }

        if (m_devMode)
            qDebug("JustSolo LyricServer: 客户端 hello — %s", qPrintable(name));

        emit connectedClientsChanged();
        emit clientConnected(name);
    }
    // 非 hello 消息：忽略（向下兼容，旧客户端不发送任何消息）
}

// ============================================================
// 切歌：广播 init
// ============================================================

void LyricServer::onLyricsChanged()
{
    broadcast(buildInitPayload());
}

// ============================================================
// 状态变化：广播 playback + 控制进度推送
// ============================================================

void LyricServer::onPlaybackChanged()
{
    bool playing = m_mgr->isPlaying();

    QJsonObject msg;
    msg["type"] = QStringLiteral("playback");
    msg["status"] = playing ? QStringLiteral("playing")
                            : QStringLiteral("paused");
    broadcast(QJsonDocument(msg).toJson(QJsonDocument::Compact));

    // 播放中才推 progress；暂停/停止时停
    if (playing) {
        m_progressTimer->start();
        sendProgress();  // 立即推一帧，不等第一个 tick
    } else {
        m_progressTimer->stop();
    }
}

// ============================================================
// 每 300ms：广播 progress
// ============================================================

void LyricServer::onProgressTick()
{
    // 没人听就别白跑，等下次 play 再启动
    if (m_clients.isEmpty()) {
        m_progressTimer->stop();
        return;
    }
    sendProgress();
}

// ============================================================
// 工具函数
// ============================================================

void LyricServer::broadcast(const QByteArray &payload)
{
    if (m_clients.isEmpty()) return;
    const QString text = QString::fromUtf8(payload);
    for (QWebSocket *client : m_clients)
        client->sendTextMessage(text);
}

// 构建并广播一帧 progress
void LyricServer::sendProgress()
{
    if (m_clients.isEmpty()) return;
    QJsonObject msg;
    msg["type"] = QStringLiteral("progress");
    msg["position"] = qint64(m_mgr->position());  // 毫秒
    broadcast(QJsonDocument(msg).toJson(QJsonDocument::Compact));
}

// 把 MusicManager::currentLyrics() 序列化成 init 接口的 JSON
QByteArray LyricServer::buildInitPayload() const
{
    QVariantList lyrics = m_mgr->currentLyrics();

    QJsonObject msg;
    msg["type"] = QStringLiteral("init");

    QJsonArray arr;
    for (const QVariant &item : lyrics) {
        QVariantMap entry = item.toMap();
        QJsonObject line;
        line["time"] = entry.value("time").toInt();
        line["text"] = entry.value("text").toString();
        arr.append(line);
    }
    msg["lyrics"] = arr;

    return QJsonDocument(msg).toJson(QJsonDocument::Compact);
}

// 返回已连接客户端列表（供 QML 显示）
QVariantList LyricServer::connectedClients() const
{
    QVariantList list;
    for (auto it = m_clientInfo.constBegin(); it != m_clientInfo.constEnd(); ++it) {
        const ClientInfo &info = it.value();
        QVariantMap map;
        map["name"] = info.name;
        map["address"] = info.address;
        map["port"] = info.port;
        map["connectTime"] = info.connectTime.toString(QStringLiteral("yyyy-MM-dd HH:mm:ss"));
        list.append(map);
    }
    return list;
}
