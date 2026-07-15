import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// 历史页 - 播放历史记录列表
// 通过 Loader 按需加载，切换页面时销毁释放内存
// ============================================================
ColumnLayout {
    id: historyLayout
    spacing: 0
    clip: true

    // ---- 外部注入属性 ----
    property int sidebarWidth: 230
    property int windowWidth: 1200
    property string fontFamily: ""

    // ---- 列表列宽计算 ----
    property int colCover: 40
    property int colPlay: 50
    property int colSpacing: 5
    property int colPlayIconSize: 20

    property real _availW: Math.max(200,
        (historyListView.width > 0 ? historyListView.width : windowWidth - sidebarWidth - 80)
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
        visible: musicManager.history.length > 0

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 120
            spacing: historyLayout.colSpacing

            Item { Layout.preferredWidth: historyLayout.colCover }
            Label {
                text: "标题"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                Layout.fillWidth: true; Layout.preferredWidth: historyLayout.colTitle
                verticalAlignment: Text.AlignVCenter
            }
            Label {
                text: "歌手"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                Layout.fillWidth: true; Layout.preferredWidth: historyLayout.colArtist
                verticalAlignment: Text.AlignVCenter
            }
            Label {
                text: "专辑"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                Layout.fillWidth: true; Layout.preferredWidth: historyLayout.colAlbum
                verticalAlignment: Text.AlignVCenter
            }
            Label {
                text: "时长"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                Layout.preferredWidth: historyLayout.colDuration
                verticalAlignment: Text.AlignVCenter
            }
            Item { Layout.preferredWidth: historyLayout.colPlay }
        }

        // 清除所有历史按钮 - 右上角（固定位置，不随列宽变化）
        Rectangle {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 106; height: 26
            radius: 4
            color: clearHistBtn.containsMouse ? "#4a4a6a" : "#3a3a5a"
            Label {
                anchors.centerIn: parent
                text: "清除所有历史"
                font.family: fontFamily; font.pixelSize: 12; color: "#cccccc"
            }
            MouseArea {
                id: clearHistBtn
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: musicManager.clearHistory()
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 1; color: "#2a2a48"
        visible: musicManager.history.length > 0
    }

    ListView {
        id: historyListView
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 8; clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: musicManager.history.length > 0
        cacheBuffer: height * 2

        ScrollBar.vertical: ScrollBar {
            id: histScrollBar
            policy: ScrollBar.AsNeeded; width: 10
            background: Rectangle { implicitWidth: 10; radius: 5; color: "#2a2a3a" }
            contentItem: Rectangle {
                id: histThumb
                implicitWidth: 10
                radius: 5
                color: histThumbHover.containsMouse ? "#7777aa" : "#555577"
                Behavior on color { ColorAnimation { duration: 150 } }
                MouseArea {
                    id: histThumbHover
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    propagateComposedEvents: true
                }
            }
        }

        model: musicManager.history

        delegate: Rectangle {
            width: historyListView.width
            height: 50; radius: 8
            color: histItemMouse.containsMouse ? "#2a2a48" : "#222236"
            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 5
                anchors.leftMargin: 8
                spacing: historyLayout.colSpacing

                Rectangle {
                    Layout.preferredWidth: historyLayout.colCover
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignVCenter
                    radius: 6; color: "#3a3a55"
                    Image {
                        id: histCoverImg
                        anchors.fill: parent
                        anchors.margins: 2
                        cache: false
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
                    Layout.preferredWidth: historyLayout.colTitle
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignVCenter

                    Label {
                        text: modelData.name || ""
                        font.family: fontFamily; font.pixelSize: 14
                        font.bold: true; color: "#d4d4d4"
                        elide: Text.ElideRight
                        width: parent.width
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }

                    Rectangle {
                        visible: modelData.quality && modelData.quality !== ""
                        width: Math.max(histQualText.contentWidth + 8, 20)
                        height: 16; radius: 3; color: "#D4AF37"
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left

                        Label {
                            id: histQualText
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
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: historyLayout.colArtist
                }

                Label {
                    text: modelData.album || ""
                    font.family: fontFamily; font.pixelSize: 14; color: "#888888"
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: historyLayout.colAlbum
                }

                Label {
                    text: {
                        if (modelData.duration > 0) {
                            var m = Math.floor(modelData.duration / 60)
                            var s = Math.floor(modelData.duration % 60)
                            return m + ":" + (s < 10 ? "0" : "") + s
                        }
                        return ""
                    }
                    font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                    verticalAlignment: Text.AlignVCenter
                    Layout.fillHeight: true
                    Layout.preferredWidth: historyLayout.colDuration
                }

                Item {
                    Layout.preferredWidth: historyLayout.colPlay
                    Layout.preferredHeight: historyLayout.colPlayIconSize
                    Layout.alignment: Qt.AlignVCenter
                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                        width: historyLayout.colPlayIconSize
                        height: historyLayout.colPlayIconSize
                        opacity: 0.35
                    }
                }
            }

            Menu {
                id: histContextMenu
                background: Rectangle {
                    color: "#2a2a3a"; border.color: "#444466"
                    radius: 6; implicitWidth: 140
                }
                MenuItem {
                    id: histMenuItem
                    text: "删除记录"
                    onClicked: musicManager.removeHistoryItem(index)
                    contentItem: Label {
                        text: histMenuItem.text
                        font.family: fontFamily; font.pixelSize: 14; color: "#cccccc"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: histMenuItem.hovered ? "#3a3a5a" : "transparent"
                        radius: 4
                    }
                }
            }

            MouseArea {
                id: histItemMouse
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: {
                    if (mouse.button === Qt.RightButton) {
                        histContextMenu.popup()
                    }
                }
            }
        }


    }

    Column {
        Layout.alignment: Qt.AlignCenter
        spacing: 14
        visible: musicManager.history.length === 0

        Label {
            text: "还没有历史记录"
            font.family: fontFamily; font.pixelSize: 16; color: "#757575"
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
