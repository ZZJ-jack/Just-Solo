#ifndef LYRICSERVER_H
#define LYRICSERVER_H

#include <QObject>
#include <QList>
#include <QTimer>
#include <QHash>
#include <QVariantList>
#include <QVariantMap>
#include <QDateTime>

class MusicManager;
class QWebSocketServer;
class QWebSocket;

/**
 * 实时歌词推送服务端（WebSocket）
 */
class LyricServer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ isRunning NOTIFY runningChanged)
    Q_PROPERTY(QVariantList connectedClients READ connectedClients NOTIFY connectedClientsChanged)

public:
    explicit LyricServer(MusicManager *mgr, bool devMode = false, QObject *parent = nullptr);
    ~LyricServer();

    bool start(quint16 port = 47290);

    bool isRunning() const;
    static QString protocolVersion();

    // 已连接客户端列表（供 QML 显示）
    QVariantList connectedClients() const;

signals:
    void runningChanged();
    void clientConnected(const QString &clientName);   // 第三方客户端连接
    void connectedClientsChanged();

private slots:
    void onNewConnection();
    void onClientDisconnected();
    void onTextMessageReceived(const QString &message); // 接收客户端 hello
    void onLyricsChanged();     // → init
    void onPlaybackChanged();   // → playback + 控制 progress / spectrum 定时器
    void onProgressTick();      // → progress
    void onSpectrumTick();      // → spectrum

private:
    void broadcast(const QByteArray &payload);
    QByteArray buildInitPayload() const;
    void sendProgress();         // 构建并广播一帧 progress
    void sendSpectrum();         // 构建并广播一帧 spectrum

    struct ClientInfo {
        QString name;
        QString address;
        quint16 port = 0;
        QDateTime connectTime;
    };

    MusicManager *m_mgr;
    QWebSocketServer *m_server;
    QList<QWebSocket *> m_clients;
    QTimer *m_progressTimer;
    QTimer *m_spectrumTimer;
    bool m_devMode = false;
    QHash<QWebSocket *, QTimer *> m_helloTimers;  // hello 超时定时器
    QHash<QWebSocket *, ClientInfo> m_clientInfo;  // 客户端详细信息
};

#endif // LYRICSERVER_H
