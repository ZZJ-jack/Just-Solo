#include "MusicManager.h"
#include "MetadataReader.h"
#include <QFileInfo>
#include <QDirIterator>
#include <QUrl>
#include <QStandardPaths>
#include <QCryptographicHash>
#include <QImage>
#include <QTimer>
#include <QRandomGenerator>
#include <QEventLoop>
#include <QMediaMetaData>
#include <algorithm>
#include <QCoreApplication>
#include <QMap>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QFile>
#include <QTextStream>
#include <QStringConverter>
#include <QRegularExpression>
#include <algorithm>

// ============================================================
// 工具函数
// ============================================================

// 判断文本是否看起来像翻译（非 CJK 字符占主导 → 很可能是英文翻译）
static bool looksLikeTranslation(const QString &text) {
    if (text.isEmpty()) return false;
    int cjk = 0, latin = 0;
    for (const QChar &ch : text) {
        ushort u = ch.unicode();
        if ((u >= 0x4E00 && u <= 0x9FFF) || (u >= 0x3400 && u <= 0x4DBF) ||
            (u >= 0x3040 && u <= 0x309F) || (u >= 0x30A0 && u <= 0x30FF) ||
            (u >= 0xAC00 && u <= 0xD7AF))
            ++cjk;
        else if ((u >= 'A' && u <= 'Z') || (u >= 'a' && u <= 'z'))
            ++latin;
    }
    // 拉丁字母明显多于 CJK → 翻译行
    return latin > 0 && latin >= cjk;
}

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

// 根据文件扩展名猜测音质（快路径用，无 QMediaPlayer 开销）
static QString guessQualityFromExtension(const QFileInfo &fi) {
    QString ext = fi.suffix().toLower();
    qint64 size = fi.size();
    if (ext == "flac") return QStringLiteral("无损");
    if (ext == "wav")  return size > 50 * 1024 * 1024 ? QStringLiteral("高解析") : QStringLiteral("无损");
    if (ext == "ape")  return QStringLiteral("无损");
    if (ext == "dsf" || ext == "dff") return QStringLiteral("高解析");
    if (ext == "m4a" || ext == "alac") return QStringLiteral("高品质");
    if (ext == "mp3") {
        if (size > 10 * 1024 * 1024) return QStringLiteral("高品质");
        return QStringLiteral("标准");
    }
    return QStringLiteral("标准");
}

static QString normalizeArtist(const QString &raw) {
    QString s = raw;
    s.replace(QRegularExpression("[/;｜|]"), QStringLiteral("、"));
    return s;
}

static QVariantMap buildTrack(const QString &filePath)
{
    QVariantMap track;
    QFileInfo fi(filePath);

    // ---- 快路径：MetadataReader 二进制解析（无 QMediaPlayer 开销） ----
    QString ext = fi.suffix().toLower();
    bool fastPath = (ext == "mp3" || ext == "flac" || ext == "m4a" || ext == "mp4");

    if (fastPath) {
        AudioMetadata meta = MetadataReader::read(filePath, coverDir());

        if (!meta.title.isEmpty()) {
            // 时长从 QMediaPlayer 获取（准），其他元数据用 MetadataReader（快）
            int dur = 0;
            QString durText;
            QString cover;
            if (!meta.coverPath.isEmpty())
                cover = QUrl::fromLocalFile(meta.coverPath).toString();

            // 统一用 QMediaPlayer 提取时长 + 兜底封面
            {
                QMediaPlayer player;
                QAudioOutput audioOut;
                player.setAudioOutput(&audioOut);
                QEventLoop loop;
                QTimer t; t.setSingleShot(true);
                QObject::connect(&player, &QMediaPlayer::mediaStatusChanged, [&](QMediaPlayer::MediaStatus s) {
                    if (s == QMediaPlayer::LoadedMedia || s == QMediaPlayer::BufferedMedia)
                        t.start(30);
                });
                QObject::connect(&t, &QTimer::timeout, &loop, &QEventLoop::quit);
                QTimer fb; fb.setSingleShot(true);
                QObject::connect(&fb, &QTimer::timeout, &loop, &QEventLoop::quit);
                player.setSource(QUrl::fromLocalFile(filePath));
                fb.start(2000);
                loop.exec();

                dur = (int)(player.duration() / 1000);
                if (dur > 0 && dur <= 3600)
                    durText = QString("%1:%2").arg(dur / 60).arg(dur % 60, 2, 10, QChar('0'));

                // 封面兜底
                if (cover.isEmpty()) {
                    QImage coverImg;
                    QMediaMetaData md = player.metaData();
                    for (QMediaMetaData::Key k : {QMediaMetaData::CoverArtImage, QMediaMetaData::ThumbnailImage}) {
                        QVariant v = md.value(k);
                        if (v.isValid()) { coverImg = v.value<QImage>(); if (!coverImg.isNull()) break; }
                    }
                    if (!coverImg.isNull()) {
                        QByteArray hash = QCryptographicHash::hash(filePath.toUtf8(), QCryptographicHash::Md5).toHex();
                        QString cacheFile = coverDir() + "/" + QString::fromLatin1(hash) + ".jpg";
                        if (coverImg.save(cacheFile, "JPEG"))
                            cover = QUrl::fromLocalFile(cacheFile).toString();
                    }
                    if (cover.isEmpty()) {
                        QString extCover = findExternalCover(filePath);
                        if (!extCover.isEmpty())
                            cover = QUrl::fromLocalFile(extCover).toString();
                    }
                }
            }

            track["path"]         = fi.absoluteFilePath();
            track["name"]         = meta.title;
            track["artist"]       = normalizeArtist(meta.artist);
            track["album"]        = meta.album;
            track["duration"]     = dur;
            track["durationText"] = durText;
            track["cover"]        = cover;
            track["quality"]      = guessQualityFromExtension(fi);
            return track;
        }
    }

    // ---- 慢路径：QMediaPlayer 回退（.ogg/.wav/.opus 等或快路径失败） ----
    QMediaPlayer player;
    QAudioOutput audioOut;
    player.setAudioOutput(&audioOut);

    QEventLoop loop;
    QTimer debounce;
    debounce.setSingleShot(true);

    QObject::connect(&player, &QMediaPlayer::metaDataChanged,
        [&]() { debounce.start(30); });
    QObject::connect(&debounce, &QTimer::timeout, &loop, &QEventLoop::quit);

    QTimer fallbackTimer;
    fallbackTimer.setSingleShot(true);
    QObject::connect(&fallbackTimer, &QTimer::timeout, &loop, &QEventLoop::quit);

    player.setSource(QUrl::fromLocalFile(filePath));
    fallbackTimer.start(1000);
    loop.exec();

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

    QString durText;
    if (duration > 0)
        durText = QString("%1:%2").arg(duration / 60).arg(duration % 60, 2, 10, QChar('0'));

    track["path"]     = fi.absoluteFilePath();
    track["name"]     = title;
    track["artist"]   = normalizeArtist(artist.isEmpty() ? "" : artist);
    track["album"]    = album.isEmpty() ? "" : album;
    track["duration"] = duration;
    track["durationText"] = durText;
    track["quality"]  = detectQualityLabel(filePath, player);

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
    m_audioOutput->setVolume(0.9); // 留 10% 余量，防止数字削波爆音
    m_player->setAudioOutput(m_audioOutput);

    m_loadTimer = new QTimer(this);
    m_loadTimer->setSingleShot(true);
    m_loadTimer->setInterval(0);
    connect(m_loadTimer, &QTimer::timeout, this, &MusicManager::processNextPending);

    // 歌词索引防抖：positionChanged 很频繁（~10-60次/秒）
    // 用 30ms debounce 聚合成最多约 33 次/秒的歌词更新，大幅减少重复遍历开销
    m_lyricTimer = new QTimer(this);
    m_lyricTimer->setSingleShot(true);
    m_lyricTimer->setInterval(30);
    connect(m_lyricTimer, &QTimer::timeout, this, &MusicManager::updateLyricIndex);

    connect(m_player, &QMediaPlayer::positionChanged, this, [this](qint64 pos) {
        emit positionChanged(pos);
        m_lyricTimer->start();  // 防抖，不会重复触发
    });
    connect(m_player, &QMediaPlayer::playbackStateChanged, this, &MusicManager::playbackStateChanged);
    connect(m_player, &QMediaPlayer::sourceChanged, this, &MusicManager::updateCurrentTrack);
    connect(m_player, &QMediaPlayer::mediaStatusChanged, this, [this](QMediaPlayer::MediaStatus s) {
        if (s == QMediaPlayer::LoadedMedia || s == QMediaPlayer::BufferedMedia) {
            // 用真实播放时长修正列表中的 duration
            qint64 dur = m_player ? m_player->duration() : 0;
            if (dur > 0 && m_currentIndex >= 0 && m_currentIndex < m_playlist.size()) {
                QVariantMap track = m_playlist[m_currentIndex].toMap();
                int durSec = (int)(dur / 1000);
                if (durSec > 0 && durSec <= 3600) {
                    track["duration"] = durSec;
                    track["durationText"] = QString("%1:%2")
                        .arg(durSec / 60).arg(durSec % 60, 2, 10, QChar('0'));
                    m_playlist[m_currentIndex] = track;
                    emit playlistChanged();
                }
            }
            emit durationChanged();
        }
        else if (s == QMediaPlayer::EndOfMedia) {
            // 根据播放模式决定下一步
            if (m_playMode == SingleLoop) {
                m_player->play();  // 单曲循环：从头播放
            } else if (m_playMode == StopAfter) {
                m_player->stop();  // 关闭循环：停止
            } else {
                next();  // 顺序/列表循环/随机：下一首
            }
        }
    });
    // 嵌入式歌词：等媒体元数据加载完成后尝试提取
    connect(m_player, &QMediaPlayer::metaDataChanged, this, &MusicManager::onMetaDataChanged);
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
    loadSettings();
    loadCache();
    loadFavorites();
    loadHistory();
}

// ---- 设置文件（透明度等） ----

void MusicManager::loadSettings() {
    if (m_cacheDir.isEmpty()) return;
    QFile file(m_cacheDir + "/settings.json");
    if (!file.open(QIODevice::ReadOnly)) return;
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();
    if (!doc.isObject()) return;
    QJsonObject obj = doc.object();
    if (obj.contains("detailOpacity")) {
        m_detailOpacity = obj.value("detailOpacity").toDouble(m_detailOpacity);
        emit detailOpacityChanged();
    }
    if (obj.contains("lyricOffset")) {
        m_lyricOffset = obj.value("lyricOffset").toInt(m_lyricOffset);
        emit lyricOffsetChanged();
    }
    if (obj.contains("playMode")) {
        m_playMode = obj.value("playMode").toInt(m_playMode);
        emit playModeChanged();
    }
    if (obj.contains("menuOpacity")) {
        m_menuOpacity = obj.value("menuOpacity").toDouble(m_menuOpacity);
        emit menuOpacityChanged();
    }
    if (obj.contains("trackCrossSource")) {
        m_trackCrossSource = obj.value("trackCrossSource").toBool(false);
        emit trackCrossSourceChanged();
    }
}

void MusicManager::saveSettings() {
    if (m_cacheDir.isEmpty()) return;
    QJsonObject obj;
    obj["detailOpacity"] = m_detailOpacity;
    obj["lyricOffset"] = m_lyricOffset;
    obj["playMode"] = m_playMode;
    obj["menuOpacity"] = m_menuOpacity;
    obj["trackCrossSource"] = m_trackCrossSource;
    QJsonDocument doc(obj);
    QFile file(m_cacheDir + "/settings.json");
    if (file.open(QIODevice::WriteOnly)) {
        file.write(doc.toJson());
        file.close();
    }
}

void MusicManager::setDetailOpacity(qreal v) {
    v = qBound(0.3, v, 1.0);
    if (qFuzzyCompare(v, m_detailOpacity)) return;
    m_detailOpacity = v;
    emit detailOpacityChanged();
    saveSettings();
}

void MusicManager::setLyricOffset(int v) {
    v = qBound(-500, v, 500);
    if (v == m_lyricOffset) return;
    m_lyricOffset = v;
    emit lyricOffsetChanged();
    saveSettings();
}

void MusicManager::setMenuOpacity(qreal v) {
    v = qBound(0.3, v, 1.0);
    if (qFuzzyCompare(v, m_menuOpacity)) return;
    m_menuOpacity = v;
    emit menuOpacityChanged();
    saveSettings();
}

void MusicManager::setTrackCrossSource(bool v) {
    if (v == m_trackCrossSource) return;
    m_trackCrossSource = v;
    emit trackCrossSourceChanged();
    saveSettings();
}

void MusicManager::setPlayMode(int mode) {
    if (mode < 0 || mode > 4 || mode == m_playMode) return;
    m_playMode = mode;
    emit playModeChanged();
    saveSettings();
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
    writeVariantListToFile(m_library, m_cacheDir + "/playlist_cache.json");
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
        m_library.append(map);
    }
    if (removed) saveCache();
    // 播放列表初始化为音乐库的副本
    m_playlist = m_library;
    // 播放列表未恢复时也同步（兜底）
    if (m_playlist.isEmpty() && !m_library.isEmpty()) {
        m_playlist = m_library;
    }
    if (!m_playlist.isEmpty())
        emit playlistChanged();
    if (!m_library.isEmpty())
        emit libraryChanged();
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

    // 批处理：每轮处理最多 BATCH_SIZE 个快路径文件，减少事件循环轮次
    static const int BATCH_SIZE = 8;
    int processed = 0;
    bool playlistModified = false;

    while (!m_pendingPaths.isEmpty() && processed < BATCH_SIZE) {
        QString path = m_pendingPaths.takeFirst();
        QVariantMap track = buildTrack(path);

        QString filePath = track["path"].toString();
        QString songKey = track["name"].toString() + "|||" + track["artist"].toString();
        int newQualityRank = qualityRank(track["quality"].toString());

        bool shouldAdd = true;

        for (int i = 0; i < m_library.size(); i++) {
            QVariantMap existing = m_library[i].toMap();

            if (existing["path"].toString() == filePath) {
                shouldAdd = false;
                break;
            }

            QString existingKey = existing["name"].toString() + "|||" + existing["artist"].toString();
            if (existingKey == songKey) {
                int existingQualityRank = qualityRank(existing["quality"].toString());
                if (newQualityRank > existingQualityRank) {
                    m_library[i] = track;
                    m_playlist[i] = track;  // 同步更新播放列表中的高音质版本
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
            m_library.append(track);
            m_playlist.append(track);
            playlistModified = true;
        }

        m_importProcessed++;
        processed++;
    }

    // 批量发一次信号，减少 QML 绑定刷新次数
    if (playlistModified) {
        emit playlistChanged();
        emit libraryChanged();
        saveCache();
    }
    emit importProgressChanged();

    // 如果批量里遇到了慢路径文件（QMediaPlayer），提前结束本轮让 UI 刷新
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
    // 同时从音乐库中删除
    QString rmPath = m_playlist[index].toMap()["path"].toString();
    for (int i = 0; i < m_library.size(); i++) {
        if (m_library[i].toMap()["path"].toString() == rmPath) {
            m_library.removeAt(i);
            emit libraryChanged();
            break;
        }
    }
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
    m_playlistSource = 0;
    m_currentCover.clear();            // 清空封面
    m_currentAlbum.clear();            // 清空专辑
    m_player->stop();
    emit playlistChanged();
    emit playlistSourceChanged();
    emit currentIndexChanged();
    emit currentTrackChanged();         // 强制 QML 底部栏全清
}

QVariantList &MusicManager::currentPlaylist() {
    switch (m_playlistSource) {
        case 1: return m_favorites;
        case 2: return m_history;
        default: return m_playlist;
    }
}

void MusicManager::playIndex(int index) {
    QVariantList &list = currentPlaylist();
    if (m_playlistSource == 0 && list.isEmpty() && !m_library.isEmpty()) {
        m_playlist = m_library;
        list = m_playlist;
        emit playlistChanged();
    }
    if (index < 0 || index >= list.size()) return;
    m_currentIndex = index;
    QVariantMap track = list[index].toMap();
    QUrl url = QUrl::fromLocalFile(track["path"].toString());
    m_currentCover = track["cover"].toString();
    m_currentAlbum = track["album"].toString();
    m_player->setSource(url);
    m_player->play();
    emit currentIndexChanged();
    emit currentTrackChanged();
    addToHistory(track);
}

void MusicManager::playFromLibrary(int libraryIndex) {
    if (libraryIndex < 0 || libraryIndex >= m_library.size()) return;

    // 同步播放列表 = 音乐库，不改变顺序
    m_playlist = m_library;
    m_playlistSource = 0;
    emit playlistSourceChanged();
    emit playlistChanged();

    // 直接播放（同步后 playlist 索引与 library 一致）
    playIndex(libraryIndex);
}

void MusicManager::setPlaylistSource(int source) {
    if (source < 0 || source > 2 || source == m_playlistSource) {
        if (source == 0 && m_playlist.isEmpty() && !m_library.isEmpty()) {
            m_playlist = m_library;
            emit playlistChanged();
        }
        return;
    }
    if (source == 0 && m_playlist.isEmpty() && !m_library.isEmpty()) {
        m_playlist = m_library;
        emit playlistChanged();
    }
    m_playlistSource = source;
    m_currentIndex = -1;
    emit playlistSourceChanged();
}

void MusicManager::addToPlaylist(const QVariantMap &track) {
    if (track.isEmpty() || track["path"].toString().isEmpty()) return;
    QString path = track["path"].toString();
    for (const QVariant &item : m_playlist) {
        if (item.toMap()["path"].toString() == path) return;
    }
    m_playlist.append(track);
    saveCache();
    emit playlistChanged();
}

void MusicManager::removeFromPlaylist(const QVariantMap &track) {
    QString path = track["path"].toString();
    if (path.isEmpty()) return;
    for (int i = 0; i < m_playlist.size(); i++) {
        if (m_playlist[i].toMap()["path"].toString() == path) {
            m_playlist.removeAt(i);
            if (m_playlistSource == 0 && m_currentIndex == i) {
                // 正在播放的曲目被删 → 全部清空
                m_currentIndex = -1;
                m_currentCover.clear();
                m_currentAlbum.clear();
                m_player->stop();
                emit currentIndexChanged();
                emit currentTrackChanged();
            } else if (m_playlistSource == 0 && m_currentIndex > i) {
                m_currentIndex--;
            }
            emit playlistChanged();
            return;
        }
    }
}

void MusicManager::copyToPlaylist(int source) {
    QVariantList sourceList;
    switch (source) {
        case 1: sourceList = m_favorites; break;
        case 2: sourceList = m_history; break;
        default: return;  // source=0 (already playlist) is a no-op
    }
    if (sourceList.isEmpty()) return;
    m_playlist = sourceList;
    m_playlistSource = 0;   // 切换为播放列表
    m_currentIndex = -1;
    saveCache();
    emit playlistChanged();
    emit playlistSourceChanged();
}

void MusicManager::play() {
    QVariantList &list = currentPlaylist();
    if (m_currentIndex >= 0 && m_currentIndex < list.size()) {
        m_player->play();
    }
}

void MusicManager::pause() {
    m_player->pause();
}

void MusicManager::stop() {
    m_player->stop();
    releaseOriginalCover();
}

void MusicManager::shutdown() {
    m_player->stop();
    m_loadTimer->stop();
    m_lyricTimer->stop();
    releaseOriginalCover();
}

void MusicManager::next() {
    QVariantList &list = currentPlaylist();
    if (list.isEmpty()) return;
    int nextIdx;
    if (m_playMode == Shuffle) {
        nextIdx = QRandomGenerator::global()->bounded(list.size());
    } else if (m_playMode == Sequential && m_currentIndex + 1 >= list.size()) {
        m_player->stop();
        emit playbackStateChanged();
        return;
    } else {
        nextIdx = (m_currentIndex + 1) % list.size();
    }
    playIndex(nextIdx);
}

void MusicManager::previous() {
    QVariantList &list = currentPlaylist();
    if (list.isEmpty()) return;
    int prevIdx = m_currentIndex <= 0 ? list.size() - 1 : m_currentIndex - 1;
    playIndex(prevIdx);
}

void MusicManager::updateCurrentTrack() {
    QVariantList &list = currentPlaylist();
    if (m_currentIndex >= 0 && m_currentIndex < list.size()) {
        QVariantMap track = list[m_currentIndex].toMap();
        m_currentCover = track["cover"].toString();
        m_currentAlbum = track["album"].toString();
        m_currentMediaPath = track["path"].toString();
        // 加载歌词
        m_currentLyrics = loadLyricsForFile(m_currentMediaPath);
        rebuildLyricCache();
        m_lyricIndex = -1;
        m_embeddedLyricsLoaded = false;  // 等待 metaDataChanged 回调
    } else {
        m_currentCover.clear();
        m_currentAlbum.clear();
        m_currentMediaPath.clear();
        m_currentLyrics.clear();
    }
    emit currentTrackChanged();
    emit currentLyricsChanged();
}

// ---- C++ 端计算歌词索引（纯整数比较，零分配） ----
void MusicManager::updateLyricIndex() {
    if (m_lyricCache.isEmpty()) {
        if (m_lyricIndex != -1) {
            m_lyricIndex = -1;
            emit lyricIndexChanged();
        }
        return;
    }

    qint64 pos = m_player ? m_player->position() + m_lyricOffset : 0;
    int newIdx = -1;

    for (int i = 0; i < m_lyricCache.size(); i++) {
        const auto &e = m_lyricCache[i];
        if (e.time <= pos + e.offset)
            newIdx = i;
        else
            break;
    }

    if (newIdx != m_lyricIndex) {
        m_lyricIndex = newIdx;
        emit lyricIndexChanged();
    }
}

// ---- 歌词预编译缓存：将 QVariantList 转为纯整数数组，消除播放时的分配开销 ----
void MusicManager::rebuildLyricCache() {
    m_lyricCache.clear();
    m_lyricCache.reserve(m_currentLyrics.size());
    for (const auto &item : m_currentLyrics) {
        QVariantMap map = item.toMap();
        LyricEntry e;
        e.time = map["time"].toInt();
        e.offset = qint64(2.15 * map["text"].toString().length());
        m_lyricCache.append(e);
    }
}

// ---- 从音频文件二进制数据中提取嵌入式歌词 ----
static QString extractEmbeddedLyricsFromFile(const QString &filePath) {
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) return {};

    QByteArray data = file.readAll();
    file.close();
    if (data.isEmpty()) return {};

    // === MP3 ID3v2 USLT (Unsynchronized Lyrics) ===
    if (data.startsWith("ID3")) {
        // 读取 ID3v2 头大小（syncsafe 编码）
        quint32 tagSize = 0;
        for (int i = 6; i <= 9; ++i) {
            tagSize = (tagSize << 7) | (static_cast<quint8>(data[i]) & 0x7F);
        }
        tagSize += 10; // 加上头本身

        if (tagSize > static_cast<quint32>(data.size())) tagSize = data.size();

        // 遍历 ID3v2 帧
        int pos = 10; // 跳过头部
        while (pos + 10 <= static_cast<int>(tagSize)) {
            QString frameId = QString::fromLatin1(data.mid(pos, 4));
            // 帧大小: ID3v2.3 中是 4 字节大端，ID3v2.4 中也是 4 字节大端
            quint32 frameSize = static_cast<quint8>(data[pos + 4]) << 24
                              | static_cast<quint8>(data[pos + 5]) << 16
                              | static_cast<quint8>(data[pos + 6]) << 8
                              | static_cast<quint8>(data[pos + 7]);
            // quint16 frameFlags = (static_cast<quint8>(data[pos + 8]) << 8) | static_cast<quint8>(data[pos + 9]);

            if (frameSize == 0) break; // 空帧
            if (pos + 10 + static_cast<int>(frameSize) > static_cast<int>(tagSize)) break;

            if (frameId == "USLT") {
                // USLT 帧: encoding(1B) + language(3B) + descriptor(null-terminated) + lyrics
                int dataPos = pos + 10;
                int dataEnd = dataPos + frameSize;

                // 跳过 encoding(1B) + language(3B)
                int textStart = dataPos + 4;

                // 跳过 content descriptor（null-terminated）
                while (textStart < dataEnd && data[textStart] != '\0') ++textStart;
                if (textStart < dataEnd) ++textStart; // 跳过 null

                // 提取歌词文本
                quint8 encoding = static_cast<quint8>(data[dataPos]);
                QString lyrics;
                QByteArray lyricBytes = data.mid(textStart, dataEnd - textStart);
                if (encoding == 0) {
                    // ISO-8859-1
                    lyrics = QString::fromLatin1(lyricBytes).trimmed();
                } else if (encoding == 1 || encoding == 2) {
                    // UTF-16 with BOM or UTF-16BE
                    lyrics = QString::fromUtf16(
                        reinterpret_cast<const char16_t*>(lyricBytes.constData()),
                        lyricBytes.size() / 2).trimmed();
                } else if (encoding == 3) {
                    // UTF-8
                    lyrics = QString::fromUtf8(lyricBytes).trimmed();
                }

                if (!lyrics.isEmpty()) return lyrics;
            }

            pos += 10 + frameSize;
        }
    }

    // === FLAC Vorbis Comment ===
    if (data.startsWith("fLaC")) {
        int pos = 4; // 跳过 "fLaC"
        while (pos + 4 <= data.size()) {
            quint8 blockType = static_cast<quint8>(data[pos]) & 0x7F;
            quint32 blockLen = (static_cast<quint8>(data[pos + 1]) << 16)
                             | (static_cast<quint8>(data[pos + 2]) << 8)
                             | static_cast<quint8>(data[pos + 3]);
            bool isLast = (static_cast<quint8>(data[pos]) & 0x80) != 0;

            if (blockType == 4) { // Vorbis Comment
                int vcPos = pos + 4;
                int vcEnd = vcPos + blockLen;

                // 读取 vendor string 长度并跳过
                if (vcPos + 4 > vcEnd) break;
                quint32 vendorLen = *reinterpret_cast<const quint32*>(data.constData() + vcPos);
                vcPos += 4 + vendorLen;
                if (vcPos + 4 > vcEnd) break;

                // 读取注释数量
                quint32 numComments = *reinterpret_cast<const quint32*>(data.constData() + vcPos);
                vcPos += 4;

                for (quint32 i = 0; i < numComments && vcPos + 4 <= vcEnd; ++i) {
                    quint32 commentLen = *reinterpret_cast<const quint32*>(data.constData() + vcPos);
                    vcPos += 4;
                    if (vcPos + static_cast<int>(commentLen) > vcEnd) break;

                    QByteArray comment = data.mid(vcPos, commentLen);
                    vcPos += commentLen;

                    // 查找 "LYRICS="
                    if (comment.toUpper().startsWith("LYRICS=")) {
                        QString lyrics = QString::fromUtf8(comment.mid(7)).trimmed();
                        if (!lyrics.isEmpty()) return lyrics;
                    }
                }
            }

            if (isLast) break;
            pos += 4 + blockLen;
        }
    }

    return {};
}

// ---- 从媒体元数据中提取嵌入式歌词 ----
void MusicManager::onMetaDataChanged() {
    if (m_embeddedLyricsLoaded) return;

    // 优先使用外部 .lrc 文件
    if (!m_currentLyrics.isEmpty()) {
        m_embeddedLyricsLoaded = true;
        return;
    }

    // 从文件二进制数据中提取嵌入式歌词（兼容 Qt 6.8 无 Lyrics 键）
    if (!m_currentMediaPath.isEmpty()) {
        QString lyrics = extractEmbeddedLyricsFromFile(m_currentMediaPath);
        if (!lyrics.isEmpty()) {
            m_currentLyrics = parseEmbeddedLyrics(lyrics);
            rebuildLyricCache();
            if (!m_currentLyrics.isEmpty()) {
                m_lyricIndex = -1;
                emit currentLyricsChanged();
                emit lyricIndexChanged();
            }
        }
    }

    m_embeddedLyricsLoaded = true;
}

// ============================================================
// 歌词解析工具函数
// ============================================================

// lrc 时间标签解析: [mm:ss.xx] 或 [mm:ss]
static int parseLrcTime(const QString &tag) {
    // tag 形如 "[01:23.45]" 或 "[01:23]"
    QString inner = tag.mid(1, tag.length() - 2);  // 去掉 [ ]
    int colonIdx = inner.indexOf(':');
    if (colonIdx < 0) return -1;
    int minutes = inner.left(colonIdx).toInt();
    QString secPart = inner.mid(colonIdx + 1);
    // 处理 "12.34" 或 "12"
    int dotIdx = secPart.indexOf('.');
    int seconds = 0, centiseconds = 0;
    if (dotIdx >= 0) {
        seconds = secPart.left(dotIdx).toInt();
        QString cs = secPart.mid(dotIdx + 1);
        if (cs.length() == 1) cs += '0';       // "5" → "50" 百分秒
        else if (cs.length() == 3) {            // "665" → 665 毫秒
            int ms = cs.toInt();
            return minutes * 60000 + seconds * 1000 + ms;
        }
        centiseconds = cs.toInt();               // 2位 = 百分秒
    } else {
        seconds = secPart.toInt();
    }
    return minutes * 60000 + seconds * 1000 + centiseconds * 10;
}

// ---- 解析嵌入式歌词文本（可能是 LRC 格式或纯文本） ----
QVariantList MusicManager::parseEmbeddedLyrics(const QString &text) {
    QVariantList result;
    if (text.isEmpty()) return result;

    // 检查是否包含 LRC 时间标签
    static QRegularExpression lrcRx(R"(\[\d{1,3}:\d{1,3}[\.\:]\d{1,3}\])");
    if (text.contains(lrcRx)) {
        // LRC 格式：复用已有的解析逻辑
        // 按行拆分并解析时间标签
        QStringList lines = text.split('\n', Qt::SkipEmptyParts);
        for (const QString &line : lines) {
            QString trimmed = line.trimmed();
            if (trimmed.isEmpty()) continue;

            QRegularExpressionMatchIterator it = lrcRx.globalMatch(trimmed);
            QList<int> times;
            while (it.hasNext()) {
                QRegularExpressionMatch m = it.next();
                times.append(parseLrcTime(m.captured(0)));
            }
            if (times.isEmpty()) continue;

            // 提取文本（去掉所有时间标签）
            QString lyricText = trimmed;
            lyricText.replace(lrcRx, QString());

            for (int t : times) {
                QVariantMap item;
                item["time"] = t;
                item["text"] = lyricText;
                result.append(item);
            }
        }
        // 按时间排序
        std::stable_sort(result.begin(), result.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap()["time"].toInt() < b.toMap()["time"].toInt();
        });

        // 同时间戳行：真翻译 → translation；否则堆叠为双行 text
        QVariantList grouped;
        for (int i = 0; i < result.size(); ++i) {
            QVariantMap item = result[i].toMap();
            int curTime = item["time"].toInt();
            if (i + 1 < result.size() && result[i + 1].toMap()["time"].toInt() == curTime) {
                QString nextText = result[i + 1].toMap()["text"].toString();
                if (looksLikeTranslation(nextText))
                    item["translation"] = nextText;
                else
                    item["text"] = item["text"].toString() + "\n" + nextText;
                ++i;
            }
            grouped.append(item);
        }
        result = grouped;
    } else {
        // 纯文本：按行拆分，均匀分配时间戳（基于歌曲时长）
        QStringList lines = text.split('\n', Qt::SkipEmptyParts);
        qint64 duration = m_player ? m_player->duration() : 0;
        int count = lines.size();
        for (int i = 0; i < count; ++i) {
            QString trimmed = lines[i].trimmed();
            if (trimmed.isEmpty()) continue;
            QVariantMap item;
            // 均匀分布：每行 = duration / count 间隔
            item["time"] = count > 1 ? int(i * duration / (count - 1)) : 0;
            item["text"] = trimmed;
            result.append(item);
        }
    }
    return result;
}

QString MusicManager::currentTitle() const {
    const QVariantList *list = (m_playlistSource == 1) ? &m_favorites
                            : (m_playlistSource == 2) ? &m_history : &m_playlist;
    if (m_currentIndex < 0 || m_currentIndex >= list->size()) return "";
    return list->at(m_currentIndex).toMap()["name"].toString();
}

QString MusicManager::currentArtist() const {
    const QVariantList *list = (m_playlistSource == 1) ? &m_favorites
                            : (m_playlistSource == 2) ? &m_history : &m_playlist;
    if (m_currentIndex < 0 || m_currentIndex >= list->size()) return "";
    return list->at(m_currentIndex).toMap()["artist"].toString();
}

QString MusicManager::currentAlbum() const {
    const QVariantList *list = (m_playlistSource == 1) ? &m_favorites
                            : (m_playlistSource == 2) ? &m_history : &m_playlist;
    if (m_currentIndex < 0 || m_currentIndex >= list->size()) return "";
    return list->at(m_currentIndex).toMap()["album"].toString();
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
    // prepend 插到首位 → 正在播放收藏时 currentIndex +1
    if (m_playlistSource == 1 && m_currentIndex >= 0)
        m_currentIndex++;
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
    QString path = track["path"].toString();
    // 已存在 → 不重排，保持现有顺序
    for (int i = 0; i < m_history.size(); i++) {
        if (m_history[i].toMap()["path"].toString() == path) return;
    }
    // 新增 → 插到首位
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

// ============================================================
// 原画质封面：从音频文件中提取原始内嵌封面，保存为 PNG
// ============================================================

QString MusicManager::loadOriginalCover() {
    releaseOriginalCover();

    if (m_currentIndex < 0 || m_currentIndex >= m_playlist.size())
        return QString();

    // 直接使用已有缓存封面，避免临时 QMediaPlayer 阻塞 UI 线程
    return m_currentCover;
}

void MusicManager::releaseOriginalCover() {
    if (!m_originalCoverPath.isEmpty()) {
        QFile::remove(m_originalCoverPath);
        m_originalCoverPath.clear();
    }
}



QVariantList MusicManager::loadLyricsForFile(const QString &filePath) {
    QVariantList result;
    if (filePath.isEmpty()) return result;

    // 查找同名的 .lrc 文件
    QFileInfo fi(filePath);
    QString dir = fi.absolutePath();
    QString base = fi.completeBaseName();

    QStringList candidates = {
        dir + "/" + base + ".lrc",
        dir + "/" + base + ".LRC",
    };

    QString lrcPath;
    for (const QString &c : candidates) {
        if (QFileInfo::exists(c)) { lrcPath = c; break; }
    }
    if (lrcPath.isEmpty()) return result;

    QFile file(lrcPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text))
        return result;

    QTextStream in(&file);
    in.setEncoding(QStringConverter::Utf8);

    QRegularExpression timeRx(R"(\[(\d{1,3}):(\d{1,3})(?:\.(\d{1,3}))?\])");
    QRegularExpression metaRx(R"(^\[(ti|ar|al|by|offset|length):)");  // 元数据标签，跳过

    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        if (line.isEmpty()) continue;
        // 跳过元数据标签行
        if (metaRx.match(line).hasMatch()) continue;

        // 提取所有时间标签
        QRegularExpressionMatchIterator it = timeRx.globalMatch(line);
        QList<int> times;
        while (it.hasNext()) {
            QRegularExpressionMatch m = it.next();
            int min = m.captured(1).toInt();
            int sec = m.captured(2).toInt();
            int cs = 0;
            if (!m.captured(3).isEmpty()) {
                QString csStr = m.captured(3);
                if (csStr.length() == 1) cs = csStr.toInt() * 100;       // "5" → 500ms
                else if (csStr.length() == 2) cs = csStr.toInt() * 10;   // "90" → 900ms
                else if (csStr.length() == 3) cs = csStr.toInt();        // "665" → 665ms
            }
            times.append(min * 60000 + sec * 1000 + cs);
        }

        if (times.isEmpty()) continue;

        // 去除所有时间标签，得到歌词文本
        QString text = line;
        text.replace(timeRx, "");
        text = text.trimmed();
        if (text.isEmpty()) continue;

        for (int t : times) {
            QVariantMap entry;
            entry["time"] = t;
            entry["text"] = text;
            result.append(entry);
        }
    }
    file.close();

    // 按时间排序
    std::stable_sort(result.begin(), result.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap()["time"].toInt() < b.toMap()["time"].toInt();
    });

    // 同时间戳行：真翻译 → translation；否则堆叠为双行 text
    QVariantList grouped;
    for (int i = 0; i < result.size(); ++i) {
        QVariantMap item = result[i].toMap();
        int curTime = item["time"].toInt();
        if (i + 1 < result.size() && result[i + 1].toMap()["time"].toInt() == curTime) {
            QString nextText = result[i + 1].toMap()["text"].toString();
            if (looksLikeTranslation(nextText))
                item["translation"] = nextText;
            else
                item["text"] = item["text"].toString() + "\n" + nextText;
            ++i;
        }
        grouped.append(item);
    }
    result = grouped;
    std::sort(result.begin(), result.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap()["time"].toInt() < b.toMap()["time"].toInt();
    });

    return result;
}
