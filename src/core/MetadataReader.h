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
    bool    tagFound = false;  // 是否从文件内读取到标题/歌手/专辑标签
};

class MetadataReader
{
public:
    // 一站式提取所有元数据，封面自动缓存
    static AudioMetadata read(const QString &filePath, const QString &cacheDir);
    // MP4/M4A - 解析 ilst 文本标签（©nam/©ART/©alb/©lyr/----:LYRICS）+ covr 封面
    static QMap<QString, QString> readMP4TextTags(const QString &filePath, QImage *outCover);
    // Ogg/Opus - 解析 OpusTags / Vorbis 注释头，返回 TITLE/ARTIST/ALBUM/LYRICS
    static QMap<QString, QString> readOggTags(const QString &filePath, QImage *outCover);
    // 封面缓存：等比缩图到 maxSize 内后存为 JPEG(质量90)，失败回退 PNG；返回最终绝对路径（空=失败）
    static QString cacheCoverThumbnail(const QImage &image, const QString &cacheDir,
                                       const QString &fileNameBase, int maxSize = 512);

private:
    // ID3v2 (MP3) - 返回 text frame 字典 + 封面 + TLEN 时长
    static QMap<QString, QString> readID3v2TextFrames(const QString &filePath, QImage *outCover);
    // FLAC Vorbis comment + STREAMINFO 时长
    static QMap<QString, QString> readFlacComments(const QString &filePath, QImage *outCover, int *outDuration);
    // 同目录外部封面
    static QString findExternalCover(const QString &filePath);
    // MP3 估算时长（读首个帧头 bitrate → file_size*8/bitrate）
    static int estimateMP3Duration(const QString &filePath, quint32 id3TagSize);

    // ID3v2 工具
    static quint32 readSynchsafeInt(const QByteArray &data, int offset);
    static quint32 readBigEndianInt(const QByteArray &data, int offset);
    static QString readID3v2String(const QByteArray &data, int offset, int maxLen);
};

#endif
