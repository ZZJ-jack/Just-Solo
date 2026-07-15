#include "MusicManager.h"
#include <QFileInfo>
#include <QDirIterator>
#include <QUrl>
#include <QStandardPaths>
#include <QCryptographicHash>
#include <QImage>
#include <QTimer>
#include <QEventLoop>
#include <QMediaMetaData>
#include <QCoreApplication>
#include <QMap>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QFile>

// ============================================================
// 工具函数
// ============================================================

static QStringList supportedAudioExtensions() {
    return {"*.mp3", "*.flac", "*.wav", "*.ogg", "*.aac", "*.m4a", "*.wma", "*.opus"};
}

static QString coverDir()
{
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/covers";
    QDir().mkpath(dir);
    return dir;
}

static QString findExternalCover(const QString &filePath)
{
    static QStringList names = {
        "cover.jpg", "cover.png", "cover.jpeg",
        "folder.jpg", "folder.png",
        "front.jpg", "front.png",
        "album.jpg", "album.png", "albumart.jpg"
    };
    QDir dir = QFileInfo(filePath).absoluteDir();
    for (const QString &name : names) {
        QString p = dir.filePath(name);
        if (QFileInfo::exists(p)) return p;
    }
    return "";
}

// 音质分级：根据编解码器/码率判定
// 极低 / 标准 / 高品质 / 无损 / 高解析 / 母带 / 空间音频
static QString detectQualityLabel(const QString &filePath, const QMediaPlayer &player)
{
    QString ext = QFileInfo(filePath).suffix().toLower();
    QString codec = player.metaData().value(QMediaMetaData::AudioCodec).toString().toLower();
    int bitrate = player.metaData().value(QMediaMetaData::AudioBitRate).toInt();   // bits/sec

    // 空间音频 (Dolby Atmos, etc.)
    if (codec.contains("atmos") || codec.contains("dolby") || codec.contains("eac3") || codec.contains("ac3"))
        return QStringLiteral("空间音频");

    // MQA 母带级
    if (codec.contains("mqa"))
        return QStringLiteral("母带");

    // 无损格式：FLAC / ALAC / WAV / APE
    bool lossless = (ext == "flac" || ext == "alac" || ext == "wav" || ext == "ape" ||
                     codec.contains("flac") || codec.contains("alac") ||
                     codec.contains("pcm") || codec.contains("ape"));
    if (lossless) {
        // 高解析：码率 > 2000 kbps (推测为 24-bit/192kHz)
        if (bitrate > 2000000)
            return QStringLiteral("高解析");
        // 无损：16-bit/44.1kHz
        return QStringLiteral("无损");
    }

    // 有损格式：按码率分级
    if (bitrate > 0) {
        if (bitrate >= 256000) return QStringLiteral("高品质");  // 256-320 kbps
        if (bitrate >= 128000) return QStringLiteral("标准");    // 128-160 kbps
        return QStringLiteral("极低");                           // 48-96 kbps
    }

    // 码率未知时，按扩展名推断
    if (ext == "mp3" || ext == "aac" || ext == "ogg" || ext == "opus" || ext == "wma")
        return QStringLiteral("标准");
    return QStringLiteral("标准");
}

// 音质等级排名（数值越高音质越好）
static int qualityRank(const QString &quality) {
    static QMap<QString, int> rank = {
        {QStringLiteral("极低"), 1},
        {QStringLiteral("标准"), 2},
        {QStringLiteral("高品质"), 3},
        {QStringLiteral("无损"), 4},
        {QStringLiteral("高解析"), 5},
        {QStringLiteral("母带"), 6},
        {QStringLiteral("空间音频"), 7}
    };
    return rank.value(quality, 0);
}

static QVariantMap buildTrack(const QString &filePath)
{
    QVariantMap track;
    QFileInfo fi(filePath);

    QMediaPlayer player;
    QAudioOutput audioOut;
    player.setAudioOutput(&audioOut);

    QEventLoop loop;
    QTimer debounce;
    debounce.setSingleShot(true);

    // metaDataChanged 后等 30ms 收齐
    QObject::connect(&player, &QMediaPlayer::metaDataChanged,
        [&]() { debounce.start(30); });
    QObject::connect(&debounce, &QTimer::timeout, &loop, &QEventLoop::quit);

    // 最大等待 1 秒
    QTimer fallbackTimer;
    fallbackTimer.setSingleShot(true);
    QObject::connect(&fallbackTimer, &QTimer::timeout, &loop, &QEventLoop::quit);

    player.setSource(QUrl::fromLocalFile(filePath));
    fallbackTimer.start(1000);
    loop.exec();

    // 提取元数据
    QString title  = player.metaData().value(QMediaMetaData::Title).toString();
    QString artist = player.metaData().value(QMediaMetaData::ContributingArtist).toString();
    if (artist.isEmpty())
        artist = player.metaData().value(QMediaMetaData::Author).toString();
    QString album  = player.metaData().value(QMediaMetaData::AlbumTitle).toString();
    int duration   = (int)(player.duration() / 1000);

    if (title.isEmpty() && artist.isEmpty()) {
        int sep = fi.baseName().indexOf(" - ");
        if (sep > 0) {
            artist = fi.baseName().left(sep).trimmed();
            title  = fi.baseName().mid(sep + 3).trimmed();
        }
    }
    if (title.isEmpty())
        title = fi.baseName();

    track["path"]     = fi.absoluteFilePath();
    track["name"]     = title;
    track["artist"]   = artist.isEmpty() ? "" : artist;
    track["album"]    = album.isEmpty() ? "" : album;
    track["duration"] = duration;
    track["quality"]  = detectQualityLabel(filePath, player);

    // 封面
    QImage coverImg;
    QMediaMetaData md = player.metaData();
    for (QMediaMetaData::Key k : {QMediaMetaData::CoverArtImage, QMediaMetaData::ThumbnailImage}) {
        QVariant v = md.value(k);
        if (v.isValid()) { coverImg = v.value<QImage>(); if (!coverImg.isNull()) break; }
    }
    if (coverImg.isNull()) {
        for (QMediaMetaData::Key k : md.keys()) {
            QImage img = md.value(k).value<QImage>();
            if (!img.isNull()) { coverImg = img; break; }
        }
    }
    if (!coverImg.isNull()) {
        QByteArray hash = QCryptographicHash::hash(filePath.toUtf8(), QCryptographicHash::Md5).toHex();
        QString cacheFile = coverDir() + "/" + QString::fromLatin1(hash) + ".jpg";
        if (coverImg.save(cacheFile, "JPEG"))
            track["cover"] = QUrl::fromLocalFile(cacheFile).toString();
    }
    if (!track.contains("cover") || track["cover"].toString().isEmpty()) {
        QString ext = findExternalCover(filePath);
        track["cover"] = ext.isEmpty() ? "" : QUrl::fromLocalFile(ext).toString();
    }

    return track;
}

// ============================================================
// MusicManager
// ============================================================

MusicManager::MusicManager(QObject *parent)
    : QObject(parent)
{
    m_player = new QMediaPlayer(this);
    m_audioOutput = new QAudioOutput(this);
    m_audioOutput->setVolume(1.0);  // 直通输出，不衰减
    m_player->setAudioOutput(m_audioOutput);

    m_loadTimer = new QTimer(this);
    m_loadTimer->setSingleShot(true);
    m_loadTimer->setInterval(0);
    connect(m_loadTimer, &QTimer::timeout, this, &MusicManager::processNextPending);

    connect(m_player, &QMediaPlayer::positionChanged, this, &MusicManager::positionChanged);
    connect(m_player, &QMediaPlayer::playbackStateChanged, this, &MusicManager::playbackStateChanged);
    connect(m_player, &QMediaPlayer::sourceChanged, this, &MusicManager::updateCurrentTrack);
    connect(m_player, &QMediaPlayer::mediaStatusChanged, this, [this](QMediaPlayer::MediaStatus s) {
        if (s == QMediaPlayer::LoadedMedia || s == QMediaPlayer::BufferedMedia)
            emit durationChanged();
    });
}

// ============================================================
// 缓存：持久化播放列表到用户目录（开发者模式跳过）
// ============================================================

void MusicManager::setUseCache(bool use) {
    m_useCache = use;
    if (!m_useCache) {
        // 开发者模式：删除已有持久化数据，每次启动从头开始
        QString devCache = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
        QDir(devCache).removeRecursively();
        return;
    }

    // 缓存目录：%APPDATA%/Just Solo （Windows）
    //            ~/.local/share/Just Solo （Linux / macOS）
    m_cacheDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(m_cacheDir);
    loadCache();
    loadFavorites();
    loadHistory();
}

// ---- 通用：QVariantList <-> JSON 文件读写 ----

static void writeVariantListToFile(const QVariantList &list, const QString &filePath) {
    QJsonArray arr;
    for (const QVariant &item : list) {
        QVariantMap map = item.toMap();
        QJsonObject obj;
        for (auto it = map.cbegin(); it != map.cend(); ++it)
            obj[it.key()] = QJsonValue::fromVariant(it.value());
        arr.append(obj);
    }
    QJsonDocument doc(arr);
    QFile file(filePath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        file.write(doc.toJson(QJsonDocument::Indented));
        file.close();
    }
}

static QVariantList readVariantListFromFile(const QString &filePath) {
    QVariantList result;
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) return result;
    QByteArray data = file.readAll();
    file.close();
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isArray()) return result;
    for (const QJsonValue &val : doc.array()) {
        QJsonObject obj = val.toObject();
        QVariantMap map;
        for (auto it = obj.begin(); it != obj.end(); ++it)
            map[it.key()] = it.value().toVariant();
        result.append(map);
    }
    return result;
}

// ---- 播放列表缓存 ----

void MusicManager::saveCache() {
    if (!m_useCache || m_cacheDir.isEmpty()) return;
    writeVariantListToFile(m_playlist, m_cacheDir + "/playlist_cache.json");
}

void MusicManager::loadCache() {
    if (!m_useCache || m_cacheDir.isEmpty()) return;
    QVariantList list = readVariantListFromFile(m_cacheDir + "/playlist_cache.json");
    bool removed = false;
    for (const QVariant &item : list) {
        QVariantMap map = item.toMap();
        // 文件已被删除/移动 → 跳过
        if (!QFileInfo::exists(map["path"].toString())) {
            removed = true;
            continue;
        }
        m_playlist.append(map);
    }
    if (removed) saveCache();
    if (!m_playlist.isEmpty())
        emit playlistChanged();
}

// ---- 收藏缓存 ----

void MusicManager::saveFavorites() {
    if (!m_useCache || m_cacheDir.isEmpty()) return;
    writeVariantListToFile(m_favorites, m_cacheDir + "/favorites_cache.json");
}

void MusicManager::loadFavorites() {
    if (!m_useCache || m_cacheDir.isEmpty()) return;
    m_favorites = readVariantListFromFile(m_cacheDir + "/favorites_cache.json");
    if (!m_favorites.isEmpty())
        emit favoritesChanged();
}

// ---- 历史缓存 ----

void MusicManager::saveHistory() {
    if (!m_useCache || m_cacheDir.isEmpty()) return;
    writeVariantListToFile(m_history, m_cacheDir + "/history_cache.json");
}

void MusicManager::loadHistory() {
    if (!m_useCache || m_cacheDir.isEmpty()) return;
    m_history = readVariantListFromFile(m_cacheDir + "/history_cache.json");
    if (!m_history.isEmpty())
        emit historyChanged();
}

void MusicManager::addFiles(const QStringList &paths) {
    m_pendingPaths.append(paths);
    if (!m_loading) {
        m_loading = true;
        m_importProcessed = 0;
        m_importTotal = paths.size();
        emit isLoadingChanged();
        emit importProgressChanged();
        m_loadTimer->start();
    } else {
        m_importTotal += paths.size();
        emit importProgressChanged();
    }
}

void MusicManager::processNextPending() {
    if (m_pendingPaths.isEmpty()) {
        m_loading = false;
        m_importProcessed = m_importTotal;
        emit isLoadingChanged();
        emit importProgressChanged();
        return;
    }

    QString path = m_pendingPaths.takeFirst();
    QVariantMap track = buildTrack(path);

    QString filePath = track["path"].toString();
    QString songKey = track["name"].toString() + "|||" + track["artist"].toString();
    int newQualityRank = qualityRank(track["quality"].toString());

    bool shouldAdd = true;
    bool playlistModified = false;

    for (int i = 0; i < m_playlist.size(); i++) {
        QVariantMap existing = m_playlist[i].toMap();

        // 1. 同一文件路径 → 跳过
        if (existing["path"].toString() == filePath) {
            shouldAdd = false;
            break;
        }

        // 2. 同一首歌（同名+同歌手）→ 保留音质更高的
        QString existingKey = existing["name"].toString() + "|||" + existing["artist"].toString();
        if (existingKey == songKey) {
            int existingQualityRank = qualityRank(existing["quality"].toString());
            if (newQualityRank > existingQualityRank) {
                // 新文件音质更高 → 替换
                m_playlist[i] = track;
                if (m_currentIndex == i) {
                    m_player->setSource(QUrl::fromLocalFile(track["path"].toString()));
                    if (m_player->playbackState() == QMediaPlayer::PlayingState)
                        m_player->play();
                    emit currentIndexChanged();
                }
                playlistModified = true;
            }
            shouldAdd = false;
            break;
        }
    }

    if (shouldAdd) {
        m_playlist.append(track);
        playlistModified = true;
    }

    if (playlistModified) {
        emit playlistChanged();
        saveCache();    // 有变更就持久化
    }

    m_importProcessed++;
    emit importProgressChanged();

    // 下一首排队（让出事件循环保持 UI 响应）
    m_loadTimer->start();
}

void MusicManager::addFolder(const QString &path) {
    scanFolder(path);
    emit playlistChanged();
}

void MusicManager::scanFolder(const QString &path) {
    QDir dir(path);
    if (!dir.exists()) return;

    QStringList paths;
    for (const QString &ext : supportedAudioExtensions()) {
        QDirIterator it(path, QStringList{ext}, QDir::Files | QDir::Readable, QDirIterator::Subdirectories);
        while (it.hasNext()) {
            it.next();
            paths.append(it.filePath());
        }
    }
    addFiles(paths);
}

void MusicManager::removeTrack(int index) {
    if (index < 0 || index >= m_playlist.size()) return;
    m_playlist.removeAt(index);
    if (m_currentIndex == index) {
        m_currentIndex = -1;
        m_player->stop();
        emit currentIndexChanged();
    } else if (m_currentIndex > index) {
        m_currentIndex--;
    }
    emit playlistChanged();
    saveCache();
}

void MusicManager::clearPlaylist() {
    m_playlist.clear();
    m_currentIndex = -1;
    m_player->stop();
    emit playlistChanged();
    saveCache();
    emit currentIndexChanged();
}

void MusicManager::playIndex(int index) {
    if (index < 0 || index >= m_playlist.size()) return;
    m_currentIndex = index;
    QVariantMap track = m_playlist[index].toMap();
    QUrl url = QUrl::fromLocalFile(track["path"].toString());
    m_player->setSource(url);
    m_player->play();
    emit currentIndexChanged();
    // 自动加入历史（最近播放）
    addToHistory(track);
}

void MusicManager::play() {
    if (m_currentIndex >= 0 && m_currentIndex < m_playlist.size()) {
        m_player->play();
    }
}

void MusicManager::pause() {
    m_player->pause();
}

void MusicManager::stop() {
    m_player->stop();
}

void MusicManager::next() {
    if (m_playlist.isEmpty()) return;
    int nextIdx = (m_currentIndex + 1) % m_playlist.size();
    playIndex(nextIdx);
}

void MusicManager::previous() {
    if (m_playlist.isEmpty()) return;
    int prevIdx = m_currentIndex <= 0 ? m_playlist.size() - 1 : m_currentIndex - 1;
    playIndex(prevIdx);
}

void MusicManager::updateCurrentTrack() {
    if (m_currentIndex >= 0 && m_currentIndex < m_playlist.size()) {
        QVariantMap track = m_playlist[m_currentIndex].toMap();
        m_currentCover = track["cover"].toString();
    }
    emit currentTrackChanged();
}

QString MusicManager::currentTitle() const {
    if (m_currentIndex < 0 || m_currentIndex >= m_playlist.size()) return "";
    return m_playlist[m_currentIndex].toMap()["name"].toString();
}

QString MusicManager::currentArtist() const {
    if (m_currentIndex < 0 || m_currentIndex >= m_playlist.size()) return "";
    return m_playlist[m_currentIndex].toMap()["artist"].toString();
}

qint64 MusicManager::position() const {
    return m_player ? m_player->position() : 0;
}

qint64 MusicManager::duration() const {
    return m_player ? m_player->duration() : 0;
}

void MusicManager::seek(qint64 ms) {
    if (m_player) m_player->setPosition(ms);
}

// ============================================================
// 收藏
// ============================================================

void MusicManager::toggleFavorite(const QVariantMap &track) {
    QString path = track["path"].toString();
    for (int i = 0; i < m_favorites.size(); i++) {
        if (m_favorites[i].toMap()["path"].toString() == path) {
            m_favorites.removeAt(i);
            saveFavorites();
            emit favoritesChanged();
            return;
        }
    }
    // 不存在则添加
    m_favorites.prepend(track);
    saveFavorites();
    emit favoritesChanged();
}

void MusicManager::removeFavorite(int index) {
    if (index < 0 || index >= m_favorites.size()) return;
    m_favorites.removeAt(index);
    saveFavorites();
    emit favoritesChanged();
}

bool MusicManager::isFavorite(const QVariantMap &track) {
    QString path = track["path"].toString();
    for (const QVariant &item : m_favorites) {
        if (item.toMap()["path"].toString() == path)
            return true;
    }
    return false;
}

// ============================================================
// 历史（最近播放）
// ============================================================

void MusicManager::addToHistory(const QVariantMap &track) {
    // 去重：同一文件移到最前面
    QString path = track["path"].toString();
    for (int i = 0; i < m_history.size(); i++) {
        if (m_history[i].toMap()["path"].toString() == path) {
            m_history.removeAt(i);
            break;
        }
    }
    // 限制最大 500 条
    while (m_history.size() >= 500)
        m_history.removeLast();
    m_history.prepend(track);
    saveHistory();
    emit historyChanged();
}

void MusicManager::clearHistory() {
    m_history.clear();
    saveHistory();
    emit historyChanged();
}

void MusicManager::removeHistoryItem(int index) {
    if (index < 0 || index >= m_history.size()) return;
    m_history.removeAt(index);
    saveHistory();
    emit historyChanged();
}
