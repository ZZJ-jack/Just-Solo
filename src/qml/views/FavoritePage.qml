import QtQuick

// ============================================================
// 收藏页 — 继承 MusicListView，定制点击/右键/空提示
// 排序模式相关绑定由 main.qml 实例注入（songList/点击/拖拽/提示行）
// ============================================================
MusicListView {
    songList: musicManager.favorites
    pageListIndex: 1
    showDefaultContextMenu: false
    emptyHint: "还没有收藏的歌曲"
    emptySubHint: "在首页右键歌曲即可收藏"
    contextMenuExtra: [{ text: "取消收藏", onClicked: function() { musicManager.removeFavorite(rightClickedIndex) } }]
}
