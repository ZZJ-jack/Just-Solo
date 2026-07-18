import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// SongRow — 共享歌曲行组件
// model / index 由 ListView delegate 自动注入
// ============================================================
Rectangle {
    id: songRow
    width: parent ? parent.width : 200
    height: 50
    radius: 8
    color: isCurrent ? "#36365a"
         : (rowMouse.containsMouse ? "#2a2a48" : "#222236")
    Behavior on color { ColorAnimation { duration: 120 } }

    // ListView delegate 自动注入
    required property var    model
    required property int    index

    // 外部显式传入
    required property bool   isCurrent
    required property string fontFamily
    required property real   colCover
    required property real   colTitle
    required property real   colArtist
    required property real   colAlbum
    required property real   colDuration
    required property real   colPlay
    property bool showSourceHint: false  // 首页 source≠0 时显示提示

    signal leftClicked()
    signal rightClicked()

    RowLayout {
        anchors.fill: parent
        anchors.margins: 5
        anchors.leftMargin: 8
        spacing: 0

        Rectangle {
            Layout.preferredWidth: Math.min(songRow.colCover, 40)
            Layout.preferredHeight: 40
            Layout.maximumWidth: 40
            Layout.alignment: Qt.AlignVCenter
            radius: 6; color: "#3a3a55"
            Image {
                anchors.fill: parent; anchors.margins: 2
                sourceSize.width: 40; sourceSize.height: 40
                source: model.cover || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Label {
                anchors.centerIn: parent
                text: "\u266B"; font.family: songRow.fontFamily; font.pixelSize: 18; color: "#666"
                visible: !model.cover || model.cover === ""
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredWidth: songRow.colTitle
            Layout.preferredHeight: 40
            Layout.alignment: Qt.AlignVCenter
            Label {
                text: model.name || ""
                font.family: songRow.fontFamily; font.pixelSize: 14
                font.bold: true; color: "#d4d4d4"
                elide: Text.ElideRight
                width: parent.width
                anchors.top: parent.top; anchors.left: parent.left
            }
            Rectangle {
                visible: model.quality && model.quality !== ""
                width: Math.max(qualityText.contentWidth + 8, 20)
                height: 16; radius: 3; color: "#D4AF37"
                anchors.bottom: parent.bottom; anchors.left: parent.left
                Label {
                    id: qualityText
                    text: model.quality || ""
                    font.family: songRow.fontFamily; font.pixelSize: 10; font.bold: true
                    color: "white"; anchors.centerIn: parent
                }
            }
        }

        Label {
            text: model.artist || "未知"
            font.family: songRow.fontFamily; font.pixelSize: 14; color: "#969696"
            elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: songRow.colArtist
        }

        Label {
            text: model.album || ""
            font.family: songRow.fontFamily; font.pixelSize: 14; color: "#888888"
            elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: songRow.colAlbum
        }

        Label {
            text: model.durationText || ""
            font.family: songRow.fontFamily; font.pixelSize: 14; color: "#969696"
            verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
            Layout.fillHeight: true; Layout.preferredWidth: songRow.colDuration
        }

        Item {
            Layout.preferredWidth: songRow.colPlay
            Layout.preferredHeight: 20; Layout.alignment: Qt.AlignVCenter
            Image {
                anchors.centerIn: parent
                source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                width: 18; height: 18; opacity: 0.35
                visible: !songRow.isCurrent
            }
            Image {
                anchors.centerIn: parent
                source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                width: 18; height: 18
                visible: songRow.isCurrent && !musicManager.isPlaying
            }
            Image {
                anchors.centerIn: parent
                source: "qrc:/qt/qml/JustSolo/data/image/playing.png"
                width: 18; height: 18
                visible: songRow.isCurrent && musicManager.isPlaying
            }

            ToolTip {
                visible: songRow.showSourceHint && rowMouse.containsMouse
                text: "播放列表来源不是首页\n请前往「播放列表」页管理"
                delay: 600
                font.family: songRow.fontFamily
            }
        }
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent; hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton)
                songRow.rightClicked()
            else
                songRow.leftClicked()
        }
    }
}
