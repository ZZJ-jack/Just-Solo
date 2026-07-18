import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// 收藏页 - 已收藏音乐列表（SongRow 共享组件）
// ============================================================
ColumnLayout {
    id: favoriteLayout
    spacing: 0
    clip: true

    property int sidebarWidth: 230
    property int windowWidth: 1200
    property int rightClickedIndex: -1
    property var rightClickedTrack: null
    property string fontFamily: ""

    // ---- 列宽 (2:2:2:2:1) ----
    property int colPlay: 36
    property real _totalW: Math.max(400,
        (favoriteListView.width > 0 ? favoriteListView.width : windowWidth - sidebarWidth - 80) - 20 - colPlay)
    property real colCover:    Math.max(40, _totalW * 2 / 9)
    property real colTitle:    Math.max(60, _totalW * 2 / 9)
    property real colArtist:   Math.max(50, _totalW * 2 / 9)
    property real colAlbum:    Math.max(50, _totalW * 2 / 9)
    property real colDuration: Math.max(36, _totalW * 1 / 9)
    property string currentPath: {
        try {
            var ms = musicManager
            if (!ms) return ""
            var ci = ms.currentIndex
            if (ci < 0 || ci === undefined) return ""
            var src = ms.playlistSource
            var list = src === 1 ? ms.favorites : (src === 2 ? ms.history : ms.playlist)
            if (!list || list.length === 0) return ""
            var item = list[ci]
            if (!item || item.path === undefined) return ""
            return item.path || ""
        } catch (e) { return "" }
    }

    // ---- 列标题 ----
    Rectangle {
        Layout.fillWidth: true; height: 32; color: "transparent"
        visible: musicManager.favorites.length > 0
        RowLayout {
            anchors.fill: parent; anchors.margins: 5; anchors.leftMargin: 8; spacing: 0
            Item { Layout.preferredWidth: favoriteLayout.colCover; Layout.maximumWidth: 40 }
            Label { text: "标题"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: favoriteLayout.colTitle; verticalAlignment: Text.AlignVCenter }
            Label { text: "歌手"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: favoriteLayout.colArtist; verticalAlignment: Text.AlignVCenter }
            Label { text: "专辑"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: favoriteLayout.colAlbum; verticalAlignment: Text.AlignVCenter }
            Label { text: "时长"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.preferredWidth: favoriteLayout.colDuration; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
            Item { Layout.preferredWidth: favoriteLayout.colPlay }
        }
    }
    Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a48"; visible: musicManager.favorites.length > 0 }

    // ---- 歌曲列表 ----
    ListView {
        id: favoriteListView
        Layout.fillWidth: true; Layout.fillHeight: true
        spacing: 8; clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: musicManager.favorites.length > 0
        cacheBuffer: height * 2; reuseItems: true

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded; width: 10
            background: Rectangle { implicitWidth: 10; radius: 5; color: "#2a2a3a" }
            contentItem: Rectangle {
                implicitWidth: 10; radius: 5
                color: favThumbHover.containsMouse ? "#7777aa" : "#555577"
                Behavior on color { ColorAnimation { duration: 150 } }
                MouseArea { id: favThumbHover; hoverEnabled: true; acceptedButtons: Qt.NoButton; propagateComposedEvents: true }
            }
        }

        model: musicManager.favorites

        delegate: SongRow {
            width: favoriteListView.width
            isCurrent: {
                try {
                    var cp = favoriteLayout.currentPath
                    return cp !== "" && model && (model.path || "") === cp
                } catch (e) { return false }
            }
            fontFamily: favoriteLayout.fontFamily
            colCover: favoriteLayout.colCover
            colTitle: favoriteLayout.colTitle
            colArtist: favoriteLayout.colArtist
            colAlbum: favoriteLayout.colAlbum
            colDuration: favoriteLayout.colDuration
            colPlay: favoriteLayout.colPlay

            onLeftClicked: {
                if (musicManager.playlistSource === 1) {
                    if (musicManager.currentIndex === index) {
                        if (musicManager.isPlaying) musicManager.pause()
                        else musicManager.play()
                    } else {
                        musicManager.playIndex(index)
                    }
                } else {
                    musicManager.playlistSource = 1
                    musicManager.playIndex(index)
                }
            }
            onRightClicked: {
                favoriteLayout.rightClickedIndex = index
                favoriteLayout.rightClickedTrack = model
                favContextMenu.popup()
            }
        }
    }

    // ---- 右键菜单 ----
    Menu {
        id: favContextMenu
        background: Rectangle { color: "#2a2a3a"; border.color: "#444466"; radius: 6; implicitWidth: 160 }
        MenuItem {
            visible: musicManager.playlistSource !== 1
            contentItem: Row {
                spacing: 6; anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 8
                Image { source: "qrc:/qt/qml/JustSolo/data/image/AddToPlayList.png"; width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter }
                Label { text: "添加到音乐列表"; font.family: fontFamily; font.pixelSize: 14; color: "#cccccc"; anchors.verticalCenter: parent.verticalCenter }
            }
            onClicked: { if (favoriteLayout.rightClickedTrack) musicManager.addToPlaylist(favoriteLayout.rightClickedTrack) }
            background: Rectangle { color: parent.hovered ? "#3a3a5a" : "transparent"; radius: 4 }
        }
        MenuItem {
            text: "取消收藏"
            onClicked: musicManager.removeFavorite(favoriteLayout.rightClickedIndex)
            contentItem: Label { text: "取消收藏"; font.family: fontFamily; font.pixelSize: 14; color: "#cccccc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: parent.hovered ? "#3a3a5a" : "transparent"; radius: 4 }
        }
    }

    // ---- 空列表提示 ----
    Column {
        Layout.alignment: Qt.AlignCenter; spacing: 14
        visible: musicManager.favorites.length === 0
        Label { text: "还没有收藏的歌曲"; font.family: fontFamily; font.pixelSize: 16; color: "#757575"; anchors.horizontalCenter: parent.horizontalCenter }
        Label { text: "在首页右键歌曲即可收藏"; font.family: fontFamily; font.pixelSize: 13; color: "#666"; anchors.horizontalCenter: parent.horizontalCenter }
    }
}
