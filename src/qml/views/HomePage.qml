import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// ============================================================
// 首页 - 音乐列表视图
// 通过 Loader 按需加载，切换页面时销毁释放内存
// ============================================================
ColumnLayout {
    id: musicListLayout
    spacing: 0
    clip: true

    // ---- 外部注入属性 ----
    property int sidebarWidth: 230
    property int windowWidth: 1200

    // ---- 缓存右键点击的曲目（避免 reuseItems 导致 modelData 错乱） ----
    property var rightClickedTrack: null
    property string fontFamily: ""

    // ---- 列表列宽计算 ----
    property int colCover: 40
    property int colPlay: 50
    property int colSpacing: 5
    property int colPlayIconSize: 20

    property real _availW: Math.max(200,
        (musicListView.width > 0 ? musicListView.width : windowWidth - sidebarWidth - 80)
        - 20 - colCover - colPlay - colSpacing * 5)

    property real colTitle:    Math.max(100, _availW * 0.35)
    property real colArtist:   Math.max(80,  _availW * 0.25)
    property real colAlbum:    Math.max(80,  _availW * 0.25)
    property real colDuration: Math.max(45,  _availW * 0.15)

    // ---- 列标题栏 ----
    Rectangle {
        Layout.fillWidth: true
        height: 32
        color: "transparent"
        visible: musicManager.playlist.length > 0

        RowLayout {
            anchors.fill: parent
            anchors.margins: 5
            anchors.leftMargin: 8
            spacing: musicListLayout.colSpacing

            Item { Layout.preferredWidth: musicListLayout.colCover }

            Label {
                text: "标题"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                Layout.fillWidth: true; Layout.preferredWidth: musicListLayout.colTitle
                verticalAlignment: Text.AlignVCenter
            }
            Label {
                text: "歌手"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                Layout.fillWidth: true; Layout.preferredWidth: musicListLayout.colArtist
                verticalAlignment: Text.AlignVCenter
            }
            Label {
                text: "专辑"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                Layout.fillWidth: true; Layout.preferredWidth: musicListLayout.colAlbum
                verticalAlignment: Text.AlignVCenter
            }
            Label {
                text: "时长"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                Layout.preferredWidth: musicListLayout.colDuration
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight
            }
            Item { Layout.preferredWidth: musicListLayout.colPlay }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: "#2a2a48"
        visible: musicManager.playlist.length > 0
    }

    // ---- 歌曲列表 ----
    ListView {
        id: musicListView
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: musicManager.playlist.length > 0
        cacheBuffer: height * 2
        reuseItems: true

        ScrollBar.vertical: ScrollBar {
            id: listScrollBar
            policy: ScrollBar.AsNeeded; width: 10
            background: Rectangle { implicitWidth: 10; radius: 5; color: "#2a2a3a" }
            contentItem: Rectangle {
                id: thumb
                implicitWidth: 10
                radius: 5
                color: thumbHoverArea.containsMouse ? "#7777aa" : "#555577"
                Behavior on color { ColorAnimation { duration: 150 } }
                MouseArea {
                    id: thumbHoverArea
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    propagateComposedEvents: true
                }
            }
        }

        model: musicManager.playlist

        delegate: Rectangle {
            width: musicListView.width
            height: 50
            radius: 8
            color: musicManager.currentIndex === index ? "#36365a"
                 : (musicItemMouse.containsMouse ? "#2a2a48" : "#222236")
            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 5
                anchors.leftMargin: 8
                spacing: musicListLayout.colSpacing

                Rectangle {
                    Layout.preferredWidth: musicListLayout.colCover
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignVCenter
                    radius: 6; color: "#3a3a55"
                    Image {
                        id: coverImg
                        anchors.fill: parent
                        anchors.margins: 2
                        sourceSize.width: 30
                        sourceSize.height: 30
                        source: modelData.cover || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Label {
                        anchors.centerIn: parent
                        text: "\u266B"; font.family: fontFamily; font.pixelSize: 18; color: "#666"
                        visible: !modelData.cover || modelData.cover === ""
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredWidth: musicListLayout.colTitle
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignVCenter

                    Label {
                        id: titleText
                        text: modelData.name || ""
                        font.family: fontFamily; font.pixelSize: 14
                        font.bold: true; color: "#d4d4d4"
                        elide: Text.ElideRight
                        width: parent.width
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }

                    Rectangle {
                        id: qualityBadge
                        visible: modelData.quality && modelData.quality !== ""
                        width: Math.max(qualityText.contentWidth + 8, 20)
                        height: 16; radius: 3; color: "#D4AF37"
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left

                        Label {
                            id: qualityText
                            text: modelData.quality || ""
                            font.family: fontFamily; font.pixelSize: 10; font.bold: true
                            color: "white"
                            anchors.centerIn: parent
                        }
                    }
                }

                Label {
                    text: modelData.artist || "未知"
                    font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: musicListLayout.colArtist
                }

                Label {
                    text: modelData.album || ""
                    font.family: fontFamily; font.pixelSize: 14; color: "#888888"
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: musicListLayout.colAlbum
                }

                Label {
                    text: modelData.durationText || ""
                    font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    Layout.fillHeight: true
                    Layout.preferredWidth: musicListLayout.colDuration
                }

                Item {
                    Layout.preferredWidth: musicListLayout.colPlay
                    Layout.preferredHeight: musicListLayout.colPlayIconSize
                    Layout.alignment: Qt.AlignVCenter
                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                        width: musicListLayout.colPlayIconSize
                        height: musicListLayout.colPlayIconSize
                        opacity: 0.35
                        visible: musicManager.currentIndex !== index
                    }
                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                        width: musicListLayout.colPlayIconSize
                        height: musicListLayout.colPlayIconSize
                        visible: musicManager.currentIndex === index && !musicManager.isPlaying
                    }
                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/qt/qml/JustSolo/data/image/playing.png"
                        width: musicListLayout.colPlayIconSize
                        height: musicListLayout.colPlayIconSize
                        visible: musicManager.currentIndex === index && musicManager.isPlaying
                    }
                }
            }

            Menu {
                id: homeContextMenu
                background: Rectangle {
                    color: "#2a2a3a"; border.color: "#444466"
                    radius: 6; implicitWidth: 140
                }
                MenuItem {
                    id: homeMenuItem
                    text: musicListLayout.rightClickedTrack ? (musicManager.isFavorite(musicListLayout.rightClickedTrack) ? "取消收藏" : "收藏") : "收藏"
                    onClicked: {
                        if (musicListLayout.rightClickedTrack)
                            musicManager.toggleFavorite(musicListLayout.rightClickedTrack)
                    }
                    contentItem: Label {
                        text: homeMenuItem.text
                        font.family: fontFamily; font.pixelSize: 14; color: "#cccccc"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: homeMenuItem.hovered ? "#3a3a5a" : "transparent"
                        radius: 4
                    }
                }
            }

            MouseArea {
                id: musicItemMouse
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                        musicListLayout.rightClickedTrack = modelData
                        homeContextMenu.popup()
                    } else {
                        if (musicManager.currentIndex === index) {
                            if (musicManager.isPlaying) musicManager.pause()
                            else musicManager.play()
                        } else {
                            musicManager.playIndex(index)
                        }
                    }
                }
            }
        }


    }

    // ---- 空列表提示 ----
    Column {
        Layout.alignment: Qt.AlignCenter
        spacing: 14
        visible: musicManager.playlist.length === 0

        Label {
            text: "还没有音乐"
            font.family: fontFamily; font.pixelSize: 16; color: "#757575"
            anchors.horizontalCenter: parent.horizontalCenter
        }
        Label {
            text: "点击上方「添加音乐」导入本地文件"
            font.family: fontFamily; font.pixelSize: 13; color: "#666"
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
