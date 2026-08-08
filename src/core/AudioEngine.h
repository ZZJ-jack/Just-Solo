#ifndef AUDIOENGINE_H
#define AUDIOENGINE_H

#include <QObject>
#include <QString>
#include <QTimer>

struct ma_engine;
struct ma_sound;
struct ma_context;
struct ma_device;
struct ma_resource_manager;

class AudioEngine : public QObject
{
    Q_OBJECT
public:
    explicit AudioEngine(QObject *parent = nullptr);
    ~AudioEngine() override;

    bool load(const QString &filePath);
    void play();
    void pause();
    void stop();
    void seek(qint64 ms);

    qint64 position() const;
    qint64 duration() const;
    void setVolume(float vol);
    float volume() const;
    void setPitch(float pitch);
    float pitch() const { return m_pitch; }
    bool isPlaying() const;

    // WASAPI 输出模式：true=独占, false=共享（默认）。切换时重建引擎并保留播放现场。
    // 返回请求的模式是否实际生效（独占失败会自动回退共享并返回 false）
    bool exclusive() const { return m_exclusive; }
    bool setExclusiveMode(bool exclusive, bool force = false);  // force=true 跳过探测强制尝试开启独占
    // 探测 WASAPI 独占通道：0=可用，1=被其他独占客户端占用，2=设备不支持等其他原因不可用
    int exclusiveModeProbe() const;

signals:
    void positionChanged(qint64 ms);
    void playbackStateChanged();
    void endOfMedia();
    void durationChanged();

private:
    void pollAudio();
    void retryLoad();

    // 设备回调：驱动引擎混音输出（ma_engine_data_callback 为内部静态函数，这里等价实现）
    static void deviceDataCallback(ma_device *pDevice, void *pFramesOut,
                                   const void *pFramesIn, unsigned int frameCount);

    bool initAudioDevice();    // 按 m_exclusive 创建 context/device/engine
    void shutdownAudioDevice(); // 逆序销毁 sound/engine/device/context
    // 音频通道是否被占用：有其他进程正在播放且设备确实在出声（Active 会话 + 峰值），
    // 或被其他独占客户端占用（MA_BUSY/MA_ACCESS_DENIED）时为 true；
    // 已暂停/静默或"流运行但无声"的会话不视为占用
    bool audioChannelInUse() const;

    ma_context *m_context = nullptr;
    ma_device *m_device = nullptr;
    ma_engine *m_engine = nullptr;
    ma_resource_manager *m_resourceManager = nullptr;  // 注册自定义解码后端（Opus/AAC）
    bool m_resourceManagerInited = false;
    ma_sound *m_sound = nullptr;
    bool m_soundInitialized = false;
    bool m_exclusive = false;  // true=WASAPI 独占, false=共享

    QString m_currentFilePath;
    qint64 m_cachedDuration = 0;   // milliseconds
    bool m_wasPlaying = false;
    float m_volume = 0.9f;
    float m_pitch = 1.0f;  // 变速倍率 (0.5-2.0)，改变 pitch 会同时改变播放速度

    // Hotplug retry: 设备拔出时冻结状态并定时重试
    bool m_hotplugMode = false;
    QString m_hotplugFilePath;
    qint64 m_hotplugPosition = 0;
    bool m_hotplugWasPlaying = false;
    qint64 m_hotplugDuration = 0;
    QTimer *m_retryTimer = nullptr;
};

#endif
