import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// 收藏页 - 已收藏音乐列表
// 通过 Loader 按需加载，切换页面时销毁释放内存
// ============================================================
ColumnLayout {
    id: favoriteLayout
    spacing: 0
    clip: true

    // ---- 外部注入属性 ----
    property int sidebarWidth: 230
    property int windowWidth: 1200
    property string fontFamily: ""

    // ---- 缓存右键点击的索引（避免 reuseItems 滚动后 index 错乱） ----
    property int rightClickedIndex: -1

    // ---- 列表列宽计算 ----
    property int colCover: 40
    property int colPlay: 50
    property int colSpacing: 5
    property int colPlayIconSize: 20

    property real _availW: Math.max(200,
        (favoriteListView.width > 0 ? favoriteListView.width : windowWidth - sidebarWidth - 80)
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
        visible: musicManager.favorites.length > 0

        RowLayout {
            anchors.fill: parent
            anchors.margins: 5
            anchors.leftMargin: 8
            spacing: favoriteLayout.colSpacing

            Item { Layout.preferredWidth: favoriteLayout.colCover }
            Label {
                text: "标题"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                Layout.fillWidth: true; Layout.preferredWidth: favoriteLayout.colTitle
                verticalAlignment: Text.AlignVCenter
            }
            Label {
                text: "歌手"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                Layout.fillWidth: true; Layout.preferredWidth: favoriteLayout.colArtist
                verticalAlignment: Text.AlignVCenter
            }
            Label {
                text: "专辑"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                Layout.fillWidth: true; Layout.preferredWidth: favoriteLayout.colAlbum
                verticalAlignment: Text.AlignVCenter
            }
            Label {
                text: "时长"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                Layout.preferredWidth: favoriteLayout.colDuration
                verticalAlignment: Text.AlignVCenter
                horizontalAlignment: Text.AlignRight
            }
            Item { Layout.preferredWidth: favoriteLayout.colPlay }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 1; color: "#2a2a48"
        visible: musicManager.favorites.length > 0
    }

    ListView {
        id: favoriteListView
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 8; clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: musicManager.favorites.length > 0
        cacheBuffer: height * 2
        reuseItems: true

        ScrollBar.vertical: ScrollBar {
            id: favScrollBar
            policy: ScrollBar.AsNeeded; width: 10
            background: Rectangle { implicitWidth: 10; radius: 5; color: "#2a2a3a" }
            contentItem: Rectangle {
                id: favThumb
                implicitWidth: 10
                radius: 5
                color: favThumbHover.containsMouse ? "#7777aa" : "#555577"
                Behavior on color { ColorAnimation { duration: 150 } }
                MouseArea {
                    id: favThumbHover
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    propagateComposedEvents: true
                }
            }
        }

        model: musicManager.favorites

        delegate: Rectangle {
            width: favoriteListView.width
            height: 50; radius: 8
            color: favItemMouse.containsMouse ? "#2a2a48" : "#222236"
            Behavior on color { ColorAnimation { duration: 120 } }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 5
                anchors.leftMargin: 8
                spacing: favoriteLayout.colSpacing

                Rectangle {
                    Layout.preferredWidth: favoriteLayout.colCover
                    Layout.preferredHeight: 40
                    Layout.alignment: Qt.AlignVCenter
                    radius: 6; color: "#3a3a55"
                    Image {
                        id: favCoverImg
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
                    Layout.preferredWidth: favoriteLayout.colTitle
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
                        width: Math.max(favQualText.contentWidth + 8, 20)
                        height: 16; radius: 3; color: "#D4AF37"
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left

                        Label {
                            id: favQualText
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
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: favoriteLayout.colArtist
                }

                Label {
                    text: modelData.album || ""
                    font.family: fontFamily; font.pixelSize: 14; color: "#888888"
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: favoriteLayout.colAlbum
                }

                Label {
                    text: modelData.durationText || ""
                    font.family: fontFamily; font.pixelSize: 14; color: "#969696"
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignRight
                    Layout.fillHeight: true
                    Layout.preferredWidth: favoriteLayout.colDuration
                }

                Item {
                    Layout.preferredWidth: favoriteLayout.colPlay
                    Layout.preferredHeight: favoriteLayout.colPlayIconSize
                    Layout.alignment: Qt.AlignVCenter
                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                        width: favoriteLayout.colPlayIconSize
                        height: favoriteLayout.colPlayIconSize
                        opacity: 0.35
                    }
                }
            }

            Menu {
                id: favContextMenu
                background: Rectangle {
                    color: "#2a2a3a"; border.color: "#444466"
                    radius: 6; implicitWidth: 140
                }
                MenuItem {
                    id: favMenuItem
                    text: "取消收藏"
                    onClicked: musicManager.removeFavorite(favoriteLayout.rightClickedIndex)
                    contentItem: Label {
                        text: favMenuItem.text
                        font.family: fontFamily; font.pixelSize: 14; color: "#cccccc"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        color: favMenuItem.hovered ? "#3a3a5a" : "transparent"
                        radius: 4
                    }
                }
            }

            MouseArea {
                id: favItemMouse
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: {
                    if (mouse.button === Qt.RightButton) {
                        favoriteLayout.rightClickedIndex = index
                        favContextMenu.popup()
                    }
                }
            }
        }


    }

    Column {
        Layout.alignment: Qt.AlignCenter
        spacing: 14
        visible: musicManager.favorites.length === 0

        Label {
            text: "还没有收藏的歌曲"
            font.family: fontFamily; font.pixelSize: 16; color: "#757575"
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
