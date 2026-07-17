import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// ============================================================
// 首页 - 音乐列表视图（SongRow 共享组件）
// ============================================================
ColumnLayout {
    id: musicListLayout
    spacing: 0
    clip: true

    property int sidebarWidth: 230
    property int windowWidth: 1200
    property var rightClickedTrack: null
    property string fontFamily: ""

    // ---- 列宽 (2:2:2:2:1) ----
    property int colPlay: 36
    property real _totalW: Math.max(400,
        (musicListView.width > 0 ? musicListView.width : windowWidth - sidebarWidth - 80) - 20 - colPlay)
    property real colCover:    Math.max(40, _totalW * 2 / 9)
    property real colTitle:    Math.max(60, _totalW * 2 / 9)
    property real colArtist:   Math.max(50, _totalW * 2 / 9)
    property real colAlbum:    Math.max(50, _totalW * 2 / 9)
    property real colDuration: Math.max(36, _totalW * 1 / 9)

    // ---- 列标题 ----
    Rectangle {
        Layout.fillWidth: true; height: 32; color: "transparent"
        visible: musicManager.playlist.length > 0
        RowLayout {
            anchors.fill: parent; anchors.margins: 5; anchors.leftMargin: 8; spacing: 0
            Item { Layout.preferredWidth: musicListLayout.colCover; Layout.maximumWidth: 40 }
            Label { text: "标题"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: musicListLayout.colTitle; verticalAlignment: Text.AlignVCenter }
            Label { text: "歌手"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: musicListLayout.colArtist; verticalAlignment: Text.AlignVCenter }
            Label { text: "专辑"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: musicListLayout.colAlbum; verticalAlignment: Text.AlignVCenter }
            Label { text: "时长"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.preferredWidth: musicListLayout.colDuration; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
            Item { Layout.preferredWidth: musicListLayout.colPlay }
        }
    }
    Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a48"; visible: musicManager.playlist.length > 0 }

    // ---- 歌曲列表 ----
    ListView {
        id: musicListView
        Layout.fillWidth: true; Layout.fillHeight: true
        spacing: 8; clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: musicManager.playlist.length > 0
        cacheBuffer: height * 2; reuseItems: true

        ScrollBar.vertical: ScrollBar {
            id: listScrollBar; policy: ScrollBar.AsNeeded; width: 10
            background: Rectangle { implicitWidth: 10; radius: 5; color: "#2a2a3a" }
            contentItem: Rectangle {
                implicitWidth: 10; radius: 5
                color: thumbHover.containsMouse ? "#7777aa" : "#555577"
                Behavior on color { ColorAnimation { duration: 150 } }
                MouseArea { id: thumbHover; hoverEnabled: true; acceptedButtons: Qt.NoButton; propagateComposedEvents: true }
            }
        }

        model: musicManager.playlist

        delegate: SongRow {
            width: musicListView.width
            isCurrent: musicManager.currentIndex === index
            fontFamily: musicListLayout.fontFamily
            colCover: musicListLayout.colCover
            colTitle: musicListLayout.colTitle
            colArtist: musicListLayout.colArtist
            colAlbum: musicListLayout.colAlbum
            colDuration: musicListLayout.colDuration
            colPlay: musicListLayout.colPlay

            onLeftClicked: {
                if (musicManager.currentIndex === index) {
                    if (musicManager.isPlaying) musicManager.pause()
                    else musicManager.play()
                } else {
                    musicManager.playIndex(index)
                }
            }
            onRightClicked: {
                musicListLayout.rightClickedTrack = model
                homeContextMenu.popup()
            }
        }
    }

    // ---- 右键菜单 ----
    Menu {
        id: homeContextMenu
        background: Rectangle { color: "#2a2a3a"; border.color: "#444466"; radius: 6; implicitWidth: 140 }
        MenuItem {
            id: homeMenuItem
            text: musicListLayout.rightClickedTrack ? (musicManager.isFavorite(musicListLayout.rightClickedTrack) ? "取消收藏" : "收藏") : "收藏"
            onClicked: { if (musicListLayout.rightClickedTrack) musicManager.toggleFavorite(musicListLayout.rightClickedTrack) }
            contentItem: Label { text: homeMenuItem.text; font.family: fontFamily; font.pixelSize: 14; color: "#cccccc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: homeMenuItem.hovered ? "#3a3a5a" : "transparent"; radius: 4 }
        }
    }

    // ---- 空列表提示 ----
    Column {
        Layout.alignment: Qt.AlignCenter; spacing: 14
        visible: musicManager.playlist.length === 0
        Label { text: "还没有音乐"; font.family: fontFamily; font.pixelSize: 16; color: "#757575"; anchors.horizontalCenter: parent.horizontalCenter }
        Label { text: "点击上方「添加音乐」导入本地文件"; font.family: fontFamily; font.pixelSize: 13; color: "#666"; anchors.horizontalCenter: parent.horizontalCenter }
    }
}
