import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// 历史页 - 播放历史记录（SongRow 共享组件）
// ============================================================
ColumnLayout {
    id: historyLayout
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
        (historyListView.width > 0 ? historyListView.width : windowWidth - sidebarWidth - 80) - 20 - colPlay)
    property real colCover:    Math.max(40, _totalW * 2 / 9)
    property real colTitle:    Math.max(60, _totalW * 2 / 9)
    property real colArtist:   Math.max(50, _totalW * 2 / 9)
    property real colAlbum:    Math.max(50, _totalW * 2 / 9)
    property real colDuration: Math.max(36, _totalW * 1 / 9)

    // 当前播放曲目的 path，跨来源匹配
    property string currentPath: {
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

    // ---- 列标题 ----
    Rectangle {
        Layout.fillWidth: true; height: 32; color: "transparent"
        visible: musicManager.history.length > 0
        RowLayout {
            anchors.fill: parent; anchors.margins: 5; anchors.leftMargin: 8; spacing: 0
            Item { Layout.preferredWidth: historyLayout.colCover; Layout.maximumWidth: 40 }
            Label { text: "标题"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: historyLayout.colTitle; verticalAlignment: Text.AlignVCenter }
            Label { text: "歌手"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: historyLayout.colArtist; verticalAlignment: Text.AlignVCenter }
            Label { text: "专辑"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: historyLayout.colAlbum; verticalAlignment: Text.AlignVCenter }
            Label { text: "时长"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.preferredWidth: historyLayout.colDuration; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
            Item { Layout.preferredWidth: historyLayout.colPlay }
        }
    }
    Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a48"; visible: musicManager.history.length > 0 }

    // ---- 歌曲列表 ----
    ListView {
        id: historyListView
        Layout.fillWidth: true; Layout.fillHeight: true
        spacing: 8; clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: musicManager.history.length > 0
        cacheBuffer: height * 2; reuseItems: true

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded; width: 10
            background: Rectangle { implicitWidth: 10; radius: 5; color: "#2a2a3a" }
            contentItem: Rectangle {
                implicitWidth: 10; radius: 5
                color: histThumbHover.containsMouse ? "#7777aa" : "#555577"
                Behavior on color { ColorAnimation { duration: 150 } }
                MouseArea { id: histThumbHover; hoverEnabled: true; acceptedButtons: Qt.NoButton; propagateComposedEvents: true }
            }
        }

        model: musicManager.history

        delegate: SongRow {
            width: historyListView.width
            isCurrent: {
                try {
                    var cp = historyLayout.currentPath
                    return cp !== "" && model && (model.path || "") === cp
                } catch (e) { return false }
            }
            fontFamily: historyLayout.fontFamily
            colCover: historyLayout.colCover
            colTitle: historyLayout.colTitle
            colArtist: historyLayout.colArtist
            colAlbum: historyLayout.colAlbum
            colDuration: historyLayout.colDuration
            colPlay: historyLayout.colPlay

            onLeftClicked: {
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
            onRightClicked: {
                historyLayout.rightClickedIndex = index
                historyLayout.rightClickedTrack = model
                histContextMenu.popup()
            }
        }
    }

    // ---- 右键菜单 ----
    Menu {
        id: histContextMenu
        background: Rectangle { color: "#2a2a3a"; border.color: "#444466"; radius: 6; implicitWidth: 140 }
        MenuItem {
            text: "删除历史"
            onClicked: musicManager.removeHistoryItem(historyLayout.rightClickedIndex)
            contentItem: Label { text: "删除历史"; font.family: fontFamily; font.pixelSize: 14; color: "#cccccc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: parent.hovered ? "#3a3a5a" : "transparent"; radius: 4 }
        }
    }

    // ---- 空列表提示 ----
    Column {
        Layout.alignment: Qt.AlignCenter; spacing: 14
        visible: musicManager.history.length === 0
        Label { text: "还没有播放历史"; font.family: fontFamily; font.pixelSize: 16; color: "#757575"; anchors.horizontalCenter: parent.horizontalCenter }
        Label { text: "播放歌曲后会自动记录"; font.family: fontFamily; font.pixelSize: 13; color: "#666"; anchors.horizontalCenter: parent.horizontalCenter }
    }
}
