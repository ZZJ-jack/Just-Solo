import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// ============================================================
// 播放列表页 — 展示当前全局播放列表
// ============================================================
ColumnLayout {
    id: playlistLayout
    spacing: 0
    clip: true

    property int sidebarWidth: 230
    property int windowWidth: 1200
    property var rightClickedTrack: null
    property string fontFamily: ""

    property int scrollToIndex: -1

    onScrollToIndexChanged: {
        if (scrollToIndex >= 0 && scrollToIndex < dynamicModel.length) {
            Qt.callLater(function() {
                playlistListView.positionViewAtIndex(scrollToIndex, ListView.Center)
            })
        }
    }

    Component.onCompleted: {
        if (musicManager.currentIndex >= 0) scrollTimer.start()
    }

    onVisibleChanged: {
        if (visible && musicManager.currentIndex >= 0) scrollTimer.start()
    }

    Timer {
        id: scrollTimer
        interval: 60
        repeat: false
        onTriggered: {
            var idx = musicManager.currentIndex
            if (idx >= 0 && idx < dynamicModel.length)
                playlistListView.positionViewAtIndex(idx, ListView.Center)
        }
    }

    property string playingPath: {
        try {
            var ci = musicManager.currentIndex
            if (ci < 0) return ""
            var src = musicManager.playlistSource
            var list = src === 1 ? musicManager.favorites : (src === 2 ? musicManager.history : musicManager.playlist)
            if (!list || list.length === 0) return ""
            if (ci >= 0 && ci < list.length) return (list[ci].path || "")
        } catch (e) {}
        return ""
    }

    // 动态模型：跟随 playlistSource
    property var dynamicModel: {
        try {
            var src = musicManager.playlistSource
            return src === 1 ? musicManager.favorites
                 : (src === 2 ? musicManager.history : musicManager.playlist)
        } catch (e) { return musicManager.playlist }
    }

    // ---- 列宽 (2:2:2:2:1) ----
    property int colPlay: 36
    property real _totalW: Math.max(400,
        (playlistListView.width > 0 ? playlistListView.width : windowWidth - sidebarWidth - 80) - 20 - colPlay)
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
            Item { Layout.preferredWidth: playlistLayout.colCover; Layout.maximumWidth: 40 }
            Label { text: "标题"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: playlistLayout.colTitle; verticalAlignment: Text.AlignVCenter }
            Label { text: "歌手"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: playlistLayout.colArtist; verticalAlignment: Text.AlignVCenter }
            Label { text: "专辑"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: playlistLayout.colAlbum; verticalAlignment: Text.AlignVCenter }
            Label { text: "时长"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.preferredWidth: playlistLayout.colDuration; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
            Item { Layout.preferredWidth: playlistLayout.colPlay }
        }
    }
    Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a48"; visible: musicManager.playlist.length > 0 }

    // ---- 歌曲列表 ----
    ListView {
        id: playlistListView
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

        model: playlistLayout.dynamicModel

        delegate: SongRow {
            width: playlistListView.width
            isCurrent: {
                try { return model && model.path === playlistLayout.playingPath } catch (e) { return false }
            }
            fontFamily: playlistLayout.fontFamily
            colCover: playlistLayout.colCover
            colTitle: playlistLayout.colTitle
            colArtist: playlistLayout.colArtist
            colAlbum: playlistLayout.colAlbum
            colDuration: playlistLayout.colDuration
            colPlay: playlistLayout.colPlay

            onLeftClicked: {
                var src = musicManager.playlistSource
                if (musicManager.currentIndex === index && (src === 0 || src === 1 || src === 2)) {
                    if (musicManager.isPlaying) musicManager.pause()
                    else musicManager.play()
                } else {
                    musicManager.playIndex(index)
                }
            }
            onRightClicked: {
                playlistLayout.rightClickedTrack = model
                playlistContextMenu.popup()
            }
        }
    }

    // ---- 右键菜单 ----
    Menu {
        id: playlistContextMenu
        background: Rectangle { color: "#2a2a3a"; border.color: "#444466"; radius: 6; implicitWidth: 140 }
        MenuItem {
            text: "从播放列表删除"
            onClicked: { if (playlistLayout.rightClickedTrack) musicManager.removeFromPlaylist(playlistLayout.rightClickedTrack) }
            contentItem: Label { text: "从播放列表删除"; font.family: fontFamily; font.pixelSize: 14; color: "#cccccc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: parent.hovered ? "#3a3a5a" : "transparent"; radius: 4 }
        }
        MenuItem {
            id: plMenuItem
            text: playlistLayout.rightClickedTrack ? (musicManager.isFavorite(playlistLayout.rightClickedTrack) ? "取消收藏" : "收藏") : "收藏"
            onClicked: { if (playlistLayout.rightClickedTrack) musicManager.toggleFavorite(playlistLayout.rightClickedTrack) }
            contentItem: Label { text: plMenuItem.text; font.family: fontFamily; font.pixelSize: 14; color: "#cccccc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: plMenuItem.hovered ? "#3a3a5a" : "transparent"; radius: 4 }
        }
    }

    // ---- 空列表提示 ----
    Column {
        Layout.alignment: Qt.AlignCenter; spacing: 14
        visible: musicManager.playlist.length === 0
        Label { text: "播放列表为空"; font.family: fontFamily; font.pixelSize: 16; color: "#757575"; anchors.horizontalCenter: parent.horizontalCenter }
        Label { text: "在其他页面右键歌曲即可添加"; font.family: fontFamily; font.pixelSize: 13; color: "#666"; anchors.horizontalCenter: parent.horizontalCenter }
    }
}
