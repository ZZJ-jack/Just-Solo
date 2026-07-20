#pragma once

#include <QObject>
#include <QTimer>
#include <windows.h>

// 前向声明 WRL COM 智能指针，避免在头文件中引入 WRL 头
namespace Microsoft { namespace WRL { template<typename T> class ComPtr; } }
namespace ABI {
    namespace Windows { namespace Media {
        struct ISystemMediaTransportControls;
        struct ISystemMediaTransportControls2;
        struct ISystemMediaTransportControlsDisplayUpdater;
        struct ISystemMediaTransportControlsTimelineProperties;
    }}
}

class MusicManager;

/// Windows 系统媒体传输控件（SMTC）管理器
/// 在任务栏音量弹窗、锁屏界面、蓝牙耳机等位置显示歌名/歌手并提供播放控制
/// 仅编译于 Windows（.cpp 由 #ifdef Q_OS_WIN 守卫）
class SMTCManager : public QObject
{
    Q_OBJECT
public:
    explicit SMTCManager(MusicManager *manager, HWND hwnd, QObject *parent = nullptr);
    ~SMTCManager();

public slots:
    void onPlaybackStateChanged();
    void onCurrentTrackChanged();

private slots:
    void updateTimelineTick();  // 定时器回调：更新播放位置

private:
    HRESULT initialize(HWND hwnd);
    HRESULT updatePlaybackStatus(bool playing);
    HRESULT updateMetadata(const QString &title, const QString &artist, const QString &coverUrl);
    HRESULT updateTimeline(qint64 positionMs, qint64 durationMs);

    MusicManager *m_musicManager;
    QTimer *m_timelineTimer = nullptr;   // 定时更新播放位置 (~500ms)
    qint64 m_cachedDuration = 0;         // 缓存歌曲总时长，非活页每次查

    // PIMPL — 把 Windows COM 细节封在 .cpp 里
    struct Impl;
    Impl *m_impl = nullptr;
};
