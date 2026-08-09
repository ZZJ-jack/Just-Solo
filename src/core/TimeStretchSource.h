/*
 * TimeStretchSource.h —— 时间拉伸数据源（变速不变调 / 音调补偿）
 *
 * 将 ma_decoder（解码本地文件）与 SoundTouch（时间拉伸算法）封装为一个
 * 自定义 ma_data_source，挂载到 ma_sound 上由引擎拉取：
 *
 *   文件 → ma_decoder 解码(f32) → SoundTouch::setTempo(speed) → 引擎输出
 *
 * 音频回调线程中调用 onRead；UI 线程调用 setTempo/onGetCursor 等，内部用互斥锁保护。
 * 注意：ma_sound_init_from_data_source 不会接管数据源所有权，须由持有方负责销毁。
 */
#ifndef TIMESTRETCHSOURCE_H
#define TIMESTRETCHSOURCE_H

#include "miniaudio.h"

#include <QString>
#include <mutex>
#include <vector>

namespace soundtouch { class SoundTouch; }

class TimeStretchSource
{
public:
    TimeStretchSource();
    ~TimeStretchSource();

    // 打开文件并初始化解码器 + SoundTouch；失败返回 false
    bool open(const QString &filePath);
    void close();

    // 设置变速倍率（0.5 ~ 2.0），线程安全
    void setTempo(float tempo);

    // ma_data_source 基类，必须作为第一个成员（回调据此从地址找回自身）
    ma_data_source_base base;

    ma_uint32 channels = 0;
    ma_uint32 sampleRate = 0;

private:
    ma_decoder m_decoder;
    soundtouch::SoundTouch *m_st = nullptr;
    std::mutex m_mutex;
    std::vector<float> m_inBuf;   // 解码缓冲（样本）
    std::vector<float> m_outBuf;  // 处理后输出缓冲（样本）
    ma_uint64 m_inputFramesFed = 0;      // 已送入 SoundTouch 的输入帧数（源帧）
    double m_sourcePosFrames = 0.0;      // 游标（源帧）：随产出增量累加，变速后仍连续
    ma_uint64 m_totalFrames = 0;          // 文件总源帧数（游标上限）
    float m_tempo = 1.0f;                 // 当前变速倍率（源帧 = 输出帧 × tempo）
    bool m_eof = false;              // 解码器已读完且已 flush
    bool m_opened = false;

    // ma_data_source 回调
    static ma_result onRead(ma_data_source *pDS, void *pFramesOut,
                            ma_uint64 frameCount, ma_uint64 *pFramesRead);
    static ma_result onSeek(ma_data_source *pDS, ma_uint64 frameIndex);
    static ma_result onGetDataFormat(ma_data_source *pDS, ma_format *pFormat,
                                     ma_uint32 *pChannels, ma_uint32 *pSampleRate,
                                     ma_channel *pChannelMap, size_t channelMapCap);
    static ma_result onGetCursor(ma_data_source *pDS, ma_uint64 *pCursor);
    static ma_result onGetLength(ma_data_source *pDS, ma_uint64 *pLength);
    static ma_result onSetLooping(ma_data_source *pDS, ma_bool32 isLooping);

    static ma_data_source_vtable k_vtable;
};

#endif // TIMESTRETCHSOURCE_H
