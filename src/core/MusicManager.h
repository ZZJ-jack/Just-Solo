#ifndef MUSICMANAGER_H
#define MUSICMANAGER_H

#include <QObject>
#include <QVariantList>
#include <QString>
#include <QStringList>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QFileInfo>
#include <QDir>
#include <QTimer>

class MusicManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList playlist READ playlist NOTIFY playlistChanged)
    Q_PROPERTY(QVariantList favorites READ favorites NOTIFY favoritesChanged)
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    Q_PROPERTY(int currentIndex READ currentIndex NOTIFY currentIndexChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY playbackStateChanged)
    Q_PROPERTY(QString currentTitle READ currentTitle NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentArtist READ currentArtist NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentCover READ currentCover NOTIFY currentTrackChanged)
    Q_PROPERTY(bool isLoading READ isLoading NOTIFY isLoadingChanged)
    Q_PROPERTY(qreal importProgress READ importProgress NOTIFY importProgressChanged)
    Q_PROPERTY(int importProcessed READ importProcessed NOTIFY importProgressChanged)
    Q_PROPERTY(int importTotal READ importTotal NOTIFY importProgressChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)

public:
    explicit MusicManager(QObject *parent = nullptr);

    Q_INVOKABLE void addFiles(const QStringList &paths);
    Q_INVOKABLE void addFolder(const QString &path);
    Q_INVOKABLE void removeTrack(int index);
    Q_INVOKABLE void clearPlaylist();

    Q_INVOKABLE void playIndex(int index);
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();

    QVariantList playlist() const { return m_playlist; }
    QVariantList favorites() const { return m_favorites; }
    QVariantList history() const { return m_history; }
    int currentIndex() const { return m_currentIndex; }
    bool isPlaying() const { return m_player && m_player->playbackState() == QMediaPlayer::PlayingState; }
    bool isLoading() const { return m_loading; }
    qreal importProgress() const { return m_importTotal > 0 ? qreal(m_importProcessed) / m_importTotal : 0.0; }
    int importProcessed() const { return m_importProcessed; }
    int importTotal() const { return m_importTotal; }

    QString currentTitle() const;
    QString currentArtist() const;
    QString currentCover() const { return m_currentCover; }

    Q_INVOKABLE qint64 position() const;
    Q_INVOKABLE qint64 duration() const;
    Q_INVOKABLE void seek(qint64 ms);

    // 缓存控制：开发者模式不启用，非开发者模式持久化到用户目录
    Q_INVOKABLE void setUseCache(bool use);

    // ---- 收藏 ----
    Q_INVOKABLE void toggleFavorite(const QVariantMap &track);   // 切换收藏（有则删，无则加）
    Q_INVOKABLE void removeFavorite(int index);                  // 按收藏列表索引删除
    Q_INVOKABLE bool isFavorite(const QVariantMap &track);       // 检查是否已收藏

    // ---- 历史 ----
    Q_INVOKABLE void addToHistory(const QVariantMap &track);     // 播放时自动调用
    Q_INVOKABLE void clearHistory();
    Q_INVOKABLE void removeHistoryItem(int index);

signals:
    void playlistChanged();
    void favoritesChanged();
    void historyChanged();
    void currentIndexChanged();
    void playbackStateChanged();
    void currentTrackChanged();
    void positionChanged(qint64 ms);
    void durationChanged();
    void isLoadingChanged();
    void importProgressChanged();

private:
    void updateCurrentTrack();
    void scanFolder(const QString &path);
    void processNextPending();
    static QStringList supportedExtensions();

    // ---- 缓存 ----
    void saveCache();
    void loadCache();
    void saveFavorites();
    void loadFavorites();
    void saveHistory();
    void loadHistory();
    QString m_cacheDir;          // 缓存目录（如 %APPDATA%/Just Solo）
    bool m_useCache = false;     // 开发者模式=false，非开发者模式=true

    QVariantList m_playlist;
    QVariantList m_favorites;
    QVariantList m_history;
    int m_currentIndex = -1;
    QString m_currentCover;
    bool m_loading = false;
    int m_importProcessed = 0;
    int m_importTotal = 0;

    QStringList m_pendingPaths;
    QTimer *m_loadTimer = nullptr;

    QMediaPlayer *m_player = nullptr;
    QAudioOutput *m_audioOutput = nullptr;
};

#endif
