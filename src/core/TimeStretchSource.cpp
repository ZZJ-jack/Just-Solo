/*
 * TimeStretchSource.cpp —— 时间拉伸数据源实现（详见 TimeStretchSource.h）
 */
#include "TimeStretchSource.h"
#include "decoder_backends.h"   // 自定义解码后端（Opus / AAC）
#include "SoundTouch.h"

#include <algorithm>
#include <cstring>

// 每次从解码器读取/输出缓冲的容量（样本数），帧数 = 容量 / 声道数
static constexpr ma_uint32 kBufSamples = 16384;

TimeStretchSource::TimeStretchSource()
{
    ma_data_source_config cfg = ma_data_source_config_init();
    cfg.vtable = &k_vtable;
    ma_data_source_init(&cfg, &base);
}

TimeStretchSource::~TimeStretchSource()
{
    close();
}

bool TimeStretchSource::open(const QString &filePath)
{
    close();

    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 0, 0); // 原生声道/采样率，输出 f32
    ma_decoding_backend_vtable *backends[] = {
        ma_decoding_backend_libopus,
        ma_decoding_backend_fdkaac
    };
    cfg.ppCustomBackendVTables = backends;
    cfg.customBackendCount = sizeof(backends) / sizeof(backends[0]);

    ma_result r;
#ifdef Q_OS_WIN
    r = ma_decoder_init_file_w(filePath.toStdWString().c_str(), &cfg, &m_decoder);
#else
    r = ma_decoder_init_file(filePath.toUtf8().constData(), &cfg, &m_decoder);
#endif
    if (r != MA_SUCCESS) {
        return false;
    }

    ma_format fmt = ma_format_unknown;
    if (ma_decoder_get_data_format(&m_decoder, &fmt, &channels, &sampleRate,
                                   nullptr, 0) != MA_SUCCESS
        || fmt != ma_format_f32 || channels == 0 || sampleRate == 0) {
        close();
        return false;
    }

    try {
        m_st = new soundtouch::SoundTouch;
        m_st->setSampleRate(sampleRate);
        m_st->setChannels(channels);
        m_st->setTempo(1.0);
        // 关闭快速搜索以获得更好音质（变速倍率范围不大，CPU 开销可接受）
        m_st->setSetting(SETTING_USE_QUICKSEEK, 0);
    } catch (...) {
        delete m_st;
        m_st = nullptr;
        ma_decoder_uninit(&m_decoder);
        m_opened = false;
        return false;
    }

    m_inBuf.resize(kBufSamples * channels);
    m_outBuf.resize(kBufSamples * channels);
    m_inputFramesFed = 0;
    m_sourcePosFrames = 0.0;
    m_tempo = 1.0f;
    m_eof = false;
    m_opened = true;

    // 文件总源帧数：游标上限（seek 后 inputFramesFed 会归零，不能用它做钳制）
    if (ma_decoder_get_length_in_pcm_frames(&m_decoder, &m_totalFrames) != MA_SUCCESS) {
        m_totalFrames = 0;
    }
    return true;
}

void TimeStretchSource::close()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_st) {
        delete m_st;
        m_st = nullptr;
    }
    if (m_opened) {
        ma_decoder_uninit(&m_decoder);
        m_opened = false;
    }
    m_inputFramesFed = 0;
    m_sourcePosFrames = 0.0;
    m_totalFrames = 0;
    m_tempo = 1.0f;
    m_eof = false;
    channels = 0;
    sampleRate = 0;
}

void TimeStretchSource::setTempo(float tempo)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_st) {
        m_st->setTempo(tempo);
    }
    m_tempo = tempo;
}

// ---- ma_data_source 回调 ----

ma_result TimeStretchSource::onRead(ma_data_source *pDS, void *pFramesOut,
                                    ma_uint64 frameCount, ma_uint64 *pFramesRead)
{
    if (pFramesRead) *pFramesRead = 0;
    auto *self = reinterpret_cast<TimeStretchSource *>(pDS);
    if (!self->m_st || !self->m_opened) {
        return MA_AT_END;
    }

    std::lock_guard<std::mutex> lock(self->m_mutex);
    const ma_uint32 ch = self->channels;
    float *out = static_cast<float *>(pFramesOut);
    ma_uint64 total = 0;

    try {
        while (total < frameCount) {
            // 1) 先取已处理好的输出
            const uint want = static_cast<uint>(
                std::min<ma_uint64>(frameCount - total, self->m_outBuf.size() / ch));
            uint got = self->m_st->receiveSamples(self->m_outBuf.data(), want);
            if (got > 0) {
                std::memcpy(out + total * ch, self->m_outBuf.data(),
                            static_cast<size_t>(got) * ch * sizeof(float));
                total += got;
                // 源位置增量累加：产出 got 帧输出对应 got×tempo 帧源音频，
                // 变速中途变化也保持位置连续
                self->m_sourcePosFrames += static_cast<double>(got) * self->m_tempo;
                continue;
            }

            // 2) 已到底且输出排空 → 结束
            if (self->m_eof) {
                break;
            }

            // 3) 解码更多输入
            ma_uint64 framesRead = 0;
            ma_result r = ma_decoder_read_pcm_frames(
                &self->m_decoder, self->m_inBuf.data(), self->m_inBuf.size() / ch, &framesRead);
            if (r != MA_SUCCESS && r != MA_AT_END) {
                // 解码异常按 EOF 处理，先排空已有输出
                self->m_eof = true;
                self->m_st->flush();
                continue;
            }
            if (framesRead > 0) {
                self->m_st->putSamples(self->m_inBuf.data(), static_cast<uint>(framesRead));
                self->m_inputFramesFed += framesRead;
                continue;
            }

            // 4) 解码器到底：flush 排空 SoundTouch 尾音
            self->m_eof = true;
            self->m_st->flush();
        }
    } catch (...) {
        // SoundTouch 抛异常时安全退出（避免异常穿越音频回调）
        self->m_eof = true;
    }

    if (pFramesRead) *pFramesRead = total;
    return MA_SUCCESS;   // total == 0 时上层会转为 MA_AT_END
}

ma_result TimeStretchSource::onSeek(ma_data_source *pDS, ma_uint64 frameIndex)
{
    auto *self = reinterpret_cast<TimeStretchSource *>(pDS);
    std::lock_guard<std::mutex> lock(self->m_mutex);
    if (self->m_st) {
        self->m_st->clear();
    }
    self->m_inputFramesFed = 0;
    self->m_eof = false;
    // 游标回到目标源帧：seek 后引擎从新位置拉取数据
    self->m_sourcePosFrames = static_cast<double>(frameIndex);
    return ma_decoder_seek_to_pcm_frame(&self->m_decoder, frameIndex);
}

ma_result TimeStretchSource::onGetDataFormat(ma_data_source *pDS, ma_format *pFormat,
                                             ma_uint32 *pChannels, ma_uint32 *pSampleRate,
                                             ma_channel *pChannelMap, size_t channelMapCap)
{
    auto *self = reinterpret_cast<TimeStretchSource *>(pDS);
    if (pFormat) *pFormat = ma_format_f32;
    if (pChannels) *pChannels = self->channels;
    if (pSampleRate) *pSampleRate = self->sampleRate;
    (void)pChannelMap;
    (void)channelMapCap;
    return MA_SUCCESS;
}

ma_result TimeStretchSource::onGetCursor(ma_data_source *pDS, ma_uint64 *pCursor)
{
    auto *self = reinterpret_cast<TimeStretchSource *>(pDS);
    if (!self->m_st || !self->m_opened) {
        if (pCursor) *pCursor = self->m_inputFramesFed;
        return MA_SUCCESS;
    }

    std::lock_guard<std::mutex> lock(self->m_mutex);
    // 游标以源（文件）帧表示：随产出增量累加，变速/seek 后均保持与实际可听位置一致
    ma_uint64 pos = static_cast<ma_uint64>(self->m_sourcePosFrames);
    // 上限钳制到文件总帧数（仅防 EOF 处舍入越界）
    if (self->m_totalFrames > 0 && pos > self->m_totalFrames) {
        pos = self->m_totalFrames;
    }
    *pCursor = pos;
    return MA_SUCCESS;
}

ma_result TimeStretchSource::onGetLength(ma_data_source *pDS, ma_uint64 *pLength)
{
    auto *self = reinterpret_cast<TimeStretchSource *>(pDS);
    return ma_decoder_get_length_in_pcm_frames(&self->m_decoder, pLength);
}

ma_result TimeStretchSource::onSetLooping(ma_data_source *pDS, ma_bool32 isLooping)
{
    (void)pDS;
    (void)isLooping;
    // 循环由上层 MusicManager 通过 endOfMedia 处理，数据源不实现内部循环
    return MA_NOT_IMPLEMENTED;
}

ma_data_source_vtable TimeStretchSource::k_vtable = {
    TimeStretchSource::onRead,
    TimeStretchSource::onSeek,
    TimeStretchSource::onGetDataFormat,
    TimeStretchSource::onGetCursor,
    TimeStretchSource::onGetLength,
    TimeStretchSource::onSetLooping,
    0
};
