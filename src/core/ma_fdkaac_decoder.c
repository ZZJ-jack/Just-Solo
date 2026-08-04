/*
 * ma_fdkaac_decoder.c —— miniaudio 自定义解码后端：AAC（.aac / .m4a / .mp4）
 *
 * 基于 fdk-aac（AAC 解码器库），支持两种容器：
 *   - .aac ：裸 ADTS 流（逐帧扫描建立索引，支持 VBR 与精确 seek）
 *   - .m4a/.mp4 ：MP4 容器（解析 moov/stbl 原子建立采样表，fdk-aac 解码）
 *
 * 输出固定为 s16 交错 PCM（FDK-AAC 的 INT_PCM 输出），采样率/声道由解码器
 * 实时上报（HE-AAC/SBR 会输出 2 倍采样率）。
 *
 * 仅实现 onInit（read/seek/tell 回调）：miniaudio 对文件路径通过默认 VFS
 * （Windows 下 CreateFileW，天然支持中文路径）回调本后端的 onInit。
 *
 * 编译本文件需要：fdk-aac（libAACdec/include 等）头文件与静态库。
 */
#include "miniaudio.h"
#include "decoder_backends.h"
#include <string.h>
#include <stdlib.h>

#if !defined(MA_NO_FDKAAC)
#include "aacdecoder_lib.h"
#endif

#define MA_FDKAAC_MAX_CHANNELS  (8)          /* 最大输出声道数（7.1 = 8ch） */
#define MA_FDKAAC_MAX_FRAMESIZE (4096)       /* USAC 最大帧尺寸 */
#define MA_FDKAAC_PCM_CAP       (MA_FDKAAC_MAX_CHANNELS * MA_FDKAAC_MAX_FRAMESIZE)  /* shorts */

#define MA_FDKAAC_MIN(a, b) ((a) < (b) ? (a) : (b))

typedef struct
{
    ma_uint64 offset;   /* 绝对文件偏移 */
    ma_uint32 size;     /* 帧/采样字节数 */
    ma_uint32 duration; /* ADTS: 输出帧数（首帧解码后填充）；MP4: stts 时长（timescale 单位） */
} ma_fdkaac_sample;

typedef struct
{
    ma_data_source_base ds;
    ma_read_proc onRead;
    ma_seek_proc onSeek;
    ma_tell_proc onTell;
    void* pReadSeekTellUserData;
    ma_allocation_callbacks alloc;

    int isMP4;                  /* 0=ADTS, 1=MP4 容器 */
    ma_uint64 fileSize;
    ma_uint64 startOffset;      /* ADTS 数据起点（跳过 ID3 等） */

    /* 输出格式（首帧解码后确定，可能随流更新） */
    ma_uint32 channels;
    ma_uint32 sampleRate;
    ma_uint64 lengthInFrames;   /* 输出 PCM 帧总数 */
    ma_uint64 cursor;           /* 当前游标（输出 PCM 帧） */

#if !defined(MA_NO_FDKAAC)
    HANDLE_AACDECODER decoder;
#endif

    /* 采样表 */
    ma_fdkaac_sample* pSamples;
    ma_uint64 sampleCount;
    ma_uint64 sampleIndex;      /* 下一个待解码采样 */
    ma_uint64* pCumDurations;   /* MP4: 累计时长（timescale 单位），用于 seek 二分查找 */

    /* 解码缓冲 */
    ma_uint8* pSampleData;      /* 单帧数据缓冲 */
    size_t sampleDataCap;
    short* pPcm;                /* FDK 输出缓冲（交错） */
    ma_uint32 pcmCap;           /* shorts */
    ma_uint32 pcmCount;         /* 有效帧数 */
    ma_uint32 pcmPos;           /* 已消费帧数 */

    /* MP4 解析中间态 */
    ma_uint32 mp4Timescale;
    ma_uint32 mp4SampleCount;
    ma_uint32 mp4ChunkCount;
    ma_uint64* mp4ChunkOffsets;
    ma_uint32* mp4StscFirst;        /* 原始 stsc 条目（first_chunk 为 1 基） */
    ma_uint32* mp4StscSamples;
    ma_uint32 mp4StscEntries;
    ma_uint32* mp4SampleSizes;
    ma_uint32* mp4SttsCounts;
    ma_uint32* mp4SttsDeltas;
    ma_uint32 mp4SttsEntries;
    ma_uint8* pAsc;
    ma_uint32 ascSize;
    ma_uint64 mp4CumTotal;          /* 全部采样时长之和（timescale 单位） */
} ma_fdkaac;

/* ------------------------------------------------------------------ */
/* 大端工具                                                             */
/* ------------------------------------------------------------------ */
static ma_uint32 ma_fdkaac_be32(const ma_uint8* p)
{
    return ((ma_uint32)p[0] << 24) | ((ma_uint32)p[1] << 16) |
           ((ma_uint32)p[2] << 8) | (ma_uint32)p[3];
}

static ma_uint64 ma_fdkaac_be64(const ma_uint8* p)
{
    return ((ma_uint64)ma_fdkaac_be32(p) << 32) | ma_fdkaac_be32(p + 4);
}

/* 在指定偏移读取完整数据（循环读直到读满） */
static ma_result ma_fdkaac_read_at(ma_fdkaac* pF, ma_uint64 offset, void* pBuf, size_t size)
{
    ma_uint8* p = (ma_uint8*)pBuf;
    size_t total = 0;
    ma_result result = pF->onSeek(pF->pReadSeekTellUserData, (ma_int64)offset, ma_seek_origin_start);
    if (result != MA_SUCCESS) return result;
    while (total < size) {
        size_t bytesRead = 0;
        result = pF->onRead(pF->pReadSeekTellUserData, p + total, size - total, &bytesRead);
        if (result != MA_SUCCESS && result != MA_AT_END) return result;
        if (bytesRead == 0) return MA_AT_END;   /* EOF */
        total += bytesRead;
    }
    return MA_SUCCESS;
}

/* ------------------------------------------------------------------ */
/* 格式探测：ADTS / MP4 / ID3                                          */
/* ------------------------------------------------------------------ */
static ma_bool32 ma_fdkaac_is_adts(const ma_uint8* h, size_t n)
{
    if (n < 7) return MA_FALSE;
    /* 同步字 0xFFF + layer==00（ID 位与保护位忽略） */
    return (h[0] == 0xFF) && ((h[1] & 0xF6) == 0xF0);
}

static ma_result ma_fdkaac_probe(ma_fdkaac* pF)
{
    ma_uint8 hdr[16];
    ma_int64 end = 0;
    if (pF->onTell == NULL) return MA_INVALID_FILE;
    if (pF->onSeek(pF->pReadSeekTellUserData, 0, ma_seek_origin_end) != MA_SUCCESS) return MA_INVALID_FILE;
    if (pF->onTell(pF->pReadSeekTellUserData, &end) != MA_SUCCESS) return MA_INVALID_FILE;
    pF->fileSize = (end < 0) ? 0 : (ma_uint64)end;
    if (pF->fileSize < 16) return MA_INVALID_FILE;

    ma_result result = ma_fdkaac_read_at(pF, 0, hdr, 16);
    if (result != MA_SUCCESS) return result;

    /* ID3v2 标签（.aac 文件常见），跳过 */
    pF->startOffset = 0;
    if (hdr[0] == 'I' && hdr[1] == 'D' && hdr[2] == '3') {
        if (pF->fileSize < 10) return MA_INVALID_FILE;
        ma_uint8 id3[10];
        result = ma_fdkaac_read_at(pF, 0, id3, 10);
        if (result != MA_SUCCESS) return result;
        ma_uint64 tagSize = ((ma_uint64)(id3[6] & 0x7F) << 21) | ((ma_uint64)(id3[7] & 0x7F) << 14) |
                            ((ma_uint64)(id3[8] & 0x7F) << 7) | (ma_uint64)(id3[9] & 0x7F);
        pF->startOffset = 10 + tagSize;
        if ((id3[5] & 0x10) != 0) pF->startOffset += 10;   /* footer 标志 */
        if (pF->startOffset + 7 > pF->fileSize) return MA_INVALID_FILE;
        result = ma_fdkaac_read_at(pF, pF->startOffset, hdr, 7);
        if (result != MA_SUCCESS) return result;
    }

    if (ma_fdkaac_is_adts(hdr, 7)) {
        pF->isMP4 = 0;   /* 裸 ADTS 流 */
        return MA_SUCCESS;
    }

    /* 其余一律按 MP4 容器尝试（首盒可能是 ftyp/moov/free/wide 等），
     * 无 moov/mp4a 时由后续解析返回失败，miniaudio 会继续尝试其他后端 */
    pF->isMP4 = 1;
    return MA_SUCCESS;
}

/* ------------------------------------------------------------------ */
/* ADTS 帧索引：扫描全部帧，支持 VBR 与精确 seek                       */
/* ------------------------------------------------------------------ */
static ma_result ma_fdkaac_scan_adts(ma_fdkaac* pF)
{
    ma_uint8 hdr[7];
    ma_uint64 pos = pF->startOffset;
    ma_uint64 cap = 0;
    ma_uint64 count = 0;

    while (pos + 7 <= pF->fileSize) {
        if (ma_fdkaac_read_at(pF, pos, hdr, 7) != MA_SUCCESS) break;
        if (!ma_fdkaac_is_adts(hdr, 7)) { pos += 1; continue; }
        ma_uint32 frameLen = ((ma_uint32)(hdr[3] & 0x03) << 11) |
                             ((ma_uint32)hdr[4] << 3) |
                             ((ma_uint32)hdr[5] >> 5);
        if (frameLen < 7 || pos + frameLen > pF->fileSize) break;
        if (count >= cap) {
            ma_uint64 newCap = (cap == 0) ? 4096 : cap * 2;
            ma_fdkaac_sample* pNew = (ma_fdkaac_sample*)ma_realloc(pF->pSamples, (size_t)newCap * sizeof(*pNew), &pF->alloc);
            if (pNew == NULL) return MA_OUT_OF_MEMORY;
            pF->pSamples = pNew;
            cap = newCap;
        }
        pF->pSamples[count].offset = pos;
        pF->pSamples[count].size = frameLen;
        pF->pSamples[count].duration = 0;   /* 首帧解码后填充 */
        count++;
        pos += frameLen;
    }
    if (count == 0) return MA_INVALID_FILE;
    pF->sampleCount = count;
    return MA_SUCCESS;
}

/* ------------------------------------------------------------------ */
/* MP4 解析：遍历盒结构提取音频采样表                                  */
/* ------------------------------------------------------------------ */
/* 盒迭代器回调：type + data 区段，返回 MA_NOT_IMPLEMENTED 表示继续遍历，
 * 返回其他值（MA_SUCCESS / 错误码）表示停止遍历并向外传递。 */
typedef ma_result (*ma_fdkaac_box_cb)(ma_fdkaac* pF, const char* type, ma_uint64 dataPos, ma_uint64 dataSize);

/* 前向声明 */
static ma_result ma_fdkaac_parse_stbl_box(ma_fdkaac* pF, const char* type, ma_uint64 dataPos, ma_uint64 dataSize);
static ma_result ma_fdkaac_parse_minf_box(ma_fdkaac* pF, const char* type, ma_uint64 dataPos, ma_uint64 dataSize);
static ma_result ma_fdkaac_parse_moov(ma_fdkaac* pF, ma_uint64 pos, ma_uint64 end);

static ma_result ma_fdkaac_walk_boxes(ma_fdkaac* pF, ma_uint64 pos, ma_uint64 end, ma_fdkaac_box_cb cb)
{
    ma_uint8 hdr[16];
    while (pos + 8 <= end) {
        ma_result result = ma_fdkaac_read_at(pF, pos, hdr, 8);
        if (result != MA_SUCCESS) return result;
        ma_uint64 boxSize = ma_fdkaac_be32(hdr);
        size_t hdrSize = 8;
        char type[5] = { (char)hdr[4], (char)hdr[5], (char)hdr[6], (char)hdr[7], 0 };
        if (boxSize == 1) {
            result = ma_fdkaac_read_at(pF, pos + 8, hdr + 8, 8);
            if (result != MA_SUCCESS) return result;
            boxSize = ma_fdkaac_be64(hdr + 8);
            hdrSize = 16;
        } else if (boxSize == 0) {
            boxSize = end - pos;
        }
        if (boxSize < hdrSize || pos + boxSize > end) return MA_INVALID_FILE;
        result = cb(pF, type, pos + hdrSize, boxSize - hdrSize);
        if (result != MA_NOT_IMPLEMENTED) return result;   /* 停止（命中或出错） */
        pos += boxSize;
    }
    return MA_NOT_IMPLEMENTED;   /* 遍历完毕，未停止 */
}

/* 解析 esds 盒内的 AudioSpecificConfig（type 参数与 ma_fdkaac_box_cb 一致，忽略非 esds 盒） */
static ma_result ma_fdkaac_parse_esds(ma_fdkaac* pF, const char* type, ma_uint64 dataPos, ma_uint64 dataSize)
{
    if (strcmp(type, "esds") != 0) return MA_NOT_IMPLEMENTED;
    if (dataSize < 8) return MA_INVALID_FILE;
    ma_uint8* pBuf = (ma_uint8*)ma_malloc((size_t)dataSize, &pF->alloc);
    if (pBuf == NULL) return MA_OUT_OF_MEMORY;
    ma_result result = ma_fdkaac_read_at(pF, dataPos, pBuf, (size_t)dataSize);
    if (result != MA_SUCCESS) { ma_free(pBuf, &pF->alloc); return result; }

    size_t cap = (size_t)dataSize;
    size_t pos = 4;   /* 跳过 version/flags */

    /* ES_Descriptor (0x03) */
    if (pos >= cap || pBuf[pos] != 0x03) { ma_free(pBuf, &pF->alloc); return MA_INVALID_FILE; }
    pos++;
    size_t consumed = 0;
    ma_uint32 esLen = 0;
    while (pos < cap) {
        ma_uint8 b = pBuf[pos++];
        esLen = (esLen << 7) | (b & 0x7F);
        if ((b & 0x80) == 0) break;
    }
    if (pos + 3 > cap) { ma_free(pBuf, &pF->alloc); return MA_INVALID_FILE; }
    (void)esLen;
    ma_uint8 flags = pBuf[pos + 2];
    pos += 3;   /* ES_ID(2) + flags(1) */
    if (flags & 0x80) pos += 2;             /* dependsOn_ES_ID */
    if (flags & 0x40) { if (pos >= cap) { ma_free(pBuf, &pF->alloc); return MA_INVALID_FILE; } pos += 1 + pBuf[pos]; }
    if (flags & 0x20) pos += 2;             /* OCR_ES_ID */

    /* DecoderConfigDescriptor (0x04) */
    if (pos >= cap || pBuf[pos] != 0x04) { ma_free(pBuf, &pF->alloc); return MA_INVALID_FILE; }
    pos++;
    while (pos < cap) {
        ma_uint8 b = pBuf[pos++];
        if ((b & 0x80) == 0) break;
    }
    pos += 13;  /* objectTypeIndication(1) + streamType(1) + bufferSize(3) + maxBitrate(4) + avgBitrate(4) */

    /* DecoderSpecificInfo (0x05) → ASC */
    if (pos >= cap || pBuf[pos] != 0x05) { ma_free(pBuf, &pF->alloc); return MA_INVALID_FILE; }
    pos++;
    ma_uint32 ascLen = 0;
    while (pos < cap) {
        ma_uint8 b = pBuf[pos++];
        ascLen = (ascLen << 7) | (b & 0x7F);
        if ((b & 0x80) == 0) break;
    }
    if (ascLen == 0 || pos + ascLen > cap) { ma_free(pBuf, &pF->alloc); return MA_INVALID_FILE; }

    ma_uint8* pAsc = (ma_uint8*)ma_malloc(ascLen, &pF->alloc);
    if (pAsc == NULL) { ma_free(pBuf, &pF->alloc); return MA_OUT_OF_MEMORY; }
    memcpy(pAsc, pBuf + pos, ascLen);
    pF->pAsc = pAsc;
    pF->ascSize = ascLen;
    ma_free(pBuf, &pF->alloc);
    return MA_NOT_IMPLEMENTED;   /* 提取完成，继续遍历（可能还有别的音轨） */
}

/* 解析 stsd：从 'mp4a' 采样条目中提取 esds → ASC */
static ma_result ma_fdkaac_parse_stsd(ma_fdkaac* pF, ma_uint64 dataPos, ma_uint64 dataSize)
{
    if (dataSize < 8) return MA_INVALID_FILE;
    ma_uint8 hdr[8];
    ma_result result = ma_fdkaac_read_at(pF, dataPos, hdr, 8);
    if (result != MA_SUCCESS) return result;
    ma_uint32 entryCount = ma_fdkaac_be32(hdr + 4);
    ma_uint64 pos = dataPos + 8;
    ma_uint64 end = dataPos + dataSize;
    ma_uint32 i;
    for (i = 0; i < entryCount && pos + 8 <= end; i++) {
        result = ma_fdkaac_read_at(pF, pos, hdr, 8);
        if (result != MA_SUCCESS) return result;
        ma_uint64 entrySize = ma_fdkaac_be32(hdr);
        char fmt[5] = { (char)hdr[4], (char)hdr[5], (char)hdr[6], (char)hdr[7], 0 };
        if (entrySize < 16 || pos + entrySize > end) return MA_INVALID_FILE;
        if (strcmp(fmt, "mp4a") == 0) {
            /* AudioSampleEntry：SampleEntry(16) + 音频特定字段(20: version/revision/
             * vendor/channelcount/samplesize/predefined/reserved/samplerate)，
             * version>=1 时还有额外字段，esds 等子盒在其后 */
            ma_uint64 childPos = pos + 16 + 20;
            ma_uint64 childEnd = pos + entrySize;
            if (pos + 16 + 20 <= childEnd) {
                ma_uint8 audioHdr[20];
                if (ma_fdkaac_read_at(pF, pos + 16, audioHdr, 20) == MA_SUCCESS) {
                    ma_uint16 version = (ma_uint16)((audioHdr[0] << 8) | audioHdr[1]);
                    if (version == 1) childPos += 16;
                    else if (version == 2) childPos += 36;
                }
            } else {
                childPos = childEnd;
            }
            if (childPos < childEnd) {
                ma_fdkaac_walk_boxes(pF, childPos, childEnd, (ma_fdkaac_box_cb)ma_fdkaac_parse_esds);
            }
        }
        pos += entrySize;
    }
    return MA_NOT_IMPLEMENTED;   /* 继续遍历其他子盒 */
}

/* 解析 stbl 的子盒 */
static ma_result ma_fdkaac_parse_stbl(ma_fdkaac* pF, ma_uint64 dataPos, ma_uint64 dataSize)
{
    return ma_fdkaac_walk_boxes(pF, dataPos, dataPos + dataSize, (ma_fdkaac_box_cb)ma_fdkaac_parse_stbl_box);
}

static ma_result ma_fdkaac_parse_stts(ma_fdkaac* pF, ma_uint64 dataPos, ma_uint64 dataSize)
{
    ma_uint8 hdr[8];
    if (dataSize < 8) return MA_INVALID_FILE;
    ma_result result = ma_fdkaac_read_at(pF, dataPos, hdr, 8);
    if (result != MA_SUCCESS) return result;
    ma_uint32 count = ma_fdkaac_be32(hdr + 4);
    if (count == 0 || (ma_uint64)count * 8 + 8 > dataSize) return MA_INVALID_FILE;
    pF->mp4SttsCounts = (ma_uint32*)ma_malloc((size_t)count * sizeof(ma_uint32), &pF->alloc);
    pF->mp4SttsDeltas = (ma_uint32*)ma_malloc((size_t)count * sizeof(ma_uint32), &pF->alloc);
    if (pF->mp4SttsCounts == NULL || pF->mp4SttsDeltas == NULL) return MA_OUT_OF_MEMORY;
    pF->mp4SttsEntries = count;
    ma_uint64 pos = dataPos + 8;
    ma_uint32 i;
    for (i = 0; i < count; i++) {
        result = ma_fdkaac_read_at(pF, pos + (ma_uint64)i * 8, hdr, 8);
        if (result != MA_SUCCESS) return result;
        pF->mp4SttsCounts[i] = ma_fdkaac_be32(hdr);
        pF->mp4SttsDeltas[i] = ma_fdkaac_be32(hdr + 4);
    }
    return MA_NOT_IMPLEMENTED;   /* 继续遍历其他子盒 */
}

static ma_result ma_fdkaac_parse_stsc(ma_fdkaac* pF, ma_uint64 dataPos, ma_uint64 dataSize)
{
    ma_uint8 hdr[12];   /* 每条目 12 字节: first_chunk(4) + samples_per_chunk(4) + sd_index(4) */
    if (dataSize < 8) return MA_INVALID_FILE;
    ma_result result = ma_fdkaac_read_at(pF, dataPos, hdr, 8);
    if (result != MA_SUCCESS) return result;
    ma_uint32 count = ma_fdkaac_be32(hdr + 4);
    if ((ma_uint64)count * 12 + 8 > dataSize) return MA_INVALID_FILE;
    /* 每个条目: first_chunk(1基), samples_per_chunk, sample_description_index。
     * 注意 stsc 通常位于 stco 之前，chunk 总数此时未知，因此只保存原始条目，
     * 展开到逐 chunk 采样数在 build_mp4_sample_table 中完成。 */
    pF->mp4StscFirst = (ma_uint32*)ma_malloc((size_t)count * sizeof(ma_uint32), &pF->alloc);
    pF->mp4StscSamples = (ma_uint32*)ma_malloc((size_t)count * sizeof(ma_uint32), &pF->alloc);
    if (pF->mp4StscFirst == NULL || pF->mp4StscSamples == NULL) return MA_OUT_OF_MEMORY;
    pF->mp4StscEntries = count;
    ma_uint32 i;
    for (i = 0; i < count; i++) {
        result = ma_fdkaac_read_at(pF, dataPos + 8 + (ma_uint64)i * 12, hdr, 12);
        if (result != MA_SUCCESS) return result;
        pF->mp4StscFirst[i] = ma_fdkaac_be32(hdr);
        pF->mp4StscSamples[i] = ma_fdkaac_be32(hdr + 4);
    }
    return MA_NOT_IMPLEMENTED;
}

/* 查询第 chunk（1 基）的采样数：取 last entry with first_chunk <= chunk */
static ma_uint32 ma_fdkaac_stsc_lookup(ma_fdkaac* pF, ma_uint32 chunk1Based)
{
    ma_uint32 spc = 0;
    ma_uint32 i;
    for (i = 0; i < pF->mp4StscEntries; i++) {
        if (pF->mp4StscFirst[i] <= chunk1Based) spc = pF->mp4StscSamples[i];
        else break;
    }
    return spc;
}

static ma_result ma_fdkaac_parse_stsz(ma_fdkaac* pF, ma_uint64 dataPos, ma_uint64 dataSize)
{
    ma_uint8 hdr[12];
    if (dataSize < 12) return MA_INVALID_FILE;
    ma_result result = ma_fdkaac_read_at(pF, dataPos, hdr, 12);
    if (result != MA_SUCCESS) return result;
    ma_uint32 sampleSize = ma_fdkaac_be32(hdr + 4);
    ma_uint32 count = ma_fdkaac_be32(hdr + 8);
    if ((ma_uint64)count * 4 + 12 > dataSize) return MA_INVALID_FILE;
    pF->mp4SampleCount = count;
    pF->mp4SampleSizes = (ma_uint32*)ma_malloc((size_t)count * sizeof(ma_uint32), &pF->alloc);
    if (pF->mp4SampleSizes == NULL) return MA_OUT_OF_MEMORY;
    ma_uint32 i;
    if (sampleSize != 0) {
        for (i = 0; i < count; i++) pF->mp4SampleSizes[i] = sampleSize;
    } else {
        for (i = 0; i < count; i++) {
            result = ma_fdkaac_read_at(pF, dataPos + 12 + (ma_uint64)i * 4, hdr, 4);
            if (result != MA_SUCCESS) return result;
            pF->mp4SampleSizes[i] = ma_fdkaac_be32(hdr);
        }
    }
    return MA_NOT_IMPLEMENTED;
}

static ma_result ma_fdkaac_parse_stco(ma_fdkaac* pF, ma_uint64 dataPos, ma_uint64 dataSize, int co64)
{
    ma_uint8 hdr[8];
    if (dataSize < 8) return MA_INVALID_FILE;
    ma_result result = ma_fdkaac_read_at(pF, dataPos, hdr, 8);
    if (result != MA_SUCCESS) return result;
    ma_uint32 count = ma_fdkaac_be32(hdr + 4);
    ma_uint32 stride = co64 ? 8 : 4;
    if ((ma_uint64)count * stride + 8 > dataSize) return MA_INVALID_FILE;
    pF->mp4ChunkCount = count;
    pF->mp4ChunkOffsets = (ma_uint64*)ma_malloc((size_t)count * sizeof(ma_uint64), &pF->alloc);
    if (pF->mp4ChunkOffsets == NULL) return MA_OUT_OF_MEMORY;
    ma_uint32 i;
    for (i = 0; i < count; i++) {
        result = ma_fdkaac_read_at(pF, dataPos + 8 + (ma_uint64)i * stride, hdr, stride);
        if (result != MA_SUCCESS) return result;
        pF->mp4ChunkOffsets[i] = co64 ? ma_fdkaac_be64(hdr) : (ma_uint64)ma_fdkaac_be32(hdr);
    }
    return MA_NOT_IMPLEMENTED;
}

static ma_result ma_fdkaac_parse_stbl_box(ma_fdkaac* pF, const char* type, ma_uint64 dataPos, ma_uint64 dataSize)
{
    if (strcmp(type, "stsd") == 0) return ma_fdkaac_parse_stsd(pF, dataPos, dataSize);
    if (strcmp(type, "stts") == 0) return ma_fdkaac_parse_stts(pF, dataPos, dataSize);
    if (strcmp(type, "stsc") == 0) return ma_fdkaac_parse_stsc(pF, dataPos, dataSize);
    if (strcmp(type, "stsz") == 0) return ma_fdkaac_parse_stsz(pF, dataPos, dataSize);
    if (strcmp(type, "stco") == 0) return ma_fdkaac_parse_stco(pF, dataPos, dataSize, 0);
    if (strcmp(type, "co64") == 0) return ma_fdkaac_parse_stco(pF, dataPos, dataSize, 1);
    return MA_NOT_IMPLEMENTED;
}

static ma_result ma_fdkaac_parse_mdhd(ma_fdkaac* pF, ma_uint64 dataPos, ma_uint64 dataSize)
{
    /* mdhd: version/flags(4) + creation(4|8) + modification(4|8) + timescale(4) + duration(4|8) */
    ma_uint8 hdr[24];
    if (dataSize < 24) return MA_INVALID_FILE;
    ma_result result = ma_fdkaac_read_at(pF, dataPos, hdr, 24);
    if (result != MA_SUCCESS) return result;
    if (hdr[0] == 0) {
        pF->mp4Timescale = ma_fdkaac_be32(hdr + 12);   /* 4+4+4 */
    } else {
        pF->mp4Timescale = ma_fdkaac_be32(hdr + 20);   /* 4+8+8 */
    }
    return MA_NOT_IMPLEMENTED;
}

/* minf → 需要 hdlr 判定音轨；这里简化：遍历 stbl */
static ma_result ma_fdkaac_parse_minf(ma_fdkaac* pF, ma_uint64 dataPos, ma_uint64 dataSize)
{
    return ma_fdkaac_walk_boxes(pF, dataPos, dataPos + dataSize, (ma_fdkaac_box_cb)ma_fdkaac_parse_minf_box);
}

static ma_result ma_fdkaac_parse_minf_box(ma_fdkaac* pF, const char* type, ma_uint64 dataPos, ma_uint64 dataSize)
{
    if (strcmp(type, "stbl") == 0) return ma_fdkaac_parse_stbl(pF, dataPos, dataSize);
    return MA_NOT_IMPLEMENTED;
}

static ma_result ma_fdkaac_parse_mdia_box(ma_fdkaac* pF, const char* type, ma_uint64 dataPos, ma_uint64 dataSize)
{
    if (strcmp(type, "mdhd") == 0) return ma_fdkaac_parse_mdhd(pF, dataPos, dataSize);
    if (strcmp(type, "minf") == 0) return ma_fdkaac_parse_minf(pF, dataPos, dataSize);
    return MA_NOT_IMPLEMENTED;
}

static ma_result ma_fdkaac_parse_trak_box(ma_fdkaac* pF, const char* type, ma_uint64 dataPos, ma_uint64 dataSize)
{
    if (strcmp(type, "mdia") == 0) {
        /* 找到音频音轨即解析其 stbl；忽略视频轨（无 'soun' 检查，stsd 无 mp4a 会自然失败） */
        return ma_fdkaac_walk_boxes(pF, dataPos, dataPos + dataSize, (ma_fdkaac_box_cb)ma_fdkaac_parse_mdia_box);
    }
    return MA_NOT_IMPLEMENTED;
}

static ma_result ma_fdkaac_parse_moov_box(ma_fdkaac* pF, const char* type, ma_uint64 dataPos, ma_uint64 dataSize)
{
    if (strcmp(type, "trak") == 0) {
        ma_result result = ma_fdkaac_walk_boxes(pF, dataPos, dataPos + dataSize, (ma_fdkaac_box_cb)ma_fdkaac_parse_trak_box);
        return result;   /* 命中（ASC + 采样表都拿到）或继续 */
    }
    return MA_NOT_IMPLEMENTED;
}

/* 解析 moov：遍历全部 trak，尽量收集音频采样所需信息 */
static ma_result ma_fdkaac_parse_moov(ma_fdkaac* pF, ma_uint64 pos, ma_uint64 end)
{
    return ma_fdkaac_walk_boxes(pF, pos, end, (ma_fdkaac_box_cb)ma_fdkaac_parse_moov_box);
}

/* 顶层遍历：定位 moov 并解析（moov 可能在文件末尾，如非 faststart 文件） */
static ma_result ma_fdkaac_parse_mp4(ma_fdkaac* pF)
{
    ma_uint8 hdr[16];
    ma_uint64 pos = 0;
    while (pos + 8 <= pF->fileSize) {
        ma_result result = ma_fdkaac_read_at(pF, pos, hdr, 8);
        if (result != MA_SUCCESS) return result;
        ma_uint64 boxSize = ma_fdkaac_be32(hdr);
        size_t hdrSize = 8;
        char type[5] = { (char)hdr[4], (char)hdr[5], (char)hdr[6], (char)hdr[7], 0 };
        if (boxSize == 1) {
            result = ma_fdkaac_read_at(pF, pos + 8, hdr + 8, 8);
            if (result != MA_SUCCESS) return result;
            boxSize = ma_fdkaac_be64(hdr + 8);
            hdrSize = 16;
        } else if (boxSize == 0) {
            boxSize = pF->fileSize - pos;
        }
        if (boxSize < hdrSize || pos + boxSize > pF->fileSize) return MA_INVALID_FILE;
        if (strcmp(type, "moov") == 0) {
            result = ma_fdkaac_parse_moov(pF, pos + hdrSize, pos + boxSize);
            /* 完整性由 build_mp4_sample_table 校验；MA_NOT_IMPLEMENTED 表示遍历完成 */
            if (result != MA_SUCCESS && result != MA_NOT_IMPLEMENTED) return result;
            return MA_SUCCESS;
        }
        pos += boxSize;
    }
    return MA_INVALID_FILE;   /* 未找到 moov */
}

/* moov 解析完成后，根据 stts/stsc/stsz/stco 构建采样表 */
static ma_result ma_fdkaac_build_mp4_sample_table(ma_fdkaac* pF)
{
    ma_uint32 total = pF->mp4SampleCount;
    if (total == 0 || pF->mp4ChunkCount == 0 || pF->mp4ChunkOffsets == NULL ||
        pF->mp4SampleSizes == NULL || pF->mp4StscEntries == 0 || pF->mp4Timescale == 0 ||
        pF->pAsc == NULL || pF->ascSize == 0) {
        return MA_INVALID_FILE;
    }

    pF->pSamples = (ma_fdkaac_sample*)ma_malloc((size_t)total * sizeof(ma_fdkaac_sample), &pF->alloc);
    pF->pCumDurations = (ma_uint64*)ma_malloc((size_t)(total + 1) * sizeof(ma_uint64), &pF->alloc);
    if (pF->pSamples == NULL || pF->pCumDurations == NULL) return MA_OUT_OF_MEMORY;
    pF->sampleCount = total;

    ma_uint32 chunk = 0;
    ma_uint32 chunkSamplesLeft = 0;
    ma_uint64 chunkOffset = 0;
    ma_uint32 sttsEntry = 0;
    ma_uint32 sttsSamplesLeft = 0;
    ma_uint32 sttsDelta = 0;
    ma_uint64 cum = 0;
    ma_uint32 i;

    pF->pCumDurations[0] = 0;
    for (i = 0; i < total; i++) {
        if (chunkSamplesLeft == 0) {
            if (chunk >= pF->mp4ChunkCount) break;
            chunkSamplesLeft = ma_fdkaac_stsc_lookup(pF, chunk + 1);   /* chunk 为 0 基，stsc 为 1 基 */
            chunkOffset = pF->mp4ChunkOffsets[chunk];
            chunk++;
        }
        if (sttsSamplesLeft == 0 && sttsEntry < pF->mp4SttsEntries) {
            sttsSamplesLeft = pF->mp4SttsCounts[sttsEntry];
            sttsDelta = pF->mp4SttsDeltas[sttsEntry];
            sttsEntry++;
        }
        if (sttsSamplesLeft == 0) break;
        pF->pSamples[i].offset = chunkOffset;
        pF->pSamples[i].size = pF->mp4SampleSizes[i];
        pF->pSamples[i].duration = sttsDelta;
        chunkOffset += pF->mp4SampleSizes[i];
        chunkSamplesLeft--;
        sttsSamplesLeft--;
        cum += sttsDelta;
        pF->pCumDurations[i + 1] = cum;
    }
    if (i == 0) return MA_INVALID_FILE;
    pF->sampleCount = i;
    pF->mp4CumTotal = cum;
    return MA_SUCCESS;
}

/* ------------------------------------------------------------------ */
/* FDK-AAC 解码器打开/关闭                                             */
/* ------------------------------------------------------------------ */
#if !defined(MA_NO_FDKAAC)
static ma_result ma_fdkaac_open_decoder(ma_fdkaac* pF)
{
    TRANSPORT_TYPE tp = pF->isMP4 ? TT_MP4_RAW : TT_MP4_ADTS;
    pF->decoder = aacDecoder_Open(tp, 1);
    if (pF->decoder == NULL) return MA_OUT_OF_MEMORY;
    aacDecoder_SetParam(pF->decoder, AAC_PCM_MAX_OUTPUT_CHANNELS, MA_FDKAAC_MAX_CHANNELS);
    if (pF->isMP4) {
        UCHAR* pConf[1] = { pF->pAsc };
        UINT confLen[1] = { pF->ascSize };
        if (aacDecoder_ConfigRaw(pF->decoder, pConf, confLen) != AAC_DEC_OK) {
            aacDecoder_Close(pF->decoder);
            pF->decoder = NULL;
            return MA_INVALID_FILE;
        }
    }
    return MA_SUCCESS;
}
#endif

/* ------------------------------------------------------------------ */
/* 解码单帧采样（ADTS 帧 / MP4 采样）                                  */
/* ------------------------------------------------------------------ */
static ma_result ma_fdkaac_decode_sample(ma_fdkaac* pF, ma_uint64 sampleIndex, ma_uint32* pOutFrames)
{
    ma_fdkaac_sample* s = &pF->pSamples[sampleIndex];
    *pOutFrames = 0;
    if (s->size == 0) return MA_SUCCESS;   /* 空采样（MP4 padding） */

    if ((size_t)s->size > pF->sampleDataCap) {
        ma_uint8* pNew = (ma_uint8*)ma_realloc(pF->pSampleData, s->size, &pF->alloc);
        if (pNew == NULL) return MA_OUT_OF_MEMORY;
        pF->pSampleData = pNew;
        pF->sampleDataCap = s->size;
    }
    ma_result result = ma_fdkaac_read_at(pF, s->offset, pF->pSampleData, s->size);
    if (result != MA_SUCCESS) return result;

#if !defined(MA_NO_FDKAAC)
    UCHAR* pBuf[1] = { pF->pSampleData };
    UINT bufSize[1] = { s->size };
    UINT bytesValid = s->size;
    AAC_DECODER_ERROR err = aacDecoder_Fill(pF->decoder, pBuf, bufSize, &bytesValid);
    if (err != AAC_DEC_OK && err != AAC_DEC_NOT_ENOUGH_BITS) return MA_SUCCESS;

    /* 容量以 PCM 采样（short）计 */
    err = aacDecoder_DecodeFrame(pF->decoder, pF->pPcm, (INT)pF->pcmCap, 0);
    if (err == AAC_DEC_NOT_ENOUGH_BITS || err == AAC_DEC_TRANSPORT_SYNC_ERROR) return MA_SUCCESS;

    CStreamInfo* info = aacDecoder_GetStreamInfo(pF->decoder);
    if (info != NULL) {
        if (info->numChannels > 0) {
            pF->channels = (ma_uint32)info->numChannels;
            pF->sampleRate = (ma_uint32)info->sampleRate;
            *pOutFrames = (ma_uint32)info->frameSize;
            if (!pF->isMP4) s->duration = *pOutFrames;   /* ADTS：记录每帧输出帧数（HE-AAC 为 2048） */
        }
    }
#else
    (void)result;
#endif
    return MA_SUCCESS;
}

/* ------------------------------------------------------------------ */
/* ma_data_source 接口                                                 */
/* ------------------------------------------------------------------ */
static ma_result ma_fdkaac_read_pcm_frames(ma_fdkaac* pF, void* pFramesOut, ma_uint64 frameCount, ma_uint64* pFramesRead)
{
    short* pOut = (short*)pFramesOut;
    ma_uint64 written = 0;
    if (pFramesRead != NULL) *pFramesRead = 0;

    while (written < frameCount) {
        if (pF->pcmPos < pF->pcmCount) {
            ma_uint32 avail = pF->pcmCount - pF->pcmPos;
            ma_uint32 want = (ma_uint32)MA_FDKAAC_MIN(frameCount - written, avail);
            if (pOut != NULL) {
                memcpy(pOut + written * pF->channels, pF->pPcm + pF->pcmPos * pF->channels,
                       (size_t)want * pF->channels * sizeof(short));
            }
            pF->pcmPos += want;
            written += want;
            continue;
        }
        if (pF->sampleIndex >= pF->sampleCount) break;
        ma_uint32 outFrames = 0;
        ma_result result = ma_fdkaac_decode_sample(pF, pF->sampleIndex, &outFrames);
        pF->sampleIndex++;
        if (result != MA_SUCCESS && result != MA_AT_END) return result;
        if (outFrames > 0) {
            pF->pcmCount = outFrames;
            pF->pcmPos = 0;
        }
    }

    pF->cursor += written;
    if (pFramesRead != NULL) *pFramesRead = written;
    if (written == 0) return MA_AT_END;
    return MA_SUCCESS;
}

static ma_result ma_fdkaac_ds_read(ma_data_source* pDataSource, void* pFramesOut, ma_uint64 frameCount, ma_uint64* pFramesRead)
{
    return ma_fdkaac_read_pcm_frames((ma_fdkaac*)pDataSource, pFramesOut, frameCount, pFramesRead);
}

static ma_result ma_fdkaac_seek_to_pcm_frame(ma_fdkaac* pF, ma_uint64 frameIndex)
{
    if (frameIndex > pF->lengthInFrames) frameIndex = pF->lengthInFrames;

    if (pF->isMP4 && pF->pCumDurations != NULL && pF->mp4Timescale > 0 && pF->sampleRate > 0) {
        /* 输出帧 → timescale 单位 → 二分查找采样 */
        ma_uint64 target = (ma_uint64)((frameIndex * (ma_uint64)pF->mp4Timescale) / (ma_uint64)pF->sampleRate);
        ma_uint64 lo = 0, hi = pF->sampleCount;
        while (lo + 1 < hi) {
            ma_uint64 mid = (lo + hi) / 2;
            if (pF->pCumDurations[mid] <= target) lo = mid; else hi = mid;
        }
        pF->sampleIndex = (target == 0) ? 0 : hi;
    } else {
        ma_uint64 perFrame = (ma_uint64)(pF->pSamples != NULL && pF->pSamples[0].duration > 0
                                         ? pF->pSamples[0].duration
                                         : (pF->sampleCount > 0 ? pF->lengthInFrames / pF->sampleCount : 1));
        if (perFrame == 0) perFrame = 1024;
        pF->sampleIndex = (ma_uint64)(frameIndex / perFrame);
        if (pF->sampleIndex > pF->sampleCount) pF->sampleIndex = pF->sampleCount;
    }

    pF->cursor = frameIndex;
    pF->pcmCount = 0;
    pF->pcmPos = 0;

#if !defined(MA_NO_FDKAAC)
    if (pF->decoder != NULL) {
        aacDecoder_Close(pF->decoder);
        pF->decoder = NULL;
    }
    return ma_fdkaac_open_decoder(pF);
#else
    return MA_NOT_IMPLEMENTED;
#endif
}

static ma_result ma_fdkaac_ds_seek(ma_data_source* pDataSource, ma_uint64 frameIndex)
{
    return ma_fdkaac_seek_to_pcm_frame((ma_fdkaac*)pDataSource, frameIndex);
}

static ma_result ma_fdkaac_get_data_format(ma_fdkaac* pF, ma_format* pFormat, ma_uint32* pChannels, ma_uint32* pSampleRate, ma_channel* pChannelMap, size_t channelMapCap)
{
    if (pFormat != NULL) *pFormat = ma_format_s16;
    if (pChannels != NULL) *pChannels = pF->channels;
    if (pSampleRate != NULL) *pSampleRate = pF->sampleRate;
    if (pChannelMap != NULL) {
        memset(pChannelMap, 0, sizeof(*pChannelMap) * channelMapCap);
        ma_channel_map_init_standard(ma_standard_channel_map_default, pChannelMap, channelMapCap, pF->channels);
    }
    return (pF->sampleRate > 0 && pF->channels > 0) ? MA_SUCCESS : MA_INVALID_OPERATION;
}

static ma_result ma_fdkaac_ds_get_data_format(ma_data_source* pDataSource, ma_format* pFormat, ma_uint32* pChannels, ma_uint32* pSampleRate, ma_channel* pChannelMap, size_t channelMapCap)
{
    return ma_fdkaac_get_data_format((ma_fdkaac*)pDataSource, pFormat, pChannels, pSampleRate, pChannelMap, channelMapCap);
}

static ma_result ma_fdkaac_ds_get_cursor(ma_data_source* pDataSource, ma_uint64* pCursor)
{
    ma_fdkaac* pF = (ma_fdkaac*)pDataSource;
    if (pCursor == NULL) return MA_INVALID_ARGS;
    *pCursor = pF->cursor;
    return MA_SUCCESS;
}

static ma_result ma_fdkaac_ds_get_length(ma_data_source* pDataSource, ma_uint64* pLength)
{
    ma_fdkaac* pF = (ma_fdkaac*)pDataSource;
    if (pLength == NULL) return MA_INVALID_ARGS;
    *pLength = pF->lengthInFrames;
    return MA_SUCCESS;
}

static ma_data_source_vtable g_ma_fdkaac_ds_vtable =
{
    ma_fdkaac_ds_read,
    ma_fdkaac_ds_seek,
    ma_fdkaac_ds_get_data_format,
    ma_fdkaac_ds_get_cursor,
    ma_fdkaac_ds_get_length,
    NULL,   /* onSetLooping */
    0       /* flags */
};

/* ------------------------------------------------------------------ */
/* 初始化 / 反初始化                                                    */
/* ------------------------------------------------------------------ */
static void ma_fdkaac_uninit(ma_fdkaac* pF)
{
    if (pF == NULL) return;
#if !defined(MA_NO_FDKAAC)
    if (pF->decoder != NULL) {
        aacDecoder_Close(pF->decoder);
        pF->decoder = NULL;
    }
#endif
    if (pF->pSamples != NULL) { ma_free(pF->pSamples, &pF->alloc); pF->pSamples = NULL; }
    if (pF->pCumDurations != NULL) { ma_free(pF->pCumDurations, &pF->alloc); pF->pCumDurations = NULL; }
    if (pF->pSampleData != NULL) { ma_free(pF->pSampleData, &pF->alloc); pF->pSampleData = NULL; }
    if (pF->pPcm != NULL) { ma_free(pF->pPcm, &pF->alloc); pF->pPcm = NULL; }
    if (pF->mp4ChunkOffsets != NULL) { ma_free(pF->mp4ChunkOffsets, &pF->alloc); pF->mp4ChunkOffsets = NULL; }
    if (pF->mp4StscFirst != NULL) { ma_free(pF->mp4StscFirst, &pF->alloc); pF->mp4StscFirst = NULL; }
    if (pF->mp4StscSamples != NULL) { ma_free(pF->mp4StscSamples, &pF->alloc); pF->mp4StscSamples = NULL; }
    if (pF->mp4SampleSizes != NULL) { ma_free(pF->mp4SampleSizes, &pF->alloc); pF->mp4SampleSizes = NULL; }
    if (pF->mp4SttsCounts != NULL) { ma_free(pF->mp4SttsCounts, &pF->alloc); pF->mp4SttsCounts = NULL; }
    if (pF->mp4SttsDeltas != NULL) { ma_free(pF->mp4SttsDeltas, &pF->alloc); pF->mp4SttsDeltas = NULL; }
    if (pF->pAsc != NULL) { ma_free(pF->pAsc, &pF->alloc); pF->pAsc = NULL; }
    ma_data_source_uninit(&pF->ds);
}

static ma_result ma_fdkaac_init(ma_read_proc onRead, ma_seek_proc onSeek, ma_tell_proc onTell,
    void* pReadSeekTellUserData, const ma_decoding_backend_config* pConfig,
    const ma_allocation_callbacks* pAllocationCallbacks, ma_fdkaac* pF)
{
    ma_data_source_config dataSourceConfig;
    ma_result result;
    (void)pConfig;

    memset(pF, 0, sizeof(*pF));
    pF->onRead = onRead;
    pF->onSeek = onSeek;
    pF->onTell = onTell;
    pF->pReadSeekTellUserData = pReadSeekTellUserData;
    if (pAllocationCallbacks != NULL) pF->alloc = *pAllocationCallbacks;

    dataSourceConfig = ma_data_source_config_init();
    dataSourceConfig.vtable = &g_ma_fdkaac_ds_vtable;
    result = ma_data_source_init(&dataSourceConfig, &pF->ds);
    if (result != MA_SUCCESS) return result;

    if (onRead == NULL || onSeek == NULL) return MA_INVALID_ARGS;

    result = ma_fdkaac_probe(pF);
    if (result != MA_SUCCESS) goto on_fail;

    /* 构建采样表 */
    if (pF->isMP4) {
        result = ma_fdkaac_parse_mp4(pF);
        if (result != MA_SUCCESS) goto on_fail;
        result = ma_fdkaac_build_mp4_sample_table(pF);
        if (result != MA_SUCCESS) goto on_fail;
    } else {
        result = ma_fdkaac_scan_adts(pF);
        if (result != MA_SUCCESS) goto on_fail;
    }

    /* 解码缓冲 */
    pF->pcmCap = MA_FDKAAC_PCM_CAP;
    pF->pPcm = (short*)ma_malloc((size_t)pF->pcmCap * sizeof(short), &pF->alloc);
    if (pF->pPcm == NULL) { result = MA_OUT_OF_MEMORY; goto on_fail; }
    pF->sampleDataCap = 64 * 1024;
    pF->pSampleData = (ma_uint8*)ma_malloc(pF->sampleDataCap, &pF->alloc);
    if (pF->pSampleData == NULL) { result = MA_OUT_OF_MEMORY; goto on_fail; }

#if !defined(MA_NO_FDKAAC)
    /* 打开解码器并试解码若干帧，确定输出格式（采样率/声道/每帧输出数） */
    result = ma_fdkaac_open_decoder(pF);
    if (result != MA_SUCCESS) goto on_fail;
    {
        ma_uint64 probe = 0;
        while (probe < pF->sampleCount) {
            ma_uint32 outFrames = 0;
            result = ma_fdkaac_decode_sample(pF, probe, &outFrames);
            if (result != MA_SUCCESS) goto on_fail;
            if (outFrames > 0) break;   /* 拿到输出格式 */
            probe++;
        }
        if (probe >= pF->sampleCount) { result = MA_INVALID_FILE; goto on_fail; }
    }
#else
    result = MA_NOT_IMPLEMENTED;
    goto on_fail;
#endif

    if (pF->sampleRate == 0 || pF->channels == 0) { result = MA_INVALID_FILE; goto on_fail; }

    /* 计算总时长 */
    if (pF->isMP4 && pF->mp4Timescale > 0 && pF->mp4CumTotal > 0) {
        pF->lengthInFrames = (ma_uint64)((pF->mp4CumTotal * (ma_uint64)pF->sampleRate) / (ma_uint64)pF->mp4Timescale);
    } else {
        /* ADTS：每帧输出帧数 × 帧数（首帧已由试解码填充 duration） */
        ma_uint32 perFrame = (pF->pSamples != NULL && pF->pSamples[0].duration > 0) ? pF->pSamples[0].duration : 1024;
        if (pF->pSamples != NULL) {
            ma_uint64 i;
            for (i = 1; i < pF->sampleCount; i++) {
                if (pF->pSamples[i].duration == 0) pF->pSamples[i].duration = perFrame;
            }
        }
        pF->lengthInFrames = pF->sampleCount * (ma_uint64)perFrame;
    }

    /* 恢复起点：回到第一帧 */
    pF->sampleIndex = 0;
    pF->cursor = 0;
    pF->pcmCount = 0;
    pF->pcmPos = 0;
#if !defined(MA_NO_FDKAAC)
    if (pF->decoder != NULL) {
        aacDecoder_Close(pF->decoder);
        pF->decoder = NULL;
    }
    result = ma_fdkaac_open_decoder(pF);   /* 干净状态开始播放 */
    if (result != MA_SUCCESS) goto on_fail;
#endif
    return MA_SUCCESS;

on_fail:
    ma_fdkaac_uninit(pF);
    return result;
}

/* ------------------------------------------------------------------ */
/* 解码后端 vtable（仅 onInit，文件路径由 miniaudio VFS 回调驱动）      */
/* ------------------------------------------------------------------ */
static ma_result ma_decoding_backend_init__fdkaac(void* pUserData, ma_read_proc onRead, ma_seek_proc onSeek,
    ma_tell_proc onTell, void* pReadSeekTellUserData, const ma_decoding_backend_config* pConfig,
    const ma_allocation_callbacks* pAllocationCallbacks, ma_data_source** ppBackend)
{
    ma_result result;
    ma_fdkaac* pF;
    (void)pUserData;

    pF = (ma_fdkaac*)ma_malloc(sizeof(*pF), pAllocationCallbacks);
    if (pF == NULL) return MA_OUT_OF_MEMORY;

    result = ma_fdkaac_init(onRead, onSeek, onTell, pReadSeekTellUserData, pConfig, pAllocationCallbacks, pF);
    if (result != MA_SUCCESS) {
        ma_free(pF, pAllocationCallbacks);
        return result;
    }
    *ppBackend = pF;
    return MA_SUCCESS;
}

static void ma_decoding_backend_uninit__fdkaac(void* pUserData, ma_data_source* pBackend, const ma_allocation_callbacks* pAllocationCallbacks)
{
    ma_fdkaac* pF = (ma_fdkaac*)pBackend;
    (void)pUserData;
    ma_fdkaac_uninit(pF);
    ma_free(pF, pAllocationCallbacks);
}

static ma_decoding_backend_vtable ma_gDecodingBackendVTable_fdkaac =
{
    ma_decoding_backend_init__fdkaac,
    NULL,   /* onInitFile() */
    NULL,   /* onInitFileW() */
    NULL,   /* onInitMemory() */
    ma_decoding_backend_uninit__fdkaac
};

ma_decoding_backend_vtable* ma_decoding_backend_fdkaac = &ma_gDecodingBackendVTable_fdkaac;
