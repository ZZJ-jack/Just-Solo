import QtQuick

// ============================================================
// 收藏页 — 继承 MusicListView，定制点击/右键/空提示
// ============================================================
MusicListView {
    songList: musicManager.favorites
    pageListIndex: 1
    showDefaultContextMenu: false
    emptyHint: "还没有收藏的歌曲"
    emptySubHint: "在首页右键歌曲即可收藏"
    contextMenuExtra: [{ text: "取消收藏", onClicked: function() { musicManager.removeFavorite(rightClickedIndex) } }]

    onLeftClick: function(index) {
        if (musicManager.playlistSource === 1) {
            if (musicManager.currentIndex === index) {
                if (musicManager.isPlaying) musicManager.pause()
                else musicManager.play()
            } else {
                musicManager.playIndex(index)
            }
        } else {
            // 没有正在播放 → 直接播放，否则弹窗确认
            if (musicManager.currentIndex < 0) {
                musicManager.playlistSource = 1
                musicManager.playIndex(index)
            } else {
                openSwitchDialog("switch", 1, index)
            }
        }
    }
}
