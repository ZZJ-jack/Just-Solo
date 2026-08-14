import QtQuick
import QtQuick.Controls
import QtQuick.Effects

// ============================================================
// 主页 — 首页封面墙：正方形方块 + 大圆封面
// 方块 210×210 显示歌名/歌手与播放按钮，右缘盖住第一个圆的一半
// 圆形封面 140×140 显示专辑封面，按当前播放列表顺序向右逐个排开
// （跟随 currentPlaylist：切换播放列表时主页同步更新）
// 沉浸背景模式下方块跟随当前歌曲主色
// ============================================================
Item {
    id: root

    // 由 main.qml 控制：true=当前显示主页
    property bool active: false
    property string fontFamily
    // 封面墙数据源（当前播放/查看的列表）：由 main.qml 按播放来源传入
    // （注意 root.sourceList 属性只读 m_playlist，收藏/历史播放时≠实际播放列表，勿直接用）
    property var sourceList: []
    // 原始（未排序）列表：与 sourceList 同内容仅顺序不同（当前排序模式已重排 sourceList）。
    // 播放时把 sourceList 的显示下标映射回播放列表真实下标再调用 playIndex
    property var rawSourceList: []
    // 当前列表名（收藏/历史/自定义歌单名/播放列表），由 main.qml 按播放来源传入
    property string listName: ""

    visible: active && sourceList.length > 0

    Row {
        id: homeCoverStrip
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: 5 // 与顶部边距
        anchors.leftMargin: 0 // 与左侧边距
        spacing: -homeCoverStrip.roundSize / 2   // 负间距让第一个圆露出半边

        readonly property int blockSize: 210 // 方块尺寸
        readonly property int roundSize: 140 // 圆尺寸
        readonly property int circleSpacing: 14 // 圆间距

        // 方块展示的歌曲：优先当前播放（且在播放列表中），否则第一首
        readonly property int blockSongIndex: {
            var list = root.sourceList
            if (list.length === 0) return -1
            var p = musicManager.currentPath || ""
            for (var i = 0; i < list.length; i++) {
                if (list[i].path === p) return i
            }
            return 0
        }

        // 切歌方向检测：驱动封面圆"移动动画"（下一首左滑一格 / 上一首右滑一格）。
        // 仅在"同一播放列表内"切歌时滑动；列表切换/点击圆引发的切歌直接更新窗口
        property int _prevBlockIndex: -1
        property string _prevListKey: ""
        // 初始化“上一状态”为初始显示起点：否则启动后第一次切歌时 _prevBlockIndex 仍为 -1，
        // 会被误判为“无上一首/列表切换”而直接跳变，导致首帧不滑动
        Component.onCompleted: {
            homeCoverStrip._prevBlockIndex = homeCoverStrip.blockSongIndex
            homeCoverStrip._prevListKey = root.sourceList.length > 0 ? (root.sourceList[0].path || "") : ""
            // 断开 displayIndex 的初始绑定：否则首次切歌时它会跟随 blockSongIndex 直接跳到新窗口，
            // 旧窗口未被保留，滑动动画就变成“滚过头再弹回”
            circlesRow.commitDisplay(homeCoverStrip.blockSongIndex)
        }
        onBlockSongIndexChanged: {
            var cur = blockSongIndex
            if (cur < 0) { homeCoverStrip._prevBlockIndex = cur; return }
            var listKey = root.sourceList.length > 0 ? (root.sourceList[0].path || "") : ""
            var listSwitched = (listKey !== homeCoverStrip._prevListKey)
            homeCoverStrip._prevListKey = listKey
            var prev = homeCoverStrip._prevBlockIndex
            homeCoverStrip._prevBlockIndex = cur
            // 播放列表切换：内容直接更新，不滑动
            if (listSwitched) { circlesRow.commitDisplay(cur); return }
            // 点击封面圆引发：点击圆动画已自带滑动，这里直接同步窗口
            if (Date.now() - circlesRow._lastCircleClickAt < 500) { circlesRow.commitDisplay(cur); return }
            // 同一列表内切歌：启动滑动动画（动画期间旧窗口滑出，结束 commitDisplay 新窗口滑入）
            if (prev >= 0) {
                var n = root.sourceList.length
                if (n > 1) {
                    var delta = cur - prev
                    // 循环取最短方向（如 80→0 视为 +1 而非 -80）
                    if (delta > n / 2) delta -= n
                    else if (delta < -n / 2) delta += n
                    if (delta !== 0)
                        circlesRow.playSwitchSlide(delta)
                    else
                        circlesRow.commitDisplay(cur)
                } else {
                    circlesRow.commitDisplay(cur)
                }
            } else {
                circlesRow.commitDisplay(cur)
            }
        }

        // 播放/暂停指定下标的歌曲（与封面点击行为一致，下标为当前播放列表下标）
        property double lastToggle: 0   // 方块/首圆点击防抖时间戳

        // 把排序后的显示下标映射回播放列表真实下标（在 rawSourceList 中按路径定位，未找到返回 -1）
        function toRealIndex(sortedIdx) {
            if (sortedIdx < 0) return -1
            var song = root.sourceList[sortedIdx]
            if (!song) return -1
            var path = song.path || ""
            var raw = root.rawSourceList || []
            for (var i = 0; i < raw.length; i++) {
                if ((raw[i].path || "") === path) return i
            }
            return -1
        }

        function toggleOrPlay(idx) {
            if (idx < 0) return
            // 防抖：0.5s 内重复点击直接忽略（防止快速双击导致播放/暂停抖动）
            var now = Date.now()
            if (now - homeCoverStrip.lastToggle < 500) return
            homeCoverStrip.lastToggle = now
            var song = root.sourceList[idx]
            if (musicManager.currentPath === song.path) {
                if (musicManager.isPlaying) musicManager.pause()
                else musicManager.play()
            } else {
                // sourceList 已按排序模式重排，需映射回播放列表真实下标再播放
                var realIdx = homeCoverStrip.toRealIndex(idx)
                if (realIdx >= 0) musicManager.playIndex(realIdx)
            }
        }

        // ---- 正方形方块 ----
        Rectangle {
            id: homeBlock
            width: homeCoverStrip.blockSize
            height: homeCoverStrip.blockSize
            radius: 24
            z: 3    // 盖在第一个圆的上面

            // 沉浸背景模式：跟随方块当前显示歌曲的主色（未播放也能变色），否则默认深色
            color: {
                var bg = (typeof musicManager !== "undefined" && musicManager)
                         ? musicManager.playbackBackground : 0
                if (bg !== 1) return "#2C2C2C"
                var idx = homeCoverStrip.blockSongIndex
                var c = ""
                if (idx >= 0 && idx < root.sourceList.length) {
                    var song = root.sourceList[idx]
                    c = (song && song.path) ? musicManager.coverColorOfPath(song.path) : ""
                }
                return c !== "" ? c : "#2C2C2C"
            }
            Behavior on color { ColorAnimation { duration: 600 } }

            // ---- 列表名（标题）：置顶，距卡片顶部 5px ----
            Item {
                id: listNameClip
                anchors.top: parent.top
                anchors.topMargin: 15
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.rightMargin: 20
                height: 20
                clip: true
                visible: root.listName !== ""

                property bool needsScroll: listNameText.contentWidth > width

                Text {
                    id: listNameText
                    text: root.listName
                    font.family: root.fontFamily
                    font.pixelSize: 20
                    color: "#ffffff"
                    x: listNameClip.needsScroll ? listNameClip.width : 0
                    y: (listNameClip.height - height) / 2

                    SequentialAnimation on x {
                        running: listNameClip.needsScroll && root.visible
                        loops: Animation.Infinite
                        // 从右侧滚入 → 匀速滚到左侧滚出 → 空一小下 → 循环
                        NumberAnimation {
                            from: listNameClip.width
                            to: -listNameText.contentWidth
                            duration: Math.max(6000, (listNameClip.width + listNameText.contentWidth) * 12)
                            easing.type: Easing.Linear
                        }
                        PauseAnimation { duration: 800 }
                        PropertyAnimation { property: "x"; to: listNameClip.width; duration: 0 }
                    }
                }
            }

            // ---- 歌名 / 歌手（垂直居中，靠左） ----
            Column {
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -3   // 整体上移 3px
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.rightMargin: 20
                spacing: 6

                Label {
                    width: parent.width
                    text: homeCoverStrip.blockSongIndex >= 0
                          ? (root.sourceList[homeCoverStrip.blockSongIndex].name || "未知歌曲") : ""
                    font.family: root.fontFamily
                    font.pixelSize: 27
                    font.bold: true
                    color: "#ffffff"
                    elide: Text.ElideRight
                }

                Label {
                    width: parent.width
                    text: homeCoverStrip.blockSongIndex >= 0
                          ? (root.sourceList[homeCoverStrip.blockSongIndex].artist || "未知歌手") : ""
                    font.family: root.fontFamily
                    font.pixelSize: 20
                    color: "#dddddd"
                    elide: Text.ElideRight
                }
            }

            // ---- 频谱律动（真实音频频谱，仅播放时律动） ----
            SpectrumBars {
                id: homeSpectrum
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 16
                running: musicManager.isPlaying
            }

            // ---- 点击封面：播放/暂停 ----
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: homeCoverStrip.toggleOrPlay(homeCoverStrip.blockSongIndex)
            }

            // ---- 播放 / 暂停按钮 ----
            Rectangle {
                id: homePlayBtn
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10 // 与底部边距
                anchors.rightMargin: 10 // 与右侧边距
                width: 48
                height: 48
                radius: 24
                color: homePlayMA.containsMouse ? "#59ffffff" : "#40ffffff"
                border.color: "#66ffffff"
                border.width: 1
                Behavior on color { ColorAnimation { duration: 150 } }

                Image {
                    anchors.centerIn: parent
                    anchors.leftMargin: 1
                    source: {
                        var idx = homeCoverStrip.blockSongIndex
                        var isCur = idx >= 0 && idx < root.sourceList.length
                                   && musicManager.currentPath === root.sourceList[idx].path
                        return (isCur && musicManager.isPlaying)
                               ? "qrc:/qt/qml/JustSolo/data/image/playing.png"
                               : "qrc:/qt/qml/JustSolo/data/image/play.png"
                    }
                    width: 37
                    height: 37
                    fillMode: Image.PreserveAspectFit
                }

                MouseArea {
                    id: homePlayMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: homeCoverStrip.toggleOrPlay(homeCoverStrip.blockSongIndex)
                }
            }
        }

        // ---- 封面圆 ----
        Row {
            id: circlesRow
            y: (homeCoverStrip.blockSize - homeCoverStrip.roundSize) / 2   // 与方块上下居中
            spacing: homeCoverStrip.circleSpacing
            transform: Translate { id: circleShift; x: 0 }

            property int shiftTarget: -1   // 动画结束后窗口起点（sourceList 显示下标）
            property int shiftPlayTarget: -1   // 动画结束后要播放的歌曲真实下标（-1=仅滑动不播放）
            property double lastCircleClick: 0   // 封面圆点击防抖时间戳（0.5s 内忽略重复点击）
            property double _lastCircleClickAt: 0  // 点击圆时间戳：其引发的切歌不再触发切歌滑动（避免多滑一格）
            // 封面墙"显示起点"：delegate 绑定它而非 blockSongIndex——
            // 滑动动画期间保持旧窗口内容，动画结束(commitDisplay)才切换到新窗口，实现"旧排滑出→新排滑入"
            property int displayIndex: homeCoverStrip.blockSongIndex >= 0 ? homeCoverStrip.blockSongIndex : 0
            property int _pendingDisplayIndex: -1   // 动画结束后要应用的新窗口起点
            function commitDisplay(idx) {
                circlesRow.displayIndex = idx
                circlesRow._pendingDisplayIndex = -1
            }
            // 固定窗口：常驻 10 个圆。delegate 数量恒定，切歌时仅更新封面内容
            // （见 delegate 内 songIndex 绑定 + Image.cache:false 自动清理旧图），
            // 不销毁/创建对象，避免切歌产生垃圾与纹理缓存累积
            readonly property int windowSize: 10

            // ---- 切歌移动动画：旧窗口向切换方向滑一格，结束后切换到新窗口（下一首左滑/上一首右滑）----
            NumberAnimation {
                id: circleSwitchAnim
                target: circleShift
                property: "x"
                duration: 260
                easing.type: Easing.OutCubic
                onRunningChanged: {
                    if (!circleSwitchAnim.running) {
                        circleShift.x = 0
                        if (circlesRow._pendingDisplayIndex >= 0)
                            circlesRow.commitDisplay(circlesRow._pendingDisplayIndex)
                    }
                }
            }
            function playSwitchSlide(delta) {
                if (delta === 0) return
                circlesRow._pendingDisplayIndex = homeCoverStrip.blockSongIndex  // 动画结束后窗口起点=新当前歌
                circleSwitchAnim.stop()
                circleShiftAnim.stop()   // 互斥：切歌滑动打断点击滑动
                circleShift.x = 0
                circleSwitchAnim.to = -delta * (homeCoverStrip.roundSize + homeCoverStrip.circleSpacing)
                circleSwitchAnim.start()
            }

            // 点击后面的圆：整排圆向左滑，被点的圆滑到封面位置
            NumberAnimation {
                id: circleShiftAnim
                target: circleShift
                property: "x"
                duration: 350
                easing.type: Easing.OutCubic
                onRunningChanged: {
                    if (!circleShiftAnim.running) {
                        circleShift.x = 0
                        var t = circlesRow.shiftTarget
                        var p = circlesRow.shiftPlayTarget
                        circlesRow.shiftTarget = -1   // 消费目标，防止被 stop() 误触发重复播放
                        circlesRow.shiftPlayTarget = -1
                        if (t >= 0) {
                            circlesRow.commitDisplay(t)  // 新窗口以目标歌为起点
                            if (p >= 0) musicManager.playIndex(p)   // 用真实下标播放
                        }
                    }
                }
            }

            Repeater {
                // model 固定为窗口索引 [0..windowSize)：delegate 数量恒定、永不销毁重建。
                // 切歌/切播放列表时 blockSongIndex 变化 → delegate 内 songIndex 绑定重算
                // → Image.source 原位更新为新歌曲封面（旧图随 cache:false 立即释放）
                model: {
                    var n = root.sourceList.length
                    if (n === 0) return []
                    var arr = []
                    var count = Math.min(circlesRow.windowSize, n)
                    for (var i = 0; i < count; i++) arr.push(i)
                    return arr
                }

                delegate: Rectangle {
                    width: homeCoverStrip.roundSize
                    height: homeCoverStrip.roundSize
                    radius: width / 2
                    color: "#3A3A3A"
                    border.color: circleHover.containsMouse ? "#ffffff" : "#dddddd"
                    border.width: 6
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    // 窗口内第 index 个圆对应的播放列表真实下标
                    // （起点用 displayIndex：滑动动画期间保持旧窗口，动画结束 commitDisplay 后切换新窗口）
                    readonly property int songIndex: {
                        var n = root.sourceList.length
                        if (n === 0) return -1
                        var start = circlesRow.displayIndex
                        if (start < 0) start = 0
                        return (start + index) % n
                    }
                    // 当前圆显示的歌曲对象（不存在返回 null，供 source/visible 判断）
                    readonly property var song: songIndex >= 0 && songIndex < root.sourceList.length
                                               ? root.sourceList[songIndex] : null

                    Image {
                        anchors.fill: parent
                        anchors.margins: 6
                        source: (song && song.cover) ? song.cover : ""
                        sourceSize.width: 128
                        sourceSize.height: 128
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false   // 不进全局图片缓存：切歌换封面时旧图立即释放，防止内存累积
                        visible: song && song.cover && song.cover !== ""
                        // 切歌动画：封面切换时淡出→淡入（status 变化驱动）
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: circleCoverMask
                        }
                        Rectangle {
                            id: circleCoverMask
                            anchors.fill: parent
                            radius: width / 2
                            visible: false
                            layer.enabled: true
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        text: "\u266B"
                        font.family: root.fontFamily
                        font.pixelSize: 36
                        color: "#666"
                        visible: !song || !song.cover || song.cover === ""
                    }

                    MouseArea {
                        id: circleHover
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // 点击防抖：0.5s 内重复点击忽略（防止滑动动画叠加/错乱）
                            var now = Date.now()
                            if (now - circlesRow.lastCircleClick < 500) return
                            circlesRow.lastCircleClick = now
                            circlesRow._lastCircleClickAt = now   // 抑制本次点击引发的切歌滑动动画
                            // 圆圈按循环顺序排列，点击时映射回播放列表真实下标
                            var n = root.sourceList.length
                            if (n === 0 || songIndex < 0) return
                            var realIndex = songIndex
                            if (index === 0) {
                                // 第一个圆与封面是同一首歌：当作点击封面，播放/暂停
                                homeCoverStrip.toggleOrPlay(realIndex)
                            } else {
                                // 点击后面的圆：动画滑到封面位置后再播放
                                circlesRow.shiftTarget = realIndex   // 显示下标（sourceList 排序后）
                                circlesRow.shiftPlayTarget = homeCoverStrip.toRealIndex(realIndex)  // 真实播放下标
                                circleShift.x = 0
                                circleSwitchAnim.stop()   // 互斥：点击滑动打断切歌滑动
                                circleShiftAnim.to = -index * (homeCoverStrip.roundSize + homeCoverStrip.circleSpacing)
                                circleShiftAnim.start()
                            }
                        }
                    }
                }
            }
        }
    }
}
