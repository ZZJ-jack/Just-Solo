import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs

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
    property string settingsSubMenu: "appearance"

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
                anchors.margins: 10
                spacing: 0

                // 顶部区域（logo + 标题）
                Rectangle {
                    Layout.preferredWidth: sidebarWidth
                    Layout.preferredHeight: 60
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        spacing: 12

                        Image {
                            source: "qrc:/qt/qml/JustSolo/data/image/logo2.png"
                            sourceSize.width: 42
                            sourceSize.height: 42
                            fillMode: Image.PreserveAspectFit
                        }

                        Column {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            Label {
                                text: "Just Solo"
                                font.family: appFont.name
                                font.pixelSize: 28
                                font.bold: true
                                color: "#cccccc"
                            }

                            Label {
                                text: APP_VERSION
                                font.family: appFont.name
                                font.pixelSize: 11
                                color: "#555"
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: "#3a3a55"
                }

                Item { Layout.preferredHeight: 14 }

                // 设置按钮（列表上方）
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 6
                    color: currentMenu === "settings" ? "#36365a" : (settingsTopMouse.containsMouse ? "#2a2a48" : "transparent")

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        spacing: 10

                        Rectangle {
                            width: 34; height: 34; radius: 4; color: "transparent"
                            Label {
                                anchors.centerIn: parent
                                text: "⚙"; font.family: appFont.name; font.pixelSize: 22; color: "#888"
                            }
                        }

                        Label {
                            text: "设置"
                            font.family: appFont.name
                            font.pixelSize: 17
                            color: currentMenu === "settings" ? "#cccccc" : "#888"
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    MouseArea {
                        id: settingsTopMouse
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: currentMenu = "settings"
                    }
                }

                Item { Layout.preferredHeight: 4 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: "#3a3a55"
                }

                Item { Layout.preferredHeight: 14 }

                // 主列表（非设置页显示）
                ColumnLayout {
                    spacing: 2
                    visible: currentMenu !== "settings"

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

                // 设置子菜单（设置页显示）
                ColumnLayout {
                    spacing: 2
                    visible: currentMenu === "settings"

                    SubNavItem {
                        label: "外观"
                        active: settingsSubMenu === "appearance"
                        onClicked: settingsSubMenu = "appearance"
                    }
                    SubNavItem {
                        label: "软件更新"
                        active: settingsSubMenu === "update"
                        onClicked: settingsSubMenu = "update"
                    }
                    SubNavItem {
                        label: "关于"
                        active: settingsSubMenu === "about"
                        onClicked: settingsSubMenu = "about"
                    }

                    Item { Layout.preferredHeight: 8 }

                    // 退出设置按钮
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 6
                        color: exitSettingsMouse.containsMouse ? "#3e2e3e" : "transparent"

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Label {
                                text: "←"
                                font.family: appFont.name
                                font.pixelSize: 14
                                color: "#888"
                            }
                            Label {
                                text: "退出设置"
                                font.family: appFont.name
                                font.pixelSize: 13
                                color: "#888"
                            }
                        }

                        MouseArea {
                            id: exitSettingsMouse
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: currentMenu = "home"
                        }
                    }
                }

                Item { Layout.fillHeight: true }
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

                // 搜索框
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    visible: currentMenu !== "settings"

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

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Item {
                        width: 30; height: 30
                        Image {
                            anchors.centerIn: parent
                            source: currentMenu === "home" ? "qrc:/qt/qml/JustSolo/data/image/home.png"
                                   : (currentMenu === "favorite" ? "qrc:/qt/qml/JustSolo/data/image/mylike.png"
                                   : (currentMenu === "history" ? "qrc:/qt/qml/JustSolo/data/image/history.png"
                                   : ""))
                            sourceSize.width: 28
                            sourceSize.height: 28
                            fillMode: Image.PreserveAspectFit
                            visible: currentMenu !== "settings"
                        }

                        Rectangle {
                            width: 30; height: 30; radius: 6; color: "transparent"
                            visible: currentMenu === "settings"
                            Label {
                                anchors.centerIn: parent
                                text: "⚙"; font.family: appFont.name; font.pixelSize: 22; color: "#888"
                            }
                        }
                    }

                    Label {
                        text: currentMenu === "home" ? "首页"
                              : (currentMenu === "favorite" ? "收藏"
                              : (currentMenu === "history" ? "历史"
                              : (settingsSubMenu === "update" ? "软件更新"
                              : (settingsSubMenu === "appearance" ? "外观" : "关于"))))
                        font.family: appFont.name
                        font.pixelSize: 24
                        font.bold: true
                        color: "#dddddd"
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    // 添加音乐按钮（仅首页显示）
                    Rectangle {
                        Layout.preferredWidth: 140
                        Layout.preferredHeight: 36
                        radius: 6
                        color: addMusicBtn.containsMouse ? "#4a4a6a" : "#3a3a5a"
                        visible: currentMenu === "home"
                        Label {
                            anchors.centerIn: parent
                            text: "+ 添加音乐"
                            font.family: appFont.name
                            font.pixelSize: 13
                            color: "#cccccc"
                        }
                        MouseArea {
                            id: addMusicBtn
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: fileDialog.open()
                        }
                    }
                }

                Item { Layout.preferredHeight: 16 }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: "transparent"
                    visible: currentMenu === "settings"

                    // 设置页内容
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0
                        visible: currentMenu === "settings" && settingsSubMenu === "update"

                        Label {
                            text: "软件更新"
                            font.family: appFont.name
                            font.pixelSize: 18
                            font.bold: true
                            color: "#dddddd"
                        }

                        Item { Layout.preferredHeight: 24 }

                        // 软件版本 + 构建版本卡片
                        Rectangle {
                            Layout.preferredWidth: 480
                            Layout.preferredHeight: 80
                            radius: 8
                            color: "#2e2e4a"
                            border.color: "#3a3a55"

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 20
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: "软件版本"
                                        font.family: appFont.name
                                        font.pixelSize: 14
                                        color: "#888"
                                        Layout.preferredWidth: 72
                                    }
                                    Item { Layout.fillWidth: true }
                                    Label {
                                        text: APP_VERSION
                                        font.family: appFont.name
                                        font.pixelSize: 14
                                        font.bold: true
                                        color: "#cccccc"
                                    }
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: "构建版本"
                                        font.family: appFont.name
                                        font.pixelSize: 13
                                        color: "#666"
                                        Layout.preferredWidth: 72
                                    }
                                    Item { Layout.fillWidth: true }
                                    Label {
                                        text: BUILD_VERSION
                                        font.family: appFont.name
                                        font.pixelSize: 13
                                        color: "#888"
                                    }
                                }
                            }
                        }

                        Item { Layout.preferredHeight: 16 }

                        // 检查更新按钮（暂禁用）
                        Rectangle {
                            Layout.preferredWidth: 160
                            Layout.preferredHeight: 40
                            radius: 8
                            color: "#2a2a3a"
                            opacity: 0.5

                            Label {
                                anchors.centerIn: parent
                                text: "检查更新"
                                font.family: appFont.name
                                font.pixelSize: 14
                                color: "#666"
                            }
                        }

                        // 更新链接
                        Label {
                            text: "请前往以下地址查看更新："
                            font.family: appFont.name; font.pixelSize: 13; color: "#888"
                            Layout.topMargin: 8
                        }

                        Label {
                            text: `<a href="https://gitcode.com/ZZJ-JACK/Just-Solo">https://gitcode.com/ZZJ-JACK/Just-Solo</a>`
                            textFormat: Text.RichText
                            font.family: appFont.name; font.pixelSize: 13
                            color: "#00d4ff"
                            Layout.topMargin: 4
                            onLinkActivated: Qt.openUrlExternally(link)
                        }

                        Label {
                            text: `<a href="https://github.com/ZZJ-jack/Just-Solo">https://github.com/ZZJ-jack/Just-Solo</a>`
                            textFormat: Text.RichText
                            font.family: appFont.name; font.pixelSize: 13
                            color: "#00d4ff"
                            Layout.topMargin: 2
                            onLinkActivated: Qt.openUrlExternally(link)
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // 外观设置页
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0
                        visible: currentMenu === "settings" && settingsSubMenu === "appearance"

                        Label {
                            text: "外观"
                            font.family: appFont.name
                            font.pixelSize: 18
                            font.bold: true
                            color: "#dddddd"
                        }

                        Item { Layout.preferredHeight: 16 }

                        Label {
                            text: "外观设置（开发中）"
                            font.family: appFont.name
                            font.pixelSize: 14
                            color: "#666"
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // 关于页
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0
                        visible: currentMenu === "settings" && settingsSubMenu === "about"

                        Label {
                            text: "关于"
                            font.family: appFont.name
                            font.pixelSize: 18
                            font.bold: true
                            color: "#dddddd"
                        }

                        Item { Layout.preferredHeight: 16 }

                        Label {
                            text: "Just Solo - 轻量级桌面音乐播放器"
                            font.family: appFont.name
                            font.pixelSize: 14
                            color: "#888"
                        }

                        Item { Layout.preferredHeight: 4 }

                        Label {
                            text: "作者: ZZJ-JACK"
                            font.family: appFont.name
                            font.pixelSize: 13
                            color: "#666"
                        }

                        Label {
                            text: `<a href="https://zzjjack.us.kg">https://zzjjack.us.kg</a>`
                            textFormat: Text.RichText
                            font.family: appFont.name; font.pixelSize: 13
                            color: "#00d4ff"
                            Layout.topMargin: 4
                            onLinkActivated: Qt.openUrlExternally(link)
                        }

                        Item { Layout.preferredHeight: 8 }

                        Label {
                            text: "基于 Qt 6.8.3 + QML 构建"
                            font.family: appFont.name
                            font.pixelSize: 13
                            color: "#666"
                        }

                        Item { Layout.preferredHeight: 8 }

                        Label {
                            text: "构建版本: " + BUILD_VERSION
                            font.family: appFont.name
                            font.pixelSize: 13
                            color: "#666"
                        }

                        Item { Layout.preferredHeight: 12 }

                        Label {
                            text: "项目地址"
                            font.family: appFont.name
                            font.pixelSize: 13
                            color: "#888"
                        }

                        Label {
                            text: `<a href="https://gitcode.com/ZZJ-JACK/Just-Solo">https://gitcode.com/ZZJ-JACK/Just-Solo</a>`
                            textFormat: Text.RichText
                            font.family: appFont.name; font.pixelSize: 13
                            color: "#00d4ff"
                            Layout.topMargin: 4
                            onLinkActivated: Qt.openUrlExternally(link)
                        }

                        Label {
                            text: `<a href="https://github.com/ZZJ-jack/Just-Solo">https://github.com/ZZJ-jack/Just-Solo</a>`
                            textFormat: Text.RichText
                            font.family: appFont.name; font.pixelSize: 13
                            color: "#00d4ff"
                            Layout.topMargin: 2
                            onLinkActivated: Qt.openUrlExternally(link)
                        }

                        Item { Layout.preferredHeight: 12 }

                        Label {
                            text: "图标来源: 鸿蒙开发者"
                            font.family: appFont.name
                            font.pixelSize: 13
                            color: "#888"
                        }

                        Label {
                            text: `<a href="https://developer.huawei.com/consumer/cn/">https://developer.huawei.com/consumer/cn</a>`
                            textFormat: Text.RichText
                            font.family: appFont.name; font.pixelSize: 13
                            color: "#00d4ff"
                            Layout.topMargin: 4
                            onLinkActivated: Qt.openUrlExternally(link)
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                    // 非设置页的音乐列表/空状态
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "transparent"
                        clip: true
                        visible: currentMenu !== "settings"

                        // 首页音乐列表
                        ColumnLayout {
                            id: musicListLayout
                            anchors.fill: parent
                            spacing: 0
                            visible: currentMenu === "home"

                            // ---- 共享列宽：改这里，标题栏和歌行自动对齐 ----
                            property int colCover: 40
                            property int colTitle: 120
                            property int colArtist: 110
                            property int colAlbum: 120
                            property int colDuration: 20
                            property int colPlay: 50
                            property int colPlayIconSize: 20  // 播放按钮图标大小
                            property int colSpacing: 5        // 列间距

                            // 列表标题栏
                            Rectangle {
                                Layout.fillWidth: true
                                height: 32
                                color: "transparent"
                                visible: musicManager.playlist.length > 0

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: musicListLayout.colSpacing

                                    Item { Layout.preferredWidth: musicListLayout.colCover }

                                    Label {
                                        text: "标题"; font.family: appFont.name; font.pixelSize: 14; color: "#888"
                                        Layout.fillWidth: true; Layout.preferredWidth: musicListLayout.colTitle
                                    }
                                    Label {
                                        text: "歌手"; font.family: appFont.name; font.pixelSize: 14; color: "#888"
                                        Layout.fillWidth: true; Layout.preferredWidth: musicListLayout.colArtist
                                    }
                                    Label {
                                        text: "专辑"; font.family: appFont.name; font.pixelSize: 14; color: "#888"
                                        Layout.fillWidth: true; Layout.preferredWidth: musicListLayout.colAlbum
                                    }
                                    Label {
                                        text: "时长"; font.family: appFont.name; font.pixelSize: 14; color: "#888"
                                        Layout.preferredWidth: musicListLayout.colDuration
                                    }
                                    Item { Layout.preferredWidth: musicListLayout.colPlay }
                                }
                            }

                            // 分割线
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: "#2a2a48"
                                visible: musicManager.playlist.length > 0
                            }

                            // 音乐列表
                            ListView {
                                id: musicListView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 8
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                visible: musicManager.playlist.length > 0

                                // 自定义滚动条
                                ScrollBar.vertical: ScrollBar {
                                    id: listScrollBar
                                    policy: ScrollBar.AsNeeded
                                    width: 10
                                    hoverEnabled: false
                                    palette.mid: "#555577"
                                    palette.dark: "#2a2a3a"
                                    palette.button: "#555577"
                                    palette.window: "#2a2a3a"
                                    palette.base: "#2a2a3a"
                                    palette.text: "#555577"
                                    palette.buttonText: "#555577"
                                    palette.brightText: "#555577"
                                    palette.light: "#555577"
                                    palette.shadow: "#2a2a3a"
                                    palette.highlight: "#555577"
                                    palette.highlightedText: "#555577"
                                    palette.windowText: "#555577"
                                    palette.accent: "#555577"
                                    palette.alternateBase: "#2a2a3a"
                                    background: Rectangle {
                                        implicitWidth: 10; radius: 5
                                        color: listScrollBar.palette.dark
                                    }
                                    contentItem: Item {
                                        implicitWidth: 10
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: 5
                                            color: "#555577"
                                        }
                                    }
                                }

                                model: musicManager.playlist

                                delegate: Rectangle {
                                    width: musicListView.width
                                    height: 60
                                    radius: 8
                                    color: musicManager.currentIndex === index ? "#36365a" : (musicItemMouse.containsMouse ? "#2a2a48" : "#222236")

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 10
                                        spacing: musicListLayout.colSpacing

                                        // 封面
                                        Rectangle {
                                            Layout.preferredWidth: musicListLayout.colCover; Layout.preferredHeight: 40
                                            radius: 6; color: "#3a3a55"
                                            Image {
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                source: modelData.cover ? modelData.cover : ""
                                                fillMode: Image.PreserveAspectCrop
                                                visible: modelData.cover && modelData.cover !== ""
                                                asynchronous: true
                                            }
                                            Label {
                                                anchors.centerIn: parent
                                                text: "\u266B"; font.family: appFont.name; font.pixelSize: 18; color: "#666"
                                                visible: !modelData.cover || modelData.cover === ""
                                            }
                                        }

                                        // 标题
                                        Label {
                                            text: modelData.name || ""
                                            font.family: appFont.name; font.pixelSize: 14
                                            font.bold: true; color: "#cccccc"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true; Layout.preferredWidth: musicListLayout.colTitle
                                        }

                                        // 歌手
                                        Label {
                                            text: modelData.artist || "未知"
                                            font.family: appFont.name; font.pixelSize: 14; color: "#888"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true; Layout.preferredWidth: musicListLayout.colArtist
                                        }

                                        // 专辑
                                        Label {
                                            text: modelData.album || ""
                                            font.family: appFont.name; font.pixelSize: 14; color: "#777"
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true; Layout.preferredWidth: musicListLayout.colAlbum
                                        }

                                        // 时长
                                        Label {
                                            text: {
                                                if (modelData.duration > 0) {
                                                    var m = Math.floor(modelData.duration / 60)
                                                    var s = Math.floor(modelData.duration % 60)
                                                    return m + ":" + (s < 10 ? "0" : "") + s
                                                }
                                                return ""
                                            }
                                            font.family: appFont.name; font.pixelSize: 14; color: "#888"
                                            Layout.preferredWidth: musicListLayout.colDuration
                                        }

                                        // 播放状态
                                        Item {
                                            Layout.preferredWidth: musicListLayout.colPlay
                                            Layout.preferredHeight: musicListLayout.colPlayIconSize
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

                                    MouseArea {
                                        id: musicItemMouse
                                        anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (musicManager.currentIndex === index) {
                                                if (musicManager.isPlaying) musicManager.pause()
                                                else musicManager.play()
                                            } else {
                                                musicManager.playIndex(index)
                                            }
                                        }
                                    }
                                }

                                Component.onCompleted: {
                                    musicManager.playlistChanged.connect(function() { musicListView.model = musicManager.playlist })
                                }
                            }

                            // 空状态
                            Column {
                                Layout.alignment: Qt.AlignCenter
                                spacing: 14
                                visible: musicManager.playlist.length === 0

                                Label {
                                    text: "还没有音乐"
                                    font.family: appFont.name
                                    font.pixelSize: 16
                                    color: "#666"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Label {
                                    text: "点击上方「添加音乐」导入本地文件"
                                    font.family: appFont.name
                                    font.pixelSize: 13
                                    color: "#555"
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }

                        // 收藏页
                        Column {
                            anchors.centerIn: parent
                            spacing: 14
                            visible: currentMenu === "favorite"

                            Label {
                                text: "还没有收藏的歌曲"
                                font.family: appFont.name
                                font.pixelSize: 16
                                color: "#666"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        // 历史页
                        Column {
                            anchors.centerIn: parent
                            spacing: 14
                            visible: currentMenu === "history"

                            Label {
                                text: "还没有历史记录"
                                font.family: appFont.name
                                font.pixelSize: 16
                                color: "#666"
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }

                    // 文件选择对话框
                    FileDialog {
                        id: fileDialog
                        title: "选择音乐文件"
                        modality: Window.Windowed
                        fileMode: FileDialog.OpenFiles
                        nameFilters: ["音频文件 (*.mp3 *.flac *.wav *.ogg *.aac *.m4a *.wma *.opus)"]
                        onAccepted: {
                            var paths = []
                            for (var i = 0; i < fileDialog.selectedFiles.length; i++) {
                                paths.push(fileDialog.selectedFiles[i].toString().replace("file:///", ""))
                            }
                            musicManager.addFiles(paths)
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

    // 顶部全宽拖拽区域（logo 块底部高度以上可拖动窗口）
    MouseArea {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 70
        z: -1

        property point lastPos
        onPressed: function(mouse) { lastPos = Qt.point(mouse.x, mouse.y) }
        onPositionChanged: function(mouse) {
            if (pressed) {
                mainWindow.x += mouse.x - lastPos.x
                mainWindow.y += mouse.y - lastPos.y
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

        // 阻止点击穿透到后面的歌曲列表
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        property double progressFraction: musicManager.duration > 0 ? musicManager.position / Math.max(1, musicManager.duration) : 0
        property int currentSeconds: Math.floor(musicManager.position / 1000)
        property int totalSeconds: Math.floor(musicManager.duration / 1000)

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
                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: musicManager.currentCover || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: musicManager.currentCover !== ""
                    }
                    Label {
                        anchors.centerIn: parent
                        text: "♫"; font.family: appFont.name; font.pixelSize: 22; color: "#666"
                        visible: musicManager.currentCover === ""
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Label {
                        text: musicManager.currentTitle ? musicManager.currentTitle : "未在播放"
                        font.family: appFont.name
                        font.pixelSize: 14
                        font.bold: true
                        color: musicManager.currentTitle ? "#cccccc" : "#777"
                        elide: Text.ElideRight
                        Layout.maximumWidth: 160
                    }
                    Label {
                        text: musicManager.currentArtist ? musicManager.currentArtist : "选择一首歌曲开始"
                        font.family: appFont.name
                        font.pixelSize: 12
                        color: "#777"
                        elide: Text.ElideRight
                        Layout.maximumWidth: 160
                    }
                }
            }

            Item { Layout.fillWidth: true }

            RowLayout {
                spacing: 24

                // 上一首
                Item {
                    Layout.preferredWidth: 22; Layout.preferredHeight: 22
                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                        width: 22; height: 22
                        opacity: 0.5
                        rotation: 180
                    }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: musicManager.previous()
                    }
                }

                // 播放/暂停
                Rectangle {
                    width: 42; height: 42; radius: 21; color: "#444466"
                    Image {
                        source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                        width: 22; height: 22
                        anchors.centerIn: parent
                        visible: !musicManager.isPlaying
                    }
                    Image {
                        source: "qrc:/qt/qml/JustSolo/data/image/playing.png"
                        width: 22; height: 22
                        anchors.centerIn: parent
                        visible: musicManager.isPlaying
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (musicManager.currentIndex >= 0) {
                                if (musicManager.isPlaying) musicManager.pause()
                                else musicManager.play()
                            }
                        }
                    }
                }

                // 下一首
                Item {
                    Layout.preferredWidth: 22; Layout.preferredHeight: 22
                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                        width: 22; height: 22
                        opacity: 0.5
                    }
                    MouseArea {
                        anchors.fill: parent; anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: musicManager.next()
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // 播放进度
            RowLayout {
                Layout.preferredWidth: 220
                spacing: 8

                // 当前播放时长
                Label {
                    text: {
                        var m = Math.floor(playerBar.currentSeconds / 60)
                        var s = Math.floor(playerBar.currentSeconds % 60)
                        return m + ":" + (s < 10 ? "0" : "") + s
                    }
                    font.family: appFont.name; font.pixelSize: 12; color: "#888"
                    Layout.preferredWidth: 35
                }

                // 进度条
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 4; radius: 2; color: "#3a3a55"
                    Rectangle {
                        width: parent.width * Math.min(1, playerBar.progressFraction)
                        height: parent.height; radius: 2; color: "#00d4ff"
                    }
                }

                // 总时长
                Label {
                    text: {
                        var m = Math.floor(playerBar.totalSeconds / 60)
                        var s = Math.floor(playerBar.totalSeconds % 60)
                        return m + ":" + (s < 10 ? "0" : "") + s
                    }
                    font.family: appFont.name; font.pixelSize: 12; color: "#888"
                    Layout.preferredWidth: 35
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
            anchors.leftMargin: 12
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

    component SubNavItem: Rectangle {
        property string label
        property bool active: false
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredHeight: 40
        radius: 6
        color: active ? "#36365a" : (subNavMouse.containsMouse ? "#2a2a48" : "transparent")

        Label {
            text: label
            font.family: appFont.name
            font.pixelSize: 14
            color: active ? "#cccccc" : "#888"
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 20
        }

        MouseArea {
            id: subNavMouse
            anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
