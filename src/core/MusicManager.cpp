#include "MusicManager.h"
#include "MetadataReader.h"
#include <QFileInfo>
#include <QDirIterator>
#include <QUrl>
#include <QStandardPaths>
#include <QCryptographicHash>
#include <QImage>
#include <QImageReader>
#include <QTimer>
#include <QRandomGenerator>
#include <QEventLoop>
#include <QMediaPlayer>
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
#include <QFontDatabase>
#include <QSet>
#include <QDialog>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QRadioButton>
#include <QButtonGroup>
#include <QPushButton>

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
    bool fastPath = (ext == "mp3" || ext == "flac" || ext == "m4a" || ext == "mp4"
                     || ext == "ogg" || ext == "opus");

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
            // 注意：不绑定 QAudioOutput——仅读取时长/元数据无需初始化音频引擎，
            // 否则在 WASAPI 独占模式下会与 miniaudio 争抢设备而报初始化失败
            {
                QMediaPlayer player;
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
                qDebug() << "[ImportDebug] fastpath QMediaPlayer duration done for" << filePath
                         << "dur=" << player.duration();

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
                        QString cacheFile = MetadataReader::cacheCoverThumbnail(coverImg, coverDir(), QString::fromLatin1(hash));
                        if (!cacheFile.isEmpty())
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
            track["_infoInferred"] = !meta.tagFound;  // 无标签 → 歌手/歌名来自文件名推断
            return track;
        }
    }

    // ---- 慢路径：QMediaPlayer 回退（.ogg/.wav/.opus 等或快路径失败） ----
    // 仅读取元数据/时长，不绑定 QAudioOutput（避免 WASAPI 独占模式下争抢设备）
    QMediaPlayer player;

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
    qDebug() << "[ImportDebug] slowpath QMediaPlayer loop done for" << filePath;

    QString title  = player.metaData().value(QMediaMetaData::Title).toString();
    QString artist = player.metaData().value(QMediaMetaData::ContributingArtist).toString();
    if (artist.isEmpty())
        artist = player.metaData().value(QMediaMetaData::Author).toString();
    QString album  = player.metaData().value(QMediaMetaData::AlbumTitle).toString();
    int duration   = (int)(player.duration() / 1000);
    bool hadTags = !title.isEmpty() || !artist.isEmpty() || !album.isEmpty();

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
    track["_infoInferred"] = !hadTags;  // 无标签 → 歌手/歌名来自文件名推断

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
        QString cacheFile = MetadataReader::cacheCoverThumbnail(coverImg, coverDir(), QString::fromLatin1(hash));
        if (!cacheFile.isEmpty())
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
    // 注册内置歌词字体（data/font），记录真实族名供 QML 选择与渲染
    registerBuiltinFonts();

    m_audioEngine = new AudioEngine(this);
    m_audioEngine->setVolume(static_cast<float>(m_volume));

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

    connect(m_audioEngine, &AudioEngine::positionChanged, this, [this](qint64 pos) {
        emit positionChanged(pos);
        m_lyricTimer->start();
    });
    connect(m_audioEngine, &AudioEngine::playbackStateChanged, this, &MusicManager::playbackStateChanged);
    connect(m_audioEngine, &AudioEngine::audioInitFailed, this, &MusicManager::audioInitFailed);
    connect(m_audioEngine, &AudioEngine::endOfMedia, this, [this]() {
        // 根据播放模式决定下一步
        if (m_playMode == SingleLoop) {
            m_audioEngine->seek(0);  // 单曲循环：先归零再播放
            m_audioEngine->play();
        } else if (m_playMode == StopAfter) {
            m_audioEngine->stop();  // 关闭循环：停止
        } else {
            next();  // 顺序/列表循环/随机：下一首
        }
    });
    // 嵌入式歌词：音源加载完成后提取
    connect(m_audioEngine, &AudioEngine::durationChanged, this, [this]() {
        if (m_audioEngine) {
            qint64 dur = m_audioEngine->duration();
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
    });
    // 嵌入式歌词提取
    connect(m_audioEngine, &AudioEngine::durationChanged, this, &MusicManager::onMetaDataChanged);
}

// ============================================================
// 缓存：持久化播放列表到用户目录（开发者模式跳过）
// ============================================================

void MusicManager::setUseCache(bool use) {
    m_useCache = use;
    m_cacheDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(m_cacheDir);
    loadSettings();
    // 用户上次选用的内置字体此时才从设置读出，补注册（启动默认只注册了鸿蒙字体）
    if (m_lyricFont.startsWith(QStringLiteral("builtin:")))
        ensureFontRegistered(m_lyricFont.mid(8));
    loadCache();
    loadFavorites();
    loadHistory();
    loadCustomPlaylists();
    // 历史版本封面缓存是全尺寸（可达 36MB/张），启动后异步压缩到 512px 内
    if (use)
        QTimer::singleShot(0, this, &MusicManager::shrinkLegacyCoverCache);
}

// 把超过 512px 的历史封面缓存原位重写为缩略图（路径不变，已存储的 URL 仍有效）
void MusicManager::shrinkLegacyCoverCache()
{
    QDir dir(coverDir());
    const QStringList entries = dir.entryList({"*.jpg", "*.jpeg", "*.png"}, QDir::Files);
    for (const QString &name : entries) {
        const QString filePath = dir.filePath(name);
        QImageReader reader(filePath);
        const QSize size = reader.size();  // 仅读文件头，不解码整图
        if (!size.isValid() || (size.width() <= 512 && size.height() <= 512))
            continue;
        QImage img = reader.read();
        if (img.isNull())
            continue;
        QImage thumb = img.scaled(512, 512, Qt::KeepAspectRatio, Qt::SmoothTransformation);
        if (QFileInfo(name).suffix().toLower() == "png")
            thumb.save(filePath, "PNG");
        else
            thumb.save(filePath, "JPEG", 90);
        qDebug() << "[CoverCache] shrunk legacy cover" << name << size;
    }
}

void MusicManager::clearUserData() {
    QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir(dir).removeRecursively();
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
    if (obj.contains("volumeMenuOpacity")) {
        m_volumeMenuOpacity = obj.value("volumeMenuOpacity").toDouble(m_volumeMenuOpacity);
        emit volumeMenuOpacityChanged();
    }
    if (obj.contains("speedMenuOpacity")) {
        m_speedMenuOpacity = obj.value("speedMenuOpacity").toDouble(m_speedMenuOpacity);
        emit speedMenuOpacityChanged();
    }
    if (obj.contains("playbackRate")) {
        m_playbackRate = qBound(0.5, obj.value("playbackRate").toDouble(m_playbackRate), 2.0);
        if (m_audioEngine)
            m_audioEngine->setPitch(static_cast<float>(m_playbackRate));
        emit playbackRateChanged();
    }
    if (obj.contains("pitchCompensation")) {
        m_pitchCompensation = obj.value("pitchCompensation").toBool(false);
        if (m_audioEngine)
            m_audioEngine->setPitchCompensation(m_pitchCompensation);
        emit pitchCompensationChanged();
    }
    if (obj.contains("autoPitchCompensation")) {
        m_autoPitchCompensation = obj.value("autoPitchCompensation").toBool(true);
        emit autoPitchCompensationChanged();
    }
    if (obj.contains("minimizeToTray")) {
        m_minimizeToTray = obj.value("minimizeToTray").toBool(false);
        emit minimizeToTrayChanged();
    }
    if (obj.contains("playbackBackground")) {
        m_playbackBackground = obj.value("playbackBackground").toInt(0);
        emit playbackBackgroundChanged();
    }
    if (obj.contains("titleBarImmersiveSync")) {
        m_titleBarImmersiveSync = obj.value("titleBarImmersiveSync").toBool(true);
        emit titleBarImmersiveSyncChanged();
    }
    if (obj.contains("volume")) {
        m_volume = obj.value("volume").toDouble(m_volume);
        emit volumeChanged();
        if (m_audioEngine)
            m_audioEngine->setVolume(static_cast<float>(m_volume));
    }
    if (obj.contains("wasapiExclusive")) {
        bool requested = obj.value("wasapiExclusive").toBool(false);
        if (requested) {
            // 启动时保存了开启独占：不在加载阶段直接开启，而是延迟通知 QML 先弹窗提示
            // （识别精确度有限，请确认已关闭全部音频设备），用户确认后再真正开启。
            // loadSettings 在 QML 加载前执行，此时 Connections 尚未建立，信号会丢失，
            // 因此延迟到事件循环启动后再发
            m_wasapiExclusive = false;
            emit wasapiExclusiveChanged();
            QTimer::singleShot(0, this, [this]() { emit exclusiveConfirmRequested(); });
        } else {
            m_wasapiExclusive = false;
            emit wasapiExclusiveChanged();
        }
    }
    if (obj.contains("lyricFont")) {
        m_lyricFont = obj.value("lyricFont").toString(m_lyricFont);
        emit lyricFontChanged();
    }
    if (obj.contains("seekStep")) {
        m_seekStep = qBound(1, obj.value("seekStep").toInt(m_seekStep), 10);
        emit seekStepChanged();
    }
}

void MusicManager::saveSettings() {
    if (m_cacheDir.isEmpty()) return;
    QJsonObject obj;
    obj["detailOpacity"] = m_detailOpacity;
    obj["lyricOffset"] = m_lyricOffset;
    obj["playMode"] = m_playMode;
    obj["menuOpacity"] = m_menuOpacity;
    obj["volumeMenuOpacity"] = m_volumeMenuOpacity;
    obj["speedMenuOpacity"] = m_speedMenuOpacity;
    obj["playbackRate"] = m_playbackRate;
    obj["pitchCompensation"] = m_pitchCompensation;
    obj["autoPitchCompensation"] = m_autoPitchCompensation;
    obj["minimizeToTray"] = m_minimizeToTray;
    obj["playbackBackground"] = m_playbackBackground;
    obj["titleBarImmersiveSync"] = m_titleBarImmersiveSync;
    obj["volume"] = m_volume;
    obj["wasapiExclusive"] = m_wasapiExclusive;
    obj["lyricFont"] = m_lyricFont;
    obj["seekStep"] = m_seekStep;
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

void MusicManager::setVolumeMenuOpacity(qreal v) {
    v = qBound(0.3, v, 1.0);
    if (qFuzzyCompare(v, m_volumeMenuOpacity)) return;
    m_volumeMenuOpacity = v;
    emit volumeMenuOpacityChanged();
    saveSettings();
}

void MusicManager::setSpeedMenuOpacity(qreal v) {
    v = qBound(0.3, v, 1.0);
    if (qFuzzyCompare(v, m_speedMenuOpacity)) return;
    m_speedMenuOpacity = v;
    emit speedMenuOpacityChanged();
    saveSettings();
}

void MusicManager::setPlaybackRate(qreal v) {
    v = qBound(0.5, v, 2.0);
    if (qFuzzyCompare(v, m_playbackRate)) return;
    m_playbackRate = v;
    if (m_audioEngine)
        m_audioEngine->setPitch(static_cast<float>(m_playbackRate));
    // 自动控制音调补偿：变速（非 1x）自动开启；恢复 1x 自动关闭
    if (m_autoPitchCompensation) {
        if (qFuzzyCompare(v, 1.0)) {
            if (m_pitchCompensation)
                setPitchCompensation(false);
        } else if (!m_pitchCompensation) {
            setPitchCompensation(true);
        }
    }
    emit playbackRateChanged();
    saveSettings();
}

void MusicManager::setPitchCompensation(bool v) {
    if (v == m_pitchCompensation) return;
    m_pitchCompensation = v;
    if (m_audioEngine)
        m_audioEngine->setPitchCompensation(m_pitchCompensation);
    emit pitchCompensationChanged();
    saveSettings();
}

void MusicManager::setAutoPitchCompensation(bool v) {
    if (v == m_autoPitchCompensation) return;
    m_autoPitchCompensation = v;
    emit autoPitchCompensationChanged();
    saveSettings();
}

void MusicManager::setMinimizeToTray(bool v) {
    if (v == m_minimizeToTray) return;
    m_minimizeToTray = v;
    emit minimizeToTrayChanged();
    saveSettings();
}

void MusicManager::setPlaybackBackground(int v) {
    if (v < 0 || v > 1 || v == m_playbackBackground) return;
    m_playbackBackground = v;
    emit playbackBackgroundChanged();
    saveSettings();
}

void MusicManager::setPlayerDetailVisible(bool v) {
    if (v == m_playerDetailVisible) return;
    m_playerDetailVisible = v;
    emit playerDetailVisibleChanged();
}

void MusicManager::setTitleBarImmersiveSync(bool v) {
    if (v == m_titleBarImmersiveSync) return;
    m_titleBarImmersiveSync = v;
    emit titleBarImmersiveSyncChanged();
    saveSettings();
}

void MusicManager::setVolume(qreal vol) {
    vol = qBound(0.0, vol, 1.0);
    if (qFuzzyCompare(vol, m_volume)) return;
    m_volume = vol;
    if (m_audioEngine)
        m_audioEngine->setVolume(static_cast<float>(vol));
    emit volumeChanged();
    saveSettings();
}

void MusicManager::setWasapiExclusive(bool v) {
    if (v == m_wasapiExclusive) return;
    m_wasapiExclusive = v;
    emit wasapiExclusiveChanged();
    bool applied = true;
    if (m_audioEngine)
        applied = m_audioEngine->setExclusiveMode(v);
    if (!applied) {
        // 独占模式不可用（如设备被占用）：回退共享并同步 UI，与启动时一致弹窗询问用户
        m_wasapiExclusive = false;
        emit wasapiExclusiveChanged();
        emit wasapiExclusiveFailed();
    }
    saveSettings();
}

void MusicManager::retryWasapiExclusive() {
    // 重新检测：再次尝试开启独占
    bool applied = false;
    if (m_audioEngine)
        applied = m_audioEngine->setExclusiveMode(true);
    if (applied) {
        m_wasapiExclusive = true;
        emit wasapiExclusiveChanged();
        saveSettings();
    } else {
        // 仍失败：继续回退共享，并再次通知 QML（弹窗保持/重新弹出）
        m_wasapiExclusive = false;
        emit wasapiExclusiveChanged();
        emit wasapiExclusiveFailed();
    }
}

void MusicManager::forceWasapiExclusive() {
    // 强制开启：跳过探测直接尝试，若真实初始化仍失败则回退共享
    bool applied = false;
    if (m_audioEngine)
        applied = m_audioEngine->setExclusiveMode(true, true);
    if (applied) {
        m_wasapiExclusive = true;
        emit wasapiExclusiveChanged();
        saveSettings();
    } else {
        m_wasapiExclusive = false;
        emit wasapiExclusiveChanged();
        emit wasapiExclusiveFailed();
    }
}

void MusicManager::disableWasapiExclusive() {
    // 关闭独占模式：回退共享并持久化，避免每次启动重复弹窗
    m_wasapiExclusive = false;
    emit wasapiExclusiveChanged();
    if (m_audioEngine && m_audioEngine->exclusive())
        m_audioEngine->setExclusiveMode(false);
    saveSettings();
}

// ---- 歌词字体 ----

QString MusicManager::builtinFontPath(const QString &file) {
    return QStringLiteral(":/qt/qml/JustSolo/data/font/") + file;
}

void MusicManager::registerBuiltinFonts() {
    // 只注册当前选用的内置字体（默认鸿蒙），其余按需注册。
    // 全部注册会让 4 个内置字体（共约 44MB）常驻内存，而同一时间只会用到一种
    QString file = m_lyricFont.startsWith(QStringLiteral("builtin:"))
            ? m_lyricFont.mid(8)
            : QStringLiteral("HarmonyOS_Sans_SC_Regular.ttf");
    ensureFontRegistered(file);
}

void MusicManager::ensureFontRegistered(const QString &file) {
    const QString path = builtinFontPath(file);
    if (m_builtinFontFamilies.contains(path))
        return;  // 已注册
    int id = QFontDatabase::addApplicationFont(path);
    if (id < 0)
        return;
    const QStringList fams = QFontDatabase::applicationFontFamilies(id);
    if (!fams.isEmpty())
        m_builtinFontFamilies[path] = fams.first();
}

QVariantList MusicManager::builtinLyricFonts() const {
    struct Entry { const char *file; const char *label; };
    static const Entry entries[] = {
        {"HarmonyOS_Sans_SC_Regular.ttf", "鸿蒙字体（默认）"},
        {"AaZhuNiWoMingMeiXiangChunTian-2.ttf", "Aa筑你我们像春天"},
    };
    QVariantList result;
    for (const auto &e : entries) {
        QString file = QString::fromUtf8(e.file);
        QVariantMap m;
        m["file"] = file;
        m["label"] = QString::fromUtf8(e.label);
        m["family"] = m_builtinFontFamilies.value(builtinFontPath(file));
        m["key"] = QStringLiteral("builtin:") + file;
        result << m;
    }
    return result;
}

QVariantList MusicManager::systemLyricFonts() const {
    // 系统字体列表（排除已注册的内置字体，避免与"内置字体"分组重复）
    QSet<QString> builtinFams;
    for (auto it = m_builtinFontFamilies.cbegin(); it != m_builtinFontFamilies.cend(); ++it)
        builtinFams.insert(it.value());
    QStringList fams = QFontDatabase().families();
    fams.erase(std::remove_if(fams.begin(), fams.end(),
                              [&builtinFams](const QString &f) { return builtinFams.contains(f); }),
               fams.end());
    QVariantList result;
    for (const QString &f : std::as_const(fams)) {
        QVariantMap m;
        m["family"] = f;
        m["key"] = QStringLiteral("system:") + f;
        result << m;
    }
    return result;
}

QString MusicManager::lyricFontFamily() const {
    if (m_lyricFont.startsWith(QStringLiteral("builtin:"))) {
        QString file = m_lyricFont.mid(8);
        QString family = m_builtinFontFamilies.value(builtinFontPath(file));
        if (!family.isEmpty()) return family;
        // 兜底：内置字体注册失败时使用已知族名，保证默认鸿蒙字体始终可用
        if (file == QLatin1String("HarmonyOS_Sans_SC_Regular.ttf"))
            return QStringLiteral("HarmonyOS Sans SC");
        return QString();
    }
    if (m_lyricFont.startsWith(QStringLiteral("system:")))
        return m_lyricFont.mid(7);
    return QString();
}

void MusicManager::setLyricFont(const QString &v) {
    if (v == m_lyricFont) return;
    m_lyricFont = v;
    // 切换到未注册的内置字体时按需注册
    if (v.startsWith(QStringLiteral("builtin:")))
        ensureFontRegistered(v.mid(8));
    emit lyricFontChanged();
    saveSettings();
}

void MusicManager::setSeekStep(int v) {
    v = qBound(1, v, 10);
    if (v == m_seekStep) return;
    m_seekStep = v;
    emit seekStepChanged();
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

// ---- 自定义播放列表缓存 ----

void MusicManager::saveCustomPlaylists() {
    if (!m_useCache || m_cacheDir.isEmpty()) return;
    writeVariantListToFile(m_customPlaylists, m_cacheDir + "/custom_playlists.json");
}

void MusicManager::loadCustomPlaylists() {
    if (!m_useCache || m_cacheDir.isEmpty()) return;
    m_customPlaylists = readVariantListFromFile(m_cacheDir + "/custom_playlists.json");
    if (!m_customPlaylists.isEmpty())
        emit customPlaylistsChanged();
}

// ---- 自定义播放列表操作 ----

void MusicManager::createCustomPlaylist(const QString &name) {
    QString n = name.trimmed();
    if (!isValidPlaylistName(n)) return;
    // 检查重名
    for (const QVariant &pl : m_customPlaylists) {
        if (pl.toMap()["name"].toString() == n) return;
    }
    QVariantMap pl;
    pl["name"] = n;
    pl["songs"] = QVariantList();
    m_customPlaylists.append(pl);
    saveCustomPlaylists();
    emit customPlaylistsChanged();
}

void MusicManager::renameCustomPlaylist(int index, const QString &newName) {
    QString n = newName.trimmed();
    if (index < 0 || index >= m_customPlaylists.size() || n.isEmpty()) return;
    // 歌手列表放宽名称校验（允许空格、顿号等），普通列表严格校验
    bool isArtist = m_customPlaylists[index].toMap()["type"].toString() == QStringLiteral("artist");
    if (!isArtist && !isValidPlaylistName(n)) return;
    // 检查重名（排除自己）
    for (int i = 0; i < m_customPlaylists.size(); i++) {
        if (i != index && m_customPlaylists[i].toMap()["name"].toString() == n) return;
    }
    QVariantMap pl = m_customPlaylists[index].toMap();
    pl["name"] = n;
    m_customPlaylists[index] = pl;
    saveCustomPlaylists();
    emit customPlaylistsChanged();
}

bool MusicManager::isValidPlaylistName(const QString &name) const {
    if (name.trimmed().isEmpty()) return false;
    // 中英文 + 数字 + - + _
    static const QRegularExpression re("^[a-zA-Z0-9_\\-\\x{4e00}-\\x{9fff}]+$");
    return re.match(name.trimmed()).hasMatch();
}

void MusicManager::playCustomPlaylist(int playlistIndex, int songIndex) {
    if (playlistIndex < 0 || playlistIndex >= m_customPlaylists.size()) return;
    QVariantMap pl = m_customPlaylists[playlistIndex].toMap();
    QVariantList songPaths = pl["songs"].toList();
    if (songIndex < 0 || songIndex >= songPaths.size()) return;

    // 根据路径从音乐库查找完整信息，构建播放列表
    QVariantList newPlaylist;
    for (const QVariant &entry : songPaths) {
        QString path = entry.toMap()["path"].toString();
        if (path.isEmpty()) continue;
        for (const QVariant &libEntry : m_library) {
            if (libEntry.toMap()["path"].toString() == path) {
                newPlaylist.append(libEntry);
                break;
            }
        }
    }

    if (newPlaylist.isEmpty()) return;

    m_playlist = newPlaylist;
    m_playingListIndex = 3 + playlistIndex;
    emit playingListIndexChanged();
    m_playlistSource = 3;
    emit playlistSourceChanged();
    emit playlistChanged();

    playIndex(songIndex);
}

void MusicManager::deleteCustomPlaylist(int index) {
    if (index < 0 || index >= m_customPlaylists.size()) return;
    bool wasPlaying = (m_playingListIndex == 3 + index);

    // 收集该列表的所有歌曲路径，用于清理历史
    QVariantMap pl = m_customPlaylists[index].toMap();
    QVariantList songs = pl["songs"].toList();
    QStringList paths;
    for (const QVariant &entry : songs) {
        paths << entry.toMap()["path"].toString();
    }

    // 从历史中删除所有该列表的条目（无论是否正在播放）
    bool histChanged = false;
    for (int h = m_history.size() - 1; h >= 0; h--) {
        if (paths.contains(m_history[h].toMap()["path"].toString())) {
            m_history.removeAt(h);
            histChanged = true;
        }
    }
    if (histChanged) {
        saveHistory();
        emit historyChanged();
    }

    if (wasPlaying) {
        // 清空播放状态
        m_playingListIndex = -1;
        m_currentIndex = -1;
        m_currentCover.clear();
        m_currentAlbum.clear();
        m_audioEngine->stop();
        emit playingListIndexChanged();
        emit currentIndexChanged();
        emit currentTrackChanged();
    }

    m_customPlaylists.removeAt(index);

    if (wasPlaying) {
        m_playlist.clear();
        emit playlistChanged();
    }

    saveCustomPlaylists();
    emit customPlaylistsChanged();
}

void MusicManager::addSongsToCustomPlaylist(const QStringList &paths, int index) {
    if (index < 0 || index >= m_customPlaylists.size()) return;
    QVariantMap pl = m_customPlaylists[index].toMap();
    QVariantList songs = pl["songs"].toList();

    for (const QString &path : paths) {
        // 去重
        bool exists = false;
        for (const QVariant &s : songs) {
            if (s.toMap()["path"].toString() == path) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            QVariantMap entry;
            entry["path"] = path;
            songs.append(entry);
        }
    }

    pl["songs"] = songs;
    m_customPlaylists[index] = pl;
    saveCustomPlaylists();
    emit customPlaylistsChanged();
}

void MusicManager::addLibrarySongsToCustomPlaylist(const QVariantList &libraryIndices, int playlistIndex) {
    if (playlistIndex < 0 || playlistIndex >= m_customPlaylists.size()) return;

    QVariantMap pl = m_customPlaylists[playlistIndex].toMap();
    QVariantList songs = pl["songs"].toList();

    for (const QVariant &idx : libraryIndices) {
        int i = idx.toInt();
        if (i < 0 || i >= m_library.size()) continue;

        QString path = m_library[i].toMap()["path"].toString();

        // 按 path 精确去重
        bool exists = false;
        for (const QVariant &s : songs) {
            if (s.toMap()["path"].toString() == path) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            QVariantMap entry;
            entry["path"] = path;
            songs.append(entry);
        }
    }

    pl["songs"] = songs;
    m_customPlaylists[playlistIndex] = pl;
    saveCustomPlaylists();
    emit customPlaylistsChanged();
}

// ---- 歌手列表 ----

QVariantList MusicManager::availableArtists() const {
    QSet<QString> seen;
    QVariantList result;
    for (const QVariant &v : m_library) {
        QString artist = v.toMap()["artist"].toString().trimmed();
        if (artist.isEmpty()) continue;
        if (!seen.contains(artist)) {
            seen.insert(artist);
            result.append(artist);
        }
    }
    std::sort(result.begin(), result.end(), [](const QVariant &a, const QVariant &b) {
        return a.toString().localeAwareCompare(b.toString()) < 0;
    });
    return result;
}

void MusicManager::createArtistPlaylist(const QString &artist) {
    QString a = artist.trimmed();
    if (a.isEmpty()) return;
    // 检查重复：同名歌手列表或同名任意列表
    for (const QVariant &pl : m_customPlaylists) {
        QVariantMap m = pl.toMap();
        if (m["type"].toString() == QStringLiteral("artist") && m["artist"].toString() == a) return;
        if (m["name"].toString() == a) return;
    }
    // 从音乐库收集该歌手的所有歌曲
    QVariantList songs;
    for (const QVariant &v : m_library) {
        if (v.toMap()["artist"].toString() == a) {
            QVariantMap entry;
            entry["path"] = v.toMap()["path"].toString();
            songs.append(entry);
        }
    }
    QVariantMap pl;
    pl["type"] = QStringLiteral("artist");
    pl["artist"] = a;
    pl["name"] = a;
    pl["songs"] = songs;
    m_customPlaylists.append(pl);
    saveCustomPlaylists();
    emit customPlaylistsChanged();
}

void MusicManager::refreshArtistPlaylist(int index) {
    if (index < 0 || index >= m_customPlaylists.size()) return;
    QVariantMap pl = m_customPlaylists[index].toMap();
    if (pl["type"].toString() != QStringLiteral("artist")) return;
    QString artist = pl["artist"].toString();
    if (artist.isEmpty()) return;
    // 重新从音乐库收集该歌手的所有歌曲
    QVariantList songs;
    for (const QVariant &v : m_library) {
        if (v.toMap()["artist"].toString() == artist) {
            QVariantMap entry;
            entry["path"] = v.toMap()["path"].toString();
            songs.append(entry);
        }
    }
    pl["songs"] = songs;
    m_customPlaylists[index] = pl;
    saveCustomPlaylists();
    emit customPlaylistsChanged();
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
    static const int BATCH_SIZE = 10;
    int processed = 0;
    bool playlistModified = false;

    while (!m_pendingPaths.isEmpty() && processed < BATCH_SIZE) {
        QString path = m_pendingPaths.takeFirst();
        qDebug() << "[ImportDebug] buildTrack start" << path;
        QVariantMap track = buildTrack(path);
        qDebug() << "[ImportDebug] buildTrack done artist=" << track["artist"]
                 << "name=" << track["name"];

        // 未识别到歌手，或歌手/歌名是从文件名推断的（可能有顺序错误）→ 弹窗确认
        bool infoInferred = track.take("_infoInferred").toBool();
        if (track["artist"].toString().isEmpty() || infoInferred) {
            QString infoTitle, infoArtist, infoAlbum;
            int infoResult = promptMissingInfo(track["path"].toString(),
                                               track["name"].toString(),
                                               &infoTitle, &infoArtist, &infoAlbum);
            qDebug() << "[ImportDebug] prompt result=" << infoResult
                     << "title=" << infoTitle << "artist=" << infoArtist;
            if (infoResult == 0) {
                if (!infoTitle.isEmpty())  track["name"]   = infoTitle;
                if (!infoArtist.isEmpty()) track["artist"] = normalizeArtist(infoArtist);
                if (!infoAlbum.isEmpty())  track["album"]  = infoAlbum;
            } else if (infoResult == 2) {
                // 取消：清空剩余待处理文件，终止本次导入
                m_pendingPaths.clear();
                break;
            }
            // infoResult == 1（跳过）：保持原解析结果
        }

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
                        bool wasPlaying = m_audioEngine && m_audioEngine->isPlaying();
                        qint64 oldPos = m_audioEngine ? m_audioEngine->position() : 0;
                        m_audioEngine->load(track["path"].toString());
                        if (wasPlaying) {
                            m_audioEngine->seek(oldPos);
                            m_audioEngine->play();
                        }
                        emit currentIndexChanged();
                    }
                    playlistModified = true;
                }
                shouldAdd = false;
                break;
            }
        }

        if (shouldAdd) {
            m_library.prepend(track);
            m_playlist.prepend(track);
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
        m_audioEngine->stop();
        emit currentIndexChanged();
    } else if (m_currentIndex > index) {
        m_currentIndex--;
    }
    emit playlistChanged();
    saveCache();
}

void MusicManager::deleteSongByPath(const QString &path) {
    if (path.isEmpty()) return;

    // 从音乐库删除
    for (int i = 0; i < m_library.size(); i++) {
        if (m_library[i].toMap()["path"].toString() == path) {
            m_library.removeAt(i);
            emit libraryChanged();
            break;
        }
    }

    // 从播放列表删除
    for (int i = 0; i < m_playlist.size(); i++) {
        if (m_playlist[i].toMap()["path"].toString() == path) {
            if (m_currentIndex == i) {
                m_currentIndex = -1;
                m_playingListIndex = -1;
                m_currentCover.clear();
                m_currentAlbum.clear();
                m_audioEngine->stop();
                emit playingListIndexChanged();
                emit currentIndexChanged();
                emit currentTrackChanged();
            } else if (m_currentIndex > i) {
                m_currentIndex--;
            }
            m_playlist.removeAt(i);
            emit playlistChanged();
            break;
        }
    }

    // 从收藏删除
    for (int i = 0; i < m_favorites.size(); i++) {
        if (m_favorites[i].toMap()["path"].toString() == path) {
            m_favorites.removeAt(i);
            saveFavorites();
            emit favoritesChanged();
            break;
        }
    }

    // 从历史删除
    for (int i = 0; i < m_history.size(); i++) {
        if (m_history[i].toMap()["path"].toString() == path) {
            m_history.removeAt(i);
            saveHistory();
            emit historyChanged();
            break;
        }
    }

    // 从所有自定义列表删除
    bool plChanged = false;
    for (int pl = 0; pl < m_customPlaylists.size(); pl++) {
        QVariantMap plMap = m_customPlaylists[pl].toMap();
        QVariantList songs = plMap["songs"].toList();
        bool removed = false;
        for (int s = 0; s < songs.size(); s++) {
            if (songs[s].toMap()["path"].toString() == path) {
                songs.removeAt(s);
                removed = true;
                break;
            }
        }
        if (removed) {
            plMap["songs"] = songs;
            m_customPlaylists[pl] = plMap;
            plChanged = true;
        }
    }
    if (plChanged) {
        saveCustomPlaylists();
        emit customPlaylistsChanged();
    }

    saveCache();
}

void MusicManager::clearPlaylist() {
    m_playlist.clear();
    m_currentIndex = -1;
    m_playlistSource = 0;
    m_playingListIndex = -1;
    m_currentCover.clear();            // 清空封面
    m_currentAlbum.clear();            // 清空专辑
    m_audioEngine->stop();
    emit playingListIndexChanged();
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
    // 同步播放列表索引（0=库, 1=收藏, 2=历史；3+n 由 playCustomPlaylist 设置）
    if (m_playlistSource < 3) {
        m_playingListIndex = m_playlistSource;
        emit playingListIndexChanged();
    }
    QVariantMap track = list[index].toMap();
    m_currentCover = track["cover"].toString();
    m_currentAlbum = track["album"].toString();
    // 更新当前曲目信息（设置 m_currentMediaPath、加载外部歌词、重置嵌入式歌词标记）
    updateCurrentTrack();
    m_audioEngine->load(track["path"].toString());
    m_audioEngine->play();
    emit currentIndexChanged();
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
    if (source < 0 || source > 3 || source == m_playlistSource) {
        if (source == 0 && m_playlist.size() != m_library.size() && !m_library.isEmpty()) {
            m_playlist = m_library;
            emit playlistChanged();
        }
        return;
    }
    if (source == 0 && !m_library.isEmpty()) {
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
                m_audioEngine->stop();
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

// ============================================================
// 手动排序
// ============================================================

void MusicManager::moveSongInLibrary(int from, int to) {
    if (from < 0 || from >= m_library.size()) return;
    if (to < 0 || to >= m_library.size()) return;
    if (from == to) return;

    QVariantMap item = m_library[from].toMap();
    m_library.removeAt(from);
    int adjustedTo = (to > from) ? to - 1 : to;
    m_library.insert(adjustedTo, item);

    if (m_playlistSource == 0) {
        m_playlist = m_library;
        if (m_currentIndex == from) {
            m_currentIndex = adjustedTo;
            emit currentIndexChanged();
        } else if (m_currentIndex > from && m_currentIndex <= adjustedTo) {
            m_currentIndex--;
        } else if (m_currentIndex < from && m_currentIndex >= adjustedTo) {
            m_currentIndex++;
        }
        emit playlistChanged();
    }

    saveCache();
    emit libraryChanged();
}

void MusicManager::moveSongInFavorites(int from, int to) {
    if (from < 0 || from >= m_favorites.size()) return;
    if (to < 0 || to >= m_favorites.size()) return;
    if (from == to) return;

    QVariantMap item = m_favorites[from].toMap();
    m_favorites.removeAt(from);
    int adjustedTo = (to > from) ? to - 1 : to;
    m_favorites.insert(adjustedTo, item);

    if (m_playlistSource == 1 && m_currentIndex >= 0) {
        if (m_currentIndex == from) {
            m_currentIndex = adjustedTo;
            emit currentIndexChanged();
        } else if (m_currentIndex > from && m_currentIndex <= adjustedTo) {
            m_currentIndex--;
        } else if (m_currentIndex < from && m_currentIndex >= adjustedTo) {
            m_currentIndex++;
        }
    }

    // 正在播放收藏列表时同步 m_playlist
    if (m_playlistSource == 1) {
        m_playlist = m_favorites;
        emit playlistChanged();
    }

    saveFavorites();
    emit favoritesChanged();
}

void MusicManager::moveSongInHistory(int from, int to) {
    if (from < 0 || from >= m_history.size()) return;
    if (to < 0 || to >= m_history.size()) return;
    if (from == to) return;

    QVariantMap item = m_history[from].toMap();
    m_history.removeAt(from);
    int adjustedTo = (to > from) ? to - 1 : to;
    m_history.insert(adjustedTo, item);

    if (m_playlistSource == 2 && m_currentIndex >= 0) {
        if (m_currentIndex == from) {
            m_currentIndex = adjustedTo;
            emit currentIndexChanged();
        } else if (m_currentIndex > from && m_currentIndex <= adjustedTo) {
            m_currentIndex--;
        } else if (m_currentIndex < from && m_currentIndex >= adjustedTo) {
            m_currentIndex++;
        }
    }

    // 正在播放历史列表时同步 m_playlist
    if (m_playlistSource == 2) {
        m_playlist = m_history;
        emit playlistChanged();
    }

    saveHistory();
    emit historyChanged();
}

void MusicManager::moveSongInCustomPlaylist(int playlistIndex, int from, int to) {
    if (playlistIndex < 0 || playlistIndex >= m_customPlaylists.size()) return;

    QVariantMap pl = m_customPlaylists[playlistIndex].toMap();
    QVariantList songs = pl["songs"].toList();

    if (from < 0 || from >= songs.size()) return;
    if (to < 0 || to >= songs.size()) return;
    if (from == to) return;

    QVariantMap entry = songs[from].toMap();
    songs.removeAt(from);
    int adjustedTo = (to > from) ? to - 1 : to;
    songs.insert(adjustedTo, entry);

    pl["songs"] = songs;
    m_customPlaylists[playlistIndex] = pl;

    if (m_playingListIndex == 3 + playlistIndex && m_currentIndex >= 0) {
        if (m_currentIndex == from) {
            m_currentIndex = adjustedTo;
            emit currentIndexChanged();
        } else if (m_currentIndex > from && m_currentIndex <= adjustedTo) {
            m_currentIndex--;
        } else if (m_currentIndex < from && m_currentIndex >= adjustedTo) {
            m_currentIndex++;
        }
    }

    // 正在播放该自定义歌单时同步 m_playlist
    if (m_playingListIndex == 3 + playlistIndex) {
        QVariantList newPlaylist;
        for (const QVariant &entry : songs) {
            QString path = entry.toMap()["path"].toString();
            for (const QVariant &libEntry : m_library) {
                if (libEntry.toMap()["path"].toString() == path) {
                    newPlaylist.append(libEntry);
                    break;
                }
            }
        }
        m_playlist = newPlaylist;
        emit playlistChanged();
    }

    saveCustomPlaylists();
    emit customPlaylistsChanged();
}

void MusicManager::moveSongInPlaylist(int from, int to) {
    if (from < 0 || from >= m_playlist.size()) return;
    if (to < 0 || to >= m_playlist.size()) return;
    if (from == to) return;

    QVariantMap item = m_playlist[from].toMap();
    m_playlist.removeAt(from);
    int adjustedTo = (to > from) ? to - 1 : to;
    m_playlist.insert(adjustedTo, item);

    if (m_playlistSource == 0 && m_currentIndex >= 0) {
        if (m_currentIndex == from) {
            m_currentIndex = adjustedTo;
            emit currentIndexChanged();
        } else if (m_currentIndex > from && m_currentIndex <= adjustedTo) {
            m_currentIndex--;
        } else if (m_currentIndex < from && m_currentIndex >= adjustedTo) {
            m_currentIndex++;
        }
    }

    // 当 source 为 0 时，播放列表即音乐库，同步更新
    if (m_playlistSource == 0) {
        m_library = m_playlist;
        saveCache();
        emit libraryChanged();
    }

    saveCache();
    emit playlistChanged();
}

void MusicManager::play() {
    QVariantList &list = currentPlaylist();
    if (m_currentIndex >= 0 && m_currentIndex < list.size()) {
        m_audioEngine->play();
    }
}

void MusicManager::pause() {
    m_audioEngine->pause();
}

void MusicManager::stop() {
    m_audioEngine->stop();
    releaseOriginalCover();
}

void MusicManager::shutdown() {
    m_audioEngine->stop();
    m_loadTimer->stop();
    m_lyricTimer->stop();
    releaseOriginalCover();
}

void MusicManager::next() {
    // 所有音乐模式：确保 m_playlist 与音乐库同步（防止被自定义列表覆盖）
    if (m_playlistSource == 0) {
        if (m_playlist.size() != m_library.size()) {
            m_playlist = m_library;
            emit playlistChanged();
        }
    }
    QVariantList &list = currentPlaylist();
    if (list.isEmpty()) return;
    int nextIdx;
    if (m_playMode == Shuffle) {
        // 随机模式下，确保不会随机到当前正在播放的歌曲（除非列表只有1首）
        if (list.size() <= 1) {
            nextIdx = 0;
        } else if (m_currentIndex < 0 || m_currentIndex >= list.size()) {
            nextIdx = QRandomGenerator::global()->bounded(list.size());
        } else {
            // 在 [0, size-1) 范围内随机，然后跳过当前索引
            nextIdx = QRandomGenerator::global()->bounded(list.size() - 1);
            if (nextIdx >= m_currentIndex) nextIdx++;
        }
    } else {
        nextIdx = (m_currentIndex + 1) % list.size();
    }
    playIndex(nextIdx);
}

void MusicManager::previous() {
    // 所有音乐模式：确保 m_playlist 与音乐库同步
    if (m_playlistSource == 0) {
        if (m_playlist.size() != m_library.size()) {
            m_playlist = m_library;
            emit playlistChanged();
        }
    }
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
    updateCurrentCoverColor();  // 提取封面主色调（在 emit currentTrackChanged 之前完成）
    emit currentTrackChanged();
    emit currentLyricsChanged();
}

// 从封面图提取主色调（#RRGGBB），失败返回空串
// 算法：缩放到 64×64 → 4-bit 量化颜色直方图 → 跳过过暗/过亮/过灰像素
// → 取像素最多的 bucket 的平均色
QString MusicManager::extractCoverColor(const QString &coverUrl) {
    if (coverUrl.isEmpty()) return QString();

    QString path = QUrl(coverUrl).toLocalFile();
    if (path.isEmpty()) return QString();

    QImage img(path);
    if (img.isNull()) return QString();

    // 缩放到小尺寸加速（保持比例，快变换）
    img = img.scaled(64, 64, Qt::KeepAspectRatio, Qt::FastTransformation);
    if (img.isNull()) return QString();

    img = img.convertToFormat(QImage::Format_RGB32);
    if (img.isNull()) return QString();

    // 4-bit per channel 量化（16 × 16 × 16 = 4096 buckets）
    const int BUCKETS = 16;
    QVector<int> count(BUCKETS * BUCKETS * BUCKETS, 0);
    QVector<quint64> rSum(BUCKETS * BUCKETS * BUCKETS, 0);
    QVector<quint64> gSum(BUCKETS * BUCKETS * BUCKETS, 0);
    QVector<quint64> bSum(BUCKETS * BUCKETS * BUCKETS, 0);
    QVector<qreal> sSum(BUCKETS * BUCKETS * BUCKETS, 0.0);  // 饱和度累加，用于加权评分

    int validPixels = 0;
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb*>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            QRgb rgb = line[x];
            int r = qRed(rgb);
            int g = qGreen(rgb);
            int b = qBlue(rgb);

            // 用 RGB max/min 近似 HSV 的 V 和 S，避免 QColor 构造开销
            int maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
            int minC = r < g ? (r < b ? r : b) : (g < b ? g : b);
            qreal v = maxC / 255.0;
            qreal s = maxC > 0 ? (maxC - minC) / qreal(maxC) : 0.0;

            if (v < 0.15 || v > 0.95 || s < 0.25) continue;

            int ri = r >> 4;  // r / 16
            int gi = g >> 4;
            int bi = b >> 4;
            int idx = (ri * BUCKETS + gi) * BUCKETS + bi;
            count[idx]++;
            rSum[idx] += quint64(r);
            gSum[idx] += quint64(g);
            bSum[idx] += quint64(b);
            sSum[idx] += s;
            ++validPixels;
        }
    }

    if (validPixels == 0) return QString();

    // 用饱和度立方加权评分：score = count * avgSat^3，鲜艳颜色优先
    int bestIdx = 0;
    qreal bestScore = 0.0;
    for (int i = 0; i < count.size(); ++i) {
        if (count[i] == 0) continue;
        qreal avgS = sSum[i] / count[i];
        qreal score = count[i] * avgS * avgS * avgS;
        if (score > bestScore) {
            bestScore = score;
            bestIdx = i;
        }
    }
    if (bestScore == 0.0) return QString();

    int bestCount = count[bestIdx];
    int r = int(rSum[bestIdx] / quint64(bestCount));
    int g = int(gSum[bestIdx] / quint64(bestCount));
    int b = int(bSum[bestIdx] / quint64(bestCount));

    // 对偏亮的颜色做压暗，避免作为背景时发白（限制最大通道值 ≤ 140，即 V ≤ 0.55）
    int maxC = r > g ? (r > b ? r : b) : (g > b ? g : b);
    const int MAX_V = 140;
    if (maxC > MAX_V) {
        qreal scale = qreal(MAX_V) / maxC;
        r = int(r * scale);
        g = int(g * scale);
        b = int(b * scale);
    }

    return QString("#%1%2%3")
        .arg(r, 2, 16, QChar('0'))
        .arg(g, 2, 16, QChar('0'))
        .arg(b, 2, 16, QChar('0'));
}

// 根据当前 m_currentCover 提取主色调，变化时发出通知
void MusicManager::updateCurrentCoverColor() {
    QString newColor = extractCoverColor(m_currentCover);
    if (newColor != m_currentCoverColor) {
        m_currentCoverColor = newColor;
        emit currentCoverColorChanged();
    }
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

    qint64 pos = m_audioEngine ? m_audioEngine->position() + m_lyricOffset : 0;
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

// 解析 Vorbis Comment / OpusTags 注释区（vendor + 条目列表），取 LYRICS=
static QString extractVorbisLyrics(const QByteArray &commentData) {
    int p = 0;
    if (p + 4 > commentData.size()) return {};
    quint32 vendorLen = (quint8)commentData[p] | ((quint8)commentData[p+1] << 8)
                      | ((quint8)commentData[p+2] << 16) | ((quint8)commentData[p+3] << 24);
    p += 4 + vendorLen;
    if (p + 4 > commentData.size()) return {};
    quint32 count = (quint8)commentData[p] | ((quint8)commentData[p+1] << 8)
                  | ((quint8)commentData[p+2] << 16) | ((quint8)commentData[p+3] << 24);
    p += 4;
    for (quint32 i = 0; i < count && p + 4 <= commentData.size(); ++i) {
        quint32 len = (quint8)commentData[p] | ((quint8)commentData[p+1] << 8)
                    | ((quint8)commentData[p+2] << 16) | ((quint8)commentData[p+3] << 24);
        p += 4;
        if (p + (int)len > commentData.size()) break;
        QByteArray comment = commentData.mid(p, len);
        p += len;
        if (comment.toUpper().startsWith("LYRICS=")) {
            QString lyrics = QString::fromUtf8(comment.mid(7)).trimmed();
            if (!lyrics.isEmpty()) return lyrics;
        }
    }
    return {};
}

static QString extractEmbeddedLyricsFromFile(const QString &filePath) {
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) return {};

    // 只读文件头判断格式，再按格式读取所需区域，避免整文件 readAll
    QByteArray head = file.read(12);
    if (head.isEmpty()) return {};

    // === MP3 ID3v2 USLT (Unsynchronized Lyrics) ===
    if (head.startsWith("ID3")) {
        // 读取 ID3v2 头大小（syncsafe 编码）
        quint32 tagSize = 0;
        for (int i = 6; i <= 9; ++i) {
            tagSize = (tagSize << 7) | (static_cast<quint8>(head[i]) & 0x7F);
        }
        tagSize += 10; // 加上头本身

        // 只读 ID3v2 标签区（通常 < 100KB），不读整首音频
        file.seek(0);
        QByteArray data = file.read(qint64(tagSize));

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
    if (head.startsWith("fLaC")) {
        // 元数据块（含 Vorbis Comment 歌词）都在文件开头，只读前 1MB
        file.seek(0);
        QByteArray data = file.read(1024 * 1024);
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

    // === Ogg/Opus (OpusTags) 与 Ogg/Vorbis（注释头）中的 LYRICS= 注释 ===
    if (head.startsWith("OggS")) {
        // 注释头在前几个 Ogg page，只读前 1MB
        file.seek(0);
        QByteArray data = file.read(1024 * 1024);
        QByteArray curPacket;   // 跨页累积的 packet（lacing=255 表示分片未结束）
        bool commentChecked = false;
        int pos = 0;
        while (!commentChecked && pos + 27 <= data.size() && data.mid(pos, 4) == "OggS") {
            int segCount = (quint8)data[pos + 26];
            int segTableEnd = pos + 27 + segCount;
            if (segTableEnd > data.size()) break;
            int payloadLen = 0;
            for (int i = 0; i < segCount; ++i)
                payloadLen += (quint8)data[pos + 27 + i];
            int payloadStart = segTableEnd;
            int payloadEnd = payloadStart + payloadLen;
            if (payloadEnd > data.size()) break;

            int p = payloadStart;
            for (int i = 0; i < segCount; ++i) {
                int segLen = (quint8)data[pos + 27 + i];
                curPacket.append(data.mid(p, segLen));
                p += segLen;
                if (segLen < 255) {
                    // packet 结束：检查是否为 OpusTags / Vorbis 注释头
                    QByteArray commentData;
                    if (curPacket.startsWith("OpusTags"))
                        commentData = curPacket.mid(8);      // 跳过 "OpusTags"
                    else if (curPacket.size() >= 7 && (quint8)curPacket[0] == 0x03
                             && curPacket.mid(1, 6) == "vorbis")
                        commentData = curPacket.mid(7);      // 跳过 0x03+"vorbis"
                    if (!commentData.isEmpty()) {
                        QString lyrics = extractVorbisLyrics(commentData);
                        if (!lyrics.isEmpty()) return lyrics;
                        commentChecked = true;  // 已检查注释头（无歌词），停止扫描
                        break;
                    }
                    curPacket.clear();
                }
            }
            pos = payloadEnd;
        }
    }

    // === MP4/M4A (iTunes ilst: ©lyr 或 ----:com.apple.iTunes:LYRICS) ===
    // 注意：MP4 首原子 = 4字节 size + 4字节类型（通常 "ftyp"，位于 offset 4），
    // 不能用 startsWith("ftyp") 判断（MP3 的 "ID3"/FLAC 的 "fLaC" 才是真正的文件头）。
    QString mp4Ext = QFileInfo(filePath).suffix().toLower();
    bool isMp4 = (mp4Ext == "m4a" || mp4Ext == "mp4");
    if (!isMp4 && head.size() >= 8) {
        const QByteArray atomType = head.mid(4, 4);
        isMp4 = (atomType == "ftyp" || atomType == "moov" || atomType == "styp");
    }
    if (isMp4) {
        // readMP4TextTags 已流式化：只读 moov 区间，不再二次整读
        QMap<QString, QString> tags = MetadataReader::readMP4TextTags(filePath, nullptr);
        QString lyrics = tags.value(QStringLiteral("LYRICS")).trimmed();
        if (!lyrics.isEmpty()) return lyrics;
    }

    return {};
}

// ---- 从媒体元数据中提取嵌入式歌词 ----
void MusicManager::onMetaDataChanged() {
    if (m_embeddedLyricsLoaded) return;
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
        qint64 duration = m_audioEngine ? m_audioEngine->duration() : 0;
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

void MusicManager::seek(qint64 ms) {
    if (m_audioEngine) m_audioEngine->seek(ms);
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

void MusicManager::toggleCurrentFavorite() {
    const QVariantList *list = (m_playlistSource == 1) ? &m_favorites
                              : (m_playlistSource == 2) ? &m_history : &m_playlist;
    if (m_currentIndex < 0 || m_currentIndex >= list->size()) return;
    // 使用当前播放列表中的完整曲目（含 name/artist/cover/album/duration 等），
    // 避免仅存 path 导致收藏页无法正常显示
    toggleFavorite(list->at(m_currentIndex).toMap());
}

bool MusicManager::isCurrentFavorite() const {
    const QVariantList *list = (m_playlistSource == 1) ? &m_favorites
                             : (m_playlistSource == 2) ? &m_history : &m_playlist;
    if (m_currentIndex < 0 || m_currentIndex >= list->size()) return false;
    QString path = list->at(m_currentIndex).toMap()["path"].toString();
    if (path.isEmpty()) return false;
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
// 拖放支持工具
// ============================================================

bool MusicManager::isDirectory(const QString &path) const {
    return QFileInfo(path).isDir();
}

bool MusicManager::isAudioFile(const QString &path) const {
    QString ext = QFileInfo(path).suffix().toLower();
    return supportedAudioExtensions().contains("*." + ext);
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

// ============================================================
// 导入信息缺失弹窗（未识别到歌手/歌名）
// ============================================================

// 从文件名解析歌手/歌名：order 0=歌手在前,1=歌名在前；sep 0='-',1=空格
static void parseFileNameParts(const QString &fileName, int order, int sep,
                               QString *outTitle, QString *outArtist) {
    QString base = QFileInfo(fileName).completeBaseName().trimmed();
    if (base.isEmpty()) return;

    QString a, b;
    if (sep == 0) {
        static const QRegularExpression reDash(R"(^(.+?)\s*[-–—]\s*(.+)$)");
        QRegularExpressionMatch m = reDash.match(base);
        if (!m.hasMatch()) return;
        a = m.captured(1).trimmed();
        b = m.captured(2).trimmed();
    } else {
        static const QRegularExpression reSpace(R"(^(.+?)\s+(\S.*)$)");
        QRegularExpressionMatch m = reSpace.match(base);
        if (!m.hasMatch()) return;
        a = m.captured(1).trimmed();
        b = m.captured(2).trimmed();
    }
    if (a.isEmpty() || b.isEmpty()) return;

    if (order == 0) {           // 歌手 - 歌名
        if (outArtist) *outArtist = a;
        if (outTitle)  *outTitle  = b;
    } else {                    // 歌名 - 歌手
        if (outTitle)  *outTitle  = a;
        if (outArtist) *outArtist = b;
    }
}

// 信息缺失弹窗（QDialog，深色主题与主界面一致）。
// action: 0=应用, 1=跳过, 2=取消（关闭窗口/Esc 视为取消）
class TrackInfoDialog : public QDialog
{
public:
    int action = 2;

    TrackInfoDialog(const QString &fileName, const QString &defaultTitle, QWidget *parent = nullptr)
        : QDialog(parent)
        , m_fileName(fileName)
    {
        setWindowTitle(QStringLiteral("未识别到歌曲信息"));
        setModal(true);
        setMinimumWidth(430);

        setStyleSheet(QStringLiteral(
            "QDialog { background-color: #222222; }"
            "QLabel { color: #dddddd; font-size: 13px; }"
            "QLabel#hint { color: #888888; }"
            "QLabel#preview { background-color: #1E1E1E; color: #dddddd;"
            "  border: 1px solid #3A3A3A; border-radius: 4px; padding: 8px; }"
            "QLineEdit { background-color: #333333; color: #dddddd;"
            "  border: 1px solid #3A3A3A; border-radius: 4px; padding: 5px 8px; font-size: 13px; }"
            "QRadioButton { color: #dddddd; font-size: 13px; spacing: 6px; }"
            "QPushButton { background-color: #1E1E1E; color: #cccccc;"
            "  border: 1px solid #3A3A3A; border-radius: 4px; padding: 6px 16px; font-size: 13px; }"
            "QPushButton:hover { background-color: #333333; }"
            "QPushButton:default { background-color: #3B82F6; color: #ffffff; }"
            "QPushButton:default:hover { background-color: #5B9EF6; }"
        ));

        auto *mainLayout = new QVBoxLayout(this);
        mainLayout->setContentsMargins(18, 16, 18, 14);
        mainLayout->setSpacing(10);

        auto *fileLabel = new QLabel(QStringLiteral("文件名：%1").arg(fileName), this);
        fileLabel->setObjectName("hint");
        fileLabel->setWordWrap(true);
        mainLayout->addWidget(fileLabel);

        // 识别方式
        m_autoRadio = new QRadioButton(QStringLiteral("自动识别文件名"), this);
        m_manualRadio = new QRadioButton(QStringLiteral("手动输入"), this);
        m_autoRadio->setChecked(true);
        auto *modeRow = new QHBoxLayout;
        modeRow->addWidget(m_autoRadio);
        modeRow->addWidget(m_manualRadio);
        modeRow->addStretch();
        mainLayout->addLayout(modeRow);

        // 自动识别：顺序 + 分隔符 + 预览
        m_autoBox = new QWidget(this);
        auto *autoLayout = new QVBoxLayout(m_autoBox);
        autoLayout->setContentsMargins(0, 0, 0, 0);
        autoLayout->setSpacing(8);

        auto *orderRow = new QHBoxLayout;
        orderRow->setSpacing(6);
        orderRow->addWidget(new QLabel(QStringLiteral("顺序："), m_autoBox));
        m_titleFirstRadio  = new QRadioButton(QStringLiteral("歌名 - 歌手"), m_autoBox);
        m_artistFirstRadio = new QRadioButton(QStringLiteral("歌手 - 歌名"), m_autoBox);
        m_titleFirstRadio->setChecked(true);   // 默认“歌名 - 歌手”（常见下载命名）
        auto *orderGroup = new QButtonGroup(this);
        orderGroup->addButton(m_artistFirstRadio, 0);
        orderGroup->addButton(m_titleFirstRadio, 1);
        orderRow->addWidget(m_titleFirstRadio);
        orderRow->addWidget(m_artistFirstRadio);
        orderRow->addSpacing(14);
        orderRow->addWidget(new QLabel(QStringLiteral("分隔："), m_autoBox));
        m_dashRadio  = new QRadioButton(QStringLiteral("-"), m_autoBox);
        m_spaceRadio = new QRadioButton(QStringLiteral("空格"), m_autoBox);
        m_dashRadio->setChecked(true);
        auto *sepGroup = new QButtonGroup(this);
        sepGroup->addButton(m_dashRadio, 0);
        sepGroup->addButton(m_spaceRadio, 1);
        orderRow->addWidget(m_dashRadio);
        orderRow->addWidget(m_spaceRadio);
        orderRow->addStretch();
        autoLayout->addLayout(orderRow);

        m_previewLabel = new QLabel(m_autoBox);
        m_previewLabel->setObjectName("preview");
        autoLayout->addWidget(m_previewLabel);
        m_autoBox->setLayout(autoLayout);
        mainLayout->addWidget(m_autoBox);

        // 手动输入
        m_manualBox = new QWidget(this);
        auto *manualLayout = new QVBoxLayout(m_manualBox);
        manualLayout->setContentsMargins(0, 0, 0, 0);
        manualLayout->setSpacing(8);
        m_artistEdit = new QLineEdit(m_manualBox);
        m_artistEdit->setPlaceholderText(QStringLiteral("歌手（必填）"));
        m_titleEdit = new QLineEdit(m_manualBox);
        m_titleEdit->setPlaceholderText(QStringLiteral("歌名（必填）"));
        m_titleEdit->setText(defaultTitle);
        manualLayout->addWidget(m_titleEdit);
        manualLayout->addWidget(m_artistEdit);
        m_manualBox->setLayout(manualLayout);
        m_manualBox->hide();
        mainLayout->addWidget(m_manualBox);

        // 专辑（可选）
        m_albumEdit = new QLineEdit(this);
        m_albumEdit->setPlaceholderText(QStringLiteral("专辑（可选，不填则留空）"));
        mainLayout->addWidget(m_albumEdit);

        // 按钮
        auto *btnRow = new QHBoxLayout;
        btnRow->addStretch();
        m_cancelBtn = new QPushButton(QStringLiteral("取消导入"), this);
        m_skipBtn   = new QPushButton(QStringLiteral("跳过"), this);
        m_okBtn     = new QPushButton(QStringLiteral("确定"), this);
        m_okBtn->setDefault(true);
        btnRow->addWidget(m_cancelBtn);
        btnRow->addWidget(m_skipBtn);
        btnRow->addWidget(m_okBtn);
        mainLayout->addLayout(btnRow);

        // 自动选择能成功解析的分隔符：先试 '-', 不行再试空格
        // （使用默认顺序“歌名 - 歌手”）
        {
            QString t, a;
            parseFileNameParts(m_fileName, 1, 0, &t, &a);
            if (t.isEmpty() || a.isEmpty()) {
                parseFileNameParts(m_fileName, 1, 1, &t, &a);
                if (!t.isEmpty() && !a.isEmpty())
                    m_spaceRadio->setChecked(true);
            }
        }

        auto updateMode = [this](bool) {
            const bool autoMode = m_autoRadio->isChecked();
            m_autoBox->setVisible(autoMode);
            m_manualBox->setVisible(!autoMode);
            updatePreview();
            updateOk();
        };
        connect(m_autoRadio, &QRadioButton::toggled, this, updateMode);
        connect(m_manualRadio, &QRadioButton::toggled, this, updateMode);
        connect(m_artistFirstRadio, &QRadioButton::toggled, this, [this]() { updatePreview(); updateOk(); });
        connect(m_titleFirstRadio,  &QRadioButton::toggled, this, [this]() { updatePreview(); updateOk(); });
        connect(m_dashRadio,        &QRadioButton::toggled, this, [this]() { updatePreview(); updateOk(); });
        connect(m_spaceRadio,       &QRadioButton::toggled, this, [this]() { updatePreview(); updateOk(); });
        connect(m_artistEdit, &QLineEdit::textChanged, this, [this]() { updateOk(); });
        connect(m_titleEdit,  &QLineEdit::textChanged, this, [this]() { updateOk(); });
        connect(m_cancelBtn, &QPushButton::clicked, this, [this]() { action = 2; reject(); });
        connect(m_skipBtn,   &QPushButton::clicked, this, [this]() { action = 1; reject(); });
        connect(m_okBtn,     &QPushButton::clicked, this, [this]() { action = 0; accept(); });

        updatePreview();
        updateOk();

        // 自动/手动两个内容区固定等高：切换模式时上方的“文件名/模式选择”
        // 与下方的专辑/按钮位置均保持不变
        {
            const int contentH = m_autoBox->sizeHint().height();
            m_autoBox->setFixedHeight(contentH);
            m_manualBox->setFixedHeight(contentH);
        }

        // 锁定窗口尺寸（以较高的“自动识别”模式为准），切换自动/手动时窗口大小不再跳动
        adjustSize();
        setFixedSize(sizeHint());
    }

    QString title() const  { return m_titleEdit->text().trimmed(); }
    QString artist() const { return m_artistEdit->text().trimmed(); }
    QString album() const  { return m_albumEdit->text().trimmed(); }

private:
    void currentAuto(QString *outTitle, QString *outArtist) const {
        const int order = m_artistFirstRadio->isChecked() ? 0 : 1;
        const int sep   = m_dashRadio->isChecked() ? 0 : 1;
        parseFileNameParts(m_fileName, order, sep, outTitle, outArtist);
    }

    void updatePreview() {
        if (!m_autoRadio->isChecked()) return;
        QString t, a;
        currentAuto(&t, &a);
        if (t.isEmpty() && a.isEmpty()) {
            m_previewLabel->setText(QStringLiteral("歌名：（无法识别）\n歌手：（无法识别）"));
        } else {
            m_previewLabel->setText(QStringLiteral("歌名：%1\n歌手：%2")
                .arg(t.isEmpty() ? QStringLiteral("（无法识别）") : t,
                     a.isEmpty() ? QStringLiteral("（无法识别）") : a));
        }
        // 同步到手动输入框，便于切换方式后直接确认
        m_titleEdit->setText(t);
        m_artistEdit->setText(a);
    }

    void updateOk() {
        if (m_autoRadio->isChecked()) {
            QString t, a;
            currentAuto(&t, &a);
            m_okBtn->setEnabled(!t.isEmpty() && !a.isEmpty());
        } else {
            m_okBtn->setEnabled(!m_titleEdit->text().trimmed().isEmpty()
                             && !m_artistEdit->text().trimmed().isEmpty());
        }
    }

    QString m_fileName;
    QRadioButton *m_autoRadio = nullptr;
    QRadioButton *m_manualRadio = nullptr;
    QRadioButton *m_artistFirstRadio = nullptr;
    QRadioButton *m_titleFirstRadio = nullptr;
    QRadioButton *m_dashRadio = nullptr;
    QRadioButton *m_spaceRadio = nullptr;
    QLabel *m_previewLabel = nullptr;
    QWidget *m_autoBox = nullptr;
    QWidget *m_manualBox = nullptr;
    QLineEdit *m_artistEdit = nullptr;
    QLineEdit *m_titleEdit = nullptr;
    QLineEdit *m_albumEdit = nullptr;
    QPushButton *m_cancelBtn = nullptr;
    QPushButton *m_skipBtn = nullptr;
    QPushButton *m_okBtn = nullptr;
};

// 阻塞弹窗（QDialog::exec）：返回 0=应用, 1=跳过, 2=取消
int MusicManager::promptMissingInfo(const QString &filePath, const QString &defaultTitle,
                                    QString *outTitle, QString *outArtist, QString *outAlbum) {
    TrackInfoDialog dlg(QFileInfo(filePath).completeBaseName(), defaultTitle);
    // 确保弹窗显示在 QML 主窗口之上（QWidget 弹窗与 QQuickWindow 可能存在层级问题）
    QTimer::singleShot(0, &dlg, [&dlg]() {
        dlg.raise();
        dlg.activateWindow();
    });
    qDebug() << "[ImportDebug] promptMissingInfo exec start" << filePath;
    const int rc = dlg.exec();
    qDebug() << "[ImportDebug] promptMissingInfo exec done rc=" << rc;
    if (rc == QDialog::Accepted) {
        if (outTitle)  *outTitle  = dlg.title();
        if (outArtist) *outArtist = dlg.artist();
        if (outAlbum)  *outAlbum  = dlg.album();
        return 0;
    }
    return dlg.action;  // 1=跳过, 2=取消
}
