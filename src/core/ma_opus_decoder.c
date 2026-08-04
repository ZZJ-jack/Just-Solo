/*
 * ma_opus_decoder.c —— miniaudio 自定义解码后端：Opus（.opus）
 *
 * 基于 libopus + libopusfile（OGG 容器 + Opus 解码，支持链式流与精确 seek）。
 * 本实现参考 miniaudio 官方 extras/decoders/libopus/miniaudio_libopus.c，
 * 仅保留 onInit（read/seek/tell 回调）路径：miniaudio 对文件路径会通过默认
 * VFS（Windows 下 CreateFileW，天然支持中文路径）回调本后端的 onInit，
 * 由 opusfile 通过 op_open_callbacks 驱动。
 *
 * 编译本文件需要：libogg / libopus / libopusfile 头文件与库。
 */
#include "miniaudio.h"
#include "decoder_backends.h"
#include <string.h>

#if !defined(MA_NO_LIBOPUS)
#include <opusfile.h>
#endif

typedef struct
{
    ma_data_source_base ds;
    ma_read_proc onRead;
    ma_seek_proc onSeek;
    ma_tell_proc onTell;
    void* pReadSeekTellUserData;
    ma_format format;           /* f32 或 s16，由 preferredFormat 决定 */
    void* of;                   /* OggOpusFile*，void* 避免头文件依赖 opusfile */
} ma_opus;

/* ---- ma_data_source 接口 ---- */
static ma_result ma_opus_ds_read(ma_data_source* pDataSource, void* pFramesOut, ma_uint64 frameCount, ma_uint64* pFramesRead)
{
    ma_opus* pOpus = (ma_opus*)pDataSource;
    ma_result result;
    ma_uint64 totalFramesRead;
    ma_uint32 channels;

    if (pFramesRead != NULL) *pFramesRead = 0;
    if (frameCount == 0 || pOpus == NULL) return MA_INVALID_ARGS;

    result = ma_opus_ds_get_data_format(pOpus, NULL, &channels, NULL, NULL, 0);
    if (result != MA_SUCCESS) return result;

    totalFramesRead = 0;
    while (totalFramesRead < frameCount) {
        long libopusResult;
        ma_uint64 framesToRead = 1024;
        const ma_uint64 framesRemaining = frameCount - totalFramesRead;
        if (framesToRead > framesRemaining) framesToRead = framesRemaining;

#if !defined(MA_NO_LIBOPUS)
        if (pOpus->format == ma_format_f32) {
            libopusResult = op_read_float((OggOpusFile*)pOpus->of,
                (float*)ma_offset_pcm_frames_ptr(pFramesOut, totalFramesRead, ma_format_f32, channels),
                (int)(framesToRead * channels), NULL);
        } else {
            libopusResult = op_read((OggOpusFile*)pOpus->of,
                (opus_int16*)ma_offset_pcm_frames_ptr(pFramesOut, totalFramesRead, ma_format_s16, channels),
                (int)(framesToRead * channels), NULL);
        }
#else
        libopusResult = -1;
#endif

        if (libopusResult < 0) {
            result = MA_ERROR;   /* 解码出错 */
            break;
        }
        totalFramesRead += (ma_uint64)libopusResult;
        if (libopusResult == 0) {
            result = MA_AT_END;  /* 流结束 */
            break;
        }
    }

    if (pFramesRead != NULL) *pFramesRead = totalFramesRead;
    if (result == MA_SUCCESS && totalFramesRead == 0) result = MA_AT_END;
    return result;
}

static ma_result ma_opus_ds_seek(ma_data_source* pDataSource, ma_uint64 frameIndex)
{
    ma_opus* pOpus = (ma_opus*)pDataSource;
    if (pOpus == NULL) return MA_INVALID_ARGS;
#if !defined(MA_NO_LIBOPUS)
    {
        int libopusResult = op_pcm_seek((OggOpusFile*)pOpus->of, (ogg_int64_t)frameIndex);
        if (libopusResult != 0) {
            if (libopusResult == OP_ENOSEEK) return MA_INVALID_OPERATION;   /* 不可 seek */
            if (libopusResult == OP_EINVAL) return MA_INVALID_ARGS;
            return MA_ERROR;
        }
        return MA_SUCCESS;
    }
#else
    (void)frameIndex;
    return MA_NOT_IMPLEMENTED;
#endif
}

static ma_result ma_opus_ds_get_data_format(ma_data_source* pDataSource, ma_format* pFormat, ma_uint32* pChannels, ma_uint32* pSampleRate, ma_channel* pChannelMap, size_t channelMapCap)
{
    ma_opus* pOpus = (ma_opus*)pDataSource;
    if (pFormat != NULL) *pFormat = ma_format_unknown;
    if (pChannels != NULL) *pChannels = 0;
    if (pSampleRate != NULL) *pSampleRate = 0;
    if (pChannelMap != NULL) memset(pChannelMap, 0, sizeof(*pChannelMap) * channelMapCap);
    if (pOpus == NULL) return MA_INVALID_OPERATION;

    if (pFormat != NULL) *pFormat = pOpus->format;
#if !defined(MA_NO_LIBOPUS)
    {
        ma_uint32 channels = (ma_uint32)op_channel_count((OggOpusFile*)pOpus->of, -1);
        if (pChannels != NULL) *pChannels = channels;
        if (pSampleRate != NULL) *pSampleRate = 48000;   /* Opus 解码输出固定 48kHz */
        if (pChannelMap != NULL)
            ma_channel_map_init_standard(ma_standard_channel_map_vorbis, pChannelMap, channelMapCap, channels);
        return MA_SUCCESS;
    }
#else
    return MA_NOT_IMPLEMENTED;
#endif
}

static ma_result ma_opus_ds_get_cursor(ma_data_source* pDataSource, ma_uint64* pCursor)
{
    ma_opus* pOpus = (ma_opus*)pDataSource;
    if (pCursor == NULL) return MA_INVALID_ARGS;
    *pCursor = 0;
    if (pOpus == NULL) return MA_INVALID_ARGS;
#if !defined(MA_NO_LIBOPUS)
    {
        ogg_int64_t offset = op_pcm_tell((OggOpusFile*)pOpus->of);
        if (offset < 0) return MA_INVALID_FILE;
        *pCursor = (ma_uint64)offset;
        return MA_SUCCESS;
    }
#else
    return MA_NOT_IMPLEMENTED;
#endif
}

static ma_result ma_opus_ds_get_length(ma_data_source* pDataSource, ma_uint64* pLength)
{
    ma_opus* pOpus = (ma_opus*)pDataSource;
    if (pLength == NULL) return MA_INVALID_ARGS;
    *pLength = 0;
    if (pOpus == NULL) return MA_INVALID_ARGS;
#if !defined(MA_NO_LIBOPUS)
    {
        ogg_int64_t length = op_pcm_total((OggOpusFile*)pOpus->of, -1);
        if (length < 0) return MA_ERROR;
        *pLength = (ma_uint64)length;
        return MA_SUCCESS;
    }
#else
    return MA_NOT_IMPLEMENTED;
#endif
}

static ma_data_source_vtable g_ma_opus_ds_vtable =
{
    ma_opus_ds_read,
    ma_opus_ds_seek,
    ma_opus_ds_get_data_format,
    ma_opus_ds_get_cursor,
    ma_opus_ds_get_length,
    NULL,   /* onSetLooping */
    0       /* flags */
};

#if !defined(MA_NO_LIBOPUS)
/* ---- opusfile 回调：桥接到 miniaudio VFS 的 read/seek/tell ---- */
static int ma_opus_of_callback__read(void* pUserData, unsigned char* pBufferOut, int bytesToRead)
{
    ma_opus* pOpus = (ma_opus*)pUserData;
    ma_result result;
    size_t bytesRead = 0;
    result = pOpus->onRead(pOpus->pReadSeekTellUserData, (void*)pBufferOut, (size_t)bytesToRead, &bytesRead);
    if (result != MA_SUCCESS && result != MA_AT_END) return -1;
    return (int)bytesRead;
}

static int ma_opus_of_callback__seek(void* pUserData, ogg_int64_t offset, int whence)
{
    ma_opus* pOpus = (ma_opus*)pUserData;
    ma_seek_origin origin;
    if (whence == SEEK_SET) origin = ma_seek_origin_start;
    else if (whence == SEEK_END) origin = ma_seek_origin_end;
    else origin = ma_seek_origin_current;
    if (pOpus->onSeek(pOpus->pReadSeekTellUserData, (ma_int64)offset, origin) != MA_SUCCESS) return -1;
    return 0;
}

static opus_int64 ma_opus_of_callback__tell(void* pUserData)
{
    ma_opus* pOpus = (ma_opus*)pUserData;
    ma_int64 cursor = 0;
    if (pOpus->onTell == NULL) return -1;
    if (pOpus->onTell(pOpus->pReadSeekTellUserData, &cursor) != MA_SUCCESS) return -1;
    return cursor;
}
#endif

static ma_result ma_opus_init_internal(const ma_decoding_backend_config* pConfig, ma_opus* pOpus)
{
    ma_data_source_config dataSourceConfig;
    if (pOpus == NULL) return MA_INVALID_ARGS;

    memset(pOpus, 0, sizeof(*pOpus));
    pOpus->format = ma_format_f32;
    if (pConfig != NULL && (pConfig->preferredFormat == ma_format_f32 || pConfig->preferredFormat == ma_format_s16)) {
        pOpus->format = pConfig->preferredFormat;
    }

    dataSourceConfig = ma_data_source_config_init();
    dataSourceConfig.vtable = &g_ma_opus_ds_vtable;
    return ma_data_source_init(&dataSourceConfig, &pOpus->ds);
}

static ma_result ma_opus_init(ma_read_proc onRead, ma_seek_proc onSeek, ma_tell_proc onTell, void* pReadSeekTellUserData,
    const ma_decoding_backend_config* pConfig, const ma_allocation_callbacks* pAllocationCallbacks, ma_opus* pOpus)
{
    ma_result result;
    (void)pAllocationCallbacks;

    result = ma_opus_init_internal(pConfig, pOpus);
    if (result != MA_SUCCESS) return result;
    if (onRead == NULL || onSeek == NULL) return MA_INVALID_ARGS;

    pOpus->onRead = onRead;
    pOpus->onSeek = onSeek;
    pOpus->onTell = onTell;
    pOpus->pReadSeekTellUserData = pReadSeekTellUserData;

#if !defined(MA_NO_LIBOPUS)
    {
        int libopusResult;
        OpusFileCallbacks libopusCallbacks;
        libopusCallbacks.read  = ma_opus_of_callback__read;
        libopusCallbacks.seek  = ma_opus_of_callback__seek;
        libopusCallbacks.close = NULL;
        libopusCallbacks.tell  = ma_opus_of_callback__tell;
        pOpus->of = op_open_callbacks(pOpus, &libopusCallbacks, NULL, 0, &libopusResult);
        if (pOpus->of == NULL) return MA_INVALID_FILE;
        return MA_SUCCESS;
    }
#else
    return MA_NOT_IMPLEMENTED;
#endif
}

static void ma_opus_uninit(ma_opus* pOpus, const ma_allocation_callbacks* pAllocationCallbacks)
{
    if (pOpus == NULL) return;
    (void)pAllocationCallbacks;
#if !defined(MA_NO_LIBOPUS)
    op_free((OggOpusFile*)pOpus->of);
#endif
    ma_data_source_uninit(&pOpus->ds);
}

/* ---- 解码后端 vtable（仅 onInit，文件路径由 miniaudio VFS 回调驱动） ---- */
static ma_result ma_decoding_backend_init__libopus(void* pUserData, ma_read_proc onRead, ma_seek_proc onSeek,
    ma_tell_proc onTell, void* pReadSeekTellUserData, const ma_decoding_backend_config* pConfig,
    const ma_allocation_callbacks* pAllocationCallbacks, ma_data_source** ppBackend)
{
    ma_result result;
    ma_opus* pOpus;
    (void)pUserData;

    pOpus = (ma_opus*)ma_malloc(sizeof(*pOpus), pAllocationCallbacks);
    if (pOpus == NULL) return MA_OUT_OF_MEMORY;

    result = ma_opus_init(onRead, onSeek, onTell, pReadSeekTellUserData, pConfig, pAllocationCallbacks, pOpus);
    if (result != MA_SUCCESS) {
        ma_free(pOpus, pAllocationCallbacks);
        return result;
    }
    *ppBackend = pOpus;
    return MA_SUCCESS;
}

static void ma_decoding_backend_uninit__libopus(void* pUserData, ma_data_source* pBackend, const ma_allocation_callbacks* pAllocationCallbacks)
{
    ma_opus* pOpus = (ma_opus*)pBackend;
    (void)pUserData;
    ma_opus_uninit(pOpus, pAllocationCallbacks);
    ma_free(pOpus, pAllocationCallbacks);
}

static ma_decoding_backend_vtable ma_gDecodingBackendVTable_libopus =
{
    ma_decoding_backend_init__libopus,
    NULL,   /* onInitFile() */
    NULL,   /* onInitFileW() */
    NULL,   /* onInitMemory() */
    ma_decoding_backend_uninit__libopus
};

ma_decoding_backend_vtable* ma_decoding_backend_libopus = &ma_gDecodingBackendVTable_libopus;
