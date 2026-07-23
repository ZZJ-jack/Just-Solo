// ============================================================
// Just Solo - 轻量级桌面音乐播放器主界面
// 技术栈: Qt 6.8.3 + QML + QtQuick Layouts
// 设计要点:
//   - 全自适应的响应式布局，所有尺寸随窗口大小弹性变化
//   - 系统原生标题栏，C++ 端通过 DWM API 深度自定义暗黑/边框颜色
//   - 支持 Home / 播放列表 / 收藏 / 历史 / 设置 五个视图切换
//   - 页面预创建，切换时仅切换 visible，消除闪屏
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

    flags: Qt.Window

    // ---- 禁用 F11 最大化 ----
    Shortcut {
        sequence: "F11"
        onActivated: {}  // 吞掉，什么也不做
    }

    // ---- 布局常量 ----
    readonly property int sidebarWidth: 230
    readonly property int playerBarHeight: 72

    // ---- 视图路由 ----
    property string currentMenu: ""              // 空串 = 未选择，不加载页面
    property string settingsSubMenu: "appearance"

    // ---- 播放详情页控制 ----
    property bool showPlayerDetail: false

    // ---- 自定义播放列表 ----
    property int currentCustomPlaylistIndex: -1
    property int _pendingAddToPlaylistIndex: -1   // 右键添加音乐的待定列表
    property int _rightClickedPlaylistIndex: -1   // 右键菜单的列表索引

    // ---- 搜索 ----
    property string searchText: ""
    property var searchResults: []
    property int searchScrollIndex: -1

    function updateSearch(text) {
        searchText = text.toLowerCase().trim()
        if (!searchText) {
            searchResults = []
            return
        }
        var lib = musicManager.library
        var res = []
        for (var i = 0; i < lib.length; i++) {
            var t = lib[i]
            var name = (t.name || "").toLowerCase()
            var artist = (t.artist || "").toLowerCase()
            var album = (t.album || "").toLowerCase()
            if (name.indexOf(searchText) >= 0 || artist.indexOf(searchText) >= 0 || album.indexOf(searchText) >= 0)
                res.push({ index: i, name: t.name || "未知", artist: t.artist || "未知", album: t.album || "" })
        }
        searchResults = res
    }

    // 搜索关键词高亮（不区分大小写）
    function highlightKw(text, keyword) {
        if (!text || !keyword) return text || ""
        var t = String(text)
        var k = String(keyword).trim()
        if (!k) return t
        var idx = t.toLowerCase().indexOf(k.toLowerCase())
        if (idx < 0) return t
        return t.substring(0, idx) + "<font color='#00d4ff'><b>" + t.substring(idx, idx + k.length) + "</b></font>" + t.substring(idx + k.length)
    }

    function onSearchResultClicked(libraryIndex) {
        // 切到首页
        currentMenu = "home"
        // 播放并滚动定位
        musicManager.playFromLibrary(libraryIndex)
        searchScrollIndex = libraryIndex
        searchInput.focus = false
        searchPopup.close()
    }

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
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: playerBar.top
        spacing: 0

        // ----------------------------------------------------------
        // 左侧 侧边栏 (230px 固定宽)
        // ----------------------------------------------------------
        Rectangle {
            Layout.preferredWidth: sidebarWidth
            Layout.fillHeight: true
            color: "#222236"

            ColumnLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: createListBtn.top
                anchors.topMargin: 10
                anchors.leftMargin: 10
                anchors.rightMargin: 10
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
                                color: "#999"
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
                        label: "所有音乐"
                        iconW: 34; iconH: 34; iconSrcSize: 26
                        active: currentMenu === "home"
                        fontFamily: appFont.name
                        onClicked: currentMenu = "home"
                    }
                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/PlayList.png"
                        label: "播放列表"
                        iconW: 34; iconH: 34; iconSrcSize: 26
                        active: currentMenu === "playlist"
                        fontFamily: appFont.name
                        onClicked: currentMenu = "playlist"
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
                        iconW: 34; iconH: 34; iconSrcSize: 26
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
                        label: "外观设置"
                        active: settingsSubMenu === "appearance"
                        fontFamily: appFont.name
                        onClicked: settingsSubMenu = "appearance"
                    }
                    SubNavItem {
                        label: "播放设置"
                        active: settingsSubMenu === "playback"
                        fontFamily: appFont.name
                        onClicked: settingsSubMenu = "playback"
                    }
                    SubNavItem {
                        label: "快捷键设置"
                        active: settingsSubMenu === "hotkeys"
                        fontFamily: appFont.name
                        onClicked: settingsSubMenu = "hotkeys"
                    }
                    SubNavItem {
                        label: "软件更新"
                        active: settingsSubMenu === "update"
                        fontFamily: appFont.name
                        onClicked: settingsSubMenu = "update"
                    }
                    SubNavItem {
                        label: "关于JustSolo"
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

                // ---- 自定义播放列表 ----
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: musicManager.customPlaylists.length > 0
                    clip: true
                    spacing: 2
                    model: musicManager.customPlaylists

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 55
                        radius: 6
                        color: mainWindow.currentMenu === "customPlaylist" && mainWindow.currentCustomPlaylistIndex === index ? "#36365a"
                             : (plMA.containsMouse ? "#2a2a48" : "transparent")

                        RowLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 34; Layout.preferredHeight: 34; radius: 4; color: "transparent"
                                Image {
                                    anchors.centerIn: parent
                                    source: "qrc:/qt/qml/JustSolo/data/image/SelfList.png"
                                    sourceSize.width: 30
                                    sourceSize.height: 30
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: modelData.name || "未命名"
                                font.family: appFont.name
                                font.pixelSize: 17
                                color: mainWindow.currentMenu === "customPlaylist" && mainWindow.currentCustomPlaylistIndex === index ? "#cccccc" : (plMA.containsMouse ? "#cccccc" : "#888")
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: plMA
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    mainWindow._pendingAddToPlaylistIndex = index
                                    mainWindow._rightClickedPlaylistIndex = index
                                    plContextMenu.popup()
                                } else {
                                    mainWindow.currentMenu = "customPlaylist"
                                    mainWindow.currentCustomPlaylistIndex = index
                                }
                            }
                        }

                        Menu {
                            id: plContextMenu
                            property QtObject win: mainWindow
                            background: Rectangle { color: "#2a2a3a"; border.color: "#444466"; radius: 6; implicitWidth: 150 }

                            MenuItem {
                                text: "添加本地音乐"
                                font.family: appFont.name; font.pixelSize: 14
                                contentItem: Label {
                                    text: "添加本地音乐"
                                    font.family: appFont.name; font.pixelSize: 14; color: "#cccccc"
                                    verticalAlignment: Text.AlignVCenter; leftPadding: 12
                                }
                                background: Rectangle { color: parent.hovered ? "#3a3a5a" : "transparent"; radius: 4 }
                                onClicked: fileDialog.open()
                            }

                            MenuItem {
                                text: "重命名"
                                font.family: appFont.name; font.pixelSize: 14
                                contentItem: Label {
                                    text: "重命名"
                                    font.family: appFont.name; font.pixelSize: 14; color: "#cccccc"
                                    verticalAlignment: Text.AlignVCenter; leftPadding: 12
                                }
                                background: Rectangle { color: parent.hovered ? "#3a3a5a" : "transparent"; radius: 4 }
                                onClicked: {
                                    renameField.text = musicManager.customPlaylists[plContextMenu.win._rightClickedPlaylistIndex]?.name || ""
                                    renameDialog.open()
                                }
                            }

                            MenuItem {
                                text: "删除"
                                font.family: appFont.name; font.pixelSize: 14
                                contentItem: Label {
                                    text: "删除"
                                    font.family: appFont.name; font.pixelSize: 14; color: "#cc5555"
                                    verticalAlignment: Text.AlignVCenter; leftPadding: 12
                                }
                                background: Rectangle { color: parent.hovered ? "#3a3a5a" : "transparent"; radius: 4 }
                                onClicked: {
                                    if (plContextMenu.win._rightClickedPlaylistIndex >= 0) {
                                        musicManager.deleteCustomPlaylist(plContextMenu.win._rightClickedPlaylistIndex)
                                        // 如果删除的是当前显示的列表，切回首页
                                        if (plContextMenu.win.currentMenu === "customPlaylist"
                                            && plContextMenu.win.currentCustomPlaylistIndex === plContextMenu.win._rightClickedPlaylistIndex) {
                                            plContextMenu.win.currentMenu = "home"
                                            plContextMenu.win.currentCustomPlaylistIndex = -1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- 弹性撑满 ----
                Item { Layout.fillHeight: true }
            }

            // ---- 创建新列表（参照 NavItem 样式） ----
            Rectangle {
                id: createListBtn
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottomMargin: 2
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                height: 50
                radius: 6
                z: 10
                color: sidebarCreateMA.containsMouse ? "#2a2a48" : "transparent"

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    spacing: 10

                    Rectangle {
                        width: 34; height: 34; radius: 4; color: "transparent"

                        Image {
                            anchors.centerIn: parent
                            source: "qrc:/qt/qml/JustSolo/data/image/creatList.png"
                            sourceSize.width: 26
                            sourceSize.height: 26
                        }
                    }

                    Label {
                        text: "创建新列表"
                        font.family: appFont.name
                        font.pixelSize: 17
                        color: sidebarCreateMA.containsMouse ? "#cccccc" : "#888"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: sidebarCreateMA
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: createListDialog.open()
                }
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
                anchors.bottomMargin: 10
                anchors.leftMargin: 30
                anchors.rightMargin: 30
                spacing: 0

                // -------- 搜索框行（全部页面可见） --------
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16
                    visible: true

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
                                id: searchInput
                                Layout.fillWidth: true
                                color: "#cccccc"
                                font.family: appFont.name
                                font.pixelSize: 15
                                clip: true
                                verticalAlignment: TextInput.AlignVCenter
                                onTextChanged: mainWindow.updateSearch(text)
                                onActiveFocusChanged: {
                                    if (activeFocus && text.trim().length > 0)
                                        searchPopup.open()
                                }

                                Text {
                                    text: "搜索本地音乐..."
                                    font.family: appFont.name
                                    font.pixelSize: 15
                                    color: "#555"
                                    visible: !parent.text && !parent.inputMethodComposing
                                }
                            }

                            // ---- 搜索下拉结果 ----
                            Popup {
                                id: searchPopup
                                x: (parent.width - width) / 2
                                y: parent.height + 4
                                width: Math.max(parent.width + 120, 420)
                                padding: 0
                                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
                                visible: searchInput.text.trim().length > 0

                                background: Rectangle {
                                    color: "#222236"
                                    border.color: "#444466"
                                    border.width: 1
                                    radius: 8
                                }

                                contentItem: Column {
                                    id: searchResultCol
                                    spacing: 0
                                    clip: true

                                    // ---- 有结果 ----
                                    Repeater {
                                        model: mainWindow.searchResults

                                        delegate: Rectangle {
                                            width: searchResultCol.width
                                            height: 42
                                            color: searchHover.containsMouse ? "#36365a" : "transparent"

                                            Rectangle {
                                                anchors.top: parent.top
                                                anchors.left: parent.left; anchors.right: parent.right
                                                height: 1; color: "#2a2a48"
                                                visible: index > 0
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 14; anchors.rightMargin: 14
                                                spacing: 8

                                                // ---- 歌名：超长滚动 ----
                                                Item {
                                                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true

                                                    Text {
                                                        id: nameText
                                                        text: mainWindow.highlightKw(modelData.name, searchInput.text)
                                                        textFormat: Text.StyledText
                                                        font.family: appFont.name; font.pixelSize: 14; color: "#cccccc"
                                                        y: (parent.height - height) / 2
                                                        x: 0

                                                        SequentialAnimation on x {
                                                            running: nameText.contentWidth > 0 && nameText.parent && nameText.parent.width > 0 && nameText.contentWidth > nameText.parent.width
                                                            loops: Animation.Infinite
                                                            NumberAnimation {
                                                                from: nameText.parent ? nameText.parent.width : 0
                                                                to: -nameText.contentWidth
                                                                duration: Math.max(8000, ((nameText.parent ? nameText.parent.width : 0) + nameText.contentWidth) * 15)
                                                                easing.type: Easing.Linear
                                                            }
                                                            PropertyAnimation { property: "x"; to: nameText.parent ? nameText.parent.width : 0; duration: 0 }
                                                        }
                                                    }
                                                }

                                                // ---- 歌手：超长滚动 ----
                                                Item {
                                                    Layout.preferredWidth: Math.max(90, parent.width * 0.26)
                                                    Layout.fillHeight: true; clip: true

                                                    Text {
                                                        id: artistText
                                                        text: mainWindow.highlightKw(modelData.artist, searchInput.text)
                                                        textFormat: Text.StyledText
                                                        font.family: appFont.name; font.pixelSize: 13; color: "#888"
                                                        y: (parent.height - height) / 2
                                                        x: 0
                                                        horizontalAlignment: Text.AlignRight

                                                        SequentialAnimation on x {
                                                            running: artistText.contentWidth > 0 && artistText.parent && artistText.parent.width > 0 && artistText.contentWidth > artistText.parent.width
                                                            loops: Animation.Infinite
                                                            NumberAnimation {
                                                                from: artistText.parent ? artistText.parent.width : 0
                                                                to: -artistText.contentWidth
                                                                duration: Math.max(6000, ((artistText.parent ? artistText.parent.width : 0) + artistText.contentWidth) * 12)
                                                                easing.type: Easing.Linear
                                                            }
                                                            PropertyAnimation { property: "x"; to: artistText.parent ? artistText.parent.width : 0; duration: 0 }
                                                        }
                                                    }
                                                }

                                                // ---- 专辑：超长滚动 ----
                                                Item {
                                                    Layout.preferredWidth: Math.max(90, parent.width * 0.26)
                                                    Layout.fillHeight: true; clip: true
                                                    visible: modelData.album !== ""

                                                    Text {
                                                        id: albumText
                                                        text: mainWindow.highlightKw(modelData.album, searchInput.text)
                                                        textFormat: Text.StyledText
                                                        font.family: appFont.name; font.pixelSize: 13; color: "#666"
                                                        y: (parent.height - height) / 2
                                                        x: 0
                                                        horizontalAlignment: Text.AlignRight

                                                        SequentialAnimation on x {
                                                            running: albumText.contentWidth > 0 && albumText.parent && albumText.parent.width > 0 && albumText.contentWidth > albumText.parent.width
                                                            loops: Animation.Infinite
                                                            NumberAnimation {
                                                                from: albumText.parent ? albumText.parent.width : 0
                                                                to: -albumText.contentWidth
                                                                duration: Math.max(6000, ((albumText.parent ? albumText.parent.width : 0) + albumText.contentWidth) * 12)
                                                                easing.type: Easing.Linear
                                                            }
                                                            PropertyAnimation { property: "x"; to: albumText.parent ? albumText.parent.width : 0; duration: 0 }
                                                        }
                                                    }
                                                }
                                            }

                                            MouseArea {
                                                id: searchHover
                                                anchors.fill: parent; hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mainWindow.onSearchResultClicked(modelData.index)
                                            }
                                        }
                                    }

                                    // ---- 无结果提示 ----
                                    Rectangle {
                                        width: searchResultCol.width
                                        height: 42
                                        visible: mainWindow.searchResults.length === 0
                                        color: "transparent"

                                        Label {
                                            anchors.centerIn: parent
                                            text: "暂无相关歌曲"
                                            font.family: appFont.name; font.pixelSize: 13; color: "#666"
                                        }
                                    }
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
                           : currentMenu === "playlist" ? "qrc:/qt/qml/JustSolo/data/image/PlayList.png"
                           : currentMenu === "favorite" ? "qrc:/qt/qml/JustSolo/data/image/mylike.png"
                           : currentMenu === "history" ? "qrc:/qt/qml/JustSolo/data/image/history.png"
                           : currentMenu === "customPlaylist" ? "qrc:/qt/qml/JustSolo/data/image/SelfList.png"
                           : ""
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
                              : currentMenu === "home" ? "所有音乐"
                              : currentMenu === "playlist" ? "播放列表"
                              : currentMenu === "favorite" ? "收藏"
                              : currentMenu === "history" ? "历史"
                              : currentMenu === "customPlaylist" ? customPlaylistName()
                              : (settingsSubMenu === "playback" ? "播放设置"
                              : (settingsSubMenu === "hotkeys" ? "快捷键设置"
                              : (settingsSubMenu === "update" ? "软件更新"
                              : (settingsSubMenu === "appearance" ? "外观设置" : "关于JustSolo"))))
                        font.family: appFont.name
                        font.pixelSize: 24
                        font.bold: true
                        color: "#dddddd"
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    // ---- 清除播放列表按钮（仅播放列表页） ----
                    Rectangle {
                        Layout.preferredHeight: 28; radius: 4
                        Layout.preferredWidth: clearPlaylistText.contentWidth + 20
                        color: clearPlaylistMA.containsMouse ? "#3a2a2a" : "transparent"
                        visible: currentMenu === "playlist"
                        Label {
                            id: clearPlaylistText
                            text: "清除播放列表"; font.family: appFont.name; font.pixelSize: 12; color: "#969696"
                            anchors.centerIn: parent
                        }
                        MouseArea {
                            id: clearPlaylistMA; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: musicManager.clearPlaylist()
                        }
                    }

                    // ---- 清除所有历史按钮（仅历史页） ----
                    Rectangle {
                        Layout.preferredHeight: 28; radius: 4
                        Layout.preferredWidth: clearBtnText.contentWidth + 20
                        color: clearBtnMA.containsMouse ? "#3a2a2a" : "transparent"
                        visible: currentMenu === "history"
                        Label {
                            id: clearBtnText
                            text: "清除所有历史"; font.family: appFont.name; font.pixelSize: 12; color: "#969696"
                            anchors.centerIn: parent
                        }
                        MouseArea {
                            id: clearBtnMA; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: musicManager.clearHistory()
                        }
                    }

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

                // 欢迎页提示语（仅无菜单时显示）
                Label {
                    text: "点击左侧列表开始使用"
                    font.family: appFont.name; font.pixelSize: 14; color: "#888"
                    visible: currentMenu === ""
                    Layout.alignment: Qt.AlignLeft
                    Layout.leftMargin: 40
                }

                Item { Layout.preferredHeight: 16 }

                // ==================================================
                // 页面内容区（预创建所有页面，切换时只切换可见性，消除闪屏）
                // ==================================================
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // 全局通用歌曲列表（所有音乐 & 自建列表共用）
                    HomePage {
                        anchors.fill: parent
                        visible: currentMenu === "home" || currentMenu === "customPlaylist"
                        sidebarWidth: mainWindow.sidebarWidth
                        windowWidth: mainWindow.width
                        fontFamily: appFont.name
                        scrollToIndex: currentMenu === "home" ? mainWindow.searchScrollIndex : -1
                        customPlaylistIndex: currentMenu === "customPlaylist" ? currentCustomPlaylistIndex : -1
                        pageListIndex: currentMenu === "customPlaylist" ? 3 + currentCustomPlaylistIndex : 0
                        emptyHint: currentMenu === "customPlaylist" ? "此列表还没有歌曲" : "还没有音乐"
                        emptySubHint: currentMenu === "customPlaylist" ? "请到侧边栏右键本列表添加音乐" : "点击上方「添加音乐」导入本地文件"
                        songList: {
                            if (currentMenu === "customPlaylist" && currentCustomPlaylistIndex >= 0
                                && currentCustomPlaylistIndex < musicManager.customPlaylists.length) {
                                var raw = musicManager.customPlaylists[currentCustomPlaylistIndex].songs || []
                                var lib = musicManager.library
                                var result = []
                                for (var i = 0; i < raw.length; i++) {
                                    var path = raw[i].path || ""
                                    for (var j = 0; j < lib.length; j++) {
                                        if (lib[j].path === path) {
                                            result.push(lib[j])
                                            break
                                        }
                                    }
                                }
                                return result
                            }
                            return musicManager.library
                        }
                    }
                    PlaylistPage {
                        anchors.fill: parent
                        visible: currentMenu === "playlist"
                        sidebarWidth: mainWindow.sidebarWidth
                        windowWidth: mainWindow.width
                        fontFamily: appFont.name
                    }
                    FavoritePage {
                        anchors.fill: parent
                        visible: currentMenu === "favorite"
                        sidebarWidth: mainWindow.sidebarWidth
                        windowWidth: mainWindow.width
                        fontFamily: appFont.name
                    }
                    HistoryPage {
                        anchors.fill: parent
                        visible: currentMenu === "history"
                        sidebarWidth: mainWindow.sidebarWidth
                        windowWidth: mainWindow.width
                        fontFamily: appFont.name
                    }
                    Loader {
                        active: currentMenu === "settings"
                        asynchronous: true
                        sourceComponent: Component {
                            SettingsPage {
                                anchors.fill: parent
                                settingsSubMenu: mainWindow.settingsSubMenu
                                fontFamily: appFont.name
                            }
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
                    // 如果是从自建列表右键调用的，同时加入该列表
                    if (mainWindow._pendingAddToPlaylistIndex >= 0) {
                        musicManager.addSongsToCustomPlaylist(paths, mainWindow._pendingAddToPlaylistIndex)
                        mainWindow._pendingAddToPlaylistIndex = -1
                    }
                    // 确保导入后页面状态不变（避免异步导入时页面被意外重置）
                    var savedMenu = mainWindow.currentMenu
                    var savedCustomIdx = mainWindow.currentCustomPlaylistIndex
                    Qt.callLater(function() {
                        if (savedMenu === "customPlaylist") {
                            mainWindow.currentMenu = savedMenu
                            mainWindow.currentCustomPlaylistIndex = savedCustomIdx
                        }
                    })
                }
                onRejected: mainWindow._pendingAddToPlaylistIndex = -1
            }
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

    // ---- 关闭窗口 ----
    // 根据设置决定最小化到系统托盘（音乐继续播放）或真退出
    onClosing: function(close) {
        if (musicManager.minimizeToTray) {
            close.accepted = false
            mainWindow.hide()
            playerDetail.visible = false      // 关 ShaderEffectSource live
        } else {
            // 真退出：清理播放状态
            playerDetail.visible = false
            musicManager.stop()
            musicManager.shutdown()
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
                    id: playerCoverRect
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
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onEntered: playerCoverRect.color = "#4a4a6a"
                        onExited: playerCoverRect.color = "#3a3a55"
                        onClicked: {
                            if (musicManager.currentIndex >= 0)
                                showPlayerDetail = true
                        }
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

            // ---- 右侧：播放进度（固定窗口 1/3） ----
            RowLayout {
                Layout.preferredWidth: mainWindow.width / 3
                Layout.minimumWidth: mainWindow.width / 3
                Layout.maximumWidth: mainWindow.width / 3
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
                    id: barProgressTrack
                    Layout.fillWidth: true; Layout.preferredHeight: 4; radius: 2; color: "#3a3a55"
                    Rectangle {
                        id: barProgressFill
                        readonly property real autoRatio: Math.min(1, playerBar.progressFraction)
                        width: parent.width * (barSeekMA.pressed ? barSeekMA._dragRatio : autoRatio)
                        height: parent.height; radius: 2; color: "#00d4ff"
                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: barSeekMA
                        anchors.fill: parent
                        anchors.topMargin: -8; anchors.bottomMargin: -8
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        preventStealing: true

                        property real _dragRatio: 0
                        property real _trackW: 0

                        function seek(mx) {
                            var w = barSeekMA.pressed ? _trackW : barProgressTrack.width
                            _dragRatio = Math.max(0, Math.min(1, mx / w))
                            if (musicManager.duration > 0)
                                musicManager.seek(_dragRatio * musicManager.duration)
                        }

                        onPressed: function(m) { _trackW = barProgressTrack.width; seek(m.x) }
                        onPositionChanged: function(m) { if (pressed) seek(m.x) }
                        onClicked: function(m) { seek(m.x) }
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
    // 播放详情页覆盖层（z: 100，高于所有界面元素）
    // ============================================================
    PlayerDetailPage {
        id: playerDetail
        anchors.fill: parent
        z: 100
        fontFamily: appFont.name
        visible: false

        onVisibleChanged: {
            if (!visible)
                mainWindow.showPlayerDetail = false
        }
    }

    // ============================================================
    // 创建新列表对话框
    // ============================================================
    Dialog {
        id: createListDialog
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 340
        padding: 28

        Overlay.modal: Rectangle { color: "transparent" }

        background: Rectangle {
            color: "#2a2a48"
            radius: 10
            border.color: "#444466"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 14

            Label {
                text: "新播放列表"
                font.family: appFont.name
                font.pixelSize: 17
                font.bold: true
                color: "#dddddd"
                Layout.bottomMargin: 4
            }

            TextField {
                id: listNameField
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                leftPadding: 12
                rightPadding: 12
                placeholderText: "例如：我的歌单"
                placeholderTextColor: "#aaa"
                font.family: appFont.name
                font.pixelSize: 14
                color: "#ddd"
                verticalAlignment: TextInput.AlignVCenter
                background: Rectangle {
                    radius: 6
                    color: "#333350"
                    border.color: "#555577"
                    border.width: 1
                }
                Keys.onReturnPressed: doCreateList()
                Keys.onEnterPressed: doCreateList()
            }

            Label {
                id: createNameHint
                text: ""
                font.family: appFont.name; font.pixelSize: 11; color: "#cc5555"
                Layout.topMargin: -4
                visible: text.length > 0
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12
                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: cancelMA.containsMouse ? "#3a3a5a" : "#333350"
                    border.color: "#444466"; border.width: 1
                    Label { text: "取消"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: cancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { listNameField.text = ""; createListDialog.close() }
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: confirmMA.containsMouse ? "#4a6a8a" : "#3a5a7a"
                    Label { text: "确定"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#ddd" }
                    MouseArea {
                        id: confirmMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: doCreateList()
                    }
                }
            }
        }
    }

    // ---- 重命名自定义列表对话框 ----
    Dialog {
        id: renameDialog
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 340
        padding: 28

        Overlay.modal: Rectangle { color: "transparent" }

        background: Rectangle {
            color: "#2a2a48"
            radius: 10
            border.color: "#444466"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 14

            Label {
                text: "重命名列表"
                font.family: appFont.name
                font.pixelSize: 17
                font.bold: true
                color: "#dddddd"
                Layout.bottomMargin: 4
            }

            TextField {
                id: renameField
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                leftPadding: 12; rightPadding: 12
                placeholderText: "输入新名称"
                placeholderTextColor: "#aaa"
                font.family: appFont.name
                font.pixelSize: 14
                color: "#ddd"
                background: Rectangle {
                    radius: 6
                    color: "#333350"
                    border.color: "#555577"
                    border.width: 1
                }
                onTextChanged: renameHint.text = ""
                Keys.onReturnPressed: doRename()
                Keys.onEnterPressed: doRename()
            }

            Label {
                id: renameHint
                text: ""
                font.family: appFont.name; font.pixelSize: 11; color: "#cc5555"
                Layout.topMargin: -4
                visible: text.length > 0
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12
                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: renameCancelMA.containsMouse ? "#3a3a5a" : "#333350"
                    border.color: "#444466"; border.width: 1
                    Label { text: "取消"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: renameCancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { renameField.text = ""; renameDialog.close() }
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: renameConfirmMA.containsMouse ? "#4a6a8a" : "#3a5a7a"
                    Label { text: "确定"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#ddd" }
                    MouseArea {
                        id: renameConfirmMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: doRename()
                    }
                }
            }
        }
    }

    function doCreateList() {
        var name = listNameField.text.trim()
        if (name.length === 0) return
        // 验证名称格式
        if (!musicManager.isValidPlaylistName(name)) {
            createNameHint.text = "仅支持中英文、数字、- 和 _"
            return
        }
        // 检查重名
        var lists = musicManager.customPlaylists
        for (var i = 0; i < lists.length; i++) {
            if (lists[i].name === name) {
                createNameHint.text = "已存在同名列表"
                return
            }
        }
        createNameHint.text = ""
        musicManager.createCustomPlaylist(name)
        listNameField.text = ""
        createListDialog.close()
    }

    function doRename() {
        var name = renameField.text.trim()
        if (name.length === 0 || mainWindow._rightClickedPlaylistIndex < 0) return
        // 验证名称格式
        if (!musicManager.isValidPlaylistName(name)) {
            renameHint.text = "仅支持中英文、数字、- 和 _"
            return
        }
        // 检查重名（排除自己）
        var lists = musicManager.customPlaylists
        for (var i = 0; i < lists.length; i++) {
            if (i !== mainWindow._rightClickedPlaylistIndex && lists[i].name === name) {
                renameHint.text = "已存在同名列表"
                return
            }
        }
        renameHint.text = ""
        musicManager.renameCustomPlaylist(mainWindow._rightClickedPlaylistIndex, name)
        renameField.text = ""
        renameDialog.close()
    }

    function customPlaylistName() {
        if (currentCustomPlaylistIndex >= 0 && currentCustomPlaylistIndex < musicManager.customPlaylists.length)
            return musicManager.customPlaylists[currentCustomPlaylistIndex].name || "自定义列表"
        return "自定义列表"
    }

    // 外部触发详情页显隐
    onShowPlayerDetailChanged: {
        if (showPlayerDetail)
            playerDetail.visible = true
    }
}
