import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// 自定义播放列表页面（参照 HomePage 布局）
// ============================================================
ColumnLayout {
    id: root
    spacing: 0
    clip: true

    property int sidebarWidth: 230
    property int windowWidth: 1200
    property int playlistIndex: -1
    property string fontFamily: ""

    // ---- 列宽 (2:2:2:2:1) ----
    property int colPlay: 36
    property real _totalW: Math.max(400,
        (listView.width > 0 ? listView.width : windowWidth - sidebarWidth - 80) - 20 - colPlay)
    property real colCover:    Math.max(40, _totalW * 2 / 9)
    property real colTitle:    Math.max(60, _totalW * 2 / 9)
    property real colArtist:   Math.max(50, _totalW * 2 / 9)
    property real colAlbum:    Math.max(50, _totalW * 2 / 9)
    property real colDuration: Math.max(36, _totalW * 1 / 9)

    // 当前列表数据（当索引变化时动态更新）
    property var songs: playlistIndex >= 0 && playlistIndex < musicManager.customPlaylists.length
                        ? musicManager.customPlaylists[playlistIndex].songs || []
                        : []

    // ---- 列头 ----
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        color: "#2a2a46"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 8
            spacing: 0

            Item { Layout.preferredWidth: root.colPlay }
            Item { Layout.preferredWidth: root.colCover }
            Label { text: "标题"; Layout.preferredWidth: root.colTitle; font.family: root.fontFamily; font.pixelSize: 12; color: "#888" }
            Label { text: "歌手"; Layout.preferredWidth: root.colArtist; font.family: root.fontFamily; font.pixelSize: 12; color: "#888" }
            Label { text: "专辑"; Layout.preferredWidth: root.colAlbum; font.family: root.fontFamily; font.pixelSize: 12; color: "#888" }
            Label { text: "时长"; Layout.preferredWidth: root.colDuration; font.family: root.fontFamily; font.pixelSize: 12; color: "#888" }
        }
    }

    // ---- 歌曲列表 ----
    ListView {
        id: listView
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 2
        clip: true

        model: root.songs

        delegate: SongRow {
            width: listView.width
            isCurrent: false
            fontFamily: root.fontFamily
            colCover: root.colCover
            colTitle: root.colTitle
            colArtist: root.colArtist
            colAlbum: root.colAlbum
            colDuration: root.colDuration
            colPlay: root.colPlay
            showSourceHint: false
        }

        // 空列表提示
        Label {
            anchors.centerIn: parent
            text: "列表为空，暂未添加歌曲"
            font.family: root.fontFamily; font.pixelSize: 14; color: "#666"
            visible: parent.count === 0
        }
    }
}
