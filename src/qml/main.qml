// ============================================================
// Just Solo - 轻量级桌面音乐播放器主界面
// 技术栈: Qt 6.8.3 + QML + QtQuick Layouts
// 设计要点:
//   - 全自适应的响应式布局，所有尺寸随窗口大小弹性变化
//   - 无边框窗口 (FramelessWindowHint)，自定义标题栏按钮
//   - 支持 Home / 收藏 / 历史 / 设置 四个视图切换
//   - 页面按需加载，切换时销毁旧页面释放内存
// ============================================================

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs

// ============================================================
// 主窗口
// ============================================================
Window {
    id: mainWindow

    // ---- 初始尺寸 ----
    width: 1200
    height: 800
    minimumWidth: 900
    minimumHeight: 600
    visible: true
    title: "Just Solo"
    color: "#1e1e2e"

    flags: Qt.FramelessWindowHint | Qt.Window

    // ---- 窗口状态 ----
    property bool isMaximized: false
    property var lastGeo: ({ x: 100, y: 100, w: 1200, h: 800 })

    // ---- 布局常量 ----
    readonly property int sidebarWidth: 230
    readonly property int playerBarHeight: 72

    // ---- 视图路由 ----
    property string currentMenu: ""              // 空串 = 未选择，不加载页面
    property string settingsSubMenu: "appearance"

    // ============================================================
    // 字体加载
    // ============================================================
    FontLoader {
        id: appFont
        source: "qrc:/qt/qml/JustSolo/data/font/HarmonyOS_Sans_SC_Regular.ttf"
    }

    // ============================================================
    // 主体布局：侧边栏 | 内容区
    // ============================================================
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ----------------------------------------------------------
        // 左侧 侧边栏 (230px 固定宽)
        // ----------------------------------------------------------
        Rectangle {
            Layout.preferredWidth: sidebarWidth
            Layout.fillHeight: true
            color: "#222236"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 0

                // ---- Logo + 标题 ----
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

                // ---- 分割线 ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: "#3a3a55"
                }

                Item { Layout.preferredHeight: 14 }

                // ---- 设置按钮 ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 42
                    radius: 6
                    color: currentMenu === "settings" ? "#36365a"
                         : (settingsTopMouse.containsMouse ? "#2a2a48" : "transparent")

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

                // ---- 分割线 ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: "#3a3a55"
                }

                Item { Layout.preferredHeight: 14 }

                // ---- 主导航（非设置页可见） ----
                ColumnLayout {
                    spacing: 2
                    visible: currentMenu !== "settings"

                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/home.png"
                        label: "首页"
                        iconW: 34; iconH: 34; iconSrcSize: 26
                        active: currentMenu === "home"
                        fontFamily: appFont.name
                        onClicked: currentMenu = "home"
                    }
                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/mylike.png"
                        label: "收藏"
                        iconW: 34; iconH: 34; iconSrcSize: 32
                        active: currentMenu === "favorite"
                        fontFamily: appFont.name
                        onClicked: currentMenu = "favorite"
                    }
                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/history.png"
                        label: "历史"
                        iconW: 34; iconH: 34; iconSrcSize: 32
                        active: currentMenu === "history"
                        fontFamily: appFont.name
                        onClicked: currentMenu = "history"
                    }
                }

                // ---- 设置子导航（设置页可见） ----
                ColumnLayout {
                    spacing: 2
                    visible: currentMenu === "settings"

                    SubNavItem {
                        label: "外观"
                        active: settingsSubMenu === "appearance"
                        fontFamily: appFont.name
                        onClicked: settingsSubMenu = "appearance"
                    }
                    SubNavItem {
                        label: "软件更新"
                        active: settingsSubMenu === "update"
                        fontFamily: appFont.name
                        onClicked: settingsSubMenu = "update"
                    }
                    SubNavItem {
                        label: "关于"
                        active: settingsSubMenu === "about"
                        fontFamily: appFont.name
                        onClicked: settingsSubMenu = "about"
                    }

                    Item { Layout.preferredHeight: 8 }

                    // ---- 退出设置 ----
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

                // ---- 弹性撑满 ----
                Item { Layout.fillHeight: true }
            }
        }

        // ----------------------------------------------------------
        // 右侧 内容区（自适应填充剩余宽度）
        // ----------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#282844"

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: 14
                anchors.bottomMargin: playerBarHeight + 14
                anchors.leftMargin: 30
                anchors.rightMargin: 30
                spacing: 0

                // -------- 搜索框行（仅首页/收藏/历史可见） --------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    visible: currentMenu !== "settings"

                    Rectangle {
                        Layout.preferredWidth: Math.min(mainWindow.width * 0.35, 420)
                        Layout.minimumWidth: 200
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

                // -------- 页面标题行 --------
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
                        text: currentMenu === "" ? "欢迎使用 Just Solo"
                              : currentMenu === "home" ? "首页"
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

                    // ---- 添加音乐按钮（仅首页） ----
                    Rectangle {
                        Layout.preferredWidth: 140
                        Layout.preferredHeight: 36
                        radius: 6
                        color: addMusicBtn.containsMouse ? "#4a4a6a" : "#3a3a5a"
                        Behavior on color { ColorAnimation { duration: 120 } }
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

                // ==================================================
                // 页面内容区（按需加载，切换时销毁旧页面释放内存）
                // ==================================================
                Loader {
                    id: pageLoader
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    asynchronous: true
                    sourceComponent: {
                        switch (mainWindow.currentMenu) {
                            case "settings": return settingsPageComp
                            case "home": return homePageComp
                            case "favorite": return favoritePageComp
                            case "history": return historyPageComp
                            default: return null
                        }
                    }
                }
            }

            // ==================================================
            // 导入加载覆盖层（按需创建，导入完毕自动销毁释放内存）
            // ==================================================
            Loader {
                id: importOverlay
                anchors.fill: parent
                z: 10
                active: musicManager.isLoading
                sourceComponent: importOverlayComp
            }

            // --------------------------------------------------
            // 文件选择对话框
            // --------------------------------------------------
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

    // ============================================================
    // 页面组件包装器 —— 注入外部依赖属性后交给 Loader 实例化
    // ============================================================

    Component {
        id: settingsPageComp
        SettingsPage {
            settingsSubMenu: mainWindow.settingsSubMenu
            fontFamily: appFont.name
        }
    }

    Component {
        id: homePageComp
        HomePage {
            sidebarWidth: mainWindow.sidebarWidth
            windowWidth: mainWindow.width
            fontFamily: appFont.name
        }
    }

    Component {
        id: favoritePageComp
        FavoritePage {
            sidebarWidth: mainWindow.sidebarWidth
            windowWidth: mainWindow.width
            fontFamily: appFont.name
        }
    }

    Component {
        id: historyPageComp
        HistoryPage {
            sidebarWidth: mainWindow.sidebarWidth
            windowWidth: mainWindow.width
            fontFamily: appFont.name
        }
    }

    // ---- 导入加载覆盖层组件（导入完毕 Loader 失活时自动销毁） ----
    Component {
        id: importOverlayComp
        Rectangle {
            anchors.fill: parent
            color: "#1e1e2e"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 20

                Label {
                    text: {
                        var total = musicManager.importTotal
                        var done = musicManager.importProcessed
                        if (total > 0)
                            return "正在导入音乐...  " + done + " / " + total
                        return "正在导入音乐..."
                    }
                    font.family: appFont.name
                    font.pixelSize: 16
                    color: "#aaaaaa"
                    Layout.alignment: Qt.AlignHCenter
                }

                Rectangle {
                    width: 320; height: 6; radius: 3; color: "#333350"
                    Layout.alignment: Qt.AlignHCenter
                    Rectangle {
                        height: parent.height; radius: 3; color: "#00d4ff"
                        width: parent.width * musicManager.importProgress
                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                }

                Label {
                    text: Math.round(musicManager.importProgress * 100) + "%"
                    font.family: appFont.name
                    font.pixelSize: 13
                    color: "#666"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    // ============================================================
    // 右上角：窗口控制按钮（最小化 / 最大化 / 关闭）
    // ============================================================
    RowLayout {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 6
        anchors.rightMargin: 6
        spacing: 6

        // 最小化
        Rectangle {
            width: 36; height: 36; radius: 6
            color: btnMinimize.containsMouse ? "#3a3a55" : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
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

        // 最大化 / 还原
        Rectangle {
            width: 36; height: 36; radius: 6
            color: btnMaximize.containsMouse ? "#3a3a55" : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
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

        // 关闭
        Rectangle {
            width: 36; height: 36; radius: 6
            color: btnClose.containsMouse ? "#e94560" : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
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

    // ============================================================
    // 顶部拖拽区域
    // ============================================================
    MouseArea {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 70
        z: -1

        property point lastPos
        onPressed: function(mouse) {
            if (isMaximized) {
                var ratioX = mouse.x / mainWindow.width
                var ratioY = mouse.y / mainWindow.height
                toggleMaximize()
                mainWindow.x = mouse.screenX - ratioX * mainWindow.width
                mainWindow.y = mouse.screenY - ratioY * mainWindow.height
                lastPos = Qt.point(ratioX * mainWindow.width, ratioY * mainWindow.height)
                return
            }
            lastPos = Qt.point(mouse.x, mouse.y)
        }
        onPositionChanged: function(mouse) {
            if (pressed) {
                mainWindow.x += mouse.x - lastPos.x
                mainWindow.y += mouse.y - lastPos.y
            }
        }
    }

    // ============================================================
    // 底部播放控制栏
    // ============================================================
    Rectangle {
        id: playerBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: playerBarHeight
        color: "#222236"
        border.color: "#353550"
        border.width: 1

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

            // ---- 左侧：封面 + 歌名/歌手 ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    width: 48; height: 48; radius: 6; color: "#3a3a55"
                    Image {
                        anchors.fill: parent
                        anchors.margins: 2
                        source: musicManager.currentCover || ""
                        sourceSize.width: 40
                        sourceSize.height: 40
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: musicManager.currentCover !== ""
                        opacity: 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        onStatusChanged: {
                            if (status === Image.Ready) opacity = 1
                            else if (status === Image.Null || status === Image.Error) opacity = 0
                        }
                    }
                    Label {
                        anchors.centerIn: parent
                        text: "♫"; font.family: appFont.name; font.pixelSize: 22; color: "#666"
                        visible: musicManager.currentCover === ""
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        text: musicManager.currentTitle ? musicManager.currentTitle : "未在播放"
                        font.family: appFont.name
                        font.pixelSize: 14
                        font.bold: true
                        color: musicManager.currentTitle ? "#cccccc" : "#777"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                    Label {
                        text: musicManager.currentArtist ? musicManager.currentArtist : "选择一首歌曲开始"
                        font.family: appFont.name
                        font.pixelSize: 12
                        color: "#777"
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // ---- 中间：播放控制按钮 ----
            RowLayout {
                spacing: 24

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

                Rectangle {
                    width: 42; height: 42; radius: 21; color: "#444466"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Image {
                        source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                        width: 22; height: 22
                        anchors.centerIn: parent
                        opacity: musicManager.isPlaying ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                    Image {
                        source: "qrc:/qt/qml/JustSolo/data/image/playing.png"
                        width: 22; height: 22
                        anchors.centerIn: parent
                        opacity: musicManager.isPlaying ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
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

            // ---- 右侧：播放进度 ----
            Item { Layout.fillWidth: true }

            RowLayout {
                Layout.preferredWidth: Math.max(180, Math.min((mainWindow.width - sidebarWidth - 80) * 0.25, 300))
                spacing: 8

                Label {
                    text: {
                        var m = Math.floor(playerBar.currentSeconds / 60)
                        var s = Math.floor(playerBar.currentSeconds % 60)
                        return m + ":" + (s < 10 ? "0" : "") + s
                    }
                    font.family: appFont.name; font.pixelSize: 12; color: "#888"
                    Layout.preferredWidth: 35
                }

                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 4; radius: 2; color: "#3a3a55"
                    Rectangle {
                        id: progressFill
                        width: parent.width * Math.min(1, playerBar.progressFraction)
                        height: parent.height; radius: 2; color: "#00d4ff"
                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }
                }

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

    // ============================================================
    // 窗口最大化 / 还原切换
    // ============================================================
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
}
