import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// 通用歌曲列表组件（全局复用）
// 所有音乐 / 自定义列表共用，通过 songList 切换数据源
// ============================================================
ColumnLayout {
    id: root
    spacing: 0
    clip: true

    property int sidebarWidth: 230
    property int windowWidth: 1200
    property var rightClickedTrack: null
    property int rightClickedIndex: -1
    property string fontFamily: ""

    // 可重载：自定义列表时传入不同的歌曲列表
    property var songList: musicManager.library
    // 自定义列表索引（-1 = 普通模式，> = 自建列表）
    property int customPlaylistIndex: -1
    // 当前页面的列表索引（-1=未设置, 0=库, 1=收藏, 2=历史, 3+n=自定义）
    property int pageListIndex: -1
    // 搜索滚动
    property int scrollToIndex: -1
    // ---- 定制化接口 ----
    // 覆盖点击行为：function(index) { ... }。设了之后不走默认点击逻辑
    property var onLeftClick: undefined
    // 空列表提示文本
    property string emptyHint: "还没有音乐"
    property string emptySubHint: "点击上方「添加音乐」导入本地文件"
    // 额外右键菜单项：[{text, onClicked}, ...]
    property var contextMenuExtra: []
    // 是否显示默认右键菜单项（收藏/取消收藏、删除此歌曲）
    property bool showDefaultContextMenu: true

    // 当前正在播放的歌曲路径（跨来源匹配）
    // 不受 trackCrossSource 影响，始终返回当前播放歌曲路径
    property string playingPath: {
        try {
            var ci = musicManager.currentIndex
            if (ci < 0) return ""
            var src = musicManager.playlistSource
            var list = src === 1 ? musicManager.favorites : (src === 2 ? musicManager.history : musicManager.playlist)
            if (!list || list.length === 0) return ""
            if (ci >= 0 && ci < list.length) return (list[ci].path || "")
        } catch (e) {}
        return ""
    }

    // ---- 列宽 (2:2:2:2:1) ----
    property int colPlay: 36
    property real _totalW: Math.max(400,
        (musicListView.width > 0 ? musicListView.width : windowWidth - sidebarWidth - 80) - 20 - colPlay)
    property real colCover:    Math.max(40, _totalW * 2 / 9)
    property real colTitle:    Math.max(60, _totalW * 2 / 9)
    property real colArtist:   Math.max(50, _totalW * 2 / 9)
    property real colAlbum:    Math.max(50, _totalW * 2 / 9)
    property real colDuration: Math.max(36, _totalW * 1 / 9)
    property int _pendingIndex: -1
    property string dialogMode: "home"   // "home" / "custom" / "switch"
    property int dialogTarget: -1        // "switch" 模式的目标 playlistSource

    // 切换到页面时若当前歌曲在此列表中，自动定位到该行
    property bool autoScrollEnabled: true

    onScrollToIndexChanged: {
        if (scrollToIndex >= 0 && scrollToIndex < songList.length) {
            Qt.callLater(function() {
                musicListView.positionViewAtIndex(scrollToIndex, ListView.Center)
            })
        }
    }

    Component.onCompleted: {
        if (autoScrollEnabled && musicManager.currentIndex >= 0) {
            scrollToPlaying()
        }
    }

    onVisibleChanged: {
        if (autoScrollEnabled && visible && musicManager.currentIndex >= 0) {
            scrollToPlaying()
        }
    }

    // 同一 HomePage 实例切换 songList（所有音乐↔自定义列表）时触发定位
    onSongListChanged: {
        if (autoScrollEnabled && visible && musicManager.currentIndex >= 0) {
            Qt.callLater(function() { scrollToPlaying() })
        }
    }

    function scrollToPlaying() {
        if (!songList) return
        var p = playingPath
        if (p.length === 0) return
        // 只有当页面列表索引与当前播放列表索引一致时才定位
        if (pageListIndex >= 0 && pageListIndex !== musicManager.playingListIndex) return
        for (var i = 0; i < songList.length; i++) {
            if (songList[i] && songList[i].path === p) {
                var idx = i
                Qt.callLater(function() {
                    musicListView.positionViewAtIndex(idx, ListView.Center)
                })
                return
            }
        }
    }

    // 供子类调用：打开切换来源弹窗
    function openSwitchDialog(mode, target, index) {
        _pendingIndex = index
        dialogMode = mode
        dialogTarget = target
        switchSourceDialog.open()
    }

    // ---- 列标题 ----
    Rectangle {
        Layout.fillWidth: true; height: 32; color: "transparent"
        visible: songList.length > 0
        RowLayout {
            anchors.fill: parent; anchors.margins: 5; anchors.leftMargin: 8; spacing: 0
            Item { Layout.preferredWidth: root.colCover; Layout.maximumWidth: 40 }
            Label { text: "标题"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: root.colTitle; verticalAlignment: Text.AlignVCenter }
            Label { text: "歌手"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: root.colArtist; verticalAlignment: Text.AlignVCenter }
            Label { text: "专辑"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.fillWidth: true; Layout.preferredWidth: root.colAlbum; verticalAlignment: Text.AlignVCenter }
            Label { text: "时长"; font.family: fontFamily; font.pixelSize: 14; color: "#969696"; Layout.preferredWidth: root.colDuration; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
            Item { Layout.preferredWidth: root.colPlay }
        }
    }
    Rectangle { Layout.fillWidth: true; height: 1; color: "#2a2a48"; visible: songList.length > 0 }

    // ---- 歌曲列表 ----
    ListView {
        id: musicListView
        Layout.fillWidth: true; Layout.fillHeight: true
        spacing: 8; clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: songList.length > 0
        cacheBuffer: height * 2; reuseItems: true

        ScrollBar.vertical: ScrollBar {
            id: listScrollBar; policy: ScrollBar.AsNeeded; width: 10
            background: Rectangle { implicitWidth: 10; radius: 5; color: "#2a2a3a" }
            contentItem: Rectangle {
                implicitWidth: 10; radius: 5
                color: thumbHover.containsMouse ? "#7777aa" : "#555577"
                Behavior on color { ColorAnimation { duration: 150 } }
                MouseArea { id: thumbHover; hoverEnabled: true; acceptedButtons: Qt.NoButton; propagateComposedEvents: true }
            }
        }

        model: songList

        delegate: SongRow {
            width: musicListView.width
            isCurrent: model.path === root.playingPath
            fontFamily: root.fontFamily
            colCover: root.colCover
            colTitle: root.colTitle
            colArtist: root.colArtist
            colAlbum: root.colAlbum
            colDuration: root.colDuration
            colPlay: root.colPlay

            onLeftClicked: {
                if (root.onLeftClick) {
                    root.onLeftClick(index)
                } else if (root.customPlaylistIndex >= 0) {
                    var thisCustomIdx = 3 + root.customPlaylistIndex
                    if (musicManager.currentIndex < 0) {
                        musicManager.playCustomPlaylist(root.customPlaylistIndex, index)
                    } else if (musicManager.playingListIndex === thisCustomIdx) {
                        // 已经是此列表在播放
                        if (musicManager.currentIndex === index) {
                            if (musicManager.isPlaying) musicManager.pause()
                            else musicManager.play()
                        } else {
                            musicManager.playCustomPlaylist(root.customPlaylistIndex, index)
                        }
                    } else {
                        root._pendingIndex = index
                        root.dialogMode = "custom"
                        switchSourceDialog.open()
                    }
                } else if (musicManager.playlistSource === 0) {
                    if (model.path === root.playingPath) {
                        if (musicManager.isPlaying) musicManager.pause()
                        else musicManager.play()
                    } else {
                        musicManager.playIndex(index)
                    }
                } else if (musicManager.trackCrossSource) {
                    musicManager.playlistSource = 0
                    musicManager.playIndex(index)
                } else {
                    // 没有正在播放 → 直接播放，否则弹窗确认
                    if (musicManager.currentIndex < 0) {
                        musicManager.playlistSource = 0
                        musicManager.playIndex(index)
                    } else {
                        root._pendingIndex = index
                        root.dialogMode = "home"
                        switchSourceDialog.open()
                    }
                }
            }
            onRightClicked: {
                root.rightClickedTrack = model
                root.rightClickedIndex = index
                contextMenu.popup()
            }
        }
    }

    // ---- 右键菜单 ----
    Menu {
        id: contextMenu
        background: Rectangle { color: "#2a2a3a"; border.color: "#444466"; radius: 6; implicitWidth: 150 }
        MenuItem {
            id: menuItem
            visible: root.showDefaultContextMenu
            text: root.rightClickedTrack ? (musicManager.isFavorite(root.rightClickedTrack) ? "取消收藏" : "收藏") : "收藏"
            onClicked: { if (root.rightClickedTrack) musicManager.toggleFavorite(root.rightClickedTrack) }
            contentItem: Label { text: menuItem.text; font.family: fontFamily; font.pixelSize: 14; color: "#cccccc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: menuItem.hovered ? "#3a3a5a" : "transparent"; radius: 4 }
        }
        MenuItem {
            visible: root.showDefaultContextMenu
            text: "删除此歌曲"
            contentItem: Label { text: "删除此歌曲"; font.family: fontFamily; font.pixelSize: 14; color: "#e06666"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: parent.hovered ? "#3a3a5a" : "transparent"; radius: 4 }
            onClicked: deleteConfirmDialog.open()
        }
        MenuSeparator {
            visible: root.showDefaultContextMenu && root.contextMenuExtra.length > 0
            contentItem: Rectangle { implicitHeight: 1; implicitWidth: 130; color: "#444466" }
        }
        Instantiator {
            model: root.contextMenuExtra
            MenuItem {
                text: modelData.text || ""
                onClicked: { if (modelData.onClicked) modelData.onClicked(); root.rightClickedTrack = null }
                contentItem: Label { text: modelData.text || ""; font.family: fontFamily; font.pixelSize: 14; color: "#cccccc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { color: parent.hovered ? "#3a3a5a" : "transparent"; radius: 4 }
            }
            onObjectAdded: function(index, object) { contextMenu.insertItem(contextMenu.count, object) }
            onObjectRemoved: function(index, object) { contextMenu.removeItem(object) }
        }
    }

    // ---- 空列表提示 ----
    Column {
        Layout.alignment: Qt.AlignCenter; spacing: 14
        visible: songList.length === 0
        Label { text: root.emptyHint; font.family: fontFamily; font.pixelSize: 16; color: "#757575"; anchors.horizontalCenter: parent.horizontalCenter }
        Label { text: root.emptySubHint; font.family: fontFamily; font.pixelSize: 13; color: "#666"; anchors.horizontalCenter: parent.horizontalCenter }
    }

    // ---- 切换来源对话框 ----
    Dialog {
        id: switchSourceDialog
        parent: Overlay.overlay
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
                text: root.dialogMode === "custom" ? "切换自定义列表"
                     : root.dialogMode === "switch" ? "切换播放来源"
                     : "切换播放列表"
                font.family: fontFamily
                font.pixelSize: 17
                font.bold: true
                color: "#dddddd"
                Layout.bottomMargin: 4
            }

            Label {
                text: root.dialogMode === "custom"
                      ? "当前播放列表不是此列表，\n点击确定将改变播放列表并播放选定的歌曲。"
                      : root.dialogMode === "switch"
                      ? "当前播放来源不是此页面，\n点击确定将切换播放来源并播放选定的歌曲。"
                      : "当前播放来源不是首页，\n点击确定将从头播放选定的歌曲。"
                font.family: fontFamily
                font.pixelSize: 14
                lineHeight: 1.4
                color: "#cccccc"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 12
                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: switchCancelMA.containsMouse ? "#3a3a5a" : "#333350"
                    border.color: "#444466"; border.width: 1
                    Label { text: "取消"; anchors.centerIn: parent; font.family: fontFamily; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: switchCancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: switchSourceDialog.close()
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: switchConfirmMA.containsMouse ? "#4a6a8a" : "#3a5a7a"
                    Label { text: "确定"; anchors.centerIn: parent; font.family: fontFamily; font.pixelSize: 13; color: "#ddd" }
                    MouseArea {
                        id: switchConfirmMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.dialogMode === "custom") {
                                musicManager.playCustomPlaylist(root.customPlaylistIndex, root._pendingIndex)
                            } else if (root.dialogMode === "switch") {
                                musicManager.playlistSource = root.dialogTarget
                                musicManager.playIndex(root._pendingIndex)
                            } else {
                                musicManager.playlistSource = 0
                                musicManager.playIndex(root._pendingIndex)
                            }
                            switchSourceDialog.close()
                            Qt.callLater(function() { root.scrollToPlaying() })
                        }
                    }
                }
            }
        }
    }

    // ---- 删除歌曲确认弹窗 ----
    Dialog {
        id: deleteConfirmDialog
        parent: Overlay.overlay
        modal: true
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 380
        padding: 28

        Overlay.modal: Rectangle { color: "transparent" }

        background: Rectangle {
            color: "#2a2a48"
            radius: 10
            border.color: "#444466"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 16

            RowLayout {
                spacing: 10
                Label {
                    text: "🗑"
                    font.pixelSize: 22
                    color: "#e06666"
                }
                Label {
                    text: "删除此歌曲"
                    font.family: fontFamily
                    font.pixelSize: 17
                    font.bold: true
                    color: "#dddddd"
                }
            }

            Label {
                text: "我们不会从磁盘删除此歌曲文件，欢迎重新加回。\n\n此操作会同步删除历史记录、播放列表、收藏及所有自定义列表中的此歌曲。"
                font.family: fontFamily
                font.pixelSize: 13
                lineHeight: 1.5
                color: "#aaaaaa"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 12
                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 80; radius: 6
                    color: delCancelMA.containsMouse ? "#3a3a5a" : "#333350"
                    border.color: "#444466"; border.width: 1
                    Label { text: "取消"; anchors.centerIn: parent; font.family: fontFamily; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: delCancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: deleteConfirmDialog.close()
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 80; radius: 6
                    color: delConfirmMA.containsMouse ? "#cc5555" : "#994444"
                    Label { text: "删除"; anchors.centerIn: parent; font.family: fontFamily; font.pixelSize: 13; color: "#eee" }
                    MouseArea {
                        id: delConfirmMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.rightClickedTrack) {
                                musicManager.deleteSongByPath(root.rightClickedTrack.path || "")
                                root.rightClickedTrack = null
                            }
                            deleteConfirmDialog.close()
                        }
                    }
                }
            }
        }
    }
}
