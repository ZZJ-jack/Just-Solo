import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls

Window {
    id: mainWindow
    width: 1200
    height: 800
    minimumWidth: 900
    minimumHeight: 600
    visible: true
    title: "Just Solo"
    color: "#1e1e2e"
    flags: Qt.FramelessWindowHint | Qt.Window

    property bool isMaximized: false
    property var lastGeo: ({ x: 100, y: 100, w: 1200, h: 800 })

    readonly property int sidebarWidth: 230
    readonly property int playerBarHeight: 72

    property string currentMenu: "home"

    FontLoader {
        id: appFont
        source: "qrc:/qt/qml/JustSolo/data/font/HarmonyOS_Sans_SC_Regular.ttf"
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // 侧边栏
        Rectangle {
            Layout.preferredWidth: sidebarWidth
            Layout.fillHeight: true
            color: "#222236"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 0

                RowLayout {
                    Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                    spacing: 12

                    Image {
                        source: "qrc:/qt/qml/JustSolo/data/image/logo2.png"
                        sourceSize.width: 42
                        sourceSize.height: 42
                        fillMode: Image.PreserveAspectFit
                    }

                    Label {
                        text: "Just Solo"
                        font.family: appFont.name
                        font.pixelSize: 28
                        font.bold: true
                        color: "#cccccc"
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                Item { Layout.preferredHeight: 20 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: "#3a3a55"
                }

                Item { Layout.preferredHeight: 12 }

                ColumnLayout {
                    spacing: 2

                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/home.png"
                        label: "首页"
                        iconW: 34; iconH: 34; iconSrcSize: 26
                        active: currentMenu === "home"
                        onClicked: currentMenu = "home"
                    }
                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/mylike.png"
                        label: "收藏"
                        iconW: 34; iconH: 34; iconSrcSize: 32
                        active: currentMenu === "favorite"
                        onClicked: currentMenu = "favorite"
                    }
                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/history.png"
                        label: "历史"
                        iconW: 34; iconH: 34; iconSrcSize: 32
                        active: currentMenu === "history"
                        onClicked: currentMenu = "history"
                    }
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38
                    radius: 6
                    color: mouseAreaSettings.containsMouse ? "#2e2e4a" : "transparent"
                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 12; spacing: 10
                        Label { text: "⚙"; font.family: appFont.name; font.pixelSize: 17; color: "#888" }
                        Label { text: "设置"; font.family: appFont.name; font.pixelSize: 14; color: "#888" }
                    }
                    MouseArea {
                        id: mouseAreaSettings
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }
        }

        // 内容区
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#282844"

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 14
                anchors.bottomMargin: 30
                anchors.leftMargin: 30
                anchors.rightMargin: 30
                spacing: 0

                // 搜索框（上移）
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 360
                        Layout.preferredHeight: 42
                        radius: 8
                        color: "#333350"
                        border.color: "#444466"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 10

                            Label {
                                text: "⌕"
                                font.family: appFont.name
                                font.pixelSize: 19
                                color: "#666"
                            }

                            TextInput {
                                Layout.fillWidth: true
                                color: "#cccccc"
                                font.family: appFont.name
                                font.pixelSize: 15
                                clip: true
                                verticalAlignment: TextInput.AlignVCenter

                                Text {
                                    text: "搜索本地音乐..."
                                    font.family: appFont.name
                                    font.pixelSize: 15
                                    color: "#555"
                                    visible: !parent.text
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                Item { Layout.preferredHeight: 32 }

                Row {
                    spacing: 10

                    Item {
                        width: 30; height: 30
                        Image {
                            anchors.centerIn: parent
                            source: currentMenu === "home" ? "qrc:/qt/qml/JustSolo/data/image/home.png"
                                   : (currentMenu === "favorite" ? "qrc:/qt/qml/JustSolo/data/image/mylike.png"
                                   : "qrc:/qt/qml/JustSolo/data/image/history.png")
                            sourceSize.width: 28
                            sourceSize.height: 28
                            fillMode: Image.PreserveAspectFit
                        }
                    }

                    Label {
                        text: currentMenu === "home" ? "首页" : (currentMenu === "favorite" ? "收藏" : "历史")
                        font.family: appFont.name
                        font.pixelSize: 24
                        font.bold: true
                        color: "#dddddd"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Item { Layout.preferredHeight: 16 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "transparent"

                    Column {
                        anchors.centerIn: parent
                        spacing: 14

                        Label {
                            text: currentMenu === "home" ? "开始探索你的音乐库"
                                   : (currentMenu === "favorite" ? "还没有收藏的歌曲" : "还没有历史记录")
                            font.family: appFont.name
                            font.pixelSize: 16
                            color: "#666"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }
    }

    // 右上角窗口控制按钮（覆盖在内容区上方）
    RowLayout {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 6
        anchors.rightMargin: 6
        spacing: 6

        Rectangle {
            width: 36; height: 36; radius: 6
            color: btnMinimize.containsMouse ? "#3a3a55" : "transparent"
            Label {
                anchors.centerIn: parent
                text: "─"; font.family: appFont.name; font.pixelSize: 17; color: "#999"
            }
            MouseArea {
                id: btnMinimize
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: mainWindow.visibility = Window.Minimized
            }
        }

        Rectangle {
            width: 36; height: 36; radius: 6
            color: btnMaximize.containsMouse ? "#3a3a55" : "transparent"
            Label {
                anchors.centerIn: parent
                text: isMaximized ? "❐" : "□"
                font.family: appFont.name; font.pixelSize: 17; color: "#999"
            }
            MouseArea {
                id: btnMaximize
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: toggleMaximize()
            }
        }

        Rectangle {
            width: 36; height: 36; radius: 6
            color: btnClose.containsMouse ? "#e94560" : "transparent"
            Label {
                anchors.centerIn: parent
                text: "✕"; font.family: appFont.name; font.pixelSize: 17
                color: btnClose.containsMouse ? "white" : "#999"
            }
            MouseArea {
                id: btnClose
                anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.quit()
            }
        }
    }

    // 底部播放栏
    Rectangle {
        id: playerBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: playerBarHeight
        color: "#222236"
        border.color: "#353550"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 20

            RowLayout {
                Layout.preferredWidth: 240
                spacing: 12

                Rectangle {
                    width: 48; height: 48; radius: 6; color: "#3a3a55"
                    Label {
                        anchors.centerIn: parent
                        text: "♫"; font.family: appFont.name; font.pixelSize: 22; color: "#999"
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Label { text: "未在播放"; font.family: appFont.name; font.pixelSize: 14; font.bold: true; color: "#cccccc" }
                    Label { text: "选择一首歌曲开始"; font.family: appFont.name; font.pixelSize: 12; color: "#777" }
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                spacing: 28

                Label {
                    text: "⏮"; font.pixelSize: 20; color: "#aaa"
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: console.log("Previous")
                    }
                }

                Rectangle {
                    width: 42; height: 42; radius: 21; color: "#444466"
                    Label {
                        anchors.centerIn: parent
                        text: "▶"; font.pixelSize: 18; color: "#dddddd"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: console.log("Play/Pause")
                    }
                }

                Label {
                    text: "⏭"; font.pixelSize: 20; color: "#aaa"
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: console.log("Next")
                    }
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                Layout.preferredWidth: 140; spacing: 8
                Label { text: "🔊"; font.pixelSize: 17 }
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 4; radius: 2; color: "#3a3a55"
                    Rectangle {
                        width: parent.width * 0.7; height: parent.height; radius: 2; color: "#888"
                    }
                }
            }
        }
    }

    function toggleMaximize() {
        if (isMaximized) {
            mainWindow.x = lastGeo.x
            mainWindow.y = lastGeo.y
            mainWindow.width = lastGeo.w
            mainWindow.height = lastGeo.h
            mainWindow.visibility = Window.Windowed
            isMaximized = false
        } else {
            lastGeo = { x: mainWindow.x, y: mainWindow.y, w: mainWindow.width, h: mainWindow.height }
            mainWindow.visibility = Window.Maximized
            isMaximized = true
        }
    }

    component NavItem: Rectangle {
        property string iconSource: ""
        property string iconColor: ""
        property string label
        property int iconW: 34
        property int iconH: 34
        property int iconSrcSize: 26
        property bool active: false
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredHeight: 50
        radius: 6
        color: active ? "#36365a" : (navMouse.containsMouse ? "#2a2a48" : "transparent")

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 24
            spacing: 10

            Rectangle {
                width: iconW; height: iconH; radius: 4; color: "transparent"

                Image {
                    anchors.centerIn: parent
                    source: iconSource
                    sourceSize.width: iconSrcSize
                    sourceSize.height: iconSrcSize
                    fillMode: Image.PreserveAspectFit
                    visible: iconSource !== ""
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: 12; height: 12; radius: 6
                    color: iconColor
                    visible: iconSource === "" && iconColor !== ""
                }
            }

            Label {
                text: label
                font.family: appFont.name
                font.pixelSize: 17
                color: active ? "#cccccc" : "#888"
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        MouseArea {
            id: navMouse
            anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
