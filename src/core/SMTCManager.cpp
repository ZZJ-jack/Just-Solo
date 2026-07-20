#include <QtGlobal>   // Q_OS_WIN 定义
#ifdef Q_OS_WIN

#include "SMTCManager.h"
#include "MusicManager.h"

#include <QDebug>
#include <QFile>
#include <QFileInfo>
#include <QMetaObject>
#include <QString>
#include <QUrl>

#include <wrl.h>
#include <wrl/event.h>
#include <wrl/wrappers/corewrappers.h>
#include <windows.media.h>          // SMTC 生产者端 ABI (ISystemMediaTransportControls, TimelineProperties)
#include <windows.media.control.h>
#include <windows.storage.h>
#include <windows.storage.streams.h>
#include <roapi.h>
#include <shlwapi.h>
#include <ShCore.h>

using namespace Microsoft::WRL;
using namespace Microsoft::WRL::Wrappers;
using namespace ABI::Windows::Media;
using namespace ABI::Windows::Foundation;
using namespace ABI::Windows::Storage;
using namespace ABI::Windows::Storage::Streams;

// ============================================================
//  ISystemMediaTransportControlsInterop — 手动定义
//  Windows SDK 10.0.26100 未导出此接口
// ============================================================
struct __declspec(uuid("ddb0472d-c911-4a1f-86d9-dc3d71a95f5a"))
ISystemMediaTransportControlsInterop : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE GetForWindow(
        HWND appWindow, REFIID riid, void **mediaTransportControl) = 0;
};

// 从本地文件设置 SMTC 缩略图
static HRESULT SetThumbnailFromFile(
    ISystemMediaTransportControlsDisplayUpdater *display,
    const QString &coverUrl)
{
    if (!display || coverUrl.isEmpty()) return E_INVALIDARG;

    // coverUrl 是 file:///C:/... 格式
    QString localPath = QUrl(coverUrl).toLocalFile();
    if (localPath.isEmpty() || !QFile::exists(localPath))
        return E_INVALIDARG;

    // 使用 SHCreateStreamOnFileW 创建 IStream
    ComPtr<IStream> stream;
    HRESULT hr = SHCreateStreamOnFileW(
        reinterpret_cast<LPCWSTR>(localPath.utf16()),
        STGM_READ | STGM_SHARE_DENY_WRITE,
        &stream);
    if (FAILED(hr)) {
        qDebug() << "[SMTC] SHCreateStreamOnFileW failed:" << hr;
        return hr;
    }

    // 将 IStream 包装为 IRandomAccessStream
    ComPtr<IRandomAccessStream> randomStream;
    hr = CreateRandomAccessStreamOverStream(
        stream.Get(), BSOS_DEFAULT, IID_PPV_ARGS(&randomStream));
    if (FAILED(hr)) {
        qDebug() << "[SMTC] CreateRandomAccessStreamOverStream failed:" << hr;
        return hr;
    }

    // 获取 IRandomAccessStreamReference
    ComPtr<ABI::Windows::Storage::Streams::IRandomAccessStreamReferenceStatics> refStatics;
    hr = RoGetActivationFactory(
        HStringReference(RuntimeClass_Windows_Storage_Streams_RandomAccessStreamReference).Get(),
        IID_PPV_ARGS(&refStatics));
    if (FAILED(hr)) {
        qDebug() << "[SMTC] RandomAccessStreamReference factory 失败:" << Qt::hex << (unsigned long)hr;
        return hr;
    }

    ComPtr<IRandomAccessStreamReference> streamRef;
    hr = refStatics->CreateFromStream(randomStream.Get(), &streamRef);
    if (FAILED(hr)) {
        qDebug() << "[SMTC] CreateRandomAccessStreamReference failed:" << hr;
        return hr;
    }

    hr = display->put_Thumbnail(streamRef.Get());
    if (FAILED(hr))
        qDebug() << "[SMTC] put_Thumbnail failed:" << hr;

    return hr;
}

// ============================================================
//  PIMPL
// ============================================================
struct SMTCManager::Impl
{
    ComPtr<ISystemMediaTransportControls> controls;
    ComPtr<ISystemMediaTransportControlsDisplayUpdater> display;
    EventRegistrationToken buttonToken;
    bool initialized = false;
};

// ============================================================
//  构造 / 析构
// ============================================================
SMTCManager::SMTCManager(MusicManager *manager, HWND hwnd, QObject *parent)
    : QObject(parent)
    , m_musicManager(manager)
    , m_impl(new Impl())
{
    // 连接 MusicManager 信号
    connect(m_musicManager, &MusicManager::playbackStateChanged,
            this, &SMTCManager::onPlaybackStateChanged);
    connect(m_musicManager, &MusicManager::currentTrackChanged,
            this, &SMTCManager::onCurrentTrackChanged);

    // Timeline 定时器：每 500ms 更新 Position，让 NSD 等工具能同步歌词
    m_timelineTimer = new QTimer(this);
    m_timelineTimer->setInterval(500);
    connect(m_timelineTimer, &QTimer::timeout, this, &SMTCManager::updateTimelineTick);

    // 初始化 SMTC
    HRESULT hr = initialize(hwnd);
    if (SUCCEEDED(hr)) {
        m_impl->initialized = true;
        qDebug() << "[SMTC] 初始化成功, 窗口 HWND:" << hwnd;
    } else {
        qDebug() << "[SMTC] 初始化失败, HRESULT:" << Qt::hex << (unsigned long)hr;
    }
}

SMTCManager::~SMTCManager()
{
    if (m_impl && m_impl->controls) {
        m_impl->controls->remove_ButtonPressed(m_impl->buttonToken);
    }
    delete m_impl;
}

// ============================================================
//  初始化
// ============================================================
HRESULT SMTCManager::initialize(HWND hwnd)
{
    // --- 1. Interop ---
    ComPtr<ISystemMediaTransportControlsInterop> interop;
    HRESULT hr = RoGetActivationFactory(
        HStringReference(RuntimeClass_Windows_Media_SystemMediaTransportControls).Get(),
        IID_PPV_ARGS(&interop));
    if (FAILED(hr)) {
        qDebug() << "[SMTC] RoGetActivationFactory 失败:" << Qt::hex << (unsigned long)hr;
        return hr;
    }

    hr = interop->GetForWindow(hwnd, IID_PPV_ARGS(&m_impl->controls));
    if (FAILED(hr)) {
        qDebug() << "[SMTC] GetForWindow 失败:" << Qt::hex << (unsigned long)hr;
        return hr;
    }

    // --- 2. Display updater ---
    hr = m_impl->controls->get_DisplayUpdater(&m_impl->display);
    if (FAILED(hr)) {
        qDebug() << "[SMTC] get_DisplayUpdater 失败:" << Qt::hex << (unsigned long)hr;
        return hr;
    }

    // --- 3. 媒体类型 + App 标识 ---
    m_impl->display->put_Type(MediaPlaybackType::MediaPlaybackType_Music);
    HString appId;
    appId.Set(L"JustSolo.JustSolo");
    m_impl->display->put_AppMediaId(appId.Get());

    // --- 4. 启用全部控制按钮 ---
    m_impl->controls->put_IsPlayEnabled(true);
    m_impl->controls->put_IsPauseEnabled(true);
    m_impl->controls->put_IsNextEnabled(true);
    m_impl->controls->put_IsPreviousEnabled(true);

    // --- 5. 注册按钮回调 ---
    auto handler = Callback<
        ITypedEventHandler<
            SystemMediaTransportControls*,
            SystemMediaTransportControlsButtonPressedEventArgs*>>
    ([this](ISystemMediaTransportControls *,
            ISystemMediaTransportControlsButtonPressedEventArgs *args) -> HRESULT
    {
        SystemMediaTransportControlsButton button;
        HRESULT hrBtn = args->get_Button(&button);
        if (FAILED(hrBtn)) return hrBtn;

        QMetaObject::invokeMethod(this, [this, button]() {
            switch (button) {
            case SystemMediaTransportControlsButton_Play:
                m_musicManager->play(); break;
            case SystemMediaTransportControlsButton_Pause:
                m_musicManager->pause(); break;
            case SystemMediaTransportControlsButton_Next:
                m_musicManager->next(); break;
            case SystemMediaTransportControlsButton_Previous:
                m_musicManager->previous(); break;
            default: break;
            }
        }, Qt::QueuedConnection);
        return S_OK;
    });

    hr = m_impl->controls->add_ButtonPressed(handler.Get(), &m_impl->buttonToken);
    if (FAILED(hr)) {
        qDebug() << "[SMTC] add_ButtonPressed 失败:" << Qt::hex << (unsigned long)hr;
        return hr;
    }

    // --- 6. 启用控件 ---
    m_impl->controls->put_IsEnabled(true);

    // --- 7. 同步初始状态（可能还没有歌曲） ---
    updatePlaybackStatus(m_musicManager->isPlaying());

    QString title = m_musicManager->currentTitle();
    QString artist = m_musicManager->currentArtist();
    QString cover = m_musicManager->currentCover();

    if (!title.isEmpty()) {
        updateMetadata(title, artist, cover);
        qDebug() << "[SMTC] 初始曲目:" << title << "-" << artist;
    } else {
        qDebug() << "[SMTC] 初始化时无曲目，等待信号...";
    }

    return S_OK;
}

// ============================================================
//  更新播放状态
// ============================================================
HRESULT SMTCManager::updatePlaybackStatus(bool playing)
{
    if (!m_impl->controls) return E_POINTER;

    MediaPlaybackStatus status = playing
        ? MediaPlaybackStatus::MediaPlaybackStatus_Playing
        : MediaPlaybackStatus::MediaPlaybackStatus_Paused;

    return m_impl->controls->put_PlaybackStatus(status);
}

// ============================================================
//  更新元数据（标题 + 歌手 + 封面）
// ============================================================
HRESULT SMTCManager::updateMetadata(const QString &title,
                                     const QString &artist,
                                     const QString &coverUrl)
{
    if (!m_impl->display) {
        qDebug() << "[SMTC] updateMetadata: display 为空";
        return E_POINTER;
    }

    qDebug() << "[SMTC] updateMetadata:" << title << "-" << artist
             << "cover:" << (coverUrl.isEmpty() ? "无" : "有");

    // 清空旧数据后必须重新声明类型，否则 get_MusicProperties 报 0x80070032
    m_impl->display->ClearAll();
    m_impl->display->put_Type(MediaPlaybackType::MediaPlaybackType_Music);
    HString appId;
    appId.Set(L"JustSolo.JustSolo");
    m_impl->display->put_AppMediaId(appId.Get());

    // 音乐属性
    ComPtr<IMusicDisplayProperties> musicProps;
    HRESULT hr = m_impl->display->get_MusicProperties(&musicProps);
    if (FAILED(hr)) {
        qDebug() << "[SMTC] get_MusicProperties 失败:" << Qt::hex << (unsigned long)hr;
        return hr;
    }

    if (!title.isEmpty()) {
        HString hTitle;
        hTitle.Set(title.toStdWString().c_str());
        hr = musicProps->put_Title(hTitle.Get());
        if (FAILED(hr))
            qDebug() << "[SMTC] put_Title 失败:" << Qt::hex << (unsigned long)hr;
    }

    if (!artist.isEmpty()) {
        HString hArtist;
        hArtist.Set(artist.toStdWString().c_str());
        hr = musicProps->put_Artist(hArtist.Get());
        if (FAILED(hr))
            qDebug() << "[SMTC] put_Artist 失败:" << Qt::hex << (unsigned long)hr;
    }

    // 缩略图（封面）
    if (!coverUrl.isEmpty()) {
        SetThumbnailFromFile(m_impl->display.Get(), coverUrl);
    }

    // 提交
    hr = m_impl->display->Update();
    if (FAILED(hr))
        qDebug() << "[SMTC] display->Update 失败:" << Qt::hex << (unsigned long)hr;

    return hr;
}

// ============================================================
//  槽函数
// ============================================================
void SMTCManager::onPlaybackStateChanged()
{
    if (!m_musicManager || !m_impl->initialized) return;

    bool playing = m_musicManager->isPlaying();
    updatePlaybackStatus(playing);

    // 播放时启动定时器持续更新 Position；暂停/停止时关掉
    if (playing) {
        if (!m_timelineTimer->isActive())
            m_timelineTimer->start();
        // 立即推送一次当前进度
        updateTimelineTick();
    } else {
        m_timelineTimer->stop();
        // 暂停时也更新一次 position，让外部读取到准确进度
        updateTimeline(m_musicManager->position(), m_cachedDuration);
    }
}

void SMTCManager::onCurrentTrackChanged()
{
    if (!m_musicManager || !m_impl->initialized) return;

    QString title = m_musicManager->currentTitle();
    QString artist = m_musicManager->currentArtist();
    QString cover = m_musicManager->currentCover();

    qDebug() << "[SMTC] onCurrentTrackChanged:"
             << title << "-" << artist;

    updateMetadata(title, artist, cover);

    // 新歌曲：记录总时长，初始化 timeline
    m_cachedDuration = m_musicManager->duration();
    updateTimeline(0, m_cachedDuration);

    // 在播放中切歌，确保定时器开着
    if (m_musicManager->isPlaying() && !m_timelineTimer->isActive())
        m_timelineTimer->start();
}

// ============================================================
//  Timeline 定时器回调
// ============================================================
void SMTCManager::updateTimelineTick()
{
    if (!m_musicManager || !m_impl->initialized) return;

    qint64 pos = m_musicManager->position();
    // 缓存 duration（只在 QMediaPlayer 初始化后有效）
    if (m_cachedDuration <= 0) {
        m_cachedDuration = m_musicManager->duration();
    }
    updateTimeline(pos, m_cachedDuration);
}

// ============================================================
//  updateTimeline — 推送 Position / EndTime 到 SMTC
// ============================================================
HRESULT SMTCManager::updateTimeline(qint64 positionMs, qint64 durationMs)
{
    if (!m_impl->controls) return E_POINTER;

    // UpdateTimelineProperties / put_PlaybackRate 在 ISystemMediaTransportControls2 上
    ComPtr<ISystemMediaTransportControls2> controls2;
    HRESULT hr = m_impl->controls.As(&controls2);
    if (FAILED(hr)) {
        qDebug() << "[SMTC] QI ISystemMediaTransportControls2 失败:" << Qt::hex << (unsigned long)hr;
        return hr;
    }

    // 创建 SystemMediaTransportControlsTimelineProperties 对象
    ComPtr<IInspectable> inspectable;
    hr = RoActivateInstance(
        HStringReference(RuntimeClass_Windows_Media_SystemMediaTransportControlsTimelineProperties).Get(),
        &inspectable);
    if (FAILED(hr)) {
        qDebug() << "[SMTC] RoActivateInstance(TimelineProperties) 失败:" << Qt::hex << (unsigned long)hr;
        return hr;
    }

    ComPtr<ISystemMediaTransportControlsTimelineProperties> timelineProps;
    hr = inspectable.As(&timelineProps);
    if (FAILED(hr)) {
        qDebug() << "[SMTC] As(TimelineProperties) 失败:" << Qt::hex << (unsigned long)hr;
        return hr;
    }

    // TimeSpan 单位是 100ns，1ms = 10000 个 100ns
    ABI::Windows::Foundation::TimeSpan posSpan = { positionMs * 10000LL };
    ABI::Windows::Foundation::TimeSpan endSpan = { durationMs * 10000LL };
    ABI::Windows::Foundation::TimeSpan zeroSpan = { 0 };

    timelineProps->put_Position(posSpan);
    timelineProps->put_EndTime(endSpan);
    timelineProps->put_StartTime(zeroSpan);
    timelineProps->put_MinSeekTime(zeroSpan);
    timelineProps->put_MaxSeekTime(endSpan);

    hr = controls2->UpdateTimelineProperties(timelineProps.Get());
    if (FAILED(hr))
        qDebug() << "[SMTC] UpdateTimelineProperties 失败:" << Qt::hex << (unsigned long)hr;

    // 同步设置播放速度 1.0x
    controls2->put_PlaybackRate(1.0);

    return hr;
}

#endif // Q_OS_WIN
