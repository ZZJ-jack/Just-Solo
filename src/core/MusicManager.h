#ifndef MUSICMANAGER_H
#define MUSICMANAGER_H

#include <QObject>
#include <QVariantList>
#include <QString>
#include <QStringList>
#include <QVector>
#include <QMap>
#include "AudioEngine.h"
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
    Q_PROPERTY(QString currentCoverColor READ currentCoverColor NOTIFY currentCoverColorChanged)
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
    Q_PROPERTY(qreal volumeMenuOpacity READ volumeMenuOpacity WRITE setVolumeMenuOpacity NOTIFY volumeMenuOpacityChanged)
    Q_PROPERTY(int playlistSource READ playlistSource WRITE setPlaylistSource NOTIFY playlistSourceChanged)
    Q_PROPERTY(bool trackCrossSource READ trackCrossSource WRITE setTrackCrossSource NOTIFY trackCrossSourceChanged)
    Q_PROPERTY(bool minimizeToTray READ minimizeToTray WRITE setMinimizeToTray NOTIFY minimizeToTrayChanged)
    Q_PROPERTY(int playbackBackground READ playbackBackground WRITE setPlaybackBackground NOTIFY playbackBackgroundChanged)
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool wasapiExclusive READ wasapiExclusive WRITE setWasapiExclusive NOTIFY wasapiExclusiveChanged)
    Q_PROPERTY(QString lyricFont READ lyricFont WRITE setLyricFont NOTIFY lyricFontChanged)
    Q_PROPERTY(QString lyricFontFamily READ lyricFontFamily NOTIFY lyricFontChanged)

    // ---- 自定义播放列表 ----
    Q_PROPERTY(QVariantList customPlaylists READ customPlaylists NOTIFY customPlaylistsChanged)
    Q_PROPERTY(int playingListIndex READ playingListIndex NOTIFY playingListIndexChanged)  // -1=无, 0=库, 1=收藏, 2=历史, 3+n=自定义

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
    Q_INVOKABLE void addSongsToCustomPlaylist(const QStringList &paths, int playlistIndex);
    Q_INVOKABLE void addLibrarySongsToCustomPlaylist(const QVariantList &libraryIndices, int playlistIndex);
    Q_INVOKABLE void addFolder(const QString &path);
    Q_INVOKABLE void removeTrack(int index);
    Q_INVOKABLE void deleteSongByPath(const QString &path);  // 从所有列表删除（库/播放列表/收藏/历史/自建）
    Q_INVOKABLE void clearPlaylist();

    // ---- 手动排序 ----
    Q_INVOKABLE void moveSongInLibrary(int from, int to);
    Q_INVOKABLE void moveSongInFavorites(int from, int to);
    Q_INVOKABLE void moveSongInHistory(int from, int to);
    Q_INVOKABLE void moveSongInCustomPlaylist(int playlistIndex, int from, int to);
    Q_INVOKABLE void moveSongInPlaylist(int from, int to);

    Q_INVOKABLE void playIndex(int index);
    Q_INVOKABLE void playFromLibrary(int libraryIndex); // 搜索后播放：同步播放列表=音乐库并按原序播放
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
    bool isPlaying() const { return m_audioEngine && m_audioEngine->isPlaying(); }
    bool isLoading() const { return m_loading; }
    qreal importProgress() const { return m_importTotal > 0 ? qreal(m_importProcessed) / m_importTotal : 0.0; }
    int importProcessed() const { return m_importProcessed; }
    int importTotal() const { return m_importTotal; }

    QString currentTitle() const;
    QString currentArtist() const;
    QString currentCover() const { return m_currentCover; }
    QString currentCoverColor() const { return m_currentCoverColor; }
    QString currentAlbum() const;
    QVariantList currentLyrics() const { return m_currentLyrics; }
    int lyricIndex() const { return m_lyricIndex; }
    qreal detailOpacity() const { return m_detailOpacity; }
    void setDetailOpacity(qreal v);
    int lyricOffset() const { return m_lyricOffset; }
    void setLyricOffset(int v);
    qreal menuOpacity() const { return m_menuOpacity; }
    void setMenuOpacity(qreal v);
    qreal volumeMenuOpacity() const { return m_volumeMenuOpacity; }
    void setVolumeMenuOpacity(qreal v);

    // ---- 播放列表来源 ----
    int playlistSource() const { return m_playlistSource; }
    void setPlaylistSource(int source);
    QVariantList &currentPlaylist();  // 根据来源返回对应列表

    // ---- 跨来源跟踪 ----
    bool trackCrossSource() const { return m_trackCrossSource; }
    void setTrackCrossSource(bool v);

    // ---- 音量 ----
    qreal volume() const { return m_volume; }
    void setVolume(qreal vol);

    // ---- 关闭到系统托盘 ----
    bool minimizeToTray() const { return m_minimizeToTray; }
    void setMinimizeToTray(bool v);

    // ---- 播放背景 ----
    int playbackBackground() const { return m_playbackBackground; }
    void setPlaybackBackground(int v);

    // ---- 音频输出模式（WASAPI 独占/共享） ----
    bool wasapiExclusive() const { return m_wasapiExclusive; }
    void setWasapiExclusive(bool v);
    Q_INVOKABLE void retryWasapiExclusive();   // 重新尝试开启独占（弹窗"重新检测"）
    Q_INVOKABLE void forceWasapiExclusive();   // 跳过探测强制开启独占（弹窗"强制开启"，可能导致其他音视频软件崩溃）
    Q_INVOKABLE void disableWasapiExclusive(); // 关闭独占并持久化（弹窗"关闭独占模式"）

    // ---- 歌词字体 ----
    QString lyricFont() const { return m_lyricFont; }
    QString lyricFontFamily() const;             // 解析当前选择为可用字体族名（空串=回退默认）
    void setLyricFont(const QString &v);
    Q_INVOKABLE QVariantList builtinLyricFonts() const;  // 内置字体列表 [{file,label,family,key}]
    Q_INVOKABLE QVariantList systemLyricFonts() const;   // 系统字体列表 [{family,key}]

    // ---- 播放列表操作 ----
    Q_INVOKABLE void addToPlaylist(const QVariantMap &track);     // 追加单曲到播放列表
    Q_INVOKABLE void removeFromPlaylist(const QVariantMap &track); // 按路径从播放队列删除
    Q_INVOKABLE void copyToPlaylist(int source);                  // 将指定来源列表全部复制到播放列表

    // ---- 自定义播放列表 ----
    Q_INVOKABLE void createCustomPlaylist(const QString &name);
    Q_INVOKABLE void renameCustomPlaylist(int index, const QString &newName);
    Q_INVOKABLE void playCustomPlaylist(int playlistIndex, int songIndex);
    Q_INVOKABLE void deleteCustomPlaylist(int index);
    Q_INVOKABLE bool isValidPlaylistName(const QString &name) const;
    int playingListIndex() const { return m_playingListIndex; }
    QVariantList customPlaylists() const { return m_customPlaylists; }

    // ---- 歌手列表（复用自定义列表基础设施，type="artist"） ----
    Q_INVOKABLE QVariantList availableArtists() const;              // 从音乐库扫描去重后的歌手名列表
    Q_INVOKABLE void createArtistPlaylist(const QString &artist);   // 以歌手名创建列表并归类歌曲
    Q_INVOKABLE void refreshArtistPlaylist(int index);              // 重新扫描音乐库刷新歌手列表歌曲

    Q_INVOKABLE qint64 position() const { return m_audioEngine ? m_audioEngine->position() : 0; }
    Q_INVOKABLE qint64 duration() const { return m_audioEngine ? m_audioEngine->duration() : 0; }
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
    Q_INVOKABLE void clearUserData();

    // ---- 收藏 ----
    Q_INVOKABLE void toggleFavorite(const QVariantMap &track);   // 切换收藏（有则删，无则加）
    Q_INVOKABLE void removeFavorite(int index);                  // 按收藏列表索引删除
    Q_INVOKABLE bool isFavorite(const QVariantMap &track);       // 检查是否已收藏

    // ---- 历史 ----
    Q_INVOKABLE void addToHistory(const QVariantMap &track);     // 播放时自动调用
    Q_INVOKABLE void clearHistory();
    Q_INVOKABLE void removeHistoryItem(int index);

    // ---- 拖放支持 ----
    Q_INVOKABLE bool isDirectory(const QString &path) const;
    Q_INVOKABLE bool isAudioFile(const QString &path) const;

signals:
    void playlistChanged();
    void libraryChanged();
    void favoritesChanged();
    void historyChanged();
    void currentIndexChanged();
    void playbackStateChanged();
    void currentTrackChanged();
    void currentCoverColorChanged();
    void currentLyricsChanged();
    void lyricIndexChanged();
    void detailOpacityChanged();
    void lyricOffsetChanged();
    void playModeChanged();
    void menuOpacityChanged();
    void volumeMenuOpacityChanged();
    void playlistSourceChanged();
    void trackCrossSourceChanged();
    void minimizeToTrayChanged();
    void playbackBackgroundChanged();
    void volumeChanged();
    void wasapiExclusiveChanged();
    void lyricFontChanged();
    void wasapiExclusiveFailed();  // 启动时开启 WASAPI 独占失败（设备被占用），QML 应弹窗询问用户
    void exclusiveConfirmRequested();  // 启动时保存了开启独占：QML 先弹窗提示（识别精度有限），用户确认后再真正开启
    void customPlaylistsChanged();
    void playingListIndexChanged();
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
    void updateCurrentCoverColor();          // 从 m_currentCover 提取主色调
    static QString extractCoverColor(const QString &coverUrl);
    void registerBuiltinFonts();             // 启动时注册 data/font 内置字体，记录族名
    static QString builtinFontPath(const QString &file);  // 内置字体 qrc 路径
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
    void saveCustomPlaylists();
    void loadCustomPlaylists();
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
    qreal m_volumeMenuOpacity = 0.80; // 音量控制条透明度 (0.3-1.0)
    int m_playlistSource = 0;       // 活跃播放列表来源 (SourcePlaylist=0)
    bool m_trackCrossSource = false; // 跨来源播放跟踪（默认关闭）
    bool m_minimizeToTray = false;
    int m_playbackBackground = 0;   // 播放背景 (0=深色背景, 1=沉浸背景)
    qreal m_volume = 0.9;
    bool m_wasapiExclusive = false; // 音频输出模式: false=共享(默认), true=WASAPI 独占
    QString m_lyricFont = QStringLiteral("builtin:HarmonyOS_Sans_SC_Regular.ttf"); // 歌词字体选择键
    QMap<QString, QString> m_builtinFontFamilies;  // 内置字体 qrc 路径 -> 族名
    QVariantList m_customPlaylists;         // 自定义播放列表
    int m_playingListIndex = -1;            // -1=无, 0=库, 1=收藏, 2=历史, 3+n=自定义
    void loadSettings();
    void saveSettings();
    int m_currentIndex = -1;
    QString m_currentCover;
    QString m_currentCoverColor;   // 从封面提取的主色调（#RRGGBB），空串表示无封面
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

    // 导入时未识别到歌手 → 阻塞弹窗（QDialog）：返回 0=应用, 1=跳过, 2=取消
    int promptMissingInfo(const QString &filePath, const QString &defaultTitle,
                          QString *outTitle, QString *outArtist, QString *outAlbum);

    AudioEngine *m_audioEngine = nullptr;
};

#endif
