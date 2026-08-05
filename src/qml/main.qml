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
import QtQuick.Effects

// ============================================================
// 主窗口
// ============================================================
Window {
    id: mainWindow

    // ---- 初始尺寸 ----
    width: 1150
    height: 780
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
    readonly property int sidebarWidth: 200
    readonly property int playerBarHeight: 75

    // ---- 视图路由 ----
    property string currentMenu: ""              // 空串 = 未选择，不加载页面
    property string settingsSubMenu: "appearance"

    // ---- 播放详情页控制 ----
    property bool showPlayerDetail: false
    // 记忆详情页打开状态：窗口隐藏到后台时记录，回到前台自动恢复
    property bool _detailWasOpen: false

    // ---- 迷你小窗 ----
    property var _miniWindow: null
    property bool _pendingMiniExit: false

    // ---- 自定义播放列表 ----
    property int currentCustomPlaylistIndex: -1
    property int _pendingAddToPlaylistIndex: -1   // 右键添加音乐的待定列表
    property int _rightClickedPlaylistIndex: -1   // 右键菜单的列表索引

    // ---- 歌手列表（复用 customPlaylists，type="artist"） ----
    property var _manualPlaylistIndices: []    // 普通自定义列表在 customPlaylists 中的索引
    property var _artistPlaylistIndices: []    // 歌手列表在 customPlaylists 中的索引
    property var _artistDialogFilter: []       // 歌手选择对话框的过滤后列表
    property string _connectedClientName: ""  // LyricServer 连接的客户端名称
    property var _existingArtistNames: ({})    // 已创建歌手列表的歌手名集合（去重标记）

    function _rebuildPlaylistIndices() {
        var manual = []
        var artist = []
        var existingArtists = ({})
        var all = musicManager.customPlaylists
        for (var i = 0; i < all.length; i++) {
            if (all[i].type === "artist") {
                artist.push(i)
                existingArtists[all[i].artist || all[i].name || ""] = true
            } else {
                manual.push(i)
            }
        }
        _manualPlaylistIndices = manual
        _artistPlaylistIndices = artist
        _existingArtistNames = existingArtists
    }

    function _isCurrentArtistList() {
        if (currentMenu !== "customPlaylist" || currentCustomPlaylistIndex < 0) return false
        if (currentCustomPlaylistIndex >= musicManager.customPlaylists.length) return false
        return musicManager.customPlaylists[currentCustomPlaylistIndex].type === "artist"
    }

    // ---- 搜索 ----
    property string searchText: ""
    property var searchResults: []
    property int searchScrollIndex: -1

    // ---- 从音乐库导入对话框 ----
    property var _libSelectedSet: ({})       // {libIndex: true}
    property var _libAlreadyInPlaylistSet: ({})  // {path: true}
    property int _importTargetPlaylist: -1
    property var _libFilteredModel: []
    property int _libSelectedVersion: 0      // 递增触发绑定刷新

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

    // ---- 从音乐库导入辅助函数 ----
    function _buildAlreadyInPlaylistSet(playlistIndex) {
        _libAlreadyInPlaylistSet = ({})
        if (playlistIndex < 0 || playlistIndex >= musicManager.customPlaylists.length) return
        var songs = musicManager.customPlaylists[playlistIndex].songs || []
        for (var i = 0; i < songs.length; i++) {
            var p = songs[i].path || ""
            if (p) _libAlreadyInPlaylistSet[p] = true
        }
    }

    // 用全局 searchText 过滤音乐库，结果写入 _libFilteredModel
    function _rebuildDialogLibrary() {
        var query = searchText  // 读但不写全局搜索
        var lib = musicManager.library
        if (!query) {
            _libFilteredModel = lib.slice()
            return
        }
        var result = []
        for (var i = 0; i < lib.length; i++) {
            var name = (lib[i].title || lib[i].name || "").toLowerCase()
            var artist = (lib[i].artist || "").toLowerCase()
            var album = (lib[i].album || "").toLowerCase()
            if (name.indexOf(query) >= 0 || artist.indexOf(query) >= 0 || album.indexOf(query) >= 0)
                result.push(lib[i])
        }
        _libFilteredModel = result
    }

    function _toggleLibSelect(libIndex) {
        if (_libAlreadyInPlaylistSet[musicManager.library[libIndex].path]) return
        if (_libSelectedSet[libIndex])
            delete _libSelectedSet[libIndex]
        else
            _libSelectedSet[libIndex] = true
        _libSelectedVersion++
    }

    function _toggleLibSelectAll() {
        var allSelected = true
        // 检查当前所有未在列表中的歌曲是否已全选
        for (var i = 0; i < _libFilteredModel.length; i++) {
            var realIdx = musicManager.library.indexOf(_libFilteredModel[i])
            if (realIdx < 0) continue
            var path = _libFilteredModel[i].path || ""
            if (_libAlreadyInPlaylistSet[path]) continue
            if (!_libSelectedSet[realIdx]) {
                allSelected = false
                break
            }
        }
        // 全选/取消
        for (var j = 0; j < _libFilteredModel.length; j++) {
            var rIdx = musicManager.library.indexOf(_libFilteredModel[j])
            if (rIdx < 0) continue
            var p = _libFilteredModel[j].path || ""
            if (_libAlreadyInPlaylistSet[p]) continue
            if (allSelected)
                delete _libSelectedSet[rIdx]
            else
                _libSelectedSet[rIdx] = true
        }
        _libSelectedVersion++
    }

    function _countLibSelected() {
        var count = 0
        for (var k in _libSelectedSet) {
            if (_libSelectedSet.hasOwnProperty(k)) count++
        }
        return count
    }

    function _doImport() {
        var indices = []
        for (var k in _libSelectedSet) {
            if (_libSelectedSet.hasOwnProperty(k))
                indices.push(parseInt(k))
        }
        if (indices.length === 0 || _importTargetPlaylist < 0) return
        musicManager.addLibrarySongsToCustomPlaylist(indices, _importTargetPlaylist)
        _libSelectedSet = ({})
        _libSelectedVersion = 0
        libraryImportDialog.close()
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
            color: "#1E1E1E"

            ColumnLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.topMargin: 10
                anchors.bottomMargin: 8
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 0

                // ---- Logo + 标题 ----
                Rectangle {
                    // 这里原来是 Layout.preferredWidth: sidebarWidth，导致宽度强制撑大溢出
                    // 现在改为 Layout.fillWidth: true，听从外层的 16px 左右留白
                    Layout.fillWidth: true
                    Layout.preferredHeight: 64
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 4
                        spacing: 10

                        Image {
                            source: "qrc:/qt/qml/JustSolo/data/image/logo2.png"
                            sourceSize.width: 28
                            sourceSize.height: 28
                            fillMode: Image.PreserveAspectFit
                        }

                        Column {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            Label {
                                text: "Just Solo"
                                font.family: appFont.name
                                font.pixelSize: 18
                                font.bold: true
                                color: "#cccccc"
                            }

                            Label {
                                text: APP_VERSION
                                font.family: appFont.name
                                font.pixelSize: 10
                                color: "#999"
                            }
                        }
                    }
                }

                // ---- 分割线 ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 12
                    Layout.bottomMargin: 0
                    color: "#3A3A3A2B"
                }

                Item { Layout.preferredHeight: 14 } // 还原你原本的代码间距

                // ---- 设置按钮 ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36
                    radius: 6
                    color: currentMenu === "settings" ? "#2C2C2C" : (settingsTopMouse.containsMouse ? "#222222" : "transparent")

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        spacing: 10

                        Rectangle {
                            width: 28; height: 28; radius: 4; color: "transparent"
                            Image {
                                anchors.centerIn: parent
                                source: "qrc:/qt/qml/JustSolo/data/image/setting.png"
                                sourceSize.width: 24
                                sourceSize.height: 24
                                fillMode: Image.PreserveAspectFit
                            }
                        }

                        Label {
                            text: "设置"
                            font.family: appFont.name
                            font.pixelSize: 15
                            color: currentMenu === "settings" ? "#cccccc" : (settingsTopMouse.containsMouse ? "#cccccc" : "#888")
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
                    Layout.topMargin: 12
                    color: "#3A3A3A2B"
                }

                Item { Layout.preferredHeight: 14 }

                // ---- 主导航（非设置页可见） ----
                ColumnLayout {
                    // 嵌套的 Layout 必须声明 Layout.fillWidth: true，否则子项边界会失控
                    Layout.fillWidth: true
                    spacing: 5
                    visible: currentMenu !== "settings"

                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/home.png"
                        label: "所有音乐"
                        iconW: 28; iconH: 28; iconSrcSize: 20
                        active: currentMenu === "home"
                        fontFamily: appFont.name
                        onClicked: currentMenu = "home"
                    }
                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/PlayList.png"
                        label: "播放列表"
                        iconW: 28; iconH: 28; iconSrcSize: 20
                        active: currentMenu === "playlist"
                        fontFamily: appFont.name
                        onClicked: currentMenu = "playlist"
                    }
                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/mylike.png"
                        label: "收藏"
                        iconW: 28; iconH: 28; iconSrcSize: 20
                        active: currentMenu === "favorite"
                        fontFamily: appFont.name
                        onClicked: currentMenu = "favorite"
                    }
                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/history.png"
                        label: "历史"
                        iconW: 28; iconH: 28; iconSrcSize: 20
                        active: currentMenu === "history"
                        fontFamily: appFont.name
                        onClicked: currentMenu = "history"
                    }
                }

                // ---- 设置子导航（设置页可见） ----
                ColumnLayout {
                    // 强制包裹容器受到 16px 留白的控制
                    Layout.fillWidth: true
                    spacing: 5
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
                        label: "LyricServer管理"
                        active: settingsSubMenu === "lyricserver"
                        fontFamily: appFont.name
                        onClicked: settingsSubMenu = "lyricserver"
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
                        Layout.preferredHeight: 36
                        radius: 6
                        color: exitSettingsMouse.containsMouse ? "#2C2C2C" : "transparent"

                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                source: "qrc:/qt/qml/JustSolo/data/image/back.png"
                                sourceSize.width: 15
                                sourceSize.height: 15
                                fillMode: Image.PreserveAspectFit
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

                // ---- 分割线 ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 12
                    Layout.bottomMargin: 8
                    color: "#3A3A3A2B"
                    visible: currentMenu !== "settings"
                }

                // ---- 自定义列表板块标题 + 新建按钮 ----
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    Layout.bottomMargin: 6
                    visible: currentMenu !== "settings"
                    spacing: 6

                    Rectangle {
                        Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 4; color: "transparent"
                        Image {
                            anchors.centerIn: parent
                            source: "qrc:/qt/qml/JustSolo/data/image/PlayList.png"
                            sourceSize.width: 20; sourceSize.height: 20
                            fillMode: Image.PreserveAspectFit
                        }
                    }

                    Label {
                        text: "自定义列表"
                        font.family: appFont.name
                        font.pixelSize: 15
                        color: "#999"
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter
                        radius: 4
                        color: sidebarCreateMA.containsMouse ? "#222222" : "transparent"

                        Image {
                            anchors.centerIn: parent
                            source: "qrc:/qt/qml/JustSolo/data/image/creatList.png"
                            sourceSize.width: 18
                            sourceSize.height: 18
                        }

                        MouseArea {
                            id: sidebarCreateMA
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: createListDialog.open()
                        }
                    }
                }

                // ---- 自定义播放列表 ----
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: currentMenu !== "settings"
                    clip: true
                    spacing: 5
                    model: _manualPlaylistIndices

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            visible: parent.size < 1.0
                            color: parent.pressed ? "#888" : "#555"
                        }
                    }

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 36 
                        radius: 6
                        color: mainWindow.currentMenu === "customPlaylist" && mainWindow.currentCustomPlaylistIndex === modelData ? "#2C2C2C" : (plMA.containsMouse ? "#222222" : "transparent")

                        RowLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 4; color: "transparent"
                                Image {
                                    anchors.centerIn: parent
                                    source: "qrc:/qt/qml/JustSolo/data/image/PlayList.png"
                                    sourceSize.width: 20
                                    sourceSize.height: 20
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: musicManager.customPlaylists[modelData].name || "未命名"
                                font.family: appFont.name
                                font.pixelSize: 15
                                color: mainWindow.currentMenu === "customPlaylist" && mainWindow.currentCustomPlaylistIndex === modelData ? "#cccccc" : (plMA.containsMouse ? "#cccccc" : "#888")
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
                                    mainWindow._pendingAddToPlaylistIndex = modelData
                                    mainWindow._rightClickedPlaylistIndex = modelData
                                    plContextMenu.popup()
                                } else {
                                    mainWindow.currentMenu = "customPlaylist"
                                    mainWindow.currentCustomPlaylistIndex = modelData
                                }
                            }
                        }

                        Menu {
                            id: plContextMenu
                            property QtObject win: mainWindow
                            background: Rectangle { color: "#222222"; border.color: "#3A3A3A"; radius: 6; implicitWidth: 150 }

                            MenuItem {
                                text: "添加本地音乐"
                                font.family: appFont.name; font.pixelSize: 15
                                contentItem: Label {
                                    text: "添加本地音乐"
                                    font.family: appFont.name; font.pixelSize: 15; color: "#cccccc"
                                    verticalAlignment: Text.AlignVCenter; leftPadding: 12
                                }
                                background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
                                onClicked: fileDialog.open()
                            }

                            MenuItem {
                                text: "从音乐库导入"
                                font.family: appFont.name; font.pixelSize: 15
                                contentItem: Label {
                                    text: "从音乐库导入"
                                    font.family: appFont.name; font.pixelSize: 15; color: "#cccccc"
                                    verticalAlignment: Text.AlignVCenter; leftPadding: 12
                                }
                                background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
                                enabled: musicManager.library.length > 0
                                onClicked: {
                                    var targetIdx = plContextMenu.win._rightClickedPlaylistIndex
                                    plContextMenu.win._importTargetPlaylist = targetIdx
                                    plContextMenu.win._buildAlreadyInPlaylistSet(targetIdx)
                                    plContextMenu.win._libSelectedSet = ({})
                                    libSearchField.text = searchText
                                    plContextMenu.win._rebuildDialogLibrary()
                                    libraryImportDialog.open()
                                }
                            }

                            MenuItem {
                                text: "重命名"
                                font.family: appFont.name; font.pixelSize: 15
                                contentItem: Label {
                                    text: "重命名"
                                    font.family: appFont.name; font.pixelSize: 15; color: "#cccccc"
                                    verticalAlignment: Text.AlignVCenter; leftPadding: 12
                                }
                                background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
                                onClicked: {
                                    renameField.text = musicManager.customPlaylists[plContextMenu.win._rightClickedPlaylistIndex]?.name || ""
                                    renameDialog.open()
                                }
                            }

                            MenuItem {
                                text: "删除"
                                font.family: appFont.name; font.pixelSize: 15
                                contentItem: Label {
                                    text: "删除"
                                    font.family: appFont.name; font.pixelSize: 15; color: "#cc5555"
                                    verticalAlignment: Text.AlignVCenter; leftPadding: 12
                                }
                                background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
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

                // ---- 歌手板块分割线 ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 8
                    Layout.bottomMargin: 8
                    color: "#3A3A3A2B"
                    visible: currentMenu !== "settings"
                }

                // ---- 歌手板块标题 + 添加按钮 ----
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    Layout.bottomMargin: 6
                    visible: currentMenu !== "settings"
                    spacing: 6

                    Rectangle {
                        Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 4; color: "transparent"
                        Image {
                            anchors.centerIn: parent
                            source: "qrc:/qt/qml/JustSolo/data/image/mylike.png"
                            sourceSize.width: 20; sourceSize.height: 20
                            fillMode: Image.PreserveAspectFit
                        }
                    }

                    Label {
                        text: "歌手列表"
                        font.family: appFont.name
                        font.pixelSize: 15
                        color: "#999"
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter
                        radius: 4
                        color: sidebarArtistAddMA.containsMouse ? "#222222" : "transparent"

                        Image {
                            anchors.centerIn: parent
                            source: "qrc:/qt/qml/JustSolo/data/image/creatList.png"
                            sourceSize.width: 18
                            sourceSize.height: 18
                        }

                        MouseArea {
                            id: sidebarArtistAddMA
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                _artistDialogFilter = musicManager.availableArtists()
                                artistSearchField.text = ""
                                artistSelectDialog.open()
                            }
                        }
                    }
                }

                // ---- 歌手列表 ----
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: currentMenu !== "settings"
                    clip: true
                    spacing: 5
                    model: _artistPlaylistIndices

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            visible: parent.size < 1.0
                            color: parent.pressed ? "#888" : "#555"
                        }
                    }

                    delegate: Rectangle {
                        width: ListView.view.width
                        height: 36
                        radius: 6
                        color: mainWindow.currentMenu === "customPlaylist" && mainWindow.currentCustomPlaylistIndex === modelData ? "#2C2C2C" : (arMA.containsMouse ? "#222222" : "transparent")

                        RowLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 4; color: "transparent"
                                Label {
                                    anchors.centerIn: parent
                                    text: "🎤"
                                    font.pixelSize: 16
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                text: musicManager.customPlaylists[modelData].name || "未知歌手"
                                font.family: appFont.name
                                font.pixelSize: 15
                                color: mainWindow.currentMenu === "customPlaylist" && mainWindow.currentCustomPlaylistIndex === modelData ? "#cccccc" : (arMA.containsMouse ? "#cccccc" : "#888")
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: arMA
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    mainWindow._rightClickedPlaylistIndex = modelData
                                    arContextMenu.popup()
                                } else {
                                    mainWindow.currentMenu = "customPlaylist"
                                    mainWindow.currentCustomPlaylistIndex = modelData
                                }
                            }
                        }

                        Menu {
                            id: arContextMenu
                            property QtObject win: mainWindow
                            background: Rectangle { color: "#222222"; border.color: "#3A3A3A"; radius: 6; implicitWidth: 150 }

                            MenuItem {
                                text: "刷新歌曲"
                                font.family: appFont.name; font.pixelSize: 15
                                contentItem: Label {
                                    text: "刷新歌曲"
                                    font.family: appFont.name; font.pixelSize: 15; color: "#cccccc"
                                    verticalAlignment: Text.AlignVCenter; leftPadding: 12
                                }
                                background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
                                onClicked: {
                                    musicManager.refreshArtistPlaylist(arContextMenu.win._rightClickedPlaylistIndex)
                                }
                            }

                            MenuItem {
                                text: "重命名"
                                font.family: appFont.name; font.pixelSize: 15
                                contentItem: Label {
                                    text: "重命名"
                                    font.family: appFont.name; font.pixelSize: 15; color: "#cccccc"
                                    verticalAlignment: Text.AlignVCenter; leftPadding: 12
                                }
                                background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
                                onClicked: {
                                    renameField.text = musicManager.customPlaylists[arContextMenu.win._rightClickedPlaylistIndex]?.name || ""
                                    renameDialog.open()
                                }
                            }

                            MenuItem {
                                text: "删除"
                                font.family: appFont.name; font.pixelSize: 15
                                contentItem: Label {
                                    text: "删除"
                                    font.family: appFont.name; font.pixelSize: 15; color: "#cc5555"
                                    verticalAlignment: Text.AlignVCenter; leftPadding: 12
                                }
                                background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
                                onClicked: {
                                    if (arContextMenu.win._rightClickedPlaylistIndex >= 0) {
                                        musicManager.deleteCustomPlaylist(arContextMenu.win._rightClickedPlaylistIndex)
                                        if (arContextMenu.win.currentMenu === "customPlaylist"
                                            && arContextMenu.win.currentCustomPlaylistIndex === arContextMenu.win._rightClickedPlaylistIndex) {
                                            arContextMenu.win.currentMenu = "home"
                                            arContextMenu.win.currentCustomPlaylistIndex = -1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- 设置页填充 ----
                Item { Layout.fillHeight: true; visible: currentMenu === "settings" }
            }
        }

        // ----------------------------------------------------------
        // 右侧 内容区（自适应填充剩余宽度）
        // ----------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#181818"

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
                        color: "#1E1E1E"
                        border.color: "#3A3A3A"
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
                                visible: searchInput.text.trim().length > 0 && !musicManager.isLoading

                                background: Rectangle {
                                    color: "#181818"
                                    border.color: "#3A3A3A"
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
                                            color: searchHover.containsMouse ? "#2C2C2C" : "transparent"

                                            Rectangle {
                                                anchors.top: parent.top
                                                anchors.left: parent.left; anchors.right: parent.right
                                                height: 1; color: "#222222"
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
                                                        font.family: appFont.name; font.pixelSize: 15; color: "#cccccc"
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
                           : currentMenu === "customPlaylist" ? "qrc:/qt/qml/JustSolo/data/image/PlayList.png"
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
                              : (settingsSubMenu === "lyricserver" ? "LyricServer管理"
                              : (settingsSubMenu === "appearance" ? "外观设置" : "关于JustSolo")))))
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
                        color: addMusicBtn.containsMouse ? "#4A4A4A" : "#333333"
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

                    // ---- 从音乐库导入（仅自定义列表页） ----
                    Rectangle {
                        Layout.preferredWidth: importLibBtnText.contentWidth + 28
                        Layout.preferredHeight: 36
                        radius: 6
                        color: importLibBtnMA.containsMouse ? "#5B9EF6" : "#3B82F6"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        visible: currentMenu === "customPlaylist" && musicManager.library.length > 0 && !_isCurrentArtistList()
                        Label {
                            id: importLibBtnText
                            anchors.centerIn: parent
                            text: "从音乐库导入"
                            font.family: appFont.name
                            font.pixelSize: 13
                            color: "#ddd"
                        }
                        MouseArea {
                            id: importLibBtnMA
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                _importTargetPlaylist = currentCustomPlaylistIndex
                                _buildAlreadyInPlaylistSet(_importTargetPlaylist)
                                _libSelectedSet = ({})
                                libSearchField.text = searchText  // 保持与全局搜索一致
                                _rebuildDialogLibrary()
                                libraryImportDialog.open()
                            }
                        }
                    }
                }

                // 欢迎页提示语（仅无菜单时显示）
                Label {
                    text: "点击左侧列表开始使用"
                    font.family: appFont.name; font.pixelSize: 15; color: "#888"
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
                        emptyHint: currentMenu === "customPlaylist" ? (_isCurrentArtistList() ? "此歌手暂无歌曲" : "此列表还没有歌曲") : "还没有音乐"
                        emptySubHint: currentMenu === "customPlaylist" ? (_isCurrentArtistList() ? "右键侧边栏列表可刷新歌曲" : "请到侧边栏右键本列表添加音乐") : "点击上方「添加音乐」导入本地文件"
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
                        // Loader 必须锚定父容器，否则默认 0×0，被加载的 SettingsPage 也会塌成 0×0
                        anchors.fill: parent
                        active: currentMenu === "settings"
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
            color: "#181818"

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
                    width: 320; height: 6; radius: 3; color: "#1E1E1E"
                    Layout.alignment: Qt.AlignHCenter
                    Rectangle {
                        height: parent.height; radius: 3; color: "#3B82F6"
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

    // 隐藏到系统托盘（音乐继续播放），由 onClosing 和托盘菜单共用
    function hideToTray() {
        _detailWasOpen = playerDetail.visible  // 记忆详情页状态，回到前台恢复
        mainWindow.hide()
        playerDetail.visible = false      // 关 ShaderEffectSource live
    }

    // ---- 关闭窗口 ----
    // 根据设置决定最小化到系统托盘（音乐继续播放）或真退出
    onClosing: function(close) {
        if (musicManager.minimizeToTray) {
            close.accepted = false
            hideToTray()
        } else {
            // 真退出：清理播放状态
            playerDetail.visible = false
            musicManager.stop()
            musicManager.shutdown()
        }
    }

    // 从托盘恢复 / 小窗退出时，播放主窗口出现动画并打开播放详情页
    onVisibleChanged: {
        if (!visible) {
            // 窗口进入后台（隐藏到托盘）：记住详情页是否打开
            if (playerDetail.visible)
                _detailWasOpen = true
            return
        }
        // 小窗退出：先销毁小窗再开详情页
        if (_miniWindow) {
            _miniWindow.destroy()
            _miniWindow = null
        }
        // 回到前台：若后台时详情页是打开的（或从小窗退出），自动拉回
        if (_pendingMiniExit || _detailWasOpen) {
            _pendingMiniExit = false
            _detailWasOpen = false
            // 用系统动画拉起主窗口后打开详情页
            showPlayerDetail = true
            playerDetail.reopen()
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
        color: "#181818"
        z: 101

        property double progressFraction: musicManager.duration > 0 ? musicManager.position / Math.max(1, musicManager.duration) : 0
        property int currentSeconds: Math.floor(musicManager.position / 1000)
        property int totalSeconds: Math.floor(musicManager.duration / 1000)

        // 吸顶进度条 (作为 playerBar 的上边框)
        Rectangle {
            id: barProgressTrack
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            // 悬浮或拖拽时高度增加到 5px，平时 3px
            height: (barSeekMA.containsMouse || barSeekMA.pressed) ? 5 : 3
            color: "#3A3A3A"
            z: 10

            opacity: (barSeekMA.containsMouse || barSeekMA.pressed) ? 1.0 : 0.4
            
            // 让高度变化有一个平滑的过渡动画
            Behavior on height { 
                NumberAnimation { duration: 150; easing.type: Easing.OutQuad } 
            }

            // 颜色渐变过渡动画
            Behavior on opacity {
                NumberAnimation { duration: 150 }
            }

            Rectangle {
                id: barProgressFill
                readonly property real autoRatio: Math.min(1, playerBar.progressFraction)
                width: parent.width * (barSeekMA.pressed ? barSeekMA._dragRatio : autoRatio)
                height: parent.height
                color: "#3B82F6"
                Behavior on width { 
                    NumberAnimation { duration: 300; easing.type: Easing.OutCubic } 
                }

                // 2. 拖动锚点
                Rectangle {
                    id: barThumb
                    width: 10
                    height: 10
                    radius: 5
                    color: "#f1f1f1"
                    
                    // 垂直居中于进度条，水平位置放在进度条的最右侧末端
                    anchors.verticalCenter: parent.verticalCenter
                    x: parent.width - width / 2 
                    
                    // 仅在鼠标悬浮或按下拖拽时显示
                    opacity: (barSeekMA.containsMouse || barSeekMA.pressed) ? 1 : 0
                    
                    // 显隐过渡动画
                    Behavior on opacity { 
                        NumberAnimation { duration: 150 } 
                    }
                }
            }

            // 悬浮时间进度
            Rectangle {
                id: hoverTimeTooltip
                width: hoverTimeText.contentWidth + 16
                height: 24
                radius: 6
                color: "#282828"
                border.color: "#3A3A3A"
                border.width: 1
                
                // 悬浮在进度条上方 12px
                y: -height - 12
                
                // X 轴跟随鼠标，并限制在进度条两端内不溢出
                property real rawX: barSeekMA.mouseX - width / 2
                x: Math.max(0, Math.min(barProgressTrack.width - width, rawX))

                // 仅在鼠标悬浮或按住拖拽时显示
                opacity: (barSeekMA.containsMouse || barSeekMA.pressed) ? 1.0 : 0.0
                
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on x { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }

                Label {
                    id: hoverTimeText
                    anchors.centerIn: parent
                    font.family: appFont.name
                    font.pixelSize: 12
                    font.bold: true
                    color: "#777777"            // 默认颜色（应用于 / 总时间 部分）
                    textFormat: Text.StyledText  // 开启富文本/样式文本支持

                    text: {
                        var totalSec = Math.floor(musicManager.duration / 1000)
                        if (totalSec <= 0) return "<font color='#ffffff'>00:00</font> / 00:00"

                        // 计算鼠标悬停位置对应的秒数
                        var hoverRatio = Math.max(0, Math.min(1, barSeekMA.mouseX / barProgressTrack.width))
                        var hoverSec = Math.floor((hoverRatio * musicManager.duration) / 1000)

                        // 格式化悬停时间 (XX:XX)
                        var m1 = Math.floor(hoverSec / 60)
                        var s1 = Math.floor(hoverSec % 60)
                        var curStr = (m1 < 10 ? "0" : "") + m1 + ":" + (s1 < 10 ? "0" : "") + s1

                        // 格式化总时长 (XX:XX)
                        var m2 = Math.floor(totalSec / 60)
                        var s2 = Math.floor(totalSec % 60)
                        var totStr = (m2 < 10 ? "0" : "") + m2 + ":" + (s2 < 10 ? "0" : "") + s2

                        // 使用 <font> 标签高亮当前时间为纯白 #ffffff，后面的 / totStr 继承默认的 #777777
                        return "<font color='#ffffff'>" + curStr + "</font> / " + totStr
                    }
                }
            }

            // 拖拽控制区
            MouseArea {
                id: barSeekMA
                anchors.fill: parent
                anchors.topMargin: -8 // 上下热区扩大，保证 hover 和拖拽的稳定性
                anchors.bottomMargin: -8
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

                onPressed: function(m) {
                    _trackW = barProgressTrack.width
                    seek(m.x)
                    if (!musicManager.isPlaying && musicManager.duration > 0)
                        musicManager.play()
                }
                onPositionChanged: function(m) { if (pressed) seek(m.x) }
                onClicked: function(m) {
                    seek(m.x)
                    if (!musicManager.isPlaying && musicManager.duration > 0)
                        musicManager.play()
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 0

            // ==========================================
        // 1. 左侧：封面 + 歌名/歌手 (靠左死死锚定)
        // ==========================================
        RowLayout {
            Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
            Layout.leftMargin: 16
            // 限制最大宽度为35%，防止歌名太长顶到中间按钮
            Layout.maximumWidth: mainWindow.width * 0.35
            spacing: 12

            Rectangle {
                id: playerCoverRect
                width: 48; height: 48; radius: 6; color: "#3A3A3A"

                Image {
                    anchors.fill: parent
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
                    layer.enabled: true
                    layer.effect: MultiEffect { maskEnabled: true; maskSource: coverMask }
                    Rectangle {
                        id: coverMask
                        anchors.fill: parent
                        radius: 6
                        visible: false
                        layer.enabled: true
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
                    onEntered: playerCoverRect.color = "#4A4A4A"
                    onExited: playerCoverRect.color = "#3A3A3A"
                    onClicked: {
                        // 详情页已打开 → 点击左下角封面退出；否则打开
                        if (playerDetail.visible) {
                            playerDetail.close()
                        } else if (musicManager.currentIndex >= 0) {
                            showPlayerDetail = true
                            playerDetail.reopen()
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label {
                    text: musicManager.currentTitle ? musicManager.currentTitle : "未在播放"
                    font.family: appFont.name
                    font.pixelSize: 16
                    font.bold: true
                    color: musicManager.currentTitle ? "#cccccc" : "#777"
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
                Label {
                    text: musicManager.currentArtist ? musicManager.currentArtist : "选择一首歌曲开始"
                    font.family: appFont.name
                    font.pixelSize: 13
                    font.bold: true
                    color: "#777"
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }
        }

        // ==========================================
        // 3. 右侧：音量控制区
        // ==========================================
        RowLayout {
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            Layout.rightMargin: 16
            spacing: 24

            // ---- 循环模式按钮 ----
            Item {
                id: modeBtnBar
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24

                property var modeIcons: ["mode_sequential.png", "mode_loop.png", "mode_single.png", "mode_shuffle.png", "mode_stop.png"]

                Image {
                    anchors.centerIn: parent
                    source: "qrc:/qt/qml/JustSolo/data/image/" + modeBtnBar.modeIcons[musicManager.playMode]
                    // 按钮图标跟随弹窗中对应的尺寸比例
                    width: musicManager.playMode === 0 ? 24 : (musicManager.playMode === 1 ? 22 : (musicManager.playMode === 4 ? 18 : 20))
                    height: musicManager.playMode === 0 ? 24 : (musicManager.playMode === 1 ? 22 : (musicManager.playMode === 4 ? 18 : 20))
                    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                    opacity: (modeMABar.containsMouse || modePopupBar.visible) ? 1.0 : 0.7
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                // 轮询检查，鼠标离开按钮和菜单 450ms 后关闭
                Timer {
                    id: modeCloseTimer
                    interval: 150
                    repeat: true
                    running: false
                    property int missCount: 0
                    onTriggered: {
                        if (modeBgMABar.containsMouse || modeMABar.containsMouse) {
                            missCount = 0
                        } else {
                            missCount++
                            if (missCount >= 3) {
                                missCount = 0
                                stop()
                                modePopupBar.close()
                            }
                        }
                    }
                }

                MouseArea {
                    id: modeMABar
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        modeCloseTimer.stop()
                        modeCloseTimer.missCount = 0
                        modeCloseTimer.start()
                        modePopupBar.open()
                    }
                    onExited: {
                        // 不立即动作，让轮询定时器判断
                    }
                }

                Popup {
                    id: modePopupBar
                    x: -width - 12
                    y: parent.height / 2 - height / 2
                    padding: 6
                    closePolicy: Popup.CloseOnEscape  // 不自动关闭，由定时器管理

                    background: Rectangle {
                        radius: 8
                        color: "#222222"
                        border.color: "#3A3A3A"
                        border.width: 1
                        opacity: musicManager.menuOpacity || 0.8
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        // 菜单框内任意位置保持打开
                        MouseArea {
                            id: modeBgMABar
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                        }
                    }

                    contentItem: Row {
                        spacing: 6
                        height: 26  // 固定高度，以最大图标为基准
                        Repeater {
                            model: 5
                            Image {
                                source: "qrc:/qt/qml/JustSolo/data/image/" + modeBtnBar.modeIcons[index]
                                // index 0=顺序播放 最大，1=列表循环 次大，4=关闭循环 最小，2=单曲 3=随机 默认
                                sourceSize.width: index === 0 ? 26 : (index === 1 ? 24 : (index === 4 ? 20 : 22))
                                sourceSize.height: index === 0 ? 26 : (index === 1 ? 24 : (index === 4 ? 20 : 22))
                                width: index === 0 ? 26 : (index === 1 ? 24 : (index === 4 ? 20 : 22))
                                height: index === 0 ? 26 : (index === 1 ? 24 : (index === 4 ? 20 : 22))
                                y: (26 - height) / 2 - (index === 3 ? 1 : 0)  // 垂直居中，随机播放上移 1px
                                fillMode: Image.PreserveAspectFit
                                opacity: (itemMABar.containsMouse || musicManager.playMode === index) ? 1.0 : 0.65
                                // 选中项加亮度提升
                                layer.enabled: musicManager.playMode === index
                                layer.effect: MultiEffect { brightness: 0.12 }
                                Behavior on opacity { NumberAnimation { duration: 120 } }

                                MouseArea {
                                    id: itemMABar
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        musicManager.playMode = index
                                        modePopupBar.close()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                id: volumeBtn
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22

                Image {
                    anchors.centerIn: parent
                    source: "qrc:/qt/qml/JustSolo/data/image/volume-logo.png"
                    width: 20; height: 20
                    opacity: (volumeMA.containsMouse || volumePopup.visible) ? 1.0 : 0.7
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                // 轮询检查，鼠标离开按钮/弹窗/间隙/滑块拖拽区 450ms 后关闭
                Timer {
                    id: volCloseTimer
                    interval: 150
                    repeat: true
                    running: false
                    property int missCount: 0
                    onTriggered: {
                        if (popupHoverMA.containsMouse || volumeMA.containsMouse
                                || volBridgeMA.containsMouse || volDragMA.containsMouse) {
                            missCount = 0
                        } else {
                            missCount++
                            if (missCount >= 3) {
                                missCount = 0
                                stop()
                                volumePopup.close()
                            }
                        }
                    }
                }

                // 悬浮触发
                MouseArea {
                    id: volumeMA
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        volCloseTimer.stop()
                        volCloseTimer.missCount = 0
                        volCloseTimer.start()
                        volumePopup.open()
                    }
                    onExited: {
                        // 不立即动作，让轮询定时器判断
                    }
                }

                // 桥接按钮与弹窗之间的间隙（不拦截点击，仅用于保持弹窗打开判定）
                MouseArea {
                    id: volBridgeMA
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.top
                    width: 44
                    height: 12
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    cursorShape: Qt.ArrowCursor
                }

                // 竖向音量悬浮窗
                Popup {
                    id: volumePopup
                    x: (parent.width - width) / 2
                    y: -height - 12
                    width: 44
                    height: 160
                    padding: 0
                    closePolicy: Popup.CloseOnEscape

                    background: Rectangle {
                        radius: 8
                        color: "#222222"
                        border.color: "#3A3A3A"
                        border.width: 1
                        opacity: musicManager.volumeMenuOpacity || 0.8
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }

                    contentItem: Item {
                        anchors.fill: parent

                        // 捕获悬浮窗内的鼠标事件
                        MouseArea {
                            id: popupHoverMA
                            anchors.fill: parent
                            hoverEnabled: true
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.topMargin: 12
                            anchors.bottomMargin: 12
                            spacing: 8

                            // 顶部音量百分比
                            Label {
                                text: Math.round(musicManager.volume * 100) + "%"
                                font.family: appFont.name
                                font.pixelSize: 11
                                color: "#aaa"
                                Layout.alignment: Qt.AlignHCenter
                            }

                            // 竖向进度条
                            Item {
                                Layout.fillHeight: true
                                Layout.alignment: Qt.AlignHCenter
                                width: 12

                                Rectangle {
                                    id: volTrack
                                    anchors.centerIn: parent
                                    width: 4
                                    height: parent.height
                                    radius: width / 2
                                    color: "#3A3A3A"
                                    Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                                    // 填充部分
                                    Rectangle {
                                        id: volFill
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: parent.height * musicManager.volume
                                        radius: volTrack.radius
                                        color: "#3B82F6"

                                        // 拖拽滑块小白点
                                        Rectangle {
                                            width: 10; height: 10
                                            radius: 5
                                            color: "#f1f1f1"
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            y: -height / 2
                                            Behavior on opacity { NumberAnimation { duration: 150 } }
                                        }
                                    }
                                }

                                // 音量独立拖拽控制
                                MouseArea {
                                    id: volDragMA
                                    anchors.fill: parent
                                    anchors.margins: -12
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    preventStealing: true

                                    onEntered: {
                                        // 保持弹窗打开，轮询定时器会检测 containsMouse
                                    }
                                    onExited: {
                                        // 不立即动作，让轮询定时器判断
                                    }

                                    function updateVolume(my) {
                                        var ratio = 1.0 - Math.max(0, Math.min(1, my / height))
                                        musicManager.volume = ratio
                                    }

                                    onPressed: function(m) { volCloseTimer.stop(); volCloseTimer.missCount = 0; volCloseTimer.start(); volumePopup.open(); updateVolume(m.y) }
                                    onPositionChanged: function(m) { if (pressed) { volCloseTimer.stop(); volCloseTimer.missCount = 0; volCloseTimer.start(); volumePopup.open(); updateVolume(m.y) } }
                                    onClicked: function(m) { updateVolume(m.y) }
                                }
                            }
                        }
                    }
                }
            }
        }
        }

        // ==========================================
        // 2. 播放控制按钮 (在 playerBar 中绝对居中)
        // ==========================================
        Row {
            anchors.centerIn: parent
            spacing: 24
            z: 5  // 高于左右区域

            // 上一首
            Item {
                width: 22; height: 22
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    anchors.centerIn: parent
                    source: "qrc:/qt/qml/JustSolo/data/image/prve.png"
                    width: 22; height: 22
                    opacity: 0.8
                }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: musicManager.previous()
                }
            }

            // 播放 / 暂停
            Rectangle {
                width: 42; height: 42; radius: 21; color: "#3A3A3A"
                anchors.verticalCenter: parent.verticalCenter
                Behavior on color { ColorAnimation { duration: 120 } }
                Image {
                    source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                    width: 24; height: 24
                    anchors.centerIn: parent
                    opacity: musicManager.isPlaying ? 0 : 1
                    anchors.horizontalCenterOffset: 1
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                Image {
                    source: "qrc:/qt/qml/JustSolo/data/image/playing.png"
                    width: 24; height: 24
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

            // 下一首
            Item {
                width: 22; height: 22
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    anchors.centerIn: parent
                    source: "qrc:/qt/qml/JustSolo/data/image/next.png"
                    width: 22; height: 22
                    opacity: 0.8
                }
                MouseArea {
                    anchors.fill: parent; anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: musicManager.next()
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

        onEnterMiniMode: {
            mainWindow._enterMiniMode()
        }
    }

    // ============================================================
    // 迷你小窗组件（动态创建/销毁）
    // ============================================================
    Component {
        id: miniPlayerComponent
        MiniPlayer {
            fontFamily: appFont.name
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
            color: "#222222"
            radius: 10
            border.color: "#3A3A3A"
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
                font.pixelSize: 15
                color: "#ddd"
                verticalAlignment: TextInput.AlignVCenter
                background: Rectangle {
                    radius: 6
                    color: "#1E1E1E"
                    border.color: "#3A3A3A"
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
                    color: cancelMA.containsMouse ? "#333333" : "#1E1E1E"
                    border.color: "#3A3A3A"; border.width: 1
                    Label { text: "取消"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: cancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { listNameField.text = ""; createListDialog.close() }
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: confirmMA.containsMouse ? "#5B9EF6" : "#3B82F6"
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
            color: "#222222"
            radius: 10
            border.color: "#3A3A3A"
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
                font.pixelSize: 15
                color: "#ddd"
                background: Rectangle {
                    radius: 6
                    color: "#1E1E1E"
                    border.color: "#3A3A3A"
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
                    color: renameCancelMA.containsMouse ? "#333333" : "#1E1E1E"
                    border.color: "#3A3A3A"; border.width: 1
                    Label { text: "取消"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: renameCancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { renameField.text = ""; renameDialog.close() }
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: renameConfirmMA.containsMouse ? "#5B9EF6" : "#3B82F6"
                    Label { text: "确定"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#ddd" }
                    MouseArea {
                        id: renameConfirmMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: doRename()
                    }
                }
            }
        }
    }

    // ============================================================
    // LyricServer 第三方客户端连接通知对话框
    // ============================================================
    Dialog {
        id: lyricServerConnectDialog
        parent: Overlay.overlay
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: Math.min(parent.width * 0.7, 440)
        height: 200
        padding: 0

        Overlay.modal: Rectangle { color: "#80000000" }

        background: Rectangle { color: "#222222"; radius: 10 }

        contentItem: ColumnLayout {
            spacing: 0

            // 标题栏
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 10
                color: "#2C2C2C"
                Rectangle { width: parent.width; height: 10; color: "#2C2C2C"; anchors.bottom: parent.bottom }
                Rectangle { width: parent.width; height: 1; color: "#3A3A3A"; anchors.bottom: parent.bottom }

                Label {
                    anchors.centerIn: parent
                    text: "LyricServer连接"
                    font.family: appFont.name; font.pixelSize: 16; font.bold: true; color: "#ddd"
                }
            }

            // 正文
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.leftMargin: 24; Layout.rightMargin: 24; Layout.topMargin: 20; Layout.bottomMargin: 8
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    text: "检测到第三方客户端连接到了"
                    font.family: appFont.name; font.pixelSize: 14; color: "#ccc"
                    wrapMode: Text.WordWrap
                }

                Label {
                    Layout.fillWidth: true
                    text: "Just Solo LyricServer服务"
                    font.family: appFont.name; font.pixelSize: 14; color: "#ccc"
                    wrapMode: Text.WordWrap
                }

                Label {
                    Layout.fillWidth: true
                    text: "客户端名称：<font color='#00d4ff'>" + mainWindow._connectedClientName + "</font>"
                    textFormat: Text.RichText
                    font.family: appFont.name; font.pixelSize: 14; color: "#ccc"
                    wrapMode: Text.WordWrap
                }
            }

            // 底部按钮
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 52; radius: 10
                color: "#222222"
                Rectangle { width: parent.width; height: 10; color: "#222222"; anchors.top: parent.top }
                Rectangle { width: parent.width; height: 1; color: "#3A3A3A"; anchors.top: parent.top }

                RowLayout {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 16; spacing: 10

                    Rectangle {
                        Layout.preferredHeight: 34; Layout.preferredWidth: 80; radius: 6
                        color: lsConnectOkMA.containsMouse ? "#333333" : "#1E1E1E"
                        border.color: "#3A3A3A"; border.width: 1
                        Label { anchors.centerIn: parent; text: "确定"; font.family: appFont.name; font.pixelSize: 13; color: "#ccc" }
                        MouseArea {
                            id: lsConnectOkMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: lyricServerConnectDialog.close()
                        }
                    }
                }
            }
        }
    }

    // ============================================================
    // 歌手选择对话框
    // ============================================================
    Dialog {
        id: artistSelectDialog
        parent: Overlay.overlay
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: Math.min(parent.width * 0.8, 540)
        height: Math.min(parent.height * 0.8, 460)
        padding: 0

        Overlay.modal: Rectangle { color: "#80000000" }

        background: Rectangle { color: "#222222"; radius: 10 }

        contentItem: ColumnLayout {
            spacing: 0

            // 标题栏
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 10
                color: "#2C2C2C"
                Rectangle { width: parent.width; height: 10; color: "#2C2C2C"; anchors.bottom: parent.bottom }
                Rectangle { width: parent.width; height: 1; color: "#3A3A3A"; anchors.bottom: parent.bottom }

                RowLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 8
                    Label {
                        text: "选择歌手"
                        font.family: appFont.name; font.pixelSize: 16; font.bold: true; color: "#ddd"
                        Layout.fillWidth: true
                    }
                    Label {
                        text: {
                            var _ = mainWindow._artistPlaylistIndices
                            return mainWindow._artistPlaylistIndices.length > 0 ? "已添加 " + mainWindow._artistPlaylistIndices.length + " 个" : ""
                        }
                        font.family: appFont.name; font.pixelSize: 12; color: "#00d4ff"
                        visible: mainWindow._artistPlaylistIndices.length > 0
                    }
                }
            }

            // 搜索栏
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 52
                color: "#1E1E1E"
                RowLayout {
                    anchors.fill: parent; anchors.margins: 8; spacing: 8
                    TextField {
                        id: artistSearchField
                        Layout.fillWidth: true; Layout.preferredHeight: 36
                        placeholderText: "搜索歌手..."
                        placeholderTextColor: "#888"
                        font.family: appFont.name; font.pixelSize: 13; color: "#ddd"
                        leftPadding: 10; rightPadding: 10
                        verticalAlignment: TextInput.AlignVCenter
                        background: Rectangle { radius: 6; color: "#333333"; border.color: "#3A3A3A" }
                        onTextChanged: {
                            var query = text.toLowerCase().trim()
                            var all = musicManager.availableArtists()
                            if (!query) {
                                mainWindow._artistDialogFilter = all
                                return
                            }
                            var result = []
                            for (var i = 0; i < all.length; i++) {
                                if (all[i].toLowerCase().indexOf(query) >= 0)
                                    result.push(all[i])
                            }
                            mainWindow._artistDialogFilter = result
                        }
                    }
                }
            }

            // 歌手列表
            ListView {
                id: artistDlgListView
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.topMargin: 4
                spacing: 1; clip: true
                model: _artistDialogFilter

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded; width: 10
                    background: Rectangle { implicitWidth: 10; radius: 5; color: "#222222" }
                    contentItem: Rectangle {
                        implicitWidth: 10; radius: 5
                        color: arThumbHover.containsMouse ? "#777777" : "#3A3A3A"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        MouseArea {
                            id: arThumbHover
                            hoverEnabled: true; acceptedButtons: Qt.NoButton
                            propagateComposedEvents: true
                        }
                    }
                }

                // 空结果提示
                Label {
                    anchors.centerIn: parent
                    text: artistSearchField.text.trim() ? "未找到匹配的歌手" : (musicManager.library.length === 0 ? "音乐库为空" : "未找到歌手")
                    font.family: appFont.name; font.pixelSize: 15; color: "#888"
                    visible: _artistDialogFilter.length === 0
                }

                delegate: Rectangle {
                    id: arItemRoot
                    width: artistDlgListView.width; height: 44; color: "transparent"

                    readonly property bool _added: mainWindow._existingArtistNames[modelData] === true

                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10

                        // 歌手图标
                        Rectangle {
                            Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 4
                            color: arItemRoot._added ? "#1E1E1E" : "#2C2C2C"
                            Label {
                                anchors.centerIn: parent
                                text: "🎤"
                                font.pixelSize: 15
                                opacity: arItemRoot._added ? 0.4 : 1.0
                            }
                        }

                        // 歌手名
                        Label {
                            Layout.fillWidth: true
                            text: modelData
                            font.family: appFont.name; font.pixelSize: 13
                            color: arItemRoot._added ? "#666" : "#ccc"
                            elide: Text.ElideRight
                        }

                        // 已添加标记
                        Label {
                            text: "已添加"
                            font.family: appFont.name; font.pixelSize: 11; color: "#00d4ff"
                            visible: arItemRoot._added
                        }
                    }

                    // hover 背景
                    Rectangle {
                        anchors.fill: parent
                        color: arDlgMA.containsMouse ? "#2C2C2C" : "transparent"
                        z: -1
                    }

                    // 点击处理
                    MouseArea {
                        id: arDlgMA
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: arItemRoot._added ? Qt.ArrowCursor : Qt.PointingHandCursor
                        enabled: !arItemRoot._added
                        onClicked: {
                            musicManager.createArtistPlaylist(modelData)
                            artistSelectDialog.close()
                        }
                    }
                }
            }

            // 底部按钮
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 52; radius: 10
                color: "#222222"
                Rectangle { width: parent.width; height: 10; color: "#222222"; anchors.top: parent.top }
                Rectangle { width: parent.width; height: 1; color: "#3A3A3A"; anchors.top: parent.top }

                RowLayout {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 16; spacing: 10

                    Rectangle {
                        Layout.preferredHeight: 34; Layout.preferredWidth: 80; radius: 6
                        color: artistDlgCancelMA.containsMouse ? "#333333" : "#1E1E1E"
                        border.color: "#3A3A3A"; border.width: 1
                        Label { anchors.centerIn: parent; text: "关闭"; font.family: appFont.name; font.pixelSize: 13; color: "#999" }
                        MouseArea {
                            id: artistDlgCancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: artistSelectDialog.close()
                        }
                    }
                }
            }
        }
    }

    // ============================================================
    // 从音乐库导入对话框
    // ============================================================
    Dialog {
        id: libraryImportDialog
        parent: Overlay.overlay
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: Math.min(parent.width * 0.8, 540)
        height: Math.min(parent.height * 0.8, 460)
        padding: 0

        Overlay.modal: Rectangle { color: "#80000000" }

        background: Rectangle { color: "#222222"; radius: 10 }

        contentItem: ColumnLayout {
            spacing: 0

            // 标题栏
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 48; radius: 10
                color: "#2C2C2C"
                Rectangle { width: parent.width; height: 10; color: "#2C2C2C"; anchors.bottom: parent.bottom }
                Rectangle { width: parent.width; height: 1; color: "#3A3A3A"; anchors.bottom: parent.bottom }

                RowLayout {
                    anchors.fill: parent; anchors.margins: 16; spacing: 8
                    Label {
                        text: "从音乐库导入"
                        font.family: appFont.name; font.pixelSize: 16; font.bold: true; color: "#ddd"
                        Layout.fillWidth: true
                    }
                    Label {
                        text: {
                            var _ = mainWindow._libSelectedVersion
                            var c = mainWindow._countLibSelected()
                            return c > 0 ? "已选 " + c + " 首" : ""
                        }
                        font.family: appFont.name; font.pixelSize: 12; color: "#00d4ff"
                        visible: {
                            mainWindow._libSelectedVersion
                            mainWindow._countLibSelected() > 0
                        }
                    }
                }
            }

            // 搜索栏
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 52
                color: "#1E1E1E"
                RowLayout {
                    anchors.fill: parent; anchors.margins: 8; spacing: 8
                    TextField {
                        id: libSearchField
                        Layout.fillWidth: true; Layout.preferredHeight: 36
                        placeholderText: "搜索歌曲或歌手..."
                        placeholderTextColor: "#888"
                        font.family: appFont.name; font.pixelSize: 13; color: "#ddd"
                        leftPadding: 10; rightPadding: 10
                        verticalAlignment: TextInput.AlignVCenter
                        background: Rectangle { radius: 6; color: "#333333"; border.color: "#3A3A3A" }
                        onTextChanged: {
                            // 独立过滤，不碰全局 searchText/updateSearch
                            var query = text.toLowerCase().trim()
                            var lib = musicManager.library
                            if (!query) {
                                mainWindow._libFilteredModel = lib.slice()
                                return
                            }
                            var result = []
                            for (var i = 0; i < lib.length; i++) {
                                var name = (lib[i].title || lib[i].name || "").toLowerCase()
                                var artist = (lib[i].artist || "").toLowerCase()
                                var album = (lib[i].album || "").toLowerCase()
                                if (name.indexOf(query) >= 0 || artist.indexOf(query) >= 0 || album.indexOf(query) >= 0)
                                    result.push(lib[i])
                            }
                            mainWindow._libFilteredModel = result
                        }
                    }
                    // 全选/取消
                    Rectangle {
                        Layout.preferredHeight: 28; Layout.preferredWidth: 50; radius: 6
                        color: selectAllMA.containsMouse ? "#4A4A4A" : "#333333"
                        Label {
                            anchors.centerIn: parent
                            text: {
                                if (_libFilteredModel.length === 0) return "全选"
                                var allSel = true
                                for (var i = 0; i < _libFilteredModel.length; i++) {
                                    var ri = musicManager.library.indexOf(_libFilteredModel[i])
                                    if (ri < 0) continue
                                    if (_libAlreadyInPlaylistSet[_libFilteredModel[i].path]) continue
                                    if (!_libSelectedSet[ri]) { allSel = false; break }
                                }
                                return allSel ? "取消" : "全选"
                            }
                            font.family: appFont.name; font.pixelSize: 12; color: "#ccc"
                        }
                        MouseArea {
                            id: selectAllMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: mainWindow._toggleLibSelectAll()
                        }
                    }
                }
            }

            // 歌曲列表
            ListView {
                id: libSongListView
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.topMargin: 4
                spacing: 1; clip: true
                model: _libFilteredModel

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded; width: 10
                    background: Rectangle { implicitWidth: 10; radius: 5; color: "#222222" }
                    contentItem: Rectangle {
                        implicitWidth: 10; radius: 5
                        color: libThumbHover.containsMouse ? "#777777" : "#3A3A3A"
                        Behavior on color { ColorAnimation { duration: 150 } }
                        MouseArea {
                            id: libThumbHover
                            hoverEnabled: true; acceptedButtons: Qt.NoButton
                            propagateComposedEvents: true
                        }
                    }
                }

                // 空结果提示
                Label {
                    anchors.centerIn: parent
                    text: libSearchField.text.trim() ? "未找到匹配的歌曲" : "音乐库为空"
                    font.family: appFont.name; font.pixelSize: 15; color: "#888"
                    visible: _libFilteredModel.length === 0
                }

                delegate: Rectangle {
                    id: libItemRoot
                    width: libSongListView.width; height: 44; color: "transparent"

                    // 从 modelData 提取路径
                    readonly property string _dp: modelData ? (modelData.path || "") : ""

                    // 是否为已存在歌曲
                    readonly property bool _iai: _dp ? (_libAlreadyInPlaylistSet[_dp] === true) : false

                    // 选中状态（依赖 _libSelectedVersion 触发刷新）
                    readonly property bool _sel: {
                        mainWindow._libSelectedVersion
                        if (_iai) return false
                        // 不使用 _rli，直接用函数计算
                        var lib = musicManager.library
                        for (var i = 0; i < lib.length; i++) {
                            if (lib[i].path === _dp) return _libSelectedSet[i] === true
                        }
                        return false
                    }

                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10

                        // Checkbox
                        Rectangle {
                            Layout.preferredWidth: 20; Layout.preferredHeight: 20; radius: 4
                            color: libItemRoot._sel ? "#00d4ff" : "transparent"
                            border.color: libItemRoot._iai ? "#3A3A3A" : (libItemRoot._sel ? "#00d4ff" : "#666")
                            border.width: libItemRoot._sel ? 0 : 1
                            Label {
                                anchors.centerIn: parent
                                text: libItemRoot._sel ? "✓" : ""
                                font.pixelSize: 13; color: "#111"
                                visible: libItemRoot._sel
                            }
                        }

                        // 歌曲信息
                        ColumnLayout {
                            Layout.fillWidth: true; spacing: 2
                            Label {
                                text: modelData.title || modelData.name || "未知歌曲"
                                font.family: appFont.name; font.pixelSize: 13
                                color: libItemRoot._iai ? "#666" : "#ccc"
                                elide: Text.ElideRight; Layout.fillWidth: true
                            }
                            Label {
                                text: modelData.artist || "未知歌手"
                                font.family: appFont.name; font.pixelSize: 11
                                color: libItemRoot._iai ? "#3B82F6" : "#888"
                                elide: Text.ElideRight; Layout.fillWidth: true
                            }
                        }

                        // 已添加标记
                        Label {
                            text: "已添加"
                            font.family: appFont.name; font.pixelSize: 11; color: "#00d4ff"
                            visible: libItemRoot._iai
                        }
                    }

                    // 点击处理
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        enabled: !libItemRoot._iai
                        onClicked: {
                            var lib = musicManager.library
                            for (var i = 0; i < lib.length; i++) {
                                if (lib[i].path === libItemRoot._dp) {
                                    mainWindow._toggleLibSelect(i)
                                    break
                                }
                            }
                        }
                    }
                }
            }

            // 底部按钮
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 52; radius: 10
                color: "#222222"
                Rectangle { width: parent.width; height: 10; color: "#222222"; anchors.top: parent.top }
                Rectangle { width: parent.width; height: 1; color: "#3A3A3A"; anchors.top: parent.top }

                RowLayout {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 16; spacing: 10

                    Rectangle {
                        Layout.preferredHeight: 34; Layout.preferredWidth: 80; radius: 6
                        color: cancelImportMA.containsMouse ? "#333333" : "#1E1E1E"
                        border.color: "#3A3A3A"; border.width: 1
                        Label { anchors.centerIn: parent; text: "取消"; font.family: appFont.name; font.pixelSize: 13; color: "#999" }
                        MouseArea {
                            id: cancelImportMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { mainWindow._libSelectedSet = ({}); libraryImportDialog.close() }
                        }
                    }
                    Rectangle {
                        Layout.preferredHeight: 34; Layout.preferredWidth: 100; radius: 6
                        property bool _canImport: { mainWindow._libSelectedVersion; return mainWindow._countLibSelected() > 0 }
                        color: _canImport ? (confirmImportMA.containsMouse ? "#5B9EF6" : "#3B82F6") : "#1E1E1E"
                        border.color: _canImport ? "#3A3A3A" : "#3A3A3A"
                        border.width: 1
                        Label {
                            anchors.centerIn: parent
                            text: "确认导入"
                            font.family: appFont.name; font.pixelSize: 13
                            color: parent._canImport ? "#ddd" : "#666"
                        }
                        MouseArea {
                            id: confirmImportMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            enabled: parent._canImport
                            onClicked: mainWindow._doImport()
                        }
                    }
                }
            }
        }
    }

    // ---- WASAPI 独占启动失败提示 ----
    Connections {
        target: musicManager
        function onWasapiExclusiveFailed() {
            exclusiveDialog.open()
        }
    }

    // ---- 自定义列表变更时重建分类索引 ----
    Connections {
        target: musicManager
        function onCustomPlaylistsChanged() {
            mainWindow._rebuildPlaylistIndices()
        }
    }

    // ---- LyricServer 第三方客户端连接通知 ----
    Connections {
        target: lyricServer
        function onClientConnected(clientName) {
            mainWindow._connectedClientName = clientName
            lyricServerConnectDialog.open()
        }
    }

    // ---- 启动时初始化分类索引 ----
    Component.onCompleted: {
        _rebuildPlaylistIndices()
    }

    // ---- WASAPI 独占开启前提示（启动时保存了开启独占：先弹窗提示，确认后再开启） ----
    Connections {
        target: musicManager
        function onExclusiveConfirmRequested() {
            mainWindow.openExclusiveWarnDialog(function(ok) {
                if (ok)
                    musicManager.wasapiExclusive = true
                else
                    musicManager.disableWasapiExclusive()
            })
        }
    }

    Dialog {
        id: exclusiveDialog
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 460
        padding: 26

        Overlay.modal: Rectangle { color: "transparent" }

        background: Rectangle {
            color: "#222222"
            radius: 10
            border.color: "#3A3A3A"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 12

            Label {
                text: "无法开启 WASAPI 独占"
                font.family: appFont.name
                font.pixelSize: 17
                font.bold: true
                color: "#dddddd"
            }

            Label {
                text: "音频通道已被占用，无法正常开启 WASAPI 独占功能，请选择以下操作："
                font.family: appFont.name
                font.pixelSize: 13
                color: "#aaaaaa"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Label {
                text: "· 重新检测：重新检测音频通道被占用情况\n· 取消 WASAPI 独占模式，切换为共享模式\n· 强制开启 WASAPI 独占模式，可能会导致其他音视频软件崩溃"
                font.family: appFont.name
                font.pixelSize: 12
                color: "#888888"
                lineHeight: 1.6
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 10
                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 118; radius: 6
                    color: disableExclMA.containsMouse ? "#333333" : "#1E1E1E"
                    border.color: "#3A3A3A"; border.width: 1
                    Label { text: "关闭独占模式"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: disableExclMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            musicManager.disableWasapiExclusive()
                            exclusiveDialog.close()
                        }
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 88; radius: 6
                    color: retryExclMA.containsMouse ? "#5B9EF6" : "#3B82F6"
                    Label { text: "重新检测"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#ddd" }
                    MouseArea {
                        id: retryExclMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            exclusiveDialog.close()
                            musicManager.retryWasapiExclusive()  // 若仍失败，wasapiExclusiveFailed 信号会重新弹出
                        }
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 88; radius: 6
                    color: forceExclMA.containsMouse ? "#C96A4E" : "#B4543B"
                    Label { text: "强制开启"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#fff" }
                    MouseArea {
                        id: forceExclMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            exclusiveDialog.close()
                            musicManager.forceWasapiExclusive()  // 跳过探测强制开启，若仍失败信号会重新弹出
                        }
                    }
                }
            }
        }
    }

    // ---- WASAPI 独占开启前提示 ----
    property var exclusiveWarnCallback: null
    function openExclusiveWarnDialog(callback) {
        exclusiveWarnCallback = callback
        exclusiveWarnDialog.open()
    }

    Dialog {
        id: exclusiveWarnDialog
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 460
        padding: 26

        Overlay.modal: Rectangle { color: "transparent" }

        background: Rectangle {
            color: "#222222"
            radius: 10
            border.color: "#3A3A3A"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 12

            Label {
                text: "开启 WASAPI 独占模式"
                font.family: appFont.name
                font.pixelSize: 17
                font.bold: true
                color: "#dddddd"
            }

            Label {
                text: "本软件仅检测正在播放音频的软件，识别精确度有限，请确保已关闭全部音频设备。"
                font.family: appFont.name
                font.pixelSize: 13
                color: "#aaaaaa"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 10
                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 88; radius: 6
                    color: exclWarnCancelMA.containsMouse ? "#333333" : "#1E1E1E"
                    border.color: "#3A3A3A"; border.width: 1
                    Label { text: "取消"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: exclWarnCancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: exclusiveWarnDialog.close()
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 88; radius: 6
                    color: exclWarnOkMA.containsMouse ? "#5B9EF6" : "#3B82F6"
                    Label { text: "确定开启"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#fff" }
                    MouseArea {
                        id: exclWarnOkMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var cb = mainWindow.exclusiveWarnCallback
                            mainWindow.exclusiveWarnCallback = null
                            exclusiveWarnDialog.close()
                            if (cb) cb(true)
                        }
                    }
                }
            }
        }

        // 任何方式关闭（取消按钮/点击空白/Esc）都视为取消
        onClosed: {
            if (mainWindow.exclusiveWarnCallback) {
                var cb = mainWindow.exclusiveWarnCallback
                mainWindow.exclusiveWarnCallback = null
                cb(false)
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
        // 歌手列表放宽名称校验（允许空格、顿号等），普通列表严格校验
        var pl = musicManager.customPlaylists[mainWindow._rightClickedPlaylistIndex]
        var isArtist = pl && pl.type === "artist"
        if (!isArtist && !musicManager.isValidPlaylistName(name)) {
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

    // ---- 迷你小窗：进入迷你模式（从详情页按钮或托盘菜单调用） ----
    function _enterMiniMode() {
        if (typeof musicManager === "undefined" || !musicManager || musicManager.currentIndex < 0)
            return
        playerDetail.close()
        mainWindow.showPlayerDetail = false
        mainWindow.hide()
        if (mainWindow._miniWindow) {
            mainWindow._miniWindow.destroy()
            mainWindow._miniWindow = null
        }
        var obj = miniPlayerComponent.createObject(null, {fontFamily: appFont.name})
        mainWindow._miniWindow = obj
        obj.exitMiniMode.connect(function() {
            if (mainWindow._miniWindow) {
                mainWindow._miniWindow.destroy()
                mainWindow._miniWindow = null
            }
            mainWindow._pendingMiniExit = true
            mainWindow.show()
        })
        obj.show()
    }

    // ============================================================
    // 全局拖放区域 — 支持从资源管理器拖入音乐文件/文件夹
    // ============================================================
    DropArea {
        id: globalDropArea
        anchors.fill: parent
        z: 9999

        onEntered: function(drag) {
            if (drag.hasUrls) {
                drag.accepted = true
                dropOverlay.visible = true
            }
        }

        onExited: dropOverlay.visible = false

        onDropped: function(drop) {
            dropOverlay.visible = false
            if (!drop.hasUrls) return

            drop.accept(Qt.CopyAction)

            var files = [], folders = []
            for (var i = 0; i < drop.urls.length; i++) {
                var url = drop.urls[i].toString()
                var path = url.replace(/^file:\/\/\//, "")
                if (musicManager.isDirectory(path))
                    folders.push(path)
                else if (musicManager.isAudioFile(path))
                    files.push(path)
            }
            // 先处理文件夹再处理文件，避免异步竞争
            for (var j = 0; j < folders.length; j++)
                musicManager.addFolder(folders[j])
            if (files.length > 0)
                musicManager.addFiles(files)
        }
    }

    // ---- 拖放视觉反馈覆盖层 ----
    Rectangle {
        id: dropOverlay
        anchors.fill: parent
        z: 9998
        color: "#121212A0"
        visible: false

        Behavior on opacity { NumberAnimation { duration: 150 } }

        Rectangle {
            anchors.centerIn: parent
            width: 260; height: 200; radius: 20
            color: "#1e1e2e"
            border.color: "#00d4ff"
            border.width: 2

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 16

                Label {
                    text: "♫"
                    font.pixelSize: 48
                    color: "#00d4ff"
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: "放开添加音乐"
                    font.family: appFont.name
                    font.pixelSize: 16
                    color: "#cccccc"
                    Layout.alignment: Qt.AlignHCenter
                }
                Label {
                    text: "支持 .mp3 .flac .wav 等格式"
                    font.family: appFont.name
                    font.pixelSize: 12
                    color: "#888"
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
