#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include "decoder_backends.h"   // 自定义解码后端（Opus / AAC）

#include "AudioEngine.h"
#include <QDebug>
#include <QFileInfo>
#include <QTimer>
#include <cstring>
#include <string>

#ifdef Q_OS_WIN
#include <windows.h>
#include <objbase.h>
#include <mmdeviceapi.h>
#include <audiopolicy.h>
#include <audiosessiontypes.h>
#include <endpointvolume.h>   // IAudioMeterInformation：设备级峰值检测
#endif

AudioEngine::AudioEngine(QObject *parent)
    : QObject(parent)
{
    initAudioDevice();

    m_sound = new ma_sound;
    std::memset(m_sound, 0, sizeof(*m_sound));
    m_soundInitialized = false;

    // 轮询定时器：50ms 间隔，用于 positionChanged 和 endOfMedia 检测
    QTimer *pollTimer = new QTimer(this);
    pollTimer->setInterval(50);
    connect(pollTimer, &QTimer::timeout, this, &AudioEngine::pollAudio);
    pollTimer->start(50);

    // 热插拔重试定时器：每秒检查设备是否恢复
    m_retryTimer = new QTimer(this);
    m_retryTimer->setInterval(1000);
    connect(m_retryTimer, &QTimer::timeout, this, &AudioEngine::retryLoad);
}

AudioEngine::~AudioEngine()
{
    m_retryTimer->stop();
    shutdownAudioDevice();
    delete m_sound;
}

// ---- 设备驱动回调：等价于 miniaudio 内部 ma_engine_data_callback ----
void AudioEngine::deviceDataCallback(ma_device *pDevice, void *pFramesOut,
                                     const void *pFramesIn, unsigned int frameCount)
{
    ma_engine *pEngine = static_cast<ma_engine *>(pDevice->pUserData);
    (void)pFramesIn;
    ma_engine_read_pcm_frames(pEngine, pFramesOut, frameCount, nullptr);
}

bool AudioEngine::initAudioDevice()
{
    if (m_engine) return true;

    m_engine = new ma_engine;
    m_context = new ma_context;
    m_device = new ma_device;
    m_resourceManager = new ma_resource_manager;

    ma_context_config contextConfig = ma_context_config_init();
    if (ma_context_init(nullptr, 0, &contextConfig, m_context) != MA_SUCCESS) {
        qWarning("AudioEngine: Failed to initialize miniaudio context");
        goto on_fail;
    }

    // 设备：与引擎内部创建方式一致（f32、原生声道/采样率），仅额外指定 WASAPI 共享/独占模式
    {
        ma_device_config deviceConfig = ma_device_config_init(ma_device_type_playback);
        deviceConfig.playback.format = ma_format_f32;
        deviceConfig.playback.channels = 0;                    // 使用设备原生声道
        deviceConfig.sampleRate = 0;                           // 使用设备原生采样率
        deviceConfig.playback.shareMode = m_exclusive ? ma_share_mode_exclusive
                                                      : ma_share_mode_shared;
        deviceConfig.dataCallback = AudioEngine::deviceDataCallback;
        deviceConfig.pUserData = m_engine;
        deviceConfig.noPreSilencedOutputBuffer = MA_TRUE;      // 引擎总是写满输出帧
        deviceConfig.noClip = MA_TRUE;                         // 削波由引擎自己处理

        if (ma_device_init(m_context, &deviceConfig, m_device) != MA_SUCCESS) {
            qWarning("AudioEngine: Failed to initialize device (exclusive=%d)", m_exclusive);
            ma_context_uninit(m_context);
            goto on_fail;
        }
    }

    // 资源管理器：注册自定义解码后端（Opus / AAC），引擎加载的所有音频文件
    // 都经由它解码（ma_sound_init_from_file → resource manager → 后端）
    {
        ma_decoding_backend_vtable *pCustomBackends[] = {
            ma_decoding_backend_libopus,
            ma_decoding_backend_fdkaac
        };
        ma_resource_manager_config rmConfig = ma_resource_manager_config_init();
        rmConfig.ppCustomDecodingBackendVTables = pCustomBackends;
        rmConfig.customDecodingBackendCount =
            sizeof(pCustomBackends) / sizeof(pCustomBackends[0]);
        if (ma_resource_manager_init(&rmConfig, m_resourceManager) != MA_SUCCESS) {
            qWarning("AudioEngine: Failed to initialize resource manager");
            ma_device_uninit(m_device);
            ma_context_uninit(m_context);
            delete m_resourceManager;
            m_resourceManager = nullptr;
            goto on_fail;
        }
        m_resourceManagerInited = true;
    }

    {
        ma_engine_config config = ma_engine_config_init();
        config.pContext = m_context;
        config.pDevice = m_device;
        config.pResourceManager = m_resourceManager;
        if (ma_engine_init(&config, m_engine) != MA_SUCCESS) {
            qWarning("AudioEngine: Failed to initialize miniaudio engine");
            ma_device_uninit(m_device);
            ma_context_uninit(m_context);
            ma_resource_manager_uninit(m_resourceManager);
            m_resourceManagerInited = false;
            delete m_resourceManager;
            m_resourceManager = nullptr;
            goto on_fail;
        }
    }

    if (m_exclusive)
        qDebug("AudioEngine: WASAPI exclusive mode enabled");
    return true;

on_fail:
    delete m_device;
    delete m_context;
    delete m_engine;
    m_device = nullptr;
    m_context = nullptr;
    m_engine = nullptr;
    return false;
}

void AudioEngine::shutdownAudioDevice()
{
    if (m_soundInitialized && m_sound) {
        ma_sound_stop(m_sound);
        ma_sound_uninit(m_sound);
        std::memset(m_sound, 0, sizeof(*m_sound));
        m_soundInitialized = false;
    }
    m_wasPlaying = false;

    if (m_engine) {
        ma_engine_uninit(m_engine);
        delete m_engine;
        m_engine = nullptr;
    }
    // 资源管理器由本类持有（引擎不接管所有权），须在引擎之后释放
    if (m_resourceManager) {
        if (m_resourceManagerInited) {
            ma_resource_manager_uninit(m_resourceManager);
            m_resourceManagerInited = false;
        }
        delete m_resourceManager;
        m_resourceManager = nullptr;
    }
    if (m_device) {
        ma_device_uninit(m_device);
        delete m_device;
        m_device = nullptr;
    }
    if (m_context) {
        ma_context_uninit(m_context);
        delete m_context;
        m_context = nullptr;
    }
}

// ---- WASAPI 会话枚举：统计默认播放端点上除自己外"正在播放"的外部会话数 ----
// 仅统计 Active（流正在运行）会话：这类会话正占用端点，开启独占会抢占并打断它们，
// 甚至导致程序异常（已实测崩溃）；已暂停（Inactive）/已过期（Expired）会话不阻塞独占，
// 不应误判为占用。返回 -1 表示检测失败
#ifdef Q_OS_WIN
// 忽略名单：常驻"静默但流运行"音频会话的桌面工具（如 Rainmeter），
// 其会话并不代表真的在播放，不应判定为占用
static bool isIgnoredAudioProcess(const WCHAR *exePath)
{
    if (!exePath || !exePath[0]) return false;
    const WCHAR *name = wcsrchr(exePath, L'\\');
    name = name ? name + 1 : exePath;
    return QString::fromWCharArray(name).compare(QStringLiteral("rainmeter.exe"),
                                                 Qt::CaseInsensitive) == 0;
}

static int countActiveExternalAudioSessions()
{
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (hr == RPC_E_CHANGED_MODE) hr = S_OK;  // 线程已初始化其他模型，仍可继续使用 MMDevice
    const bool needUninit = (hr == S_OK);
    int count = -1;

    IMMDeviceEnumerator *enumerator = nullptr;
    if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                   IID_PPV_ARGS(&enumerator)))) {
        IMMDevice *device = nullptr;
        if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device))) {
            IAudioSessionManager2 *mgr = nullptr;
            if (SUCCEEDED(device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL,
                                           nullptr, (void **)&mgr))) {
                IAudioSessionEnumerator *sessions = nullptr;
                if (SUCCEEDED(mgr->GetSessionEnumerator(&sessions))) {
                    int sessionCount = 0;
                    count = 0;
                    sessions->GetCount(&sessionCount);
                    const DWORD myPid = GetCurrentProcessId();
                    for (int i = 0; i < sessionCount; ++i) {
                        IAudioSessionControl *ctrl = nullptr;
                        if (FAILED(sessions->GetSession(i, &ctrl))) continue;
                        AudioSessionState state = AudioSessionStateExpired;
                        ctrl->GetState(&state);
                        DWORD pid = 0;
                        IAudioSessionControl2 *ctrl2 = nullptr;
                        if (SUCCEEDED(ctrl->QueryInterface(__uuidof(IAudioSessionControl2),
                                                           (void **)&ctrl2))) {
                            ctrl2->GetProcessId(&pid);
                            ctrl2->Release();
                        }
                        // 仅统计可归因于现存外部进程的会话：
                        // pid 为 0 或进程已退出的会话无法确认来源，不应视为占用
                        bool attributed = false;
                        HANDLE hProc = nullptr;
                        if (pid != 0 && pid != myPid) {
                            hProc = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
                            if (hProc) attributed = true;
                        }
                        // 仅计入 Active（正在播放）且未静音的会话；被静音的程序并未实际占用音频
                        if (attributed && state == AudioSessionStateActive) {
                            BOOL muted = FALSE;
                            ISimpleAudioVolume *vol = nullptr;
                            if (SUCCEEDED(ctrl->QueryInterface(__uuidof(ISimpleAudioVolume),
                                                               (void **)&vol))) {
                                vol->GetMute(&muted);
                                vol->Release();
                            }
                            if (!muted) {
                                WCHAR exePath[MAX_PATH] = {};
                                DWORD size = MAX_PATH;
                                if (QueryFullProcessImageNameW(hProc, 0, exePath, &size)) {
                                    // 忽略名单内的常驻会话（如 Rainmeter），不判定为占用
                                    if (isIgnoredAudioProcess(exePath)) {
                                        if (hProc) CloseHandle(hProc);
                                        ctrl->Release();
                                        continue;
                                    }
                                    // 诊断：打印占用方进程名，便于定位"总是被占用"的来源
                                    qDebug("AudioEngine: active external session: pid=%lu name=%ls",
                                           pid, exePath);
                                }
                                ++count;
                            }
                        }
                        if (hProc) CloseHandle(hProc);
                        ctrl->Release();
                    }
                    sessions->Release();
                }
                mgr->Release();
            }
            device->Release();
        }
        enumerator->Release();
    }
    if (needUninit) CoUninitialize();
    return count;
}
#else
static int countActiveExternalAudioSessions() { return 0; }
#endif

// 设备级峰值采样：默认播放端点当前是否真的在出声（调用前自身设备已关闭，峰值只反映其他程序）。
// 通过 IAudioMeterInformation 多次采样确认，把"流在运行但无声"（Active 却静默）的
// 常驻会话与真正正在播放的程序区分开。先短暂等待自身设备关闭后的残留输出淡出。
#ifdef Q_OS_WIN
static bool deviceAudiblyActive()
{
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (hr == RPC_E_CHANGED_MODE) hr = S_OK;  // 线程已初始化其他模型，仍可继续使用 MMDevice
    const bool needUninit = (hr == S_OK);
    bool audible = false;

    // 等待自身设备关闭后的残留音频淡出（约 30ms），避免把本程序刚停止的尾音误判为其他程序在出声
    Sleep(30);

    IMMDeviceEnumerator *enumerator = nullptr;
    if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                   IID_PPV_ARGS(&enumerator)))) {
        IMMDevice *device = nullptr;
        if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device))) {
            IAudioMeterInformation *meter = nullptr;
            if (SUCCEEDED(device->Activate(__uuidof(IAudioMeterInformation), CLSCTX_ALL,
                                           nullptr, (void **)&meter))) {
                // 采样约 100ms：任一时刻测得有效峰值即视为正在出声
                for (int i = 0; i < 5 && !audible; ++i) {
                    float peak = 0.0f;
                    if (SUCCEEDED(meter->GetPeakValue(&peak)) && peak > 0.0005f)
                        audible = true;
                    if (!audible) Sleep(20);
                }
                meter->Release();
            }
            device->Release();
        }
        enumerator->Release();
    }
    if (needUninit) CoUninitialize();
    return audible;
}
#else
static bool deviceAudiblyActive() { return false; }
#endif

// 探测 WASAPI 独占通道是否可用：用独立 context 临时打开独占设备，成功即释放。
// 独占模式下同一端点只允许一个独占客户端，被其他程序占用时初始化会失败（MA_BUSY/MA_ACCESS_DENIED）。
// 返回：0=可用，1=被其他独占客户端占用，2=设备不支持等其他原因不可用（不属于"占用"，不触发弹窗）
int AudioEngine::exclusiveModeProbe() const
{
    ma_context context;
    ma_device device;
    ma_context_config contextConfig = ma_context_config_init();
    if (ma_context_init(nullptr, 0, &contextConfig, &context) != MA_SUCCESS)
        return 2;

    // 与 initAudioDevice 中一致的设备配置，仅指定独占模式
    ma_device_config deviceConfig = ma_device_config_init(ma_device_type_playback);
    deviceConfig.playback.format = ma_format_f32;
    deviceConfig.playback.channels = 0;                    // 设备原生声道
    deviceConfig.sampleRate = 0;                           // 设备原生采样率
    deviceConfig.playback.shareMode = ma_share_mode_exclusive;
    deviceConfig.noPreSilencedOutputBuffer = MA_TRUE;
    deviceConfig.noClip = MA_TRUE;

    ma_result result = ma_device_init(&context, &deviceConfig, &device);
    if (result != MA_SUCCESS) {
        // 仅 MA_BUSY/MA_ACCESS_DENIED 表示被其他独占客户端占用；其余失败（如不支持独占格式）
        // 属于设备本身不可用，不应误报为"通道被占用"
        const bool busy = (result == MA_BUSY || result == MA_ACCESS_DENIED);
        qDebug("AudioEngine: exclusive mode probe failed (result=%d): %s",
               result, busy ? "channel in use" : "unsupported or other reason");
        ma_context_uninit(&context);
        return busy ? 1 : 2;
    }
    ma_device_uninit(&device);
    ma_context_uninit(&context);
    return 0;
}

// 音频通道是否被占用：
// 1) 有其他进程正在播放且设备确实在出声（Active 会话 + 设备峰值）即判定占用——
//    开启独占会抢占端点，打断其播放甚至导致程序异常（已实测崩溃），仅靠探测不可靠；
//    仅"流在运行但无声"（Active 却静默，如后台常驻流）不判定占用；
// 2) 无出声会话时，再探测是否被其他独占客户端占用（MA_BUSY/MA_ACCESS_DENIED）。
// 已暂停/静默（Inactive/Expired）的会话不阻塞独占通道，不视为占用。
bool AudioEngine::audioChannelInUse() const
{
    if (countActiveExternalAudioSessions() > 0 && deviceAudiblyActive())
        return true;
    return exclusiveModeProbe() == 1;
}

bool AudioEngine::setExclusiveMode(bool exclusive, bool force)
{
    if (exclusive == m_exclusive) return true;

    // 保存当前播放现场（含热插拔状态）
    const bool wasPlaying = isPlaying();
    const qint64 pos = position();
    const QString path = !m_currentFilePath.isEmpty() ? m_currentFilePath : m_hotplugFilePath;
    const qint64 dur = m_cachedDuration;

    m_retryTimer->stop();
    m_hotplugMode = false;

    // 切换共享/独占必须重建引擎，先释放自身设备
    shutdownAudioDevice();

    if (exclusive && !force && audioChannelInUse()) {
        // 独占通道被其他客户端实际占用：不强制开启，重建共享引擎并恢复现场，由上层弹窗询问
        qWarning("AudioEngine: audio channel in use, not switching to exclusive mode");
        m_exclusive = false;
        initAudioDevice();
    } else {
        // 正常切换（或强制开启跳过探测）：尝试请求的模式，失败则回退共享
        m_exclusive = exclusive;
        if (!initAudioDevice()) {
            qWarning("AudioEngine: failed to init in requested mode, falling back to shared mode");
            m_exclusive = false;
            initAudioDevice();
        }
    }
    if (!m_engine) return false;

    setVolume(m_volume);
    emit playbackStateChanged();

    // 恢复播放现场
    if (path.isEmpty()) return m_exclusive == exclusive;
    if (!load(path)) {
        // 文件暂不可用（如设备切换期间被拔出）：保留现场进入热插拔重试
        m_hotplugMode = true;
        m_hotplugFilePath = path;
        m_hotplugPosition = pos;
        m_hotplugWasPlaying = wasPlaying;
        m_hotplugDuration = dur;
        m_retryTimer->start();
        return m_exclusive == exclusive;
    }
    if (pos > 0) seek(pos);
    if (wasPlaying) play();
    return m_exclusive == exclusive;
}

bool AudioEngine::load(const QString &filePath)
{
    if (!m_engine || !m_sound) return false;

    // 保存旧状态（用于加载失败后的热插拔恢复）
    bool wasPlaying = m_soundInitialized && m_wasPlaying;
    qint64 oldPos = m_soundInitialized ? position() : 0;
    qint64 oldDuration = m_cachedDuration;

    // 停止重试
    m_retryTimer->stop();
    m_hotplugMode = false;

    // 停止并卸载旧声音
    if (m_soundInitialized) {
        ma_sound_stop(m_sound);
        ma_sound_uninit(m_sound);
        std::memset(m_sound, 0, sizeof(*m_sound));
        m_soundInitialized = false;
    }
    m_wasPlaying = false;

#ifdef Q_OS_WIN
    std::wstring path = filePath.toStdWString();
    ma_result result = ma_sound_init_from_file_w(
        m_engine, path.c_str(),
        MA_SOUND_FLAG_STREAM | MA_SOUND_FLAG_NO_SPATIALIZATION,
        nullptr, nullptr, m_sound
    );
#else
    QByteArray path = filePath.toUtf8();
    ma_result result = ma_sound_init_from_file(
        m_engine, path.constData(),
        MA_SOUND_FLAG_STREAM | MA_SOUND_FLAG_NO_SPATIALIZATION,
        nullptr, nullptr, m_sound
    );
#endif

    if (result != MA_SUCCESS) {
        qWarning() << "AudioEngine: Failed to load file:" << filePath << "error:" << result;
        // 进入热插拔重试模式：冻结旧状态，定时尝试重新加载
        if (!m_currentFilePath.isEmpty()) {
            m_hotplugMode = true;
            m_hotplugFilePath = filePath;
            m_hotplugPosition = oldPos;
            m_hotplugWasPlaying = wasPlaying;
            m_hotplugDuration = oldDuration;
            m_retryTimer->start();
            qDebug("AudioEngine: Entered hotplug retry mode for: %s", qPrintable(filePath));
        }
        return false;
    }

    m_soundInitialized = true;
    m_currentFilePath = filePath;

    // 恢复用户设置的变速倍率（pitch 与速度联动）
    ma_sound_set_pitch(m_sound, m_pitch);

    // 缓存时长（毫秒）
    ma_uint64 frames;
    if (ma_sound_get_length_in_pcm_frames(m_sound, &frames) == MA_SUCCESS) {
        ma_format format;
        ma_uint32 channels, sampleRate;
        if (ma_sound_get_data_format(m_sound, &format, &channels, &sampleRate, nullptr, 0) == MA_SUCCESS && sampleRate > 0) {
            m_cachedDuration = static_cast<qint64>(frames) * 1000 / sampleRate;
        } else {
            // 兜底：用引擎采样率估算
            ma_uint32 engineSampleRate = ma_engine_get_sample_rate(m_engine);
            m_cachedDuration = (engineSampleRate > 0) ? static_cast<qint64>(frames) * 1000 / engineSampleRate : 0;
        }
    } else {
        m_cachedDuration = 0;
    }

    emit durationChanged();
    return true;
}

void AudioEngine::play()
{
    if (m_hotplugMode) {
        m_hotplugWasPlaying = true;
        emit playbackStateChanged();
        return;
    }
    if (!m_soundInitialized) return;
    ma_sound_start(m_sound);
    m_wasPlaying = true;
    emit playbackStateChanged();
}

void AudioEngine::pause()
{
    if (m_hotplugMode) {
        m_hotplugWasPlaying = false;
        emit playbackStateChanged();
        return;
    }
    if (!m_soundInitialized) return;
    ma_sound_stop(m_sound);
    m_wasPlaying = false;
    emit playbackStateChanged();
}

void AudioEngine::stop()
{
    if (m_hotplugMode) {
        m_hotplugMode = false;
        m_retryTimer->stop();
        m_wasPlaying = false;
        emit playbackStateChanged();
        emit positionChanged(0);
        return;
    }
    if (!m_soundInitialized) return;
    ma_sound_stop(m_sound);
    ma_sound_seek_to_pcm_frame(m_sound, 0);
    m_wasPlaying = false;
    emit playbackStateChanged();
    emit positionChanged(0);
}

void AudioEngine::seek(qint64 ms)
{
    if (m_hotplugMode) {
        m_hotplugPosition = qBound(0LL, ms, m_hotplugDuration > 0 ? m_hotplugDuration : ms);
        emit positionChanged(m_hotplugPosition);
        return;
    }
    if (!m_soundInitialized || m_cachedDuration <= 0) return;

    ma_uint64 frames;
    if (ma_sound_get_length_in_pcm_frames(m_sound, &frames) != MA_SUCCESS || frames == 0)
        return;

    ma_uint64 targetFrame = static_cast<ma_uint64>(
        static_cast<double>(qBound(0LL, ms, m_cachedDuration)) / m_cachedDuration * frames
    );
    ma_sound_seek_to_pcm_frame(m_sound, targetFrame);
    // seek 在混音线程延迟生效，但游标接口能立即感知 seekTarget，
    // 这里主动上报一次新位置，让进度条/歌词即刻跳转，无需等 50ms 轮询
    emit positionChanged(position());
}

qint64 AudioEngine::position() const
{
    if (m_hotplugMode) return m_hotplugPosition;
    if (!m_soundInitialized) return 0;

    // 用数据源游标而非节点时间轴：ma_sound_get_time_in_milliseconds() 基于节点
    // localTime（按引擎采样率累计），而 seek 时 localTime 被写入的是“文件采样率”的
    // 帧号（ma_node_set_time(pSound, seekTarget)），却仍除以引擎采样率——文件与
    // 引擎采样率不一致时（如 44.1k 文件 + 48k 设备），seek 后位置整体偏移，歌词错位。
    // 游标则始终以数据源（文件）帧号表示，且能感知未完成的 seek（直接返回 seekTarget）。
    ma_uint64 cursor = 0;
    if (ma_sound_get_cursor_in_pcm_frames(m_sound, &cursor) == MA_SUCCESS) {
        ma_uint32 sampleRate = 0;
        if (ma_sound_get_data_format(m_sound, nullptr, nullptr, &sampleRate, nullptr, 0) == MA_SUCCESS
            && sampleRate > 0) {
            return static_cast<qint64>(cursor) * 1000 / sampleRate;
        }
    }
    // 兜底：无数据源等异常情况下退回旧实现
    return static_cast<qint64>(ma_sound_get_time_in_milliseconds(m_sound));
}

qint64 AudioEngine::duration() const
{
    if (m_hotplugMode) return m_hotplugDuration;
    return m_cachedDuration;
}

void AudioEngine::setVolume(float vol)
{
    m_volume = vol;
    if (m_soundInitialized) {
        ma_sound_set_volume(m_sound, vol);
    }
}

void AudioEngine::setPitch(float pitch)
{
    m_pitch = pitch;
    if (m_soundInitialized) {
        ma_sound_set_pitch(m_sound, m_pitch);
    }
}

float AudioEngine::volume() const
{
    return m_volume;
}

bool AudioEngine::isPlaying() const
{
    if (m_hotplugMode) return m_hotplugWasPlaying;
    return m_soundInitialized && (ma_sound_is_playing(m_sound) != MA_FALSE);
}

void AudioEngine::pollAudio()
{
    // 热插拔模式：持续发送冻结的位置，保持 UI 不跳变
    if (m_hotplugMode) {
        emit positionChanged(m_hotplugPosition);
        return;
    }

    if (!m_soundInitialized) return;

    qint64 pos = position();
    emit positionChanged(pos);

    bool currentlyPlaying = (ma_sound_is_playing(m_sound) != MA_FALSE);
    if (m_wasPlaying && !currentlyPlaying) {
        // 检测是否因设备拔出而停止播放（文件已不可访问）
        if (!QFileInfo::exists(m_currentFilePath)) {
            qDebug("AudioEngine: Device disconnected, entering hotplug retry mode");
            m_hotplugMode = true;
            m_hotplugFilePath = m_currentFilePath;
            m_hotplugPosition = pos;
            m_hotplugWasPlaying = true;
            m_hotplugDuration = m_cachedDuration;
            m_wasPlaying = false;
            emit playbackStateChanged();
            m_retryTimer->start();
            return;  // 不触发 endOfMedia
        }
        // 正常播完
        m_wasPlaying = false;
        emit playbackStateChanged();
        emit endOfMedia();
    }
    m_wasPlaying = currentlyPlaying;
}

void AudioEngine::retryLoad()
{
    if (!m_hotplugMode) {
        m_retryTimer->stop();
        return;
    }

    // 先检查文件是否存在（快速路径，避免每次调用 miniaudio）
    if (!QFileInfo::exists(m_hotplugFilePath)) {
        return;  // 设备仍未恢复
    }

    // 卸载旧声音（进入热插拔模式时可能未清理）
    if (m_soundInitialized) {
        ma_sound_stop(m_sound);
        ma_sound_uninit(m_sound);
        std::memset(m_sound, 0, sizeof(*m_sound));
        m_soundInitialized = false;
    }

    // 尝试重新加载
#ifdef Q_OS_WIN
    std::wstring path = m_hotplugFilePath.toStdWString();
    ma_result result = ma_sound_init_from_file_w(
        m_engine, path.c_str(),
        MA_SOUND_FLAG_STREAM | MA_SOUND_FLAG_NO_SPATIALIZATION,
        nullptr, nullptr, m_sound
    );
#else
    QByteArray path = m_hotplugFilePath.toUtf8();
    ma_result result = ma_sound_init_from_file(
        m_engine, path.constData(),
        MA_SOUND_FLAG_STREAM | MA_SOUND_FLAG_NO_SPATIALIZATION,
        nullptr, nullptr, m_sound
    );
#endif

    if (result != MA_SUCCESS) {
        return;  // 设备恢复但文件还不能读，继续重试
    }

    // 恢复成功
    m_soundInitialized = true;
    m_currentFilePath = m_hotplugFilePath;
    m_cachedDuration = m_hotplugDuration;
    ma_sound_set_volume(m_sound, m_volume);
    ma_sound_set_pitch(m_sound, m_pitch);

    // 跳转到保存的位置
    if (m_hotplugPosition > 0) {
        seek(m_hotplugPosition);
    }

    bool wasPlaying = m_hotplugWasPlaying;
    // 退出热插拔模式
    m_hotplugMode = false;
    m_retryTimer->stop();

    qDebug("AudioEngine: Device reconnected, resuming playback at %lld ms", m_hotplugPosition);
    emit durationChanged();
    emit positionChanged(m_hotplugPosition);

    if (wasPlaying) {
        ma_sound_start(m_sound);
        m_wasPlaying = true;
        emit playbackStateChanged();
    }
}
