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
    } else if (ext == "flac") {
        QMap<QString, QString> tags = readFlacComments(filePath, &embeddedCover);
        meta.title  = tags.value("TITLE");
        meta.artist = tags.value("ARTIST");
        meta.album  = tags.value("ALBUM");
    } else if (ext == "m4a" || ext == "mp4") {
        embeddedCover = readMP4Cover(filePath);
    }

    // 封面处理
    if (!embeddedCover.isNull()) {
        QDir cache(cacheDir);
        if (!cache.exists()) cache.mkpath(".");
        QByteArray hash = QCryptographicHash::hash(filePath.toUtf8(), QCryptographicHash::Md5).toHex();
        QString cacheFile = cache.filePath(QString::fromLatin1(hash) + ".jpg");
        if (embeddedCover.save(cacheFile, "JPEG"))
            meta.coverPath = cacheFile;
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
            frameId == "TALB" || frameId == "TAL") {
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

QMap<QString, QString> MetadataReader::readFlacComments(const QString &filePath, QImage *outCover)
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
// MP4/M4A - 简易 covr 提取
// ============================================================

QImage MetadataReader::readMP4Cover(const QString &filePath)
{
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly))
        return QImage();

    QByteArray data = file.readAll();
    file.close();
    int size = data.size();

    std::function<QImage(const QByteArray&, int, int)> findCovr;
    findCovr = [&](const QByteArray &buf, int off, int len) -> QImage {
        int p = off;
        int end = off + len;
        while (p + 8 <= end) {
            quint32 atomSize = ((quint8)buf[p] << 24) | ((quint8)buf[p+1] << 16) | ((quint8)buf[p+2] << 8) | (quint8)buf[p+3];
            QString type = QString::fromLatin1(buf.mid(p + 4, 4));
            if (atomSize < 8 || p + (int)atomSize > end) break;

            if (type == "covr") {
                // data atom starts at p+8 (skipping size+type of covr)
                // Inside covr: usually "data" atom
                int dp = p + 8;
                int dEnd = p + atomSize;
                while (dp + 12 <= dEnd) {
                    quint32 dSize = ((quint8)buf[dp] << 24) | ((quint8)buf[dp+1] << 16) | ((quint8)buf[dp+2] << 8) | (quint8)buf[dp+3];
                    QString dType = QString::fromLatin1(buf.mid(dp + 4, 4));
                    if (dSize < 12 || dp + (int)dSize > dEnd) break;
                    if (dType == "data") {
                        int imgOff = dp + 12; // skip size+type+reserved(4)
                        int imgLen = dSize - 12;
                        QImage img;
                        img.loadFromData(buf.mid(imgOff, imgLen));
                        return img;
                    }
                    dp += dSize;
                }
                return QImage();
            }

            // Recurse into container atoms
            static QStringList containers = {"moov", "udta", "meta", "ilst"};
            if (containers.contains(type)) {
                int childOff = p + 8;
                if (type == "meta")
                    childOff = p + 12;
                QImage result = findCovr(buf, childOff, atomSize - (childOff - p));
                if (!result.isNull()) return result;
            }

            p += atomSize;
        }
        return QImage();
    };

    return findCovr(data, 0, size);
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
