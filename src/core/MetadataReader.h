#ifndef METADATAREADER_H
#define METADATAREADER_H

#include <QString>
#include <QImage>
#include <QMap>

struct AudioMetadata {
    QString title;
    QString artist;
    QString album;
    QString coverPath;   // 已缓存的 file:/// 格式路径，空=无封面
    int     durationSecs = 0;  // 0=未知
};

class MetadataReader
{
public:
    // 一站式提取所有元数据，封面自动缓存
    static AudioMetadata read(const QString &filePath, const QString &cacheDir);

private:
    // ID3v2 (MP3) - 返回 text frame 字典 + 封面
    static QMap<QString, QString> readID3v2TextFrames(const QString &filePath, QImage *outCover);
    // FLAC Vorbis comment - 返回字段字典 + 封面
    static QMap<QString, QString> readFlacComments(const QString &filePath, QImage *outCover);
    // MP4/M4A
    static QImage readMP4Cover(const QString &filePath);
    // 同目录外部封面
    static QString findExternalCover(const QString &filePath);

    // ID3v2 工具
    static quint32 readSynchsafeInt(const QByteArray &data, int offset);
    static quint32 readBigEndianInt(const QByteArray &data, int offset);
    static QString readID3v2String(const QByteArray &data, int offset, int maxLen);
};

#endif
