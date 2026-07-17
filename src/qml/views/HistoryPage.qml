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

    // 当前播放曲目的 path，用于跨列表匹配
    property string currentPath: {
        var ci = musicManager.currentIndex
        var pl = musicManager.playlist
        return (ci >= 0 && ci < pl.length) ? (pl[ci].path || "") : ""
    }

    // 播放后恢复滚动位置（避免 addToHistory 导致的跳动）
    Timer { id: histRestoreTimer; interval: 0; repeat: false; property real savedY: 0; onTriggered: historyListView.contentY = savedY }

    // ---- 列标题 + 清除按钮 ----
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

        Rectangle {
            anchors.right: parent.right; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: clearBtnText.contentWidth + 16; height: 26; radius: 4
            color: clearBtnMA.containsMouse ? "#3a2a2a" : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            Label {
                id: clearBtnText
                text: "清除所有历史"; font.family: fontFamily; font.pixelSize: 12; color: "#969696"
                anchors.centerIn: parent
            }
            MouseArea {
                id: clearBtnMA; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: musicManager.clearHistory()
            }
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
            isCurrent: (model.path || "") === historyLayout.currentPath && historyLayout.currentPath !== ""
            fontFamily: historyLayout.fontFamily
            colCover: historyLayout.colCover
            colTitle: historyLayout.colTitle
            colArtist: historyLayout.colArtist
            colAlbum: historyLayout.colAlbum
            colDuration: historyLayout.colDuration
            colPlay: historyLayout.colPlay

            onLeftClicked: {
                var p = model.path || ""
                var ci = musicManager.currentIndex
                var pl = musicManager.playlist
                // 同曲目 → 切换播放/暂停
                if (ci >= 0 && ci < pl.length && (pl[ci].path || "") === p) {
                    if (musicManager.isPlaying) musicManager.pause()
                    else musicManager.play()
                    return
                }
                // 在播放列表中查找
                for (var i = 0; i < pl.length; i++) {
                    if ((pl[i].path || "") === p) {
                        histRestoreTimer.savedY = historyListView.contentY
                        histRestoreTimer.start()
                        musicManager.playIndex(i)
                        return
                    }
                }
            }
            onRightClicked: {
                historyLayout.rightClickedIndex = index
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
