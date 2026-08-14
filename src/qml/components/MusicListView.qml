import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// 通用歌曲列表组件（全局复用）
// 所有音乐 / 自建歌单共用，通过 songList 切换数据源
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

    // 可重载：自建歌单时传入不同的歌曲列表
    property var songList: musicManager.library
    // 自建歌单索引（-1 = 普通模式，> = 自建列表）
    property int customPlaylistIndex: -1
    // 当前页面的列表索引（-1=未设置, 0=库, 1=收藏, 2=历史, 3+n=自定义）
    property int pageListIndex: -1
    // 搜索滚动
    property int scrollToIndex: -1
    // ---- 定制化接口 ----
    // 覆盖点击行为：function(index) { ... }。设了之后不走默认点击逻辑
    property var onLeftClick: undefined
    // 覆盖拖拽排序行为：function(fromIdx, toIdx) { ... }。设了之后不走默认 reorderSong
    // （排序模式下手动拖拽由外层接管，用于弹窗询问保存/覆盖）
    property var onReorderRequest: undefined
    // 空列表提示文本
    property string emptyHint: "还没有音乐"
    property string emptySubHint: "点击上方「添加音乐」导入本地文件"
    // 额外右键菜单项：[{text, onClicked}, ...]
    property var contextMenuExtra: []
    // 是否显示默认右键菜单项（收藏/取消收藏、删除此歌曲）
    property bool showDefaultContextMenu: true

    property int _pendingIndex: -1

    // ---- 右键菜单状态 ----
    property bool contextMenuOpen: false

    // ---- 拖拽排序 ----
    property int draggedIndex: -1
    property int dropTargetIndex: -1
    property var draggedTrack: null
    property real dragOffsetY: 0       // 鼠标在拖拽行内的偏移（相对行顶）
    property real dragOverlayY: 0      // 拖拽浮层的 Y 坐标（相对 musicListView）

    // ---- 拖拽自动滚动 ----
    property int _autoScrollDirection: 0  // -1=向上, 1=向下, 0=停止
    property real _dragEdgeY: 0           // 进入边缘区时的鼠标 Y（相对 musicListView）
    property real _dropIndicatorY: 0      // 浮动放置指示线 Y
    property int _autoScrollFinalIndex: -1 // 自动滚动期间计算的最终目标索引
    property bool _suppressAutoScroll: false // reorder 期间抑制自动定位
    property real _savedContentY: 0          // reorder 前保存的滚动位置

    function reorderSong(fromIdx, toIdx) {
        if (fromIdx === toIdx) return
        if (fromIdx < 0 || toIdx < 0) return
        var list = songList
        if (!list || fromIdx >= list.length || toIdx >= list.length) return

        if (pageListIndex >= 3) {
            musicManager.moveSongInCustomPlaylist(pageListIndex - 3, fromIdx, toIdx)
        } else if (pageListIndex === 0) {
            musicManager.moveSongInLibrary(fromIdx, toIdx)
        } else if (pageListIndex === 1) {
            musicManager.moveSongInFavorites(fromIdx, toIdx)
        } else if (pageListIndex === 2) {
            musicManager.moveSongInHistory(fromIdx, toIdx)
        } else {
            // PlaylistPage 或未设置：根据当前播放来源判断
            var src = musicManager.playlistSource
            if (src === 1)
                musicManager.moveSongInFavorites(fromIdx, toIdx)
            else if (src === 2)
                musicManager.moveSongInHistory(fromIdx, toIdx)
            else if (src >= 3)
                musicManager.moveSongInCustomPlaylist(src - 3, fromIdx, toIdx)
            else
                musicManager.moveSongInPlaylist(fromIdx, toIdx)
        }
    }

    // 当前正在播放的歌曲路径（跨来源匹配）
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

    // ---- 列宽 ----
    property int colIndex: 24
    property int colFav: 28
    property int colMenu: 28
    property real _totalW: Math.max(400,
        (musicListView.width > 0 ? musicListView.width : windowWidth - sidebarWidth - 80) - 20 - colIndex - colFav - colMenu)
    property real colCover:    Math.max(40, _totalW * 2 / 9)
    property real colTitle:    Math.max(60, _totalW * 3 / 9)   // 标题 + 歌手 + 音质
    property real colAlbum:    Math.max(50, _totalW * 2 / 9)
    property real colDuration: Math.max(36, _totalW * 2 / 9)
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

    // 同一 AllMusicPage 实例切换 songList（所有音乐↔自建歌单）时触发定位
    onSongListChanged: {
        if (_suppressAutoScroll) {
            // reorder 使 C++ 返回新 QVariantList → 模型替换 → contentY 会重置为 0
            // 在恢复滚动位置之前隐藏 ListView，避免闪一帧（contentY=0）
            musicListView.opacity = 0
            Qt.callLater(function() {
                musicListView.contentY = Math.min(root._savedContentY,
                    Math.max(0, musicListView.contentHeight - musicListView.height))
                root._suppressAutoScroll = false
                musicListView.opacity = 1
            })
        } else if (autoScrollEnabled && visible && musicManager.currentIndex >= 0) {
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

    // ---- 歌曲列表 ----
    ListView {
        id: musicListView
        Layout.fillWidth: true; Layout.fillHeight: true
        spacing: 8; clip: true
        boundsBehavior: Flickable.StopAtBounds
        visible: songList.length > 0
        cacheBuffer: Math.min(height * 0.5, 400); reuseItems: true

        moveDisplaced: Transition {
            NumberAnimation { properties: "y"; duration: 250; easing.type: Easing.OutCubic }
        }

        displaced: Transition {
            NumberAnimation { properties: "y"; duration: 220; easing.type: Easing.OutCubic }
        }

        ScrollBar.vertical: ScrollBar {
            id: listScrollBar; policy: ScrollBar.AsNeeded; width: 10
            background: Rectangle { implicitWidth: 10; radius: 5; color: "#222222" }
            contentItem: Rectangle {
                implicitWidth: 10; radius: 5
                color: thumbHover.containsMouse ? "#777777" : "#3A3A3A"
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
            colAlbum: root.colAlbum
            colDuration: root.colDuration
            colIndex: root.colIndex
            colFav: root.colFav
            colMenu: root.colMenu
            isDragged: root.draggedTrack && model && model.path && model.path === root.draggedTrack.path
            showDropAbove: {
                var targetIdx = root._autoScrollFinalIndex >= 0 ? root._autoScrollFinalIndex : root.dropTargetIndex
                return targetIdx === index && root.draggedIndex !== index
            }
            contextMenuOpen: root.contextMenuOpen

            Behavior on opacity {
                NumberAnimation { duration: 0 }
            }

            onDragStarted: function(globalX, globalY, localY) {
                root.draggedIndex = index
                // 深拷贝：model 是 QML 引擎的包装对象，delegate 回收后属性值会变
                root.draggedTrack = {
                    name: model.name,
                    path: model.path,
                    artist: model.artist,
                    cover: model.cover,
                    album: model.album,
                    durationText: model.durationText,
                    quality: model.quality
                }
                root.dragOffsetY = localY
                var lvPt = musicListView.mapFromGlobal(globalX, globalY)
                root.dragOverlayY = lvPt.y - root.dragOffsetY
                dragOverlay.visible = true
            }
            onDragMoved: function(globalX, globalY) {
                var lvPt = musicListView.mapFromGlobal(globalX, globalY)
                root.dragOverlayY = Math.max(0, Math.min(lvPt.y - root.dragOffsetY,
                    musicListView.height - 50))

                // 计算目标索引（viewport Y + contentY → content Y）
                var rowHeight = 50 + musicListView.spacing
                var targetY = lvPt.y + musicListView.contentY
                var targetIdx = Math.floor((targetY + rowHeight / 2) / rowHeight)
                targetIdx = Math.max(0, Math.min(targetIdx, musicListView.count - 1))
                if (targetIdx !== root.dropTargetIndex) {
                    root.dropTargetIndex = targetIdx
                }
                // 更新放置指示线位置（目标行顶边缘）
                root._dropIndicatorY = targetIdx * rowHeight - musicListView.contentY - 1

                // ---- 拖拽自动滚动（边缘检测） ----
                var edgeThreshold = 50
                var lvHeight = musicListView.height
                if (lvPt.y < edgeThreshold && musicListView.contentY > 0) {
                    root._autoScrollDirection = -1
                    root._dragEdgeY = Math.max(0, lvPt.y)
                    if (!autoScrollTimer.running) autoScrollTimer.start()
                } else if (lvPt.y > lvHeight - edgeThreshold
                           && musicListView.contentY < musicListView.contentHeight - lvHeight) {
                    root._autoScrollDirection = 1
                    root._dragEdgeY = Math.min(lvHeight, lvPt.y)
                    if (!autoScrollTimer.running) autoScrollTimer.start()
                } else {
                    if (autoScrollTimer.running) autoScrollTimer.stop()
                    root._autoScrollFinalIndex = -1
                }
            }
            onDragEnded: {
                if (autoScrollTimer.running) autoScrollTimer.stop()
                var finalFrom = root.draggedIndex
                // 自动滚动结束时使用 _autoScrollFinalIndex（自动滚动期间不更新 dropTargetIndex）
                var finalTo = root._autoScrollFinalIndex >= 0 ? root._autoScrollFinalIndex : root.dropTargetIndex
                dragOverlay.visible = false
                root.draggedIndex = -1
                root.dropTargetIndex = -1
                root.draggedTrack = null
                root._autoScrollFinalIndex = -1

                if (finalFrom >= 0 && finalTo >= 0 && finalFrom !== finalTo) {
                    // 保存 contentY：C++ moveSong 返回 QVariantList 副本，
                    // 模型替换会导致 ListView contentY 重置为 0
                    var savedY = musicListView.contentY
                    root._savedContentY = savedY
                    root._suppressAutoScroll = true
                    if (root.onReorderRequest) {
                        // 排序模式：拖拽顺序由外层接管（弹窗询问保存/覆盖）
                        root.onReorderRequest(finalFrom, finalTo)
                    } else {
                        root.reorderSong(finalFrom, finalTo)
                    }
                }
            }

            opacity: (root.draggedTrack && model && model.path && model.path === root.draggedTrack.path) ? 0.4 : 1.0

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

        // ---- 拖拽浮层（排序模式时跟随鼠标） ----
        Rectangle {
            id: dragOverlay
            z: 999
            visible: false
            anchors.horizontalCenter: parent.horizontalCenter
            width: musicListView.width
            height: 50
            radius: 8
            color: "#333333"
            border.color: "#3B82F6"
            border.width: 1.5
            opacity: 0.95
            y: root.dragOverlayY

            Behavior on opacity {
                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 5
                anchors.leftMargin: 8
                spacing: 0

                // 拖拽图标
                Item {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: parent.height
                    Layout.alignment: Qt.AlignVCenter
                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/qt/qml/JustSolo/data/image/drag.png"
                        width: 16; height: 16
                        opacity: 1.0
                    }
                }

                // 序号
                Label {
                    Layout.preferredWidth: root.colIndex
                    Layout.alignment: Qt.AlignVCenter
                    text: root.draggedTrack ? ("0" + (root.draggedIndex + 1)).slice(-2) : ""
                    font.family: root.fontFamily; font.pixelSize: 13; color: "#777777"
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignVCenter
                    Layout.rightMargin: 6
                }

                Rectangle {
                    Layout.preferredWidth: Math.min(root.colCover, 40)
                    Layout.preferredHeight: 40; Layout.maximumWidth: 40
                    Layout.alignment: Qt.AlignVCenter
                    radius: 6; color: "#4a4a65"
                    Image {
                        anchors.fill: parent; anchors.margins: 2
                        sourceSize.width: 40; sourceSize.height: 40
                        source: (root.draggedTrack && root.draggedTrack.cover) ? root.draggedTrack.cover : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    Label {
                        anchors.centerIn: parent
                        text: "\u266B"; font.family: root.fontFamily; font.pixelSize: 18; color: "#666"
                        visible: !root.draggedTrack || !root.draggedTrack.cover || root.draggedTrack.cover === ""
                    }
                }

                Item {
                    Layout.fillWidth: true; Layout.preferredWidth: root.colTitle
                    Layout.preferredHeight: 40; Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 8
                    clip: true
                    Label {
                        text: root.draggedTrack ? (root.draggedTrack.name || "") : ""
                        font.family: root.fontFamily; font.pixelSize: 15; font.bold: true
                        color: "#FFFFFF"; elide: Text.ElideRight; width: parent.width
                        anchors.top: parent.top; anchors.left: parent.left
                    }
                    Row {
                        anchors.bottom: parent.bottom; anchors.left: parent.left
                        spacing: 3
                        Label {
                            text: root.draggedTrack ? (root.draggedTrack.artist || "未知") : ""
                            font.family: root.fontFamily; font.pixelSize: 13; color: "#777777"
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth,
                                parent.parent.width - (qualityOverlayRect.visible ? qualityOverlayRect.width + parent.spacing + 2 : 0) - 2)
                            visible: root.draggedTrack && root.draggedTrack.artist && root.draggedTrack.artist !== ""
                        }
                        Rectangle {
                            id: qualityOverlayRect
                            width: qualityOverlayText.contentWidth + 8
                            height: 18
                            radius: 3; color: "#777777"
                            visible: root.draggedTrack && root.draggedTrack.quality && root.draggedTrack.quality !== ""
                            opacity: 0.8
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                            Label {
                                id: qualityOverlayText
                                text: root.draggedTrack ? (root.draggedTrack.quality || "") : ""
                                font.family: root.fontFamily; font.pixelSize: 10; font.bold: true
                                color: "white"; anchors.centerIn: parent
                            }
                        }
                    }
                }

                Label {
                    text: root.draggedTrack ? (root.draggedTrack.album || "") : ""
                    font.family: root.fontFamily; font.pixelSize: 15; color: "#777777"
                    elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: root.colAlbum
                }

                Label {
                    text: root.draggedTrack ? (root.draggedTrack.durationText || "") : ""
                    font.family: root.fontFamily; font.pixelSize: 15; color: "#777777"
                    verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
                    Layout.fillHeight: true; Layout.preferredWidth: root.colDuration
                }

                Image {
                    Layout.preferredWidth: root.colFav
                    Layout.alignment: Qt.AlignVCenter
                    source: {
                        musicManager.favorites;
                        root.draggedTrack && musicManager.isFavorite(root.draggedTrack)
                            ? "qrc:/qt/qml/JustSolo/data/image/mylike-on.png"
                            : "qrc:/qt/qml/JustSolo/data/image/mylike-off.png"
                    }
                    sourceSize.width: 16; sourceSize.height: 16
                    fillMode: Image.PreserveAspectFit
                }

                Image {
                    Layout.preferredWidth: root.colMenu
                    Layout.alignment: Qt.AlignVCenter
                    source: "qrc:/qt/qml/JustSolo/data/image/menu.png"
                    sourceSize.width: 16; sourceSize.height: 16
                    fillMode: Image.PreserveAspectFit
                }
            }
        }
    }

    // ---- 拖拽自动滚动定时器 ----
    Timer {
        id: autoScrollTimer
        interval: 30
        repeat: true
        onTriggered: {
            var step = root._autoScrollDirection * 8
            var newCY = musicListView.contentY + step
            newCY = Math.max(0, Math.min(newCY,
                Math.max(0, musicListView.contentHeight - musicListView.height)))
            musicListView.contentY = newCY

            // 保持浮层在边缘位置（不超出 ListView 可视区）
            root.dragOverlayY = Math.max(0, Math.min(root._dragEdgeY - root.dragOffsetY,
                musicListView.height - 50))

            // 重新计算放置目标（viewport Y + contentY → content Y）
            var rowHeight = 50 + musicListView.spacing
            var targetY = root._dragEdgeY + musicListView.contentY
            var targetIdx = Math.floor((targetY + rowHeight / 2) / rowHeight)
            targetIdx = Math.max(0, Math.min(targetIdx, musicListView.count - 1))
            // 自动滚动期间不修改 dropTargetIndex（避免触发 per-delegate 动画导致闪烁）
            root._autoScrollFinalIndex = targetIdx
            // 仅更新浮动指示线位置
            root._dropIndicatorY = targetIdx * rowHeight - musicListView.contentY - 1

            // 到达边界时停止
            if (root._autoScrollDirection < 0 && musicListView.contentY <= 0) {
                autoScrollTimer.stop()
            } else if (root._autoScrollDirection > 0
                       && musicListView.contentY >= musicListView.contentHeight - musicListView.height) {
                autoScrollTimer.stop()
            }
        }
    }

    // ---- 右键菜单 ----
    Menu {
        id: contextMenu
        background: Rectangle { color: "#222222"; border.color: "#3A3A3A"; radius: 6; implicitWidth: 150 }
        topPadding: 0; bottomPadding: 0
        onOpened: root.contextMenuOpen = true
        onClosed: root.contextMenuOpen = false

        MenuItem {
            id: menuItem
            visible: root.showDefaultContextMenu
            height: root.showDefaultContextMenu ? implicitHeight : 0
            text: root.rightClickedTrack ? (musicManager.isFavorite(root.rightClickedTrack) ? "取消收藏" : "收藏") : "收藏"
            onClicked: { if (root.rightClickedTrack) musicManager.toggleFavorite(root.rightClickedTrack) }
            contentItem: Label { text: menuItem.text; font.family: fontFamily; font.pixelSize: 15; color: "#cccccc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: menuItem.hovered ? "#333333" : "transparent"; radius: 4 }
        }
        MenuItem {
            visible: root.showDefaultContextMenu
            height: root.showDefaultContextMenu ? implicitHeight : 0
            text: "删除此歌曲"
            contentItem: Label { text: "删除此歌曲"; font.family: fontFamily; font.pixelSize: 15; color: "#e06666"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
            onClicked: deleteConfirmDialog.open()
        }
        MenuSeparator {
            visible: root.showDefaultContextMenu && root.contextMenuExtra.length > 0
            height: root.showDefaultContextMenu && root.contextMenuExtra.length > 0 ? implicitHeight : 0
            contentItem: Rectangle { implicitHeight: 1; implicitWidth: 130; color: "#3A3A3A" }
        }
        Instantiator {
            model: root.contextMenuExtra
            MenuItem {
                text: modelData.text || ""
                onClicked: { if (modelData.onClicked) modelData.onClicked(); root.rightClickedTrack = null }
                contentItem: Label { text: modelData.text || ""; font.family: fontFamily; font.pixelSize: 15; color: "#cccccc"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { color: parent.hovered ? "#333333" : "transparent"; radius: 4 }
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
            color: "#222222"
            radius: 10
            border.color: "#3A3A3A"
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 14

            Label {
                text: "切换播放来源"
                font.family: fontFamily
                font.pixelSize: 17
                font.bold: true
                color: "#dddddd"
                Layout.bottomMargin: 4
            }

            Label {
                text: root.dialogMode === "custom"
                      ? "当前播放来源不是本列表，\n将改变播放列表并播放选定的歌曲。"
                      : root.dialogMode === "switch"
                      ? "当前播放来源不是本列表，\n将切换播放来源并播放选定的歌曲。"
                      : "当前播放来源不是本列表，\n将从头播放选定的歌曲。"
                font.family: fontFamily
                font.pixelSize: 15
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
                    color: switchCancelMA.containsMouse ? "#333333" : "#1E1E1E"
                    border.color: "#3A3A3A"; border.width: 1
                    Label { text: "取消"; anchors.centerIn: parent; font.family: fontFamily; font.pixelSize: 13; color: "#999" }
                    MouseArea {
                        id: switchCancelMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: switchSourceDialog.close()
                    }
                }

                Rectangle {
                    Layout.preferredHeight: 34; Layout.preferredWidth: 76; radius: 6
                    color: switchConfirmMA.containsMouse ? "#5B9EF6" : "#3B82F6"
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
            color: "#222222"
            radius: 10
            border.color: "#3A3A3A"
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
                text: "我们不会从磁盘删除此歌曲文件，可通过「添加本地音乐」或「从音乐库导入」重新加回。\n\n此操作会同步删除历史、播放列表、收藏及所有自建歌单（在所有音乐中删除的话）中的此歌曲。"
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
                    color: delCancelMA.containsMouse ? "#333333" : "#1E1E1E"
                    border.color: "#3A3A3A"; border.width: 1
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
