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
    property string currentMenu: "home"           // 首页
    property string settingsSubMenu: "appearance"

    // ---- 播放详情页控制 ----
    property bool showPlayerDetail: false
    // 记忆详情页打开状态：窗口隐藏到后台时记录，回到前台自动恢复
    property bool _detailWasOpen: false

    // ---- 迷你小窗 ----
    property var _miniWindow: null
    property bool _pendingMiniExit: false
    // 退出至托盘后，下次从托盘恢复主窗口时自动打开播放详情页
    property bool _pendingDetailOnShow: false

    // ---- 自定义播放列表 ----
    property int currentCustomPlaylistIndex: -1
    property int _pendingAddToPlaylistIndex: -1   // 右键添加音乐的待定列表
    property int _rightClickedPlaylistIndex: -1   // 右键菜单的列表索引

    // ---- 自建歌单分类索引（复用 customPlaylists，歌手歌单 type="artist"） ----
    property var _artistPlaylistIndices: []    // 歌手歌单在 customPlaylists 中的索引
    property var _allPlaylistIndices: []       // 全部自建歌单索引（侧边栏合并显示用）
    property var _artistDialogFilter: []       // 歌手选择对话框的过滤后列表
    property string _pendingArtist: ""          // 歌手选择对话框中当前选中的歌手（空=未选中）
    property string _connectedClientName: ""  // LyricServer 连接的客户端名称
    property var _existingArtistNames: ({})    // 已创建歌手歌单的歌手名集合（去重标记）

    // ---- 排序模式 ----
    property string sortMode: "name"           // "name"=按名称, "time"=添加时间, "custom:N"=自定义排序
    property var _manualSortOrder: []          // 手动拖拽后的路径顺序（待保存）
    property bool _manualSortPending: false    // 是否存在待保存的手动排序
    property int _rightClickedSortIndex: -1    // 排序菜单中右键的自定义排序索引

    // 判断 customPlaylists 中某索引是否为歌手歌单
    function _isArtistList(index) {
        return index >= 0 && index < musicManager.customPlaylists.length
               && musicManager.customPlaylists[index].type === "artist"
    }

    function _rebuildPlaylistIndices() {
        var artist = []
        var all = []
        var existingArtists = ({})
        var lists = musicManager.customPlaylists
        for (var i = 0; i < lists.length; i++) {
            all.push(i)
            if (lists[i].type === "artist") {
                artist.push(i)
                existingArtists[lists[i].artist || lists[i].name || ""] = true
            }
        }
        _artistPlaylistIndices = artist
        _allPlaylistIndices = all
        _existingArtistNames = existingArtists
    }

    function _isCurrentArtistList() {
        if (currentMenu !== "customPlaylist" || currentCustomPlaylistIndex < 0) return false
        return _isArtistList(currentCustomPlaylistIndex)
    }

    // ============================================================
    // 排序模式辅助函数
    // ============================================================

    // 当前生效的自定义排序索引（-1 = 未处于自定义排序）
    function currentCustomSortIndex() {
        if (sortMode.indexOf("custom:") !== 0) return -1
        var idx = parseInt(sortMode.substring(7))
        if (isNaN(idx) || idx < 0 || idx >= musicManager.sortModes.length) return -1
        return idx
    }

    // 当前自定义排序的路径顺序
    function sortModeOrder() {
        var ci = currentCustomSortIndex()
        if (ci < 0) return []
        return musicManager.sortModes[ci].order || []
    }

    // 按路径顺序重排列表（未出现的路径按原顺序追加末尾）
    function reorderByPaths(list, order) {
        var byPath = {}
        for (var i = 0; i < list.length; i++)
            byPath[list[i].path] = list[i]
        var res = []
        var added = {}
        for (var j = 0; j < order.length; j++) {
            var p = order[j]
            if (byPath[p] && !added[p]) {
                res.push(byPath[p])
                added[p] = true
            }
        }
        for (var k = 0; k < list.length; k++) {
            if (!added[list[k].path]) res.push(list[k])
        }
        return res
    }

    // 按当前排序模式重排基础列表（返回新数组，不改动原数据）
    function applySortMode(list) {
        var arr
        if (sortMode === "name") {
            arr = list.slice()
            arr.sort(function(a, b) {
                var na = String(a.name || "").toLowerCase()
                var nb = String(b.name || "").toLowerCase()
                if (na !== nb) return na < nb ? -1 : 1
                var aa = String(a.artist || "").toLowerCase()
                var ab = String(b.artist || "").toLowerCase()
                if (aa !== ab) return aa < ab ? -1 : 1
                return 0
            })
            return arr
        }
        if (sortMode === "time") {
            arr = list.slice()
            arr.sort(function(a, b) {
                var ta = Number(a.addTime || 0)
                var tb = Number(b.addTime || 0)
                if (ta !== tb) return ta - tb
                return 0
            })
            return arr
        }
        return reorderByPaths(list, sortModeOrder())
    }

    // 显示用列表：有未保存的手动排序时优先显示手动顺序
    function displaySorted(base) {
        if (_manualSortPending) return reorderByPaths(base, _manualSortOrder)
        return applySortMode(base)
    }

    // 切换排序模式：有未保存的手动排序时先弹窗询问（丢弃/覆盖/新建）
    property string _pendingSortMode: "name"

    function applySort(mode) {
        if (_manualSortPending) {
            _pendingSortMode = mode
            sortMenu.close()
            saveSortDialog.open()
        } else {
            sortMode = mode
            sortMenu.close()
        }
    }

    // 丢弃未保存排序并直接切换到目标模式
    function applySortDirect(mode) {
        discardManualSort()
        sortMode = mode
        sortMenu.close()
        saveSortDialog.close()
    }

    // 放弃未保存的手动排序
    function discardManualSort() {
        _manualSortPending = false
        _manualSortOrder = []
    }

    // 手动拖拽排序（由 MusicListView.onReorderRequest 回调）
    // srcList 为当前页面的显示列表（排序后），缺省用所有音乐页
    function handleManualReorder(fromIdx, toIdx, srcList) {
        var list = srcList || allMusicPage.songList
        if (!list || fromIdx < 0 || toIdx < 0) return
        var paths = []
        for (var i = 0; i < list.length; i++) paths.push(list[i].path || "")
        // toIdx 允许等于 paths.length：即移动到列表末尾
        if (fromIdx >= paths.length || toIdx > paths.length) return
        var item = paths.splice(fromIdx, 1)[0]
        var adj = toIdx > fromIdx ? toIdx - 1 : toIdx
        paths.splice(adj, 0, item)
        _manualSortOrder = paths
        _manualSortPending = true
        // 不弹窗：显示歌曲列表上方的提示行等待用户选择
    }

    // 从提示行/弹窗打开新建排序窗口
    function openCreateSortDialog() {
        createSortField.text = ""
        createSortHint.text = ""
        createSortDialog.open()
    }

    // 保存新排序（新建成功后停在新排序）
    function doSaveNewSort() {
        var name = createSortField.text.trim()
        if (name.length === 0) return
        if (!musicManager.isValidSortName(name)) {
            createSortHint.text = "仅支持中英文、数字、- 和 _"
            return
        }
        var modes = musicManager.sortModes
        for (var i = 0; i < modes.length; i++) {
            if (modes[i].name === name) {
                createSortHint.text = "已存在同名排序"
                return
            }
        }
        musicManager.createSortMode(name, _manualSortOrder)
        // 新排序索引 = sortModes.length - 1
        sortMode = "custom:" + (musicManager.sortModes.length - 1)
        discardManualSort()
        createSortDialog.close()
        saveSortDialog.close()
    }

    // 覆盖现有排序（仅当前处于自定义排序时可用）
    // switchTo 可选：覆盖后切换到的排序模式（弹窗场景），内联提示行不传
    function doOverwriteSort(switchTo) {
        var ci = currentCustomSortIndex()
        if (ci < 0) return
        musicManager.updateSortModeOrder(ci, _manualSortOrder)
        discardManualSort()
        if (switchTo) sortMode = switchTo
        saveSortDialog.close()
    }

    // 重命名自定义排序
    function doRenameSort() {
        var name = sortRenameField.text.trim()
        var idx = _rightClickedSortIndex
        if (name.length === 0 || idx < 0 || idx >= musicManager.sortModes.length) return
        if (!musicManager.isValidSortName(name)) {
            sortRenameHint.text = "仅支持中英文、数字、- 和 _"
            return
        }
        for (var i = 0; i < musicManager.sortModes.length; i++) {
            if (i !== idx && musicManager.sortModes[i].name === name) {
                sortRenameHint.text = "已存在同名排序"
                return
            }
        }
        musicManager.renameSortMode(idx, name)
        sortRenameField.text = ""
        sortRenameDialog.close()
    }

    // 排序模式下点击歌曲：按路径映射到真实索引再播放
    // target: "library"（所有音乐）/ "custom"（自建歌单）/ "favorites"（收藏）
    function handleSortedLeftClick(index, target) {
        var dl = allMusicPage.songList
        if (target === "favorites") dl = favoritePage ? favoritePage.songList : []
        if (!dl || index < 0 || index >= dl.length) return
        var t = dl[index]
        if (!t) return
        var path = t.path || ""

        // 收藏页：映射到收藏真实索引
        if (target === "favorites") {
            var fav = musicManager.favorites
            var fi = -1
            for (var k = 0; k < fav.length; k++) {
                if ((fav[k].path || "") === path) { fi = k; break }
            }
            if (fi < 0) return
            if (musicManager.playlistSource === 1) {
                if (musicManager.currentIndex === fi) {
                    if (musicManager.isPlaying) musicManager.pause()
                    else musicManager.play()
                } else {
                    musicManager.playIndex(fi)
                }
            } else {
                if (musicManager.currentIndex < 0) {
                    musicManager.playlistSource = 1
                    musicManager.playIndex(fi)
                } else {
                    favoritePage.openSwitchDialog("switch", 1, fi)
                }
            }
            return
        }

        // 自建歌单
        if (target === "custom" && currentCustomPlaylistIndex >= 0) {
            var songs = musicManager.customPlaylists[currentCustomPlaylistIndex].songs || []
            var realIdx = -1
            for (var i = 0; i < songs.length; i++) {
                if ((songs[i].path || "") === path) { realIdx = i; break }
            }
            if (realIdx < 0) return
            var thisCustomIdx = 3 + currentCustomPlaylistIndex
            if (musicManager.currentIndex < 0) {
                musicManager.playCustomPlaylist(currentCustomPlaylistIndex, realIdx)
            } else if (musicManager.playingListIndex === thisCustomIdx) {
                if (musicManager.currentIndex === realIdx) {
                    if (musicManager.isPlaying) musicManager.pause()
                    else musicManager.play()
                } else {
                    musicManager.playCustomPlaylist(currentCustomPlaylistIndex, realIdx)
                }
            } else {
                allMusicPage.openSwitchDialog("custom", -1, realIdx)
            }
            return
        }

        // 所有音乐：映射到库真实索引
        var lib = musicManager.library
        var li = -1
        for (var j = 0; j < lib.length; j++) {
            if ((lib[j].path || "") === path) { li = j; break }
        }
        if (li < 0) return
        if (musicManager.playlistSource === 0) {
            if (path === allMusicPage.playingPath) {
                if (musicManager.isPlaying) musicManager.pause()
                else musicManager.play()
            } else {
                musicManager.playFromLibrary(li)
            }
        } else {
            if (musicManager.currentIndex < 0) {
                musicManager.playlistSource = 0
                musicManager.playFromLibrary(li)
            } else {
                allMusicPage.openSwitchDialog("home", -1, li)
            }
        }
    }

    // 搜索结果滚动：把库索引转换为当前排序显示索引
    function _sortScrollIndex() {
        if (searchScrollIndex < 0) return -1
        var lib = musicManager.library
        if (searchScrollIndex >= lib.length) return -1
        var path = lib[searchScrollIndex].path || ""
        if (!path) return -1
        var dl = allMusicPage ? allMusicPage.songList : []
        for (var i = 0; i < dl.length; i++) {
            if (dl[i].path === path) return i
        }
        return -1
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
        currentMenu = "allMusic"
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

    // 勾选某歌手的全部歌曲（用于从音乐库导入弹窗的「选择歌手」）
    function _selectLibSongsByArtist(artist) {
        var lib = musicManager.library
        for (var i = 0; i < lib.length; i++) {
            var p = lib[i].path || ""
            if (_libAlreadyInPlaylistSet[p]) continue
            if ((lib[i].artist || "") === artist)
                _libSelectedSet[i] = true
        }
        _libSelectedVersion++
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
                        spacing: 10
                        Layout.alignment: Qt.AlignHCenter
                        layoutDirection: Qt.LeftToRight

                        // 图标 + 标题整体水平居中
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
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
                }

                // ---- 分割线 ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 12
                    Layout.bottomMargin: 0
                    color: "#3A3A3A2B"
                }

                Item { Layout.preferredHeight: 6 } // 与下方分割线间距保持一致，按钮居中于上下线之间

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
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
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

                Item { Layout.preferredHeight: 2 }

                // ---- 分割线 ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    Layout.topMargin: 4
                    color: "#3A3A3A2B"
                }

                Item { Layout.preferredHeight: 2 }

                // ---- 主导航（非设置页可见） ----
                ColumnLayout {
                    // 嵌套的 Layout 必须声明 Layout.fillWidth: true，否则子项边界会失控
                    Layout.fillWidth: true
                    spacing: 5
                    visible: currentMenu !== "settings"

                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/home.png"
                        label: "首页"
                        iconSrcSize: 20
                        active: currentMenu === "home"
                        fontFamily: appFont.name
                        onClicked: currentMenu = "home"
                    }
                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/AllMusic.png"
                        label: "所有音乐"
                        iconSrcSize: 20
                        active: currentMenu === "allMusic"
                        fontFamily: appFont.name
                        onClicked: currentMenu = "allMusic"
                    }
                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/PlayList.png"
                        label: "播放列表"
                        iconSrcSize: 20
                        active: currentMenu === "playlist"
                        fontFamily: appFont.name
                        onClicked: currentMenu = "playlist"
                    }
                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/mylike.png"
                        label: "收藏"
                        iconSrcSize: 20
                        active: currentMenu === "favorite"
                        fontFamily: appFont.name
                        onClicked: currentMenu = "favorite"
                    }
                    NavItem {
                        iconSource: "qrc:/qt/qml/JustSolo/data/image/history.png"
                        label: "历史"
                        iconSrcSize: 20
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
                        label: "音乐库同步"
                        active: settingsSubMenu === "sync"
                        fontFamily: appFont.name
                        onClicked: settingsSubMenu = "sync"
                    }
                    SubNavItem {
                        label: "LyricServer管理"
                        active: settingsSubMenu === "lyricserver"
                        fontFamily: appFont.name
                        onClicked: settingsSubMenu = "lyricserver"
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
                            onClicked: currentMenu = "allMusic"
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

                // ---- 自建歌单板块标题 + 新建按钮 ----
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
                        text: "自建歌单"
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

                // ---- 自定义播放列表（含歌手歌单，按类型区分图标与右键菜单） ----
                ListView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: currentMenu !== "settings"
                    clip: true
                    spacing: 5
                    model: _allPlaylistIndices

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
                                    source: mainWindow._isArtistList(modelData)
                                        ? "qrc:/qt/qml/JustSolo/data/image/singer_list.png"
                                        : "qrc:/qt/qml/JustSolo/data/image/PlayList.png"
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
                                    if (mainWindow._isArtistList(modelData))
                                        arContextMenu.popup()
                                    else
                                        plContextMenu.popup()
                                } else {
                                    mainWindow.currentMenu = "customPlaylist"
                                    mainWindow.currentCustomPlaylistIndex = modelData
                                }
                            }
                        }

                        // 自定义歌单右键菜单
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
                                            plContextMenu.win.currentMenu = "allMusic"
                                            plContextMenu.win.currentCustomPlaylistIndex = -1
                                        }
                                    }
                                }
                            }
                        }

                        // 歌手歌单右键菜单
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
                                            arContextMenu.win.currentMenu = "allMusic"
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
                        id: searchBox
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
                                onTextChanged: {
                                    mainWindow.updateSearch(text)
                                    // 输入非空时实时刷新下拉，清空时收起
                                    if (text.trim().length > 0 && !musicManager.isLoading)
                                        searchPopup.open()
                                    else
                                        searchPopup.close()
                                }
                                onActiveFocusChanged: {
                                    // 获得焦点且有文字时弹出下拉；失去焦点时收起
                                    if (activeFocus) {
                                        if (text.trim().length > 0 && !musicManager.isLoading)
                                            searchPopup.open()
                                    } else {
                                        searchPopup.close()
                                    }
                                }

                                // 点击搜索框文字区域时弹出下拉（与 TextInput 光标定位共存）
                                TapHandler {
                                    onTapped: {
                                        searchInput.forceActiveFocus()
                                        if (searchInput.text.trim().length > 0 && !musicManager.isLoading)
                                            searchPopup.open()
                                    }
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

                        // 点击搜索框空白区域（图标/留白）时也弹出下拉
                        TapHandler {
                            onTapped: {
                                searchInput.forceActiveFocus()
                                if (searchInput.text.trim().length > 0 && !musicManager.isLoading)
                                    searchPopup.open()
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
                           : currentMenu === "allMusic" ? "qrc:/qt/qml/JustSolo/data/image/AllMusic.png"
                           : currentMenu === "playlist" ? "qrc:/qt/qml/JustSolo/data/image/PlayList.png"
                           : currentMenu === "favorite" ? "qrc:/qt/qml/JustSolo/data/image/mylike.png"
                           : currentMenu === "history" ? "qrc:/qt/qml/JustSolo/data/image/history.png"
                           : currentMenu === "customPlaylist" ? customPlaylistIcon()
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
                        text: currentMenu === "home" ? "主页"
                              : currentMenu === "allMusic" ? "所有音乐"
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

                    // ---- 排序修改提示行（标题与右侧按钮之间；不占歌曲列表空间） ----
                    RowLayout {
                        id: sortBannerRow
                        Layout.fillWidth: true
                        spacing: 8
                        Layout.alignment: Qt.AlignVCenter
                        visible: mainWindow._manualSortPending
                            && (currentMenu === "allMusic" || currentMenu === "customPlaylist" || currentMenu === "favorite")

                        Label {
                            text: "检测到列表排序修改，请选择："
                            font.family: appFont.name; font.pixelSize: 12; color: "#cccccc"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            horizontalAlignment: Text.AlignRight
                        }
                        // 覆盖（无现有自定义排序时置灰，只能新建）
                        Rectangle {
                            Layout.preferredHeight: 24; Layout.preferredWidth: 52; radius: 5
                            color: headerOverwriteMA.enabled
                                  ? (headerOverwriteMA.containsMouse ? "#5B9EF6" : "#3B82F6")
                                  : "#2A2A2A"
                            border.color: headerOverwriteMA.enabled ? "#3B82F6" : "#3A3A3A"
                            border.width: 1
                            opacity: headerOverwriteMA.enabled ? 1.0 : 0.5
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Label {
                                anchors.centerIn: parent
                                text: "覆盖"
                                font.family: appFont.name; font.pixelSize: 12
                                color: headerOverwriteMA.enabled ? "#eee" : "#888"
                            }
                            MouseArea {
                                id: headerOverwriteMA
                                anchors.fill: parent; hoverEnabled: true
                                enabled: mainWindow.currentCustomSortIndex() >= 0
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mainWindow.doOverwriteSort()
                            }
                        }
                        // 新建
                        Rectangle {
                            Layout.preferredHeight: 24; Layout.preferredWidth: 52; radius: 5
                            color: headerCreateMA.containsMouse ? "#5B9EF6" : "#3B82F6"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Label {
                                anchors.centerIn: parent
                                text: "新建"
                                font.family: appFont.name; font.pixelSize: 12
                                color: "#eee"
                            }
                            MouseArea {
                                id: headerCreateMA
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mainWindow.openCreateSortDialog()
                            }
                        }
                    }

                    // 排序提示行隐藏时占位（互斥，保证提示行贴右侧按钮）
                    Item {
                        Layout.fillWidth: true
                        visible: !sortBannerRow.visible
                    }

                    // ---- 清除播放列表按钮（仅播放列表页） ----
                    Rectangle {
                        Layout.preferredHeight: 28; radius: 6
                        Layout.preferredWidth: clearPlaylistText.contentWidth + 20
                        Layout.alignment: Qt.AlignVCenter
                        color: clearPlaylistMA.containsMouse ? "#4A4A4A" : "#333333"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        visible: currentMenu === "playlist"
                        Label {
                            id: clearPlaylistText
                            text: "清除播放列表"; font.family: appFont.name; font.pixelSize: 13; color: "#cccccc"
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
                        Layout.preferredHeight: 28; radius: 6
                        Layout.preferredWidth: clearBtnText.contentWidth + 20
                        Layout.alignment: Qt.AlignVCenter
                        color: clearBtnMA.containsMouse ? "#4A4A4A" : "#333333"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        visible: currentMenu === "history"
                        Label {
                            id: clearBtnText
                            text: "清除所有历史"; font.family: appFont.name; font.pixelSize: 13; color: "#cccccc"
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
                        Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignVCenter
                        radius: 6
                        color: addMusicBtn.containsMouse ? "#4A4A4A" : "#333333"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        visible: currentMenu === "allMusic"
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

                    // ---- 从音乐库导入（仅自建歌单页） ----
                    Rectangle {
                        Layout.preferredWidth: importLibBtnText.contentWidth + 28
                        Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignVCenter
                        radius: 6
                        color: importLibBtnMA.containsMouse ? "#4A4A4A" : "#333333"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        visible: currentMenu === "customPlaylist" && musicManager.library.length > 0 && !_isCurrentArtistList()
                        Label {
                            id: importLibBtnText
                            anchors.centerIn: parent
                            text: "从音乐库导入"
                            font.family: appFont.name
                            font.pixelSize: 13
                            color: "#cccccc"
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

                    // ---- 刷新歌曲按钮（仅歌手类型自建歌单） ----
                    Rectangle {
                        Layout.preferredWidth: refreshArtistText.contentWidth + 20
                        Layout.preferredHeight: 28; radius: 6
                        Layout.alignment: Qt.AlignVCenter
                        color: refreshArtistMA.containsMouse ? "#4A4A4A" : "#333333"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        visible: currentMenu === "customPlaylist" && _isCurrentArtistList()
                        Label {
                            id: refreshArtistText
                            text: "刷新歌曲"; font.family: appFont.name; font.pixelSize: 13; color: "#cccccc"
                            anchors.centerIn: parent
                        }
                        MouseArea {
                            id: refreshArtistMA
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: musicManager.refreshArtistPlaylist(currentCustomPlaylistIndex)
                        }
                    }

                    // ---- 排序按钮（所有音乐 / 自建歌单 / 收藏，放标题栏最右） ----
                    Rectangle {
                        Layout.preferredHeight: 28; radius: 6
                        Layout.preferredWidth: sortBtnText.contentWidth + 38
                        Layout.alignment: Qt.AlignVCenter
                        color: sortBtnMA.containsMouse || sortMenu.visible ? "#4A4A4A" : "#333333"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        visible: currentMenu === "allMusic" || currentMenu === "customPlaylist" || currentMenu === "favorite"
                        RowLayout {
                            anchors.centerIn: parent; spacing: 6
                            Image {
                                source: "qrc:/qt/qml/JustSolo/data/image/sort.png"
                                sourceSize.width: 14; sourceSize.height: 14
                                fillMode: Image.PreserveAspectFit
                            }
                            Label {
                                id: sortBtnText
                                text: "排序"
                                font.family: appFont.name; font.pixelSize: 13; color: "#cccccc"
                            }
                        }
                        MouseArea {
                            id: sortBtnMA
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // 只负责打开：第二次点击不再关闭菜单（关闭由点击菜单外部/选择项/Esc 处理）
                            onClicked: sortMenu.open()
                        }

                        // ---- 排序菜单弹窗 ----
                        Popup {
                            id: sortMenu
                            width: 200
                            x: parent.width - width
                            y: parent.height + 6
                            padding: 0
                            // 去掉 CloseOnPressOutside：由下方全窗口点击层负责关闭，
                            // 避免点击排序按钮时被"点击外部"逻辑误关
                            closePolicy: Popup.CloseOnEscape

                            background: Rectangle {
                                color: "#222222"
                                border.color: "#3A3A3A"
                                border.width: 1
                                radius: 8
                            }

                            contentItem: Column {
                                width: 200
                                spacing: 0

                                // ---- 按名称 ----
                                Rectangle {
                                    id: sortNameRow
                                    width: parent.width; height: 34
                                    color: sortNameRowMA.containsMouse ? "#333333" : "transparent"
                                    property bool active: mainWindow.sortMode === "name"
                                    RowLayout {
                                        anchors.left: parent.left; anchors.right: parent.right
                                        anchors.leftMargin: 12; anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                        Label {
                                            text: "按名称"; font.family: appFont.name; font.pixelSize: 13
                                            color: sortNameRow.active ? "#3B82F6" : "#cccccc"
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: "✓"; font.pixelSize: 12; color: "#3B82F6"
                                            visible: sortNameRow.active
                                        }
                                    }
                                    MouseArea {
                                        id: sortNameRowMA; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mainWindow.applySort("name")
                                    }
                                }

                                // ---- 添加时间 ----
                                Rectangle {
                                    id: sortTimeRow
                                    width: parent.width; height: 34
                                    color: sortTimeRowMA.containsMouse ? "#333333" : "transparent"
                                    property bool active: mainWindow.sortMode === "time"
                                    RowLayout {
                                        anchors.left: parent.left; anchors.right: parent.right
                                        anchors.leftMargin: 12; anchors.rightMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                        Label {
                                            text: "添加时间"; font.family: appFont.name; font.pixelSize: 13
                                            color: sortTimeRow.active ? "#3B82F6" : "#cccccc"
                                            Layout.fillWidth: true
                                        }
                                        Label {
                                            text: "✓"; font.pixelSize: 12; color: "#3B82F6"
                                            visible: sortTimeRow.active
                                        }
                                    }
                                    MouseArea {
                                        id: sortTimeRowMA; anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mainWindow.applySort("time")
                                    }
                                }

                                // ---- 分隔线 ----
                                Rectangle { width: parent.width; height: 1; color: "#3A3A3A" }

                                // ---- 自定义排序标题 ----
                                Rectangle {
                                    width: parent.width; height: 30
                                    color: "transparent"
                                    Label {
                                        anchors.left: parent.left; anchors.leftMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "自定义排序"
                                        font.family: appFont.name; font.pixelSize: 12
                                        color: "#888"
                                    }
                                }

                                // ---- 自定义排序列表（右键可重命名/删除） ----
                                ListView {
                                    id: customSortList
                                    width: parent.width
                                    height: musicManager.sortModes.length * 34
                                    model: musicManager.sortModes
                                    interactive: false
                                    delegate: Rectangle {
                                        id: sortRow
                                        width: customSortList.width; height: 34
                                        color: sortRowMA.containsMouse ? "#333333" : "transparent"
                                        readonly property bool active: mainWindow.sortMode === "custom:" + index

                                        RowLayout {
                                            anchors.left: parent.left; anchors.right: parent.right
                                            anchors.leftMargin: 12; anchors.rightMargin: 10
                                            anchors.verticalCenter: parent.verticalCenter; spacing: 6
                                            Label {
                                                text: modelData.name || ""
                                                font.family: appFont.name; font.pixelSize: 13
                                                color: sortRow.active ? "#3B82F6" : "#cccccc"
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Label {
                                                text: "✓"; font.pixelSize: 12; color: "#3B82F6"
                                                visible: sortRow.active
                                            }
                                        }
                                        MouseArea {
                                            id: sortRowMA
                                            anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                                            onClicked: function(mouse) {
                                                if (mouse.button === Qt.RightButton) {
                                                    mainWindow._rightClickedSortIndex = index
                                                    sortItemMenu.popup()
                                                } else {
                                                    mainWindow.applySort("custom:" + index)
                                                }
                                            }
                                        }
                                    }
                                }

                                // ---- 无自定义排序提示 ----
                                Label {
                                    width: parent.width; height: 30
                                    text: "暂无自定义排序"
                                    font.family: appFont.name; font.pixelSize: 12; color: "#666"
                                    verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                                    visible: musicManager.sortModes.length === 0
                                }

                                // ---- 底部提示 ----
                                Rectangle {
                                    width: parent.width; height: 1; color: "#3A3A3A"
                                    visible: musicManager.sortModes.length > 0
                                }
                                Label {
                                    width: parent.width; height: 28
                                    text: "拖动歌曲可手动调整顺序"
                                    font.family: appFont.name; font.pixelSize: 11; color: "#777"
                                    verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter
                                }
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: 16 }

                // ==================================================
                // 页面内容区（预创建所有页面，切换时只切换可见性，消除闪屏）
                // ==================================================
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // ---- 主页：首页封面墙 ----
                    HomePage {
                        anchors.fill: parent
                        active: currentMenu === "home"
                        fontFamily: appFont.name
                        // 封面墙跟随"当前播放/查看的列表"：
                        // playingListIndex 1=收藏 2=历史（实际播放列表是 favorites/history，playlist 属性≠）
                        // 0=音乐库、3+n=自定义列表（m_playlist 已是对应列表，playlist 属性即正确）
                        // 显示顺序跟随对应列表页：收藏/音乐库/自定义列表按当前排序模式重排（displaySorted），
                        // 历史页固定时间序不参与排序，保持原始顺序；播放时用 rawSourceList 映射回真实下标
                        sourceList: {
                            var pl = musicManager.playingListIndex
                            if (pl === 1) return mainWindow.displaySorted(musicManager.favorites)
                            if (pl === 2) return musicManager.history
                            return mainWindow.displaySorted(musicManager.playlist)
                        }
                        // 原始（未排序）列表：与 sourceList 同内容仅顺序不同，供主页把显示下标映射回播放列表真实下标
                        rawSourceList: {
                            var pl = musicManager.playingListIndex
                            if (pl === 1) return musicManager.favorites
                            if (pl === 2) return musicManager.history
                            return musicManager.playlist
                        }
                        // 列表名：跟随播放来源（自定义歌单用其名称，其余用固定名）
                        listName: {
                            var pl = musicManager.playingListIndex
                            if (pl === 1) return "收藏"
                            if (pl === 2) return "历史"
                            if (pl >= 3) {
                                var ci = pl - 3
                                if (ci >= 0 && ci < musicManager.customPlaylists.length)
                                    return musicManager.customPlaylists[ci].name || ""
                            }
                            return "所有音乐"   // 0=音乐库（默认）
                            // 1=收藏 2=历史 3+n=自定义列表
                        }
                    }

                    // 全局通用歌曲列表（所有音乐 & 自建列表共用）
                    AllMusicPage {
                        id: allMusicPage
                        anchors.fill: parent
                        visible: currentMenu === "allMusic" || currentMenu === "customPlaylist"
                        sidebarWidth: mainWindow.sidebarWidth
                        windowWidth: mainWindow.width
                        fontFamily: appFont.name
                        scrollToIndex: currentMenu === "allMusic" ? mainWindow._sortScrollIndex() : -1
                        customPlaylistIndex: currentMenu === "customPlaylist" ? currentCustomPlaylistIndex : -1
                        pageListIndex: currentMenu === "customPlaylist" ? 3 + currentCustomPlaylistIndex : 0
                        emptyHint: currentMenu === "customPlaylist" ? (_isCurrentArtistList() ? "此歌手暂无歌曲" : "此列表还没有歌曲") : "还没有音乐"
                        emptySubHint: currentMenu === "customPlaylist" ? (_isCurrentArtistList() ? "右键侧边栏列表可刷新歌曲" : "请到侧边栏右键本列表添加音乐") : "点击上方「添加音乐」导入本地文件"
                        // 排序模式：显示顺序按当前排序模式重排（不动底层数据）
                        songList: {
                            if (currentMenu === "customPlaylist" && currentCustomPlaylistIndex >= 0
                                && currentCustomPlaylistIndex < musicManager.customPlaylists.length) {
                                var raw = musicManager.customPlaylists[currentCustomPlaylistIndex].songs || []
                                var lib = musicManager.library
                                var base = []
                                for (var i = 0; i < raw.length; i++) {
                                    var path = raw[i].path || ""
                                    for (var j = 0; j < lib.length; j++) {
                                        if (lib[j].path === path) {
                                            base.push(lib[j])
                                            break
                                        }
                                    }
                                }
                                return mainWindow.displaySorted(base)
                            }
                            return mainWindow.displaySorted(musicManager.library)
                        }
                        // 排序模式下点击歌曲：按路径映射真实索引播放
                        onLeftClick: function(index) {
                            mainWindow.handleSortedLeftClick(index,
                                currentMenu === "customPlaylist" ? "custom" : "library")
                        }
                        // 排序模式下拖拽排序：由 mainWindow 接管（显示提示行等待保存/覆盖）
                        onReorderRequest: function(fromIdx, toIdx) {
                            mainWindow.handleManualReorder(fromIdx, toIdx, allMusicPage.songList)
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
                        id: favoritePage
                        anchors.fill: parent
                        visible: currentMenu === "favorite"
                        sidebarWidth: mainWindow.sidebarWidth
                        windowWidth: mainWindow.width
                        fontFamily: appFont.name
                        // 排序模式：显示顺序按当前排序模式重排（不动底层数据）
                        songList: mainWindow.displaySorted(musicManager.favorites)
                        // 排序模式：点击歌曲按路径映射到收藏真实索引再播放
                        onLeftClick: function(index) { mainWindow.handleSortedLeftClick(index, "favorites") }
                        // 排序模式：拖拽排序由 mainWindow 接管（显示提示行等待保存/覆盖）
                        onReorderRequest: function(fromIdx, toIdx) {
                            mainWindow.handleManualReorder(fromIdx, toIdx, favoritePage.songList)
                        }
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
            // 仅正常导入显示全屏覆盖层；同步扫描导入走右下角小卡片
            // ==================================================
            Loader {
                id: importOverlay
                anchors.fill: parent
                z: 10
                active: musicManager.isLoading && !musicManager.isSyncing
                sourceComponent: importOverlayComp
            }

            // ==================================================
            // 音乐库同步小卡片（右下角，同步扫描导入时显示，不遮挡界面）
            // ==================================================
            Loader {
                id: syncCard
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: 20
                anchors.bottomMargin: 18
                z: 20
                active: musicManager.isSyncing
                sourceComponent: syncCardComp
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

    // ---- 音乐库同步小卡片组件（右下角，进度条 + 计数，同步结束自动销毁） ----
    Component {
        id: syncCardComp
        Rectangle {
            width: 300
            height: 78
            radius: 10
            color: "#222222"
            border.color: "#3A3A3A"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Label {
                        text: "正在同步音乐库"
                        font.family: appFont.name
                        font.pixelSize: 14
                        color: "#ffffff"
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: {
                            var total = musicManager.importTotal
                            var done = musicManager.importProcessed
                            return total > 0 ? done + " / " + total : ""
                        }
                        font.family: appFont.name
                        font.pixelSize: 12
                        color: "#3B82F6"
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 6; radius: 3
                    color: "#3A3A3A"
                    Rectangle {
                        height: parent.height; radius: 3; color: "#3B82F6"
                        width: parent.width * musicManager.importProgress
                        Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }
                }
            }
        }
    }

    // 隐藏到系统托盘（音乐继续播放），由 onClosing 和托盘菜单共用
    function hideToTray() {
        _detailWasOpen = playerDetail.visible  // 记忆详情页状态，回到前台恢复
        _pendingDetailOnShow = true            // 本次退出到托盘：从托盘恢复时自动打开播放详情页
        // 若迷你小窗开着，一并退出（否则小窗残留，用户看到"退出到托盘失效"）
        if (_miniWindow) {
            _miniWindow.destroy()
            _miniWindow = null
        }
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
        // 回到前台：若后台时详情页是打开的（或从小窗退出、或退出至托盘后恢复），自动拉回
        if (_pendingMiniExit || _detailWasOpen || _pendingDetailOnShow) {
            _pendingMiniExit = false
            _detailWasOpen = false
            _pendingDetailOnShow = false
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

        // ---- 沉浸背景调色层：进入详情页立即变色，退出详情页先变回原色 ----
        // 进入：showPlayerDetail=true → playerDetail.visible=true 时控制栏立即显示沉浸色
        // 退出：PlayerDetailPage.close() 中延迟 50ms 将 showPlayerDetail 置 false，
        //       控制栏先变回原色，详情页关闭动画随后完成
        Rectangle {
            anchors.fill: parent
            visible: playerDetail.visible
                     && mainWindow.showPlayerDetail
                     && (typeof musicManager !== "undefined" && musicManager)
                     && musicManager.playbackBackground === 1

            // 主色调底层（与详情页沉浸背景同一取色源）
            Rectangle {
                anchors.fill: parent
                color: (typeof musicManager !== "undefined" && musicManager)
                       ? (musicManager.currentCoverColor || "#181818") : "#181818"
                Behavior on color { ColorAnimation { duration: 600 } }
            }

            // 渐变遮罩：顶部与详情页背景底部无缝衔接，底部仅轻微加深，避免发黑
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#70000000" }
                    GradientStop { position: 1.0; color: "#90000000" }
                }
            }
        }

        // 吸顶进度条 (作为 playerBar 的上边框)
        Rectangle {
            id: barProgressTrack
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            // 悬浮或拖拽时高度增加到 5px，平时 3px
            height: (barSeekMA.containsMouse || barSeekMA.pressed) ? 5 : 3
            color: "#555555"
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
                    color: "#ffffff"            // 默认颜色（应用于 / 总时间 部分）
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
                    cache: false   // 切歌换封面旧图立即释放，不进全局图片缓存
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
            // 收藏(28)、变速(24)、循环(24)、音量(22) 按钮统一间距（Layout spacing 17，压缩宽度以右移时长/收藏）
            spacing: 17

            // ---- 当前时长 / 总时长 ----
            Label {
                Layout.alignment: Qt.AlignVCenter
                font.family: appFont.name
                font.pixelSize: 13
                color: "#ffffff"
                text: {
                    // 引用 favorites 无关，此处仅触发 position/duration 变化时刷新
                    var curSec = Math.floor(musicManager.position / 1000)
                    var totSec = Math.floor(musicManager.duration / 1000)
                    function fmt(s) {
                        if (s < 0) s = 0
                        var m = Math.floor(s / 60)
                        var ss = Math.floor(s % 60)
                        return (m < 10 ? "0" : "") + m + ":" + (ss < 10 ? "0" : "") + ss
                    }
                    return "<font color='#ffffff'>" + fmt(curSec) + "</font> / " + fmt(totSec)
                }
                textFormat: Text.StyledText
            }

            // ---- 收藏按钮 ----
            Item {
                id: favBtnBar
                Layout.preferredWidth: 28
                Layout.preferredHeight: 36

                // 当前曲目是否已收藏（引用 favorites 触发刷新）
                property bool isFav: {
                    musicManager.favorites
                    return musicManager.currentPath !== "" && musicManager.isCurrentFavorite()
                }

                Image {
                    anchors.centerIn: parent
                    source: favBtnBar.isFav
                        ? "qrc:/qt/qml/JustSolo/data/image/mylike-on.png"
                        : "qrc:/qt/qml/JustSolo/data/image/mylike-off.png"
                    width: 28; height: 28
                    opacity: (favMABar.containsMouse || favBtnBar.isFav) ? 1.0 : 0.7
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    id: favMABar
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: musicManager.currentPath !== ""
                    onClicked: musicManager.toggleCurrentFavorite()
                }
            }

            // ---- 变速按钮（循环按钮左侧） ----
            Item {
                id: speedBtnBar
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24

                Image {
                    anchors.centerIn: parent
                    source: "qrc:/qt/qml/JustSolo/data/image/speed_change.png"
                    width: 18; height: 18
                    opacity: (speedMABar.containsMouse || speedPopup.visible) ? 1.0 : 0.7
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    // 图标提亮为纯白
                    layer.enabled: true
                    layer.effect: MultiEffect { brightness: 1.0 }
                }

                // 轮询检查，鼠标离开按钮和菜单 450ms 后关闭
                Timer {
                    id: speedCloseTimer
                    interval: 150
                    repeat: true
                    running: false
                    property int missCount: 0
                    onTriggered: {
                        if (speedBgMA.containsMouse || speedMABar.containsMouse
                                || speedSlider.pressed || speedSlider.hovered
                                || speedContentHover.hovered) {
                            missCount = 0
                        } else {
                            missCount++
                            if (missCount >= 3) {
                                missCount = 0
                                stop()
                                speedPopup.close()
                            }
                        }
                    }
                }

                MouseArea {
                    id: speedMABar
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        speedCloseTimer.stop()
                        speedCloseTimer.missCount = 0
                        speedCloseTimer.start()
                        speedPopup.open()
                    }
                    onExited: {
                        // 不立即动作，让轮询定时器判断
                    }
                }

                Popup {
                    id: speedPopup
                    x: (parent.width - width) / 2
                    y: -height - 12
                    padding: 6
                    closePolicy: Popup.CloseOnEscape  // 不自动关闭，由定时器管理

                    background: Rectangle {
                        radius: 8
                        color: "#222222"
                        border.color: "#3A3A3A"
                        border.width: 1
                        opacity: musicManager.speedMenuOpacity || 0.8
                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        // 菜单框内任意位置保持打开
                        MouseArea {
                            id: speedBgMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                        }
                    }

                    contentItem: Column {
                        width: 200
                        spacing: 8

                        // 检测整个内容区域的 hover（不拦截事件，保障 Slider/档位按钮交互）
                        HoverHandler {
                            id: speedContentHover
                        }

                        // 标题行：变速 + 当前倍率
                        RowLayout {
                            width: parent.width
                            spacing: 6
                            Label {
                                text: "变速"
                                font.family: appFont.name
                                font.pixelSize: 13
                                color: "#aaaaaa"
                            }
                            Item { Layout.fillWidth: true }
                            Label {
                                text: Math.round(musicManager.playbackRate * 100) + "%"
                                font.family: appFont.name
                                font.pixelSize: 13
                                font.bold: true
                                color: "#3B82F6"
                            }
                        }

                        // 无极调节滑块 0.5x ~ 2.0x
                        Slider {
                            id: speedSlider
                            width: parent.width
                            from: 0.5; to: 2.0; stepSize: 0.01
                            value: musicManager.playbackRate
                            hoverEnabled: true  // 启用 hovered，供自动关闭判定使用
                            onMoved: musicManager.playbackRate = value

                            background: Rectangle {
                                x: 0; y: parent.height / 2 - 2
                                width: parent.width; height: 4; radius: 2; color: "#3A3A3A"
                            }
                            contentItem: Rectangle {
                                width: parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from)
                                height: 4; radius: 2; color: "#3B82F6"
                            }
                            handle: Rectangle {
                                x: parent.leftPadding + parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from) - width / 2
                                y: parent.height / 2 - height / 2
                                width: 14; height: 14; radius: 7; color: "#3B82F6"
                            }
                        }

                        // 快捷档位
                        Row {
                            spacing: 6
                            Repeater {
                                model: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                                Rectangle {
                                    readonly property bool isCurrent: Math.abs(musicManager.playbackRate - modelData) < 0.001
                                    width: 34
                                    height: 22
                                    radius: 4
                                    color: speedPresetMA.containsMouse ? "#333333" : (isCurrent ? "#2C2C2C" : "transparent")

                                    Label {
                                        anchors.centerIn: parent
                                        text: String(modelData) + "x"
                                        font.family: appFont.name
                                        font.pixelSize: 11
                                        color: isCurrent ? "#3B82F6" : "#cccccc"
                                    }
                                    MouseArea {
                                        id: speedPresetMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            musicManager.playbackRate = modelData
                                        }
                                    }
                                }
                            }
                        }

                        // 分隔线 + 音调补偿开关
                        Rectangle {
                            width: parent.width
                            height: 1
                            color: "#333333"
                        }
                        RowLayout {
                            width: parent.width
                            spacing: 6
                            Label {
                                text: "音调补偿"
                                font.family: appFont.name
                                font.pixelSize: 13
                                color: "#cccccc"
                            }
                            Item { Layout.fillWidth: true }
                            Switch {
                                checked: musicManager.pitchCompensation
                                onToggled: musicManager.pitchCompensation = checked

                                indicator: Rectangle {
                                    implicitWidth: 34
                                    implicitHeight: 20
                                    x: parent.leftPadding
                                    y: parent.topPadding + (parent.availableHeight - height) / 2
                                    radius: 10
                                    color: parent.checked ? "#3B82F6" : "#555"
                                    border.color: parent.checked ? "#3B82F6" : "#444"
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    Rectangle {
                                        x: parent.checked ? parent.width - width - 2 : 2
                                        y: (parent.height - height) / 2
                                        width: 16; height: 16; radius: 8
                                        color: "#fff"
                                        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                    }
                                }
                            }
                        }
                    }
                }
            }

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
                    // 图标提亮为纯白
                    layer.enabled: true
                    layer.effect: MultiEffect { brightness: 1.0 }
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
                    x: (parent.width - width) / 2
                    y: -height - 12
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
                    // 图标提亮为纯白
                    layer.enabled: true
                    layer.effect: MultiEffect { brightness: 1.0 }
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
            Item {
                width: 32; height: 32
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    source: "qrc:/qt/qml/JustSolo/data/image/play.png"
                    width: 36; height: 36
                    anchors.centerIn: parent
                    opacity: musicManager.isPlaying ? 0 : 1
                    anchors.horizontalCenterOffset: 1
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }
                Image {
                    source: "qrc:/qt/qml/JustSolo/data/image/playing.png"
                    width: 32; height: 32
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
    // 创建新列表对话框（选择类型：自定义歌单 / 歌手歌单）
    // ============================================================
    Dialog {
        id: createListDialog
        parent: Overlay.overlay
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: Math.min(parent.width * 0.8, 540)
        height: Math.min(parent.height * 0.8, 460)
        padding: 0

        property string _createListType: "custom"   // custom=自定义歌单, artist=歌手歌单
        property bool _canCreate: _createListType === "artist" || listNameField.text.trim().length > 0

        Overlay.modal: Rectangle { color: "#80000000" }

        background: Rectangle { color: "#222222"; radius: 10 }

        onOpened: {
            _createListType = "custom"
            listNameField.text = ""
            createNameHint.text = ""
            listNameField.forceActiveFocus()
        }

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
                        text: "创建列表"
                        font.family: appFont.name; font.pixelSize: 16; font.bold: true; color: "#ddd"
                        Layout.fillWidth: true
                    }
                    Label {
                        text: createListDialog._createListType === "artist" ? "歌手歌单" : "自定义歌单"
                        font.family: appFont.name; font.pixelSize: 12; color: "#00d4ff"
                    }
                }
            }

            // 内容区
            ColumnLayout {
                Layout.fillWidth: true; Layout.fillHeight: true
                Layout.leftMargin: 28; Layout.rightMargin: 28
                Layout.topMargin: 30; Layout.bottomMargin: 12
                spacing: 20

                // 类型选择卡片
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 16

                    Rectangle {
                        Layout.preferredWidth: 220; Layout.preferredHeight: 92
                        Layout.alignment: Qt.AlignHCenter
                        radius: 8
                        color: createListDialog._createListType === "custom" ? "#2C2C2C" : "#1E1E1E"
                        border.color: createListDialog._createListType === "custom" ? "#3B82F6" : "#3A3A3A"
                        border.width: createListDialog._createListType === "custom" ? 2 : 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 12
                            Rectangle {
                                Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: 8; color: "#1E1E1E"
                                Image {
                                    anchors.centerIn: parent
                                    source: "qrc:/qt/qml/JustSolo/data/image/PlayList.png"
                                    sourceSize.width: 26; sourceSize.height: 26
                                }
                            }
                            Column {
                                spacing: 3
                                Label {
                                    text: "自定义歌单"
                                    font.family: appFont.name; font.pixelSize: 15; font.bold: true
                                    color: createListDialog._createListType === "custom" ? "#3B82F6" : "#cccccc"
                                }
                                Label {
                                    text: "手动添加与管理音乐"
                                    font.family: appFont.name; font.pixelSize: 11; color: "#888"
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: createListDialog._createListType = "custom"
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 220; Layout.preferredHeight: 92
                        Layout.alignment: Qt.AlignHCenter
                        radius: 8
                        color: createListDialog._createListType === "artist" ? "#2C2C2C" : "#1E1E1E"
                        border.color: createListDialog._createListType === "artist" ? "#3B82F6" : "#3A3A3A"
                        border.width: createListDialog._createListType === "artist" ? 2 : 1

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 12
                            Rectangle {
                                Layout.preferredWidth: 40; Layout.preferredHeight: 40; radius: 8; color: "#1E1E1E"
                                Image {
                                    anchors.centerIn: parent
                                    source: "qrc:/qt/qml/JustSolo/data/image/singer_list.png"
                                    sourceSize.width: 26; sourceSize.height: 26
                                }
                            }
                            Column {
                                spacing: 3
                                Label {
                                    text: "歌手歌单"
                                    font.family: appFont.name; font.pixelSize: 15; font.bold: true
                                    color: createListDialog._createListType === "artist" ? "#3B82F6" : "#cccccc"
                                }
                                Label {
                                    text: "自动归类歌手歌曲"
                                    font.family: appFont.name; font.pixelSize: 11; color: "#888"
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: createListDialog._createListType = "artist"
                        }
                    }
                }

                // 自定义歌单：名称输入
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: createListDialog._createListType === "custom"
                    spacing: 8

                    TextField {
                        id: listNameField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        leftPadding: 12; rightPadding: 12
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
                        onTextChanged: createNameHint.text = ""
                        Keys.onReturnPressed: doCreateList()
                        Keys.onEnterPressed: doCreateList()
                    }

                    Label {
                        id: createNameHint
                        text: ""
                        font.family: appFont.name; font.pixelSize: 11; color: "#cc5555"
                        Layout.topMargin: -2
                        visible: text.length > 0
                    }
                }

                // 歌手歌单：说明
                Label {
                    Layout.fillWidth: true
                    visible: createListDialog._createListType === "artist"
                    text: "点击「下一步」后将打开歌手选择窗口，选择歌手后自动创建列表，并归类该歌手的全部歌曲。"
                    font.family: appFont.name; font.pixelSize: 13; color: "#aaaaaa"
                    wrapMode: Text.WordWrap
                    lineHeight: 1.6
                }

                Item { Layout.fillHeight: true }
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
                        color: cancelCreateMA.containsMouse ? "#333333" : "#1E1E1E"
                        border.color: "#3A3A3A"; border.width: 1
                        Label { anchors.centerIn: parent; text: "取消"; font.family: appFont.name; font.pixelSize: 13; color: "#999" }
                        MouseArea {
                            id: cancelCreateMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { listNameField.text = ""; createListDialog.close() }
                        }
                    }

                    Rectangle {
                        Layout.preferredHeight: 34; Layout.preferredWidth: 100; radius: 6
                        color: createListDialog._canCreate ? (confirmCreateMA.containsMouse ? "#5B9EF6" : "#3B82F6") : "#1E1E1E"
                        border.color: "#3A3A3A"; border.width: 1
                        Label {
                            anchors.centerIn: parent
                            text: createListDialog._createListType === "artist" ? "下一步" : "创建"
                            font.family: appFont.name; font.pixelSize: 13
                            color: createListDialog._canCreate ? "#ddd" : "#666"
                        }
                        MouseArea {
                            id: confirmCreateMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            enabled: createListDialog._canCreate
                            onClicked: doCreateList()
                        }
                    }
                }
            }
        }
    }

    // ---- 重命名自建歌单对话框 ----
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
    // 排序模式：自定义排序右键菜单 + 相关弹窗
    // ============================================================

    // ---- 自定义排序右键菜单（重命名 / 删除） ----
    Menu {
        id: sortItemMenu
        background: Rectangle { color: "#222222"; border.color: "#3A3A3A"; radius: 6; implicitWidth: 150 }
        topPadding: 0; bottomPadding: 0

        MenuItem {
            text: "重命名排序"
            contentItem: Label { text: "重命名排序"; font.family: appFont.name; font.pixelSize: 14; color: "#cccccc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
            onClicked: {
                var idx = mainWindow._rightClickedSortIndex
                if (idx >= 0 && idx < musicManager.sortModes.length) {
                    sortRenameField.text = musicManager.sortModes[idx].name || ""
                    sortRenameHint.text = ""
                    sortRenameDialog.open()
                }
            }
        }
        MenuItem {
            text: "删除排序"
            contentItem: Label { text: "删除排序"; font.family: appFont.name; font.pixelSize: 14; color: "#e06666"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
            onClicked: {
                var idx = mainWindow._rightClickedSortIndex
                if (idx >= 0 && idx < musicManager.sortModes.length) {
                    musicManager.deleteSortMode(idx)
                    // 删除后索引可能错位，若当前正应用自定义排序则回退到按名称
                    if (mainWindow.sortMode.indexOf("custom:") === 0)
                        mainWindow.sortMode = "name"
                }
            }
        }
    }

    // ---- 排序未保存弹窗（切换排序模式时询问：丢弃 / 覆盖 / 新建） ----
    Dialog {
        id: saveSortDialog
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 360
        padding: 28

        Overlay.modal: Rectangle { color: "#40000000" }

        background: Rectangle {
            color: "#222222"
            radius: 10
            border.color: "#3A3A3A"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 14

            Label {
                text: "排序未保存"
                font.family: appFont.name
                font.pixelSize: 17
                font.bold: true
                color: "#dddddd"
                Layout.bottomMargin: 2
            }

            Label {
                text: "检测到列表排序修改，请选择："
                font.family: appFont.name
                font.pixelSize: 14
                color: "#aaaaaa"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 10

                // 丢弃（不保存，直接切换）
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38; radius: 6
                    color: saveDiscardMA.containsMouse ? "#3A3A3A" : "#2A2A2A"
                    border.color: "#3A3A3A"; border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Label {
                        anchors.centerIn: parent
                        text: "丢弃排序并切换"
                        font.family: appFont.name; font.pixelSize: 14
                        color: "#cccccc"
                    }
                    MouseArea {
                        id: saveDiscardMA; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mainWindow.applySortDirect(mainWindow._pendingSortMode)
                    }
                }

                // 覆盖现有排序（中间，蓝色；没有当前自定义排序时置灰，只能新建）
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38; radius: 6
                    color: saveOverwriteMA.enabled
                          ? (saveOverwriteMA.containsMouse ? "#5B9EF6" : "#3B82F6")
                          : "#2A2A2A"
                    border.color: saveOverwriteMA.enabled ? "#3B82F6" : "#3A3A3A"
                    border.width: 1
                    opacity: saveOverwriteMA.enabled ? 1.0 : 0.45
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Label {
                        anchors.centerIn: parent
                        text: "覆盖现有排序"
                        font.family: appFont.name; font.pixelSize: 14
                        color: saveOverwriteMA.enabled ? "#eee" : "#888"
                    }
                    MouseArea {
                        id: saveOverwriteMA
                        anchors.fill: parent; hoverEnabled: true
                        enabled: mainWindow.currentCustomSortIndex() >= 0
                        cursorShape: Qt.PointingHandCursor
                        onClicked: mainWindow.doOverwriteSort(mainWindow._pendingSortMode)
                    }
                }

                // 保存新排序（下移，打开新建窗口）
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 38; radius: 6
                    color: saveNewMA.containsMouse ? "#5B9EF6" : "#3B82F6"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Label {
                        anchors.centerIn: parent
                        text: "保存新排序"
                        font.family: appFont.name; font.pixelSize: 14
                        color: "#eee"
                    }
                    MouseArea {
                        id: saveNewMA; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            saveSortDialog.close()
                            mainWindow.openCreateSortDialog()
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12
                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: saveCancelMA.containsMouse ? "#333333" : "#1E1E1E"
                    border.color: "#3A3A3A"; border.width: 1
                    Label { text: "取消"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: saveCancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        // 取消：不丢弃不保存，关闭弹窗继续等待用户处理
                        onClicked: saveSortDialog.close()
                    }
                }
            }
        }
    }

    // ---- 新建排序弹窗（设置排序名称） ----
    Dialog {
        id: createSortDialog
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 340
        padding: 28

        Overlay.modal: Rectangle { color: "#40000000" }

        background: Rectangle {
            color: "#222222"
            radius: 10
            border.color: "#3A3A3A"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 14

            Label {
                text: "新建排序"
                font.family: appFont.name
                font.pixelSize: 17
                font.bold: true
                color: "#dddddd"
                Layout.bottomMargin: 4
            }

            TextField {
                id: createSortField
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                leftPadding: 12; rightPadding: 12
                placeholderText: "输入排序名称"
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
                onTextChanged: createSortHint.text = ""
                Keys.onReturnPressed: doSaveNewSort()
                Keys.onEnterPressed: doSaveNewSort()
            }

            Label {
                id: createSortHint
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
                    color: createSortCancelMA.containsMouse ? "#333333" : "#1E1E1E"
                    border.color: "#3A3A3A"; border.width: 1
                    Label { text: "取消"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: createSortCancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: createSortDialog.close()
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: createSortConfirmMA.containsMouse ? "#5B9EF6" : "#3B82F6"
                    Label { text: "确定"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#ddd" }
                    MouseArea {
                        id: createSortConfirmMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: doSaveNewSort()
                    }
                }
            }
        }
    }

    // ---- 重命名排序弹窗 ----
    Dialog {
        id: sortRenameDialog
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 340
        padding: 28

        Overlay.modal: Rectangle { color: "#40000000" }

        background: Rectangle {
            color: "#222222"
            radius: 10
            border.color: "#3A3A3A"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 14

            Label {
                text: "重命名排序"
                font.family: appFont.name
                font.pixelSize: 17
                font.bold: true
                color: "#dddddd"
                Layout.bottomMargin: 4
            }

            TextField {
                id: sortRenameField
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
                onTextChanged: sortRenameHint.text = ""
                Keys.onReturnPressed: doRenameSort()
                Keys.onEnterPressed: doRenameSort()
            }

            Label {
                id: sortRenameHint
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
                    color: sortRenameCancelMA.containsMouse ? "#333333" : "#1E1E1E"
                    border.color: "#3A3A3A"; border.width: 1
                    Label { text: "取消"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: sortRenameCancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { sortRenameField.text = ""; sortRenameDialog.close() }
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: sortRenameConfirmMA.containsMouse ? "#5B9EF6" : "#3B82F6"
                    Label { text: "确定"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#ddd" }
                    MouseArea {
                        id: sortRenameConfirmMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: doRenameSort()
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
        property bool _pickerMode: false   // true=从音乐库导入弹窗选歌手，点击后直接勾选歌曲并返回
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: Math.min(parent.width * 0.8, 540)
        height: Math.min(parent.height * 0.8, 460)
        padding: 0

        onOpened: {
            // 每次打开重置选中状态与名称输入
            mainWindow._pendingArtist = ""
            artistNameField.text = ""
            artistSearchField.text = ""
            _artistDialogFilter = musicManager.availableArtists()
        }

        onClosed: artistSelectDialog._pickerMode = false

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
                    // 右上角关闭按钮（picker 模式隐藏底部栏时仍可关闭）
                    Rectangle {
                        Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 6
                        color: artistDlgCloseMA.containsMouse ? "#33ffffff" : "transparent"
                        Label {
                            anchors.centerIn: parent
                            text: "✕"
                            font.pixelSize: 14; color: "#999"
                        }
                        MouseArea {
                            id: artistDlgCloseMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: artistSelectDialog.close()
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

            // 歌手歌单
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

                    readonly property bool _added: !artistSelectDialog._pickerMode && mainWindow._existingArtistNames[modelData] === true

                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 10

                        // 歌手图标
                        Rectangle {
                            Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 4
                            color: arItemRoot._added ? "#1E1E1E" : "#2C2C2C"
                            Image {
                                anchors.centerIn: parent
                                source: "qrc:/qt/qml/JustSolo/data/image/singer_list.png"
                                sourceSize.width: 20
                                sourceSize.height: 20
                                fillMode: Image.PreserveAspectFit
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
                            // picker 模式：直接勾选该歌手的全部歌曲并返回
                            if (artistSelectDialog._pickerMode) {
                                mainWindow._selectLibSongsByArtist(modelData)
                                artistSelectDialog.close()
                                return
                            }
                            // 选中歌手：填入默认列表名，待用户点「确定」后创建
                            mainWindow._pendingArtist = modelData
                            // 再次点击同一歌手时保留已修改的名称
                            if (artistNameField.text !== modelData)
                                artistNameField.text = modelData
                            artistNameField.forceActiveFocus()
                        }
                    }
                }
            }

            // 底部栏：列表名称输入 + 操作按钮（picker 模式隐藏）
            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 52; radius: 10
                color: "#222222"
                visible: !artistSelectDialog._pickerMode
                Rectangle { width: parent.width; height: 10; color: "#222222"; anchors.top: parent.top }
                Rectangle { width: parent.width; height: 1; color: "#3A3A3A"; anchors.top: parent.top }

                RowLayout {
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 16; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    // 左下：列表名称输入框（选中歌手后出现，可修改）
                    TextField {
                        id: artistNameField
                        Layout.fillWidth: true; Layout.preferredHeight: 36
                        visible: mainWindow._pendingArtist !== ""
                        placeholderText: "列表名称"
                        placeholderTextColor: "#888"
                        font.family: appFont.name; font.pixelSize: 13; color: "#ddd"
                        leftPadding: 10; rightPadding: 10
                        verticalAlignment: TextInput.AlignVCenter
                        selectByMouse: true
                        background: Rectangle { radius: 6; color: "#333333"; border.color: "#3A3A3A" }
                        onAccepted: {
                            if (mainWindow._pendingArtist !== "")
                                mainWindow.doArtistConfirm()
                        }
                    }

                    // 未选中歌手时：左侧占位，将「关闭」按钮强制推到右下角
                    Item {
                        Layout.fillWidth: true
                        visible: mainWindow._pendingArtist === ""
                    }

                    // 右下按钮：未选中歌手时「关闭」，选中后变为「确定」
                    Rectangle {
                        Layout.preferredHeight: 34; Layout.preferredWidth: 80; radius: 6
                        color: mainWindow._pendingArtist !== "" ? (artistDlgActionMA.containsMouse ? "#5B9EF6" : "#3B82F6") : (artistDlgActionMA.containsMouse ? "#333333" : "#1E1E1E")
                        border.color: "#3A3A3A"; border.width: 1
                        Label {
                            anchors.centerIn: parent
                            text: mainWindow._pendingArtist !== "" ? "确定" : "关闭"
                            font.family: appFont.name; font.pixelSize: 13
                            color: mainWindow._pendingArtist !== "" ? "#fff" : "#999"
                        }
                        MouseArea {
                            id: artistDlgActionMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: mainWindow.doArtistConfirm()
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
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 16; anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    // 左下：选择歌手（勾选该歌手的全部歌曲）
                    Rectangle {
                        Layout.preferredHeight: 34; Layout.preferredWidth: 138; radius: 6
                        color: pickArtistMA.containsMouse ? "#333333" : "#1E1E1E"
                        border.color: "#3A3A3A"; border.width: 1
                        RowLayout {
                            anchors.centerIn: parent; spacing: 6
                            Image {
                                source: "qrc:/qt/qml/JustSolo/data/image/singer_list.png"
                                sourceSize.width: 16; sourceSize.height: 16
                                fillMode: Image.PreserveAspectFit
                            }
                            Label {
                                text: "选择歌手快速导入"
                                font.family: appFont.name; font.pixelSize: 13; color: "#ccc"
                            }
                        }
                        MouseArea {
                            id: pickArtistMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                artistSelectDialog._pickerMode = true
                                artistSelectDialog.open()
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

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

    // ---- 自建歌单变更时重建分类索引 ----
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
        // 启动时自动检查更新（可在 设置-软件更新 中关闭）
        if (musicManager.startupCheckUpdate) {
            mainWindow._startupCheckPending = true
            updateChecker.checkForUpdates()
        }
    }

    // ---- 启动时自动检查更新的结果（有新版本则弹窗提示） ----
    property bool _startupCheckPending: false

    Connections {
        target: updateChecker
        function onInfoChanged() {
            if (!mainWindow._startupCheckPending) return
            mainWindow._startupCheckPending = false
            if (updateChecker.isNewer) {
                var v = updateChecker.latestVersion
                if (v && v.charAt(0).toLowerCase() !== "v") v = "v" + v
                newVersionMsgLabel.text = "检测到新版本：" + v + "，请点进设置-软件更新中查看"
                updateAvailableDialog.open()
            }
        }
        function onNotifyMessage(title, message) {
            // 检查失败：结束启动检查流程，不弹新版本提示
            mainWindow._startupCheckPending = false
        }
    }

    // ---- WASAPI 独占启动失败提示 ----
    Connections {
        target: musicManager
        function onWasapiExclusiveFailed() {
            exclusiveDialog.open()
        }
    }

    // ---- WASAPI 独占开启前提示（启动时保存了开启独占：先弹窗提示，确认后再开启） ----
    Connections {
        target: musicManager
        function onExclusiveConfirmRequested() {
            // 若用户关闭了提示弹窗，直接开启独占
            if (!musicManager.wasapiWarnEnabled) {
                musicManager.wasapiExclusive = true
                return
            }
            mainWindow.openExclusiveWarnDialog(function(ok) {
                if (ok)
                    musicManager.wasapiExclusive = true
                else
                    musicManager.disableWasapiExclusive()
            })
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

    // ---- 检测到新版本提示（启动时自动检查发现新版本） ----
    Dialog {
        id: updateAvailableDialog
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
                text: "检测到新版本"
                font.family: appFont.name
                font.pixelSize: 17
                font.bold: true
                color: "#dddddd"
            }

            Label {
                id: newVersionMsgLabel
                text: ""
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
                    Layout.preferredHeight: 34; Layout.preferredWidth: 110; radius: 6
                    color: newVerOkMA.containsMouse ? "#5B9EF6" : "#3B82F6"
                    Label { text: "跳转设置"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#fff" }
                    MouseArea {
                        id: newVerOkMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            updateAvailableDialog.close()
                            mainWindow.currentMenu = "settings"
                            mainWindow.settingsSubMenu = "update"
                        }
                    }
                }
            }
        }
    }

    // ---- WASAPI 独占启动失败提示（设备被占用，无法开启） ----
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

    // ---- 共享模式音频初始化失败提示（通道被占用等） ----
    Connections {
        target: musicManager
        function onAudioInitFailed() {
            audioInitDialog.open()
        }
    }

    Dialog {
        id: audioInitDialog
        modal: true
        closePolicy: Popup.NoAutoClose  // 仅允许确认按钮关闭（退出软件）
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
                text: "无法初始化音频设备"
                font.family: appFont.name
                font.pixelSize: 17
                font.bold: true
                color: "#dddddd"
            }

            Label {
                text: "音频通道可能被其他软件占用，无法正常初始化音频设备。请检查并关闭可能占用音频通道的软件后，重启本软件。"
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
                    color: audioInitOkMA.containsMouse ? "#5B9EF6" : "#3B82F6"
                    Label { text: "确认"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#fff" }
                    MouseArea {
                        id: audioInitOkMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.quit()
                    }
                }
            }
        }
    }

    // 歌手选择对话框「确定」：以选中歌手 + 自定义名称创建列表
    function doArtistConfirm() {
        if (mainWindow._pendingArtist === "") {
            artistSelectDialog.close()
            return
        }
        musicManager.createArtistPlaylist(mainWindow._pendingArtist, artistNameField.text)
        artistSelectDialog.close()
    }

    function doCreateList() {
        // 歌手歌单：关闭本弹窗，进入歌手选择
        if (createListDialog._createListType === "artist") {
            createListDialog.close()
            artistSelectDialog.open()
            return
        }
        // 自定义歌单：校验名称
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
        // 歌手歌单放宽名称校验（允许空格、顿号等），普通列表严格校验
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
            return musicManager.customPlaylists[currentCustomPlaylistIndex].name || "自建歌单"
        return "自建歌单"
    }

    function customPlaylistIcon() {
        // 歌手歌单用专属图标，自定义歌单沿用 PlayList 图标
        if (_isArtistList(currentCustomPlaylistIndex))
            return "qrc:/qt/qml/JustSolo/data/image/singer_list.png"
        return "qrc:/qt/qml/JustSolo/data/image/PlayList.png"
    }

    // 外部触发详情页显隐
    onShowPlayerDetailChanged: {
        // 同步给 C++：详情页沉浸背景联动系统标题栏颜色
        musicManager.playerDetailVisible = showPlayerDetail
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
        color: "#80808080"
        visible: false

        Behavior on opacity { NumberAnimation { duration: 150 } }

        Rectangle {
            anchors.centerIn: parent
            width: 260; height: 200; radius: 20
            color: "#555555"
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

    // ============================================================
    // 全局错误弹窗 — 监听 bugReporter.errorOccurred 信号
    // 当 C++ 端发生严重错误（代码异常、加载失败等）时弹出提示
    // ============================================================
    Connections {
        target: bugReporter
        function onErrorOccurred(type, content, traceback) {
            errorDialog._errorType = type
            errorDialog._errorContent = content
            errorDialog._errorTraceback = traceback || ""
            errorDialog.open()
        }
    }

    Dialog {
        id: errorDialog
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 480
        padding: 26

        property string _errorType: ""
        property string _errorContent: ""
        property string _errorTraceback: ""

        Overlay.modal: Rectangle { color: "transparent" }

        background: Rectangle {
            color: "#222222"
            radius: 10
            border.color: "#5A2A2A"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 12

            // 标题行：错误图标 + 类型
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    text: "⚠"
                    font.pixelSize: 20
                    color: "#FF6B6B"
                }
                Label {
                    text: errorDialog._errorType || "错误"
                    font.family: appFont.name
                    font.pixelSize: 17
                    font.bold: true
                    color: "#FF6B6B"
                    Layout.fillWidth: true
                }
            }

            // 错误内容
            Label {
                text: errorDialog._errorContent
                font.family: appFont.name
                font.pixelSize: 13
                color: "#dddddd"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // 调试信息（可折叠）
            Label {
                visible: errorDialog._errorTraceback.length > 0
                text: errorDialog._errorTraceback
                font.family: appFont.name
                font.pixelSize: 11
                color: "#888888"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: 4
            }

            Label {
                text: "此错误已自动上报，将帮助改进软件。"
                font.family: appFont.name
                font.pixelSize: 11
                color: "#666666"
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 10
                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 88; radius: 6
                    color: errorCloseMA.containsMouse ? "#3A3A3A" : "#1E1E1E"
                    border.color: "#3A3A3A"; border.width: 1
                    Label { text: "关闭"; anchors.centerIn: parent; font.family: appFont.name; font.pixelSize: 13; color: "#ccc" }
                    MouseArea {
                        id: errorCloseMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: errorDialog.close()
                    }
                }
            }
        }
    }

    // ============================================================
    // 排序菜单点击外部关闭层
    // 仅排序菜单打开时显示。点击排序按钮区域放行（菜单保持打开），
    // 点击其余任意位置关闭排序菜单。
    // ============================================================
    MouseArea {
        id: sortMenuDismissLayer
        anchors.fill: parent
        visible: sortMenu.visible
        z: 9997

        onPressed: function(mouse) {
            var btnPos = sortBtnMA.mapToItem(sortMenuDismissLayer, 0, 0)
            if (mouse.x >= btnPos.x && mouse.x <= btnPos.x + sortBtnMA.width
                    && mouse.y >= btnPos.y && mouse.y <= btnPos.y + sortBtnMA.height) {
                mouse.accepted = false  // 放行给排序按钮，不关闭菜单
                return
            }
            sortMenu.close()
        }
    }
}
