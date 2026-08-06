#include "MetadataReader.h"
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QRegularExpression>
#include <QCryptographicHash>
#include <QBuffer>
#include <QImage>
#include <QUrl>
#include <functional>

// ============================================================
// Public API
// ============================================================

QString MetadataReader::cacheCoverThumbnail(const QImage &image, const QString &cacheDir,
                                            const QString &fileNameBase, int maxSize)
{
    if (image.isNull())
        return QString();
    QDir cache(cacheDir);
    if (!cache.exists())
        cache.mkpath(".");
    // 等比缩图到 maxSize 内再落盘，避免全尺寸封面解码占用内存
    QImage thumb = image;
    if (thumb.width() > maxSize || thumb.height() > maxSize)
        thumb = thumb.scaled(maxSize, maxSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    QString cacheFile = cache.filePath(fileNameBase + ".jpg");
    if (!thumb.save(cacheFile, "JPEG", 90)) {
        cacheFile = cache.filePath(fileNameBase + ".png");
        if (!thumb.save(cacheFile, "PNG"))
            return QString();
    }
    return cacheFile;
}

AudioMetadata MetadataReader::read(const QString &filePath, const QString &cacheDir)
{
    AudioMetadata meta;
    QFileInfo fi(filePath);
    if (!fi.exists()) return meta;

    QString ext = fi.suffix().toLower();
    QImage embeddedCover;

    if (ext == "mp3") {
        QMap<QString, QString> tags = readID3v2TextFrames(filePath, &embeddedCover);
        meta.title  = tags.value("TIT2");
        meta.artist = tags.value("TPE1");
        meta.album  = tags.value("TALB");
        meta.tagFound = !tags.isEmpty();
        // TLEN 帧 → 毫秒
        if (tags.contains("TLEN")) {
            bool ok = false;
            int ms = tags.value("TLEN").toInt(&ok);
            if (ok && ms > 0) meta.durationSecs = ms / 1000;
        }
        // 无 TLEN → 从帧头估算
        if (meta.durationSecs == 0) {
            QFile f(filePath);
            if (f.open(QIODevice::ReadOnly)) {
                QByteArray hdr = f.read(10);
                quint32 tagSize = 0;
                bool hasID3 = (hdr.size() >= 10 && hdr.startsWith("ID3"));
                if (hasID3)
                    tagSize = readSynchsafeInt(hdr, 6) + 10;  // 数据 + 头
                f.close();
                meta.durationSecs = estimateMP3Duration(filePath, tagSize);
            }
        }
    } else if (ext == "flac") {
        QMap<QString, QString> tags = readFlacComments(filePath, &embeddedCover, &meta.durationSecs);
        meta.title  = tags.value("TITLE");
        meta.artist = tags.value("ARTIST");
        meta.album  = tags.value("ALBUM");
        meta.tagFound = !tags.isEmpty();
    } else if (ext == "m4a" || ext == "mp4") {
        QMap<QString, QString> tags = readMP4TextTags(filePath, &embeddedCover);
        meta.title  = tags.value("TITLE");
        meta.artist = tags.value("ARTIST");
        meta.album  = tags.value("ALBUM");
        meta.tagFound = !tags.isEmpty();
    } else if (ext == "ogg" || ext == "opus") {
        QMap<QString, QString> tags = readOggTags(filePath, &embeddedCover);
        meta.title  = tags.value("TITLE");
        meta.artist = tags.value("ARTIST");
        meta.album  = tags.value("ALBUM");
        meta.tagFound = !tags.isEmpty();
    }

    // 封面处理（缩图缓存，见 cacheCoverThumbnail）
    if (!embeddedCover.isNull()) {
        QByteArray hash = QCryptographicHash::hash(filePath.toUtf8(), QCryptographicHash::Md5).toHex();
        meta.coverPath = cacheCoverThumbnail(embeddedCover, cacheDir, QString::fromLatin1(hash));
    } else {
        QString external = findExternalCover(filePath);
        if (!external.isEmpty())
            meta.coverPath = external;
    }

    // 清除 ID3v2 null 填充
    auto clean = [](QString &s) { s = s.simplified(); if (s == "0" || s.isEmpty()) s = ""; };
    clean(meta.title);
    clean(meta.artist);
    clean(meta.album);

    // 无标签时从文件名解析
    if (meta.title.isEmpty() && meta.artist.isEmpty()) {
        static QRegularExpression re(R"(^(.+?)\s*[-–—]\s*(.+)$)");
        QRegularExpressionMatch m = re.match(fi.baseName());
        if (m.hasMatch()) {
            meta.artist = m.captured(1).trimmed();
            meta.title  = m.captured(2).trimmed();
        } else {
            meta.title = fi.baseName();
        }
    }

    if (meta.title.isEmpty())
        meta.title = fi.baseName();

    return meta;
}

// ============================================================
// ID3v2 全量解析 (MP3)
// ============================================================

quint32 MetadataReader::readSynchsafeInt(const QByteArray &data, int offset)
{
    quint32 v = 0;
    for (int i = 0; i < 4; i++)
        v = (v << 7) | ((quint8)data[offset + i] & 0x7F);
    return v;
}

quint32 MetadataReader::readBigEndianInt(const QByteArray &data, int offset)
{
    return ((quint8)data[offset] << 24) | ((quint8)data[offset+1] << 16)
         | ((quint8)data[offset+2] << 8)  | (quint8)data[offset+3];
}

QString MetadataReader::readID3v2String(const QByteArray &data, int offset, int maxLen)
{
    if (maxLen <= 1) return "";
    quint8 enc = data[offset];
    int start = offset + 1;
    int len = maxLen - 1;

    if (enc == 0x00) {
        // ISO-8859-1
        int end = start;
        while (end < offset + maxLen && data[end] != 0) end++;
        return QString::fromLatin1(data.mid(start, end - start));
    } else if (enc == 0x01 || enc == 0x02) {
        // UTF-16 (with or without BOM)
        if (len >= 2) {
            // Find null terminator (2 bytes)
            int end = start;
            while (end + 1 < offset + maxLen && !(data[end] == 0 && data[end+1] == 0))
                end += 2;
            QByteArray chunk = data.mid(start, end - start);
            if (enc == 0x01)
                return QString::fromUtf16(reinterpret_cast<const char16_t*>(chunk.constData()), chunk.size() / 2);
            else {
                // UTF-16BE
                QByteArray le;
                le.resize(chunk.size());
                for (int i = 0; i + 1 < chunk.size(); i += 2) {
                    le[i] = chunk[i+1];
                    le[i+1] = chunk[i];
                }
                return QString::fromUtf16(reinterpret_cast<const char16_t*>(le.constData()), le.size() / 2);
            }
        }
    } else if (enc == 0x03) {
        // UTF-8
        int end = start;
        while (end < offset + maxLen && data[end] != 0) end++;
        return QString::fromUtf8(data.mid(start, end - start));
    }
    return "";
}

QMap<QString, QString> MetadataReader::readID3v2TextFrames(const QString &filePath, QImage *outCover)
{
    QMap<QString, QString> tags;
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
        return tags;

    QByteArray header = file.read(10);
    if (header.size() < 10 || !header.startsWith("ID3"))
        return tags;

    int verMajor = header[3];
    int verMinor = header[4];
    bool v24 = (verMajor == 4);
    bool v23 = (verMajor == 3);
    bool v22 = (verMajor == 2);

    quint32 tagSize = readSynchsafeInt(header, 6);
    bool hasFooter = (header[5] & 0x10) != 0;
    quint32 total = tagSize + 10 + (hasFooter ? 10 : 0);

    QByteArray tagData = file.read(total - 10);
    file.close();

    int pos = 0;
    while (pos + 10 <= tagData.size()) {
        if (tagData[pos] == 0) break;

        QString frameId;
        quint32 frameSize;

        if (v22) {
            frameId = QString::fromLatin1(tagData.mid(pos, 3));
            // ID3v2.2: 3-byte big-endian size
            frameSize = ((quint8)tagData[pos+3] << 16) | ((quint8)tagData[pos+4] << 8) | (quint8)tagData[pos+5];
            pos += 6;
        } else {
            frameId = QString::fromLatin1(tagData.mid(pos, 4));
            frameSize = (v24) ? readSynchsafeInt(tagData, pos + 4) : readBigEndianInt(tagData, pos + 4);
            pos += 10;
        }

        if (frameSize == 0 || pos + (int)frameSize > tagData.size()) break;

        QByteArray frameData = tagData.mid(pos, frameSize);
        pos += frameSize;

        // Text frames
        if (frameId == "TIT2" || frameId == "TT2" ||
            frameId == "TPE1" || frameId == "TP1" ||
            frameId == "TALB" || frameId == "TAL" ||
            frameId == "TLEN") {
            QString text = readID3v2String(frameData, 0, frameData.size());
            if (!text.isEmpty())
                tags[frameId.left(v22 ? 3 : 4)] = text;
        }

        // Cover art
        if ((frameId == "APIC" || frameId == "PIC") && outCover) {
            int cursor = 0;
            quint8 enc = frameData[cursor++];

            if (frameId == "PIC") {
                // ID3v2.2 PIC: enc(1) + format(3) + type(1) + desc(null) + data
                cursor += 3;  // skip format
                cursor++;     // skip type
            } else {
                // APIC: enc(1) + mime(null) + type(1) + desc(null) + data
                while (cursor < frameData.size() && frameData[cursor] != 0) cursor++;
                cursor++; // skip null (mime)
                cursor++; // skip picture type
            }
            // skip description
            if (enc == 0x01 || enc == 0x02) {
                while (cursor + 1 < frameData.size() && !(frameData[cursor] == 0 && frameData[cursor+1] == 0))
                    cursor += 2;
                cursor += 2;
            } else {
                while (cursor < frameData.size() && frameData[cursor] != 0) cursor++;
                cursor++;
            }

            if (cursor < frameData.size()) {
                QImage img;
                img.loadFromData(frameData.mid(cursor));
                if (!img.isNull())
                    *outCover = img;
            }
        }
    }

    return tags;
}

// ============================================================
// FLAC 全量解析
// ============================================================

QMap<QString, QString> MetadataReader::readFlacComments(const QString &filePath, QImage *outCover, int *outDuration)
{
    QMap<QString, QString> tags;
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
        return tags;

    QByteArray marker = file.read(4);
    if (marker != "fLaC") {
        file.close();
        return tags;
    }

    bool lastBlock = false;
    while (!lastBlock && !file.atEnd()) {
        QByteArray bh = file.read(4);
        if (bh.size() < 4) break;

        quint8 flags = bh[0];
        lastBlock = (flags & 0x80) != 0;
        quint32 blockSize = ((quint8)bh[1] << 16) | ((quint8)bh[2] << 8) | (quint8)bh[3];
        quint8 blockType = flags & 0x7F;

        QByteArray data = file.read(blockSize);
        if (data.size() < (int)blockSize) break;

        // STREAMINFO (type 0) → 解析时长
        if (blockType == 0 && outDuration && blockSize >= 18) {
            quint32 sampleRate = ((quint8)data[10] << 12) | ((quint8)data[11] << 4) | ((quint8)data[12] >> 4);
            if (sampleRate > 0) {
                // total_samples: 36 bits (byte 12 低 4 位 + byte 13-17)
                quint64 totalSamples = ((quint64)((quint8)data[12] & 0x0F) << 32)
                                     | ((quint64)(quint8)data[13] << 24)
                                     | ((quint64)(quint8)data[14] << 16)
                                     | ((quint64)(quint8)data[15] << 8)
                                     | (quint64)(quint8)data[16];
                if (totalSamples > 0)
                    *outDuration = (int)(totalSamples / sampleRate);
            }
        }

        if (blockType == 4) {
            // Vorbis Comment
            int p = 0;
            if (p + 4 > (int)blockSize) continue;
            quint32 vendorLen = (quint8)data[p] | ((quint8)data[p+1] << 8) | ((quint8)data[p+2] << 16) | ((quint8)data[p+3] << 24);
            p += 4 + vendorLen;
            if (p + 4 > (int)blockSize) continue;
            quint32 count = (quint8)data[p] | ((quint8)data[p+1] << 8) | ((quint8)data[p+2] << 16) | ((quint8)data[p+3] << 24);
            p += 4;

            for (quint32 i = 0; i < count && p + 4 <= (int)blockSize; i++) {
                quint32 len = (quint8)data[p] | ((quint8)data[p+1] << 8) | ((quint8)data[p+2] << 16) | ((quint8)data[p+3] << 24);
                p += 4;
                if (p + (int)len > (int)blockSize) break;
                QByteArray comment = data.mid(p, len);
                p += len;

                int eq = comment.indexOf('=');
                if (eq < 0) continue;
                QString key = QString::fromUtf8(comment.left(eq)).toUpper();
                QString val = QString::fromUtf8(comment.mid(eq + 1));

                if (key == "TITLE" || key == "ARTIST" || key == "ALBUM")
                    tags[key] = val;

                if (key == "METADATA_BLOCK_PICTURE" && outCover && outCover->isNull()) {
                    QByteArray decoded = QByteArray::fromBase64(comment.mid(eq + 1));
                    if (decoded.size() > 32) {
                        int dp = 0;
                        dp += 4; // picture type BE
                        qint32 mimeLen = ((quint8)decoded[dp] << 24) | ((quint8)decoded[dp+1] << 16) | ((quint8)decoded[dp+2] << 8) | (quint8)decoded[dp+3];
                        dp += 4 + mimeLen;
                        qint32 descLen = ((quint8)decoded[dp] << 24) | ((quint8)decoded[dp+1] << 16) | ((quint8)decoded[dp+2] << 8) | (quint8)decoded[dp+3];
                        dp += 4 + descLen;
                        dp += 16; // width(4)+height(4)+depth(4)+colors(4)
                        qint32 dataLen = ((quint8)decoded[dp] << 24) | ((quint8)decoded[dp+1] << 16) | ((quint8)decoded[dp+2] << 8) | (quint8)decoded[dp+3];
                        dp += 4;
                        if (dp + dataLen <= decoded.size()) {
                            QImage img;
                            img.loadFromData(decoded.mid(dp, dataLen));
                            if (!img.isNull())
                                *outCover = img;
                        }
                    }
                }
            }
        }
    }

    file.close();
    return tags;
}

// ============================================================
// MP4/M4A - ilst 元数据（标题/歌手/专辑/歌词）+ covr 封面
// ============================================================

static quint32 mp4BE32(const QByteArray &data, int off)
{
    return ((quint8)data[off] << 24) | ((quint8)data[off+1] << 16)
         | ((quint8)data[off+2] << 8) | (quint8)data[off+3];
}

// 解析 ilst 容器内的条目：©nam/©ART/©alb/©lyr/covr/----(freeform)
static void parseMp4Ilst(const QByteArray &data, int off, int len,
                         QMap<QString, QString> *tags, QImage *outCover)
{
    int p = off;
    int end = off + len;
    while (p + 8 <= end) {
        quint32 sz = mp4BE32(data, p);
        QString type = QString::fromLatin1(data.mid(p + 4, 4));
        if (sz < 8 || p + (int)sz > end) break;
        int childOff = p + 8;
        int childEnd = p + (int)sz;

        if (type == "----") {
            // 自由格式条目：mean(域) + name(键) + data(值)，歌词常用 "LYRICS"
            QString name;
            int q = childOff;
            while (q + 8 <= childEnd) {
                quint32 cs = mp4BE32(data, q);
                QString ct = QString::fromLatin1(data.mid(q + 4, 4));
                if (cs < 8 || q + (int)cs > childEnd) break;
                if (ct == "name")
                    name = QString::fromUtf8(data.mid(q + 8, cs - 8));
                else if (ct == "data" && tags && name.compare(QStringLiteral("LYRICS"), Qt::CaseInsensitive) == 0)
                    (*tags)[QStringLiteral("LYRICS")] = QString::fromUtf8(data.mid(q + 16, cs - 16)).trimmed();
                q += cs;
            }
        } else if (type == "covr") {
            int q = childOff;
            while (q + 12 <= childEnd && outCover && outCover->isNull()) {
                quint32 cs = mp4BE32(data, q);
                QString ct = QString::fromLatin1(data.mid(q + 4, 4));
                if (cs < 12 || q + (int)cs > childEnd) break;
                if (ct == "data") {
                    QImage img;
                    img.loadFromData(data.mid(q + 16, cs - 16));
                    if (!img.isNull()) *outCover = img;
                }
                q += cs;
            }
        } else {
            // 常规文本条目；注意 © 在 MP4 原子类型中是单字节 0xA9
            QString key;
            if (type == QString::fromLatin1("\xA9""nam")) key = "TITLE";
            else if (type == QString::fromLatin1("\xA9""ART") || type == QString::fromLatin1("aART")) key = "ARTIST";
            else if (type == QString::fromLatin1("\xA9""alb")) key = "ALBUM";
            else if (type == QString::fromLatin1("\xA9""lyr")) key = "LYRICS";

            if (!key.isEmpty() && tags) {
                int q = childOff;
                while (q + 8 <= childEnd) {
                    quint32 cs = mp4BE32(data, q);
                    QString ct = QString::fromLatin1(data.mid(q + 4, 4));
                    if (cs < 8 || q + (int)cs > childEnd) break;
                    if (ct == "data") {
                        // data: size(4) + "data"(4) + version/flags(4) + locale(4) + payload
                        QByteArray payload = data.mid(q + 16, cs - 16);
                        QString text = QString::fromUtf8(payload);
                        // 非法 UTF-8 时尝试 UTF-16BE
                        if (text.contains(QChar::ReplacementCharacter) && payload.size() >= 2)
                            text = QString::fromUtf16(reinterpret_cast<const char16_t*>(payload.constData()), payload.size() / 2);
                        (*tags)[key] = text.trimmed();
                        break;
                    }
                    q += cs;
                }
            }
        }
        p += sz;
    }
}

// 递归查找 ilst（moov→udta→meta→ilst）
static void walkMp4Atoms(const QByteArray &data, int off, int len,
                         QMap<QString, QString> *tags, QImage *outCover, int depth)
{
    if (depth > 8) return;
    int p = off;
    int end = off + len;
    while (p + 8 <= end) {
        quint32 sz = mp4BE32(data, p);
        QString type = QString::fromLatin1(data.mid(p + 4, 4));
        if (sz < 8 || p + (int)sz > end) break;

        if (type == "ilst") {
            parseMp4Ilst(data, p + 8, sz - 8, tags, outCover);
            return;
        }
        if (type == "moov" || type == "udta" || type == "trak" || type == "mdia"
            || type == "minf" || type == "stbl") {
            walkMp4Atoms(data, p + 8, sz - 8, tags, outCover, depth + 1);
        } else if (type == "meta") {
            // meta 原子头部后紧跟 4 字节 version/flags
            walkMp4Atoms(data, p + 12, sz - 12, tags, outCover, depth + 1);
        }
        p += sz;
    }
}

QMap<QString, QString> MetadataReader::readMP4TextTags(const QString &filePath, QImage *outCover)
{
    QMap<QString, QString> tags;
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
        return tags;

    // 流式定位 moov：只遍历顶层 atom 头（8 字节），mdat 等大块直接 seek 跳过，
    // 找到 moov 后仅把该区间读入内存（几十 KB ~ 几 MB），避免整文件 readAll
    const qint64 fileSize = file.size();
    qint64 pos = 0;
    while (pos + 8 <= fileSize) {
        if (!file.seek(pos))
            break;
        QByteArray hdr = file.read(8);
        if (hdr.size() < 8)
            break;
        quint32 sz = mp4BE32(hdr, 0);
        if (sz < 8)
            break;
        if (hdr.mid(4, 4) == "moov") {
            const qint64 moovLen = qMin<qint64>(sz, fileSize - pos);
            QByteArray moov = file.read(moovLen);
            walkMp4Atoms(moov, 0, moov.size(), &tags, outCover, 0);
            break;
        }
        pos += sz;  // 跳过该 atom（含 mdat 大块）
    }
    file.close();
    return tags;
}

// ============================================================
// Ogg/Opus - OpusTags / Vorbis 注释头（TITLE/ARTIST/ALBUM/LYRICS）
// ============================================================

QMap<QString, QString> MetadataReader::readOggTags(const QString &filePath, QImage *outCover)
{
    QMap<QString, QString> tags;
    Q_UNUSED(outCover);  // Ogg 封面极少见，暂不解析

    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
        return tags;
    // 注释头只在前几个 Ogg page 内，只读前 1MB 即可，避免整文件 readAll
    QByteArray data = file.read(1024 * 1024);
    file.close();
    if (!data.startsWith("OggS"))
        return tags;

    // 跨页重组 packet（lacing=255 表示分片未结束），找到注释头即停止
    QByteArray curPacket;
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
                QByteArray commentData;
                if (curPacket.startsWith("OpusTags"))
                    commentData = curPacket.mid(8);      // 跳过 "OpusTags"
                else if (curPacket.size() >= 7 && (quint8)curPacket[0] == 0x03
                         && curPacket.mid(1, 6) == "vorbis")
                    commentData = curPacket.mid(7);      // 跳过 0x03+"vorbis"
                if (!commentData.isEmpty()) {
                    // vendor + count + 每条 "KEY=value"
                    int cp = 0;
                    if (cp + 4 <= commentData.size()) {
                        quint32 vendorLen = (quint8)commentData[cp] | ((quint8)commentData[cp+1] << 8)
                                          | ((quint8)commentData[cp+2] << 16) | ((quint8)commentData[cp+3] << 24);
                        cp += 4 + vendorLen;
                        if (cp + 4 <= commentData.size()) {
                            quint32 count = (quint8)commentData[cp] | ((quint8)commentData[cp+1] << 8)
                                          | ((quint8)commentData[cp+2] << 16) | ((quint8)commentData[cp+3] << 24);
                            cp += 4;
                            for (quint32 j = 0; j < count && cp + 4 <= commentData.size(); ++j) {
                                quint32 len = (quint8)commentData[cp] | ((quint8)commentData[cp+1] << 8)
                                            | ((quint8)commentData[cp+2] << 16) | ((quint8)commentData[cp+3] << 24);
                                cp += 4;
                                if (cp + (int)len > commentData.size()) break;
                                QByteArray comment = commentData.mid(cp, len);
                                cp += len;
                                int eq = comment.indexOf('=');
                                if (eq < 0) continue;
                                QString key = QString::fromUtf8(comment.left(eq)).toUpper();
                                QString val = QString::fromUtf8(comment.mid(eq + 1)).trimmed();
                                if (key == "TITLE" || key == "ARTIST" || key == "ALBUM" || key == "LYRICS")
                                    if (!tags.contains(key))
                                        tags[key] = val;
                            }
                        }
                    }
                    commentChecked = true;
                    break;
                }
                curPacket.clear();
            }
        }
        pos = payloadEnd;
    }
    return tags;
}

// ============================================================
// 外部封面
// ============================================================

QString MetadataReader::findExternalCover(const QString &filePath)
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

// ============================================================
// MP3 时长估算：读首个 MPEG 帧头 → bitrate → file_size * 8 / bitrate
// ============================================================

int MetadataReader::estimateMP3Duration(const QString &filePath, quint32 id3TagSize)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
        return 0;

    qint64 fileSize = file.size();
    if (fileSize <= (qint64)id3TagSize)
        return 0;

    file.seek(id3TagSize);
    QByteArray buf = file.read(8192);
    file.close();

    // MPEG1 Layer3 bitrate 表
    static const int brMpeg1[16] = {0,32,40,48,56,64,80,96,112,128,160,192,224,256,320,0};
    // MPEG2/2.5 Layer3 bitrate 表
    static const int brMpeg2[16] = {0,8,16,24,32,40,48,56,64,80,96,112,128,144,160,0};

    for (int i = 0; i + 3 < buf.size(); i++) {
        if ((quint8)buf[i] != 0xFF)
            continue;

        quint8 b2 = (quint8)buf[i + 1];
        // 帧同步：高 3 位必须全 1 (0xE0 mask)
        if ((b2 & 0xE0) != 0xE0)
            continue;

        quint8 mpegVer = (b2 >> 3) & 0x03;  // 0=2.5, 1=reserved, 2=MPEG2, 3=MPEG1
        quint8 layer = (b2 >> 1) & 0x03;     // 0=reserved, 1=Layer3, 2=Layer2, 3=Layer1
        if (mpegVer == 1 || layer != 1)
            continue;

        quint8 b3 = (quint8)buf[i + 2];
        int bitrateIdx = (b3 >> 4) & 0x0F;
        if (bitrateIdx == 0 || bitrateIdx == 15)
            continue;

        // MPEG1 用 brMpeg1，MPEG2/2.5 用 brMpeg2
        const int *table = (mpegVer == 3) ? brMpeg1 : brMpeg2;
        int bitrate = table[bitrateIdx] * 1000;
        if (bitrate <= 0)
            continue;

        qint64 audioBytes = fileSize - id3TagSize;
        int dur = (int)(audioBytes * 8 / bitrate);
        // 合理性检查
        if (dur <= 0 || dur > 3600) return 0;
        return dur;
    }

    return 0;
}
