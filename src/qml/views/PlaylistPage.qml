import QtQuick

// ============================================================
// 播放列表页 — 继承 MusicListView，动态跟随 playlistSource
// 自动定位由 MusicListView 统一处理（autoScrollEnabled 默认 true）
// ============================================================
MusicListView {
    // 动态模型：跟随 playlistSource
    songList: {
        try {
            var src = musicManager.playlistSource
            return src === 1 ? musicManager.favorites
                 : (src === 2 ? musicManager.history : musicManager.playlist)
        } catch (e) { return musicManager.playlist }
    }
    emptyHint: "播放列表为空"
    emptySubHint: "在其他页面右键歌曲即可添加"
    contextMenuExtra: [
        { text: "从播放列表删除", onClicked: function() {
            if (rightClickedTrack) musicManager.removeFromPlaylist(rightClickedTrack)
        } }
    ]

    onLeftClick: function(index) {
        var src = musicManager.playlistSource
        if (musicManager.currentIndex === index && (src === 0 || src === 1 || src === 2)) {
            if (musicManager.isPlaying) musicManager.pause()
            else musicManager.play()
        } else {
            musicManager.playIndex(index)
        }
    }
}
