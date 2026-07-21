#ifndef MUSICMANAGER_H
#define MUSICMANAGER_H

#include <QObject>
#include <QVariantList>
#include <QString>
#include <QStringList>
#include <QVector>
#include <QMediaPlayer>
#include <QAudioOutput>
#include <QFileInfo>
#include <QDir>
#include <QTimer>

class MusicManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList playlist READ playlist NOTIFY playlistChanged)
    Q_PROPERTY(QVariantList library READ library NOTIFY libraryChanged)
    Q_PROPERTY(QVariantList favorites READ favorites NOTIFY favoritesChanged)
    Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)
    Q_PROPERTY(int currentIndex READ currentIndex NOTIFY currentIndexChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY playbackStateChanged)
    Q_PROPERTY(QString currentTitle READ currentTitle NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentArtist READ currentArtist NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentCover READ currentCover NOTIFY currentTrackChanged)
    Q_PROPERTY(QString currentAlbum READ currentAlbum NOTIFY currentTrackChanged)
    Q_PROPERTY(bool isLoading READ isLoading NOTIFY isLoadingChanged)
    Q_PROPERTY(qreal importProgress READ importProgress NOTIFY importProgressChanged)
    Q_PROPERTY(int importProcessed READ importProcessed NOTIFY importProgressChanged)
    Q_PROPERTY(int importTotal READ importTotal NOTIFY importProgressChanged)
    Q_PROPERTY(qint64 position READ position NOTIFY positionChanged)
    Q_PROPERTY(qint64 duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(QVariantList currentLyrics READ currentLyrics NOTIFY currentLyricsChanged)
    Q_PROPERTY(int lyricIndex READ lyricIndex NOTIFY lyricIndexChanged)
    Q_PROPERTY(qreal detailOpacity READ detailOpacity WRITE setDetailOpacity NOTIFY detailOpacityChanged)
    Q_PROPERTY(int lyricOffset READ lyricOffset WRITE setLyricOffset NOTIFY lyricOffsetChanged)
    Q_PROPERTY(int playMode READ playMode WRITE setPlayMode NOTIFY playModeChanged)
    Q_PROPERTY(qreal menuOpacity READ menuOpacity WRITE setMenuOpacity NOTIFY menuOpacityChanged)
    Q_PROPERTY(int playlistSource READ playlistSource WRITE setPlaylistSource NOTIFY playlistSourceChanged)
    Q_PROPERTY(bool trackCrossSource READ trackCrossSource WRITE setTrackCrossSource NOTIFY trackCrossSourceChanged)

public:
    explicit MusicManager(QObject *parent = nullptr);

    // ---- 播放模式 ----
    enum PlayMode {
        Sequential  = 0,  // 顺序播放
        ListLoop    = 1,  // 列表循环
        SingleLoop  = 2,  // 单曲循环
        Shuffle     = 3,  // 随机播放
        StopAfter   = 4   // 关闭循环（播完当前停止）
    };
    Q_ENUM(PlayMode)

    // ---- 播放列表来源 ----
    enum PlaylistSource {
        SourcePlaylist  = 0,  // 首页（全局播放列表）
        SourceFavorites = 1,  // 收藏页
        SourceHistory   = 2   // 历史页
    };
    Q_ENUM(PlaylistSource)

    Q_INVOKABLE void addFiles(const QStringList &paths);
    Q_INVOKABLE void addFolder(const QString &path);
    Q_INVOKABLE void removeTrack(int index);
    Q_INVOKABLE void clearPlaylist();

    Q_INVOKABLE void playIndex(int index);
    Q_INVOKABLE void play();
    Q_INVOKABLE void pause();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void shutdown();
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();

    QVariantList playlist() const { return m_playlist; }
    QVariantList library() const { return m_library; }
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
    QString currentAlbum() const;
    QVariantList currentLyrics() const { return m_currentLyrics; }
    int lyricIndex() const { return m_lyricIndex; }
    qreal detailOpacity() const { return m_detailOpacity; }
    void setDetailOpacity(qreal v);
    int lyricOffset() const { return m_lyricOffset; }
    void setLyricOffset(int v);
    qreal menuOpacity() const { return m_menuOpacity; }
    void setMenuOpacity(qreal v);

    // ---- 播放列表来源 ----
    int playlistSource() const { return m_playlistSource; }
    void setPlaylistSource(int source);
    QVariantList &currentPlaylist();  // 根据来源返回对应列表

    // ---- 跨来源跟踪 ----
    bool trackCrossSource() const { return m_trackCrossSource; }
    void setTrackCrossSource(bool v);

    // ---- 播放列表操作 ----
    Q_INVOKABLE void addToPlaylist(const QVariantMap &track);     // 追加单曲到播放列表
    Q_INVOKABLE void removeFromPlaylist(const QVariantMap &track); // 按路径从播放队列删除
    Q_INVOKABLE void copyToPlaylist(int source);                  // 将指定来源列表全部复制到播放列表

    Q_INVOKABLE qint64 position() const;
    Q_INVOKABLE qint64 duration() const;
    Q_INVOKABLE void seek(qint64 ms);

    // ---- 播放模式 ----
    int playMode() const { return m_playMode; }
    Q_INVOKABLE void setPlayMode(int mode);

    // 原画质封面：从音频文件中提取原始封面并保存为 PNG，返回 file:// 路径
    Q_INVOKABLE QString loadOriginalCover();
    // 释放原画质封面内存（删除临时文件）
    Q_INVOKABLE void releaseOriginalCover();

    // 歌词：解析 LRC 文件，返回 [{time: ms, text: "..."}]
    Q_INVOKABLE QVariantList loadLyricsForFile(const QString &filePath);

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
    void libraryChanged();
    void favoritesChanged();
    void historyChanged();
    void currentIndexChanged();
    void playbackStateChanged();
    void currentTrackChanged();
    void currentLyricsChanged();
    void lyricIndexChanged();
    void detailOpacityChanged();
    void lyricOffsetChanged();
    void playModeChanged();
    void menuOpacityChanged();
    void playlistSourceChanged();
    void trackCrossSourceChanged();
    void positionChanged(qint64 ms);
    void durationChanged();
    void isLoadingChanged();
    void importProgressChanged();

private:
    // 预编译歌词缓存：纯整数，播放时零分配
    struct LyricEntry {
        int time;      // 时间戳 (ms)
        qint64 offset; // 预算偏移 (2.15 × 字数)
    };
    void rebuildLyricCache();
    QVector<LyricEntry> m_lyricCache;

    void updateCurrentTrack();
    void updateLyricIndex();
    void onMetaDataChanged();
    void scanFolder(const QString &path);
    void processNextPending();
    QVariantList parseEmbeddedLyrics(const QString &text);
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
    QVariantList m_library;        // 音乐库（首页展示，持久化存储）
    QVariantList m_favorites;
    QVariantList m_history;
    QVariantList m_currentLyrics;
    int m_lyricIndex = -1;
    qreal m_detailOpacity = 0.90;  // 播放详情页背景透明度 (0.3-1.0)
    int m_lyricOffset = 130;       // 用户可调基础偏移 (ms)，最终 = base + 2.15×歌词长度
    int m_playMode = 0;             // 播放模式 (Sequential=0)
    qreal m_menuOpacity = 0.80;     // 模式菜单透明度 (0.3-1.0)
    int m_playlistSource = 0;       // 活跃播放列表来源 (SourcePlaylist=0)
    bool m_trackCrossSource = false; // 跨来源播放跟踪（默认关闭）
    void loadSettings();
    void saveSettings();
    int m_currentIndex = -1;
    QString m_currentCover;
    QString m_currentAlbum;
    QString m_currentMediaPath;    // 当前媒体文件路径
    QString m_originalCoverPath;   // 原画质封面临时文件路径
    bool m_loading = false;
    int m_importProcessed = 0;
    int m_importTotal = 0;

    QStringList m_pendingPaths;
    QTimer *m_loadTimer = nullptr;
    QTimer *m_lyricTimer = nullptr;     // 节流歌词索引更新（100ms debounce）

    // 嵌入式歌词异步加载
    bool m_embeddedLyricsLoaded = false;

    QMediaPlayer *m_player = nullptr;
    QAudioOutput *m_audioOutput = nullptr;
};

#endif
