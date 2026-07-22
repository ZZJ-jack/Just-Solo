import QtQuick

// ============================================================
// 历史页 — 继承 MusicListView，定制点击/右键/空提示
// ============================================================
MusicListView {
    songList: musicManager.history
    pageListIndex: 2
    emptyHint: "还没有播放历史"
    emptySubHint: "播放歌曲后会自动记录"
    contextMenuExtra: [{ text: "删除历史", onClicked: function() { musicManager.removeHistoryItem(rightClickedIndex) } }]

    onLeftClick: function(index) {
        if (musicManager.playlistSource === 2) {
            if (musicManager.currentIndex === index) {
                if (musicManager.isPlaying) musicManager.pause()
                else musicManager.play()
            } else {
                musicManager.playIndex(index)
            }
        } else {
            musicManager.playlistSource = 2
            musicManager.playIndex(index)
        }
    }
}
