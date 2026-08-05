#ifndef LYRICSERVER_H
#define LYRICSERVER_H

#include <QObject>
#include <QList>
#include <QTimer>
#include <QHash>

class MusicManager;
class QWebSocketServer;
class QWebSocket;

/**
 * 实时歌词推送服务端（WebSocket）
 *
 * 单向推送三个接口（详见《Just Solo LyricServer 协议 v1.0.0》）：
 *   - init      切歌时推送完整歌词时间轴
 *   - progress  播放中每 300ms 推送当前进度（毫秒）
 *   - playback  播放/暂停状态变化时推送
 *
 * v1.2.0 新增：客户端可发送 hello 消息声明名称（向下兼容）
 */
class LyricServer : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool running READ isRunning NOTIFY runningChanged)

public:
    explicit LyricServer(MusicManager *mgr, bool devMode = false, QObject *parent = nullptr);
    ~LyricServer();

    bool start(quint16 port = 47290);

    bool isRunning() const;
    static QString protocolVersion();

signals:
    void runningChanged();
    void clientConnected(const QString &clientName);   // 第三方客户端连接

private slots:
    void onNewConnection();
    void onClientDisconnected();
    void onTextMessageReceived(const QString &message); // 接收客户端 hello
    void onLyricsChanged();     // → init
    void onPlaybackChanged();   // → playback + 控制 progress 定时器
    void onProgressTick();      // → progress

private:
    void broadcast(const QByteArray &payload);
    QByteArray buildInitPayload() const;
    void sendProgress();         // 构建并广播一帧 progress

    MusicManager *m_mgr;
    QWebSocketServer *m_server;
    QList<QWebSocket *> m_clients;
    QTimer *m_progressTimer;
    bool m_devMode = false;      // 开发者模式（--develop）：输出客户端连接日志
    QHash<QWebSocket *, QTimer *> m_helloTimers;  // hello 超时定时器
};

#endif // LYRICSERVER_H
