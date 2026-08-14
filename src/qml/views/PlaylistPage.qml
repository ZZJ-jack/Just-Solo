import QtQuick

// ============================================================
// 播放列表页 — 继承 MusicListView，动态跟随 playlistSource
// 自动定位由 MusicListView 统一处理（autoScrollEnabled 默认 true）
// ============================================================
MusicListView {
    // 动态模型：跟随 playlistSource，并按当前排序模式重排
    // （历史页固定时间序不参与排序，收藏/播放列表跟随排序模式）
    songList: {
        try {
            var src = musicManager.playlistSource
            if (src === 1) return mainWindow.displaySorted(musicManager.favorites)
            if (src === 2) return musicManager.history
            return mainWindow.displaySorted(musicManager.playlist)
        } catch (e) { return musicManager.playlist }
    }
    showDefaultContextMenu: false
    emptyHint: "播放列表为空"
    emptySubHint: "在其他页面右键歌曲即可添加"
    contextMenuExtra: [
        { text: "从播放列表删除", onClicked: function() {
            if (rightClickedTrack) musicManager.removeFromPlaylist(rightClickedTrack)
        } }
    ]

    onLeftClick: function(index) {
        var src = musicManager.playlistSource
        // 显示列表已按排序模式重排，需把显示下标映射回播放来源的真实下标
        var raw = src === 1 ? musicManager.favorites
                : (src === 2 ? musicManager.history : musicManager.playlist)
        if (!raw || index < 0 || index >= songList.length) return
        var song = songList[index]
        if (!song) return
        var path = song.path || ""
        var realIdx = -1
        for (var i = 0; i < raw.length; i++) {
            if ((raw[i].path || "") === path) { realIdx = i; break }
        }
        if (realIdx < 0) return
        if (musicManager.currentIndex === realIdx && (src === 0 || src === 1 || src === 2)) {
            if (musicManager.isPlaying) musicManager.pause()
            else musicManager.play()
        } else {
            musicManager.playIndex(realIdx)
        }
    }
}
