#pragma once

#include <QObject>
#include <windows.h>

// 前向声明 WRL COM 智能指针，避免在头文件中引入 WRL 头
namespace Microsoft { namespace WRL { template<typename T> class ComPtr; } }
namespace ABI {
    namespace Windows { namespace Media {
        struct ISystemMediaTransportControls;
        struct ISystemMediaTransportControlsDisplayUpdater;
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

private:
    HRESULT initialize(HWND hwnd);
    HRESULT updatePlaybackStatus(bool playing);
    HRESULT updateMetadata(const QString &title, const QString &artist, const QString &coverUrl);

    MusicManager *m_musicManager;

    // PIMPL — 把 Windows COM 细节封在 .cpp 里
    struct Impl;
    Impl *m_impl = nullptr;
};
