#ifndef LYRICSERVER_H
#define LYRICSERVER_H

#include <QObject>
#include <QList>
#include <QTimer>

class MusicManager;
class QWebSocketServer;
class QWebSocket;

/**
 * 实时歌词推送服务端（WebSocket）
 *
 * 单向推送三个接口（详见《Just Solo 实时歌词推送接口 v1.0》）：
 *   - init      切歌时推送完整歌词时间轴
 *   - progress  播放中每 300ms 推送当前进度（毫秒）
 *   - playback  播放/暂停状态变化时推送
 */
class LyricServer : public QObject
{
    Q_OBJECT
public:
    explicit LyricServer(MusicManager *mgr, QObject *parent = nullptr);
    ~LyricServer();

    bool start(quint16 port = 47290);

private slots:
    void onNewConnection();
    void onClientDisconnected();
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
};

#endif // LYRICSERVER_H
