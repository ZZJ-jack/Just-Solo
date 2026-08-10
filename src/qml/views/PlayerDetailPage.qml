import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts

Item {
    id: root

    required property string fontFamily

    // 歌词字体（外观设置中可选；空时回退到全局字体）
    property string lyricFontFamily: {
        if (typeof musicManager === "undefined" || !musicManager) return fontFamily
        var f = musicManager.lyricFontFamily || ""
        return f !== "" ? f : fontFamily
    }

    // 歌词布局字号：最大化/全屏窗口时歌词放大，默认窗口略小
    property real _fontFactor: (typeof mainWindow !== "undefined" && mainWindow
                                && (mainWindow.visibility === Window.FullScreen
                                    || mainWindow.visibility === Window.Maximized)) ? 1.2 : 0.85
    property real mainFontSize: 52 * _fontFactor
    property real transFontSize: 30 * _fontFactor

    // 封面高度系数：最大化/全屏窗口时封面再放大一点
    property real _coverHeightFactor: (typeof mainWindow !== "undefined" && mainWindow
                                       && (mainWindow.visibility === Window.FullScreen
                                           || mainWindow.visibility === Window.Maximized)) ? 0.62 : 0.55

    property bool opening: false
    property bool _closing: false  // 是否为真正的关闭流程：控制 closeAnim 完成时是否允许隐藏页面
    property int _pastIdx: -1  // 已播放到的歌词行索引（前进时增大，回退/切歌时重置）
    property int _lastIdxTime: 0  // 上次切行的时间戳，用于区分正常播放与快速 seek
    property int _manualScrollIdx: -1  // 手动滚动时当前居中行的索引（仅 playbackRate===1.0 时生效）
    property bool _manualActive: false  // 用户手动滚动激活（控制时间/虚线/按钮显示）；播放进度变化或变速时自动关闭
    property bool _autoScrolling: false  // centerOnIndex 正在自动滚动时为 true（用于区分用户手动滚动）
    property real _manualCenterY: -999  // 居中行中心在歌词视口坐标系中的 y（供悬浮时间层定位）
    property int _manualCenterTime: 0  // 居中行的时间戳（供悬浮时间层显示）

    // 播放背景模式：0=深色背景，1=沉浸背景（与设置页联动）
    readonly property bool _immersiveBg: (typeof musicManager !== "undefined" && musicManager)
                                         ? musicManager.playbackBackground === 1 : false

    // 进入迷你小窗模式信号
    signal enterMiniMode()

    // 页面滑动偏移量（初始推至视口外，动画直接修改此值，避免绑定被 QML 重求值）
    property real _slideOffset: root.height

    opacity: 0
    visible: false

    // 使用位移来实现滑动，初始把整个页面向下推至视口外 (y: root.height)
    transform: Translate {
        id: slider
        y: _slideOffset
    }

    function fmtTime(ms) {
        if (ms <= 0) return "00:00"
        var s = Math.floor(ms / 1000)
        return ("0" + Math.floor(s / 60)).slice(-2) + ":" + ("0" + (s % 60)).slice(-2)
    }

    function close() {
        if (!visible || opening) return
        // 标记为真正的关闭流程：closeAnim 完成后才允许隐藏页面
        // （防止进入小窗后立刻退出时，残留 closeAnim 的回调把重新打开的页面又隐藏）
        root._closing = true
        closeAnim.start()
        // 延迟 50ms 后通知控制栏变回原色（让详情页关闭动画先启动一点点）
        controlBarResetTimer.restart()
    }

    // 强制重新打开（处理意外隐藏/状态不同步的情况）
    function reopen() {
        // 取消关闭流程标记：残留 closeAnim 完成时不得隐藏页面
        root._closing = false
        // 停止控制栏重置计时器，避免它把 showPlayerDetail 覆盖回 false
        // （小窗退出后立即重新打开详情页的场景）
        controlBarResetTimer.stop()
        // 确保控制栏沉浸色状态为 true（防止残留 closeAnim 回调已把其置 false）
        if (typeof mainWindow !== "undefined" && mainWindow)
            mainWindow.showPlayerDetail = true
        openAnim.stop()
        closeAnim.stop()
        opening = true
        if (visible) {
            // visible 仍为 true，但可能被动画中断导致 opacity=0 / _slideOffset=height
            // 直接重置状态并主动启动打开动画
            _slideOffset = root.height
            opacity = 0
            openAnim.start()
        } else {
            visible = true
            // onVisibleChanged 中将启动 openAnim.start()
        }
    }

    // 控制栏重置计时器：close() 后 50ms 触发，通知底部控制栏变回原色
    Timer {
        id: controlBarResetTimer
        interval: 50
        onTriggered: {
            if (typeof mainWindow !== "undefined" && mainWindow)
                mainWindow.showPlayerDetail = false
        }
    }

    // 滚动对齐到指定歌词行，使其精确居中。
    // 歌词行高度不固定（有无翻译、长文本换行不同）。由于 cacheBuffer 足够大，
    // 所有行都已实例化，几何信息始终是真实值，直接测量目标行在视口内的实际位置
    // 即可算出精确落点，不存在平均行高估算误差，也不会随歌词行数累积偏移。
    // animate=true 时从当前滚动位置平滑滚过去；false 时直接落位（进入页面/快速 seek）。
    function centerOnIndex(idx, animate) {
        if (lyricsView.count === 0 || idx < 0) return
        lyricScrollAnim.stop()
        root._autoScrolling = true  // 标记自动滚动中，防止 onMovementStarted 误判为手动滚动
        var item = lyricsView.itemAtIndex(idx)
        if (!item) {
            // delegate 还未实例化（从后台恢复时 ListView 刚重建），
            // 用粗略定位把目标行拉进视口，并延迟一帧重试精确定位
            lyricsView.positionViewAtIndex(idx, ListView.Center)
            _centerRetryTimer.idx = idx
            _centerRetryTimer.animate = animate
            _centerRetryTimer.restart()
            return
        }
        // 目标行顶部在视口内的实际位置 → 需要滚动的偏移 = 视口中心 - 行中心
        var from = lyricsView.contentY
        var topInView = item.mapToItem(lyricsView, 0, 0).y
        var to = lyricsView.contentY + topInView - (lyricsView.height - item.height) / 2
        // 边界钳制：允许越过首尾边界（借用 topMargin/bottomMargin 空间），
        // 让第一句和最后一句也能滚动到视口中心
        var minY = -lyricsView.topMargin
        var maxY = lyricsView.contentHeight - lyricsView.height + lyricsView.bottomMargin
        to = Math.max(minY, Math.min(to, maxY))
        if (animate !== false && Math.abs(to - from) >= 0.5) {
            lyricScrollAnim.from = from
            lyricScrollAnim.to = to
            lyricScrollAnim.start()
        } else {
            // 直接落位（进入页面 / 快速 seek / 从后台恢复），或目标已与当前位置一致无需动画。
            // 两种情况下都必须立即清除自动滚动标志：否则 _autoScrolling 会一直卡在 true，
            // 导致 onMovementStarted 不再激活手动滚动（表现为恢复原位置无动画后无法再滚动）
            lyricsView.contentY = to
            root._autoScrolling = false
        }
    }

    // delegate 未实例化时的精确定位重试定时器（配合 centerOnIndex 使用）
    Timer {
        id: _centerRetryTimer
        interval: 60
        property int idx: -1
        property bool animate: false
        onTriggered: {
            if (idx < 0 || lyricsView.count === 0) return
            if (lyricsView.itemAtIndex(idx)) {
                var savedIdx = idx
                var savedAnimate = animate
                idx = -1  // 清除标记，避免重复触发
                root.centerOnIndex(savedIdx, savedAnimate)
            } else {
                // delegate 仍未实例化，放弃定位（避免无限重试，等下次 lyricIndex 变化时自然对齐）；
                // 同时清除自动滚动标志，防止 _autoScrolling 卡死导致手动滚动失效
                idx = -1
                root._autoScrolling = false
            }
        }
    }

    // 变速切换回 1x 时延迟一帧检测居中行（等 delegate 宽度重排完成）
    Timer {
        id: _manualCenterTimer
        interval: 150
        onTriggered: root.updateManualCenterIdx()
    }

    // 手动滚动无操作 3s 后自动退出手动模式，恢复自动跟随
    Timer {
        id: _manualExitTimer
        interval: 3000
        onTriggered: {
            root._manualActive = false
            // 退出后自动滚动到当前播放行
            if (typeof musicManager !== "undefined" && musicManager
                    && musicManager.lyricIndex >= 0)
                root.centerOnIndex(musicManager.lyricIndex, true)
        }
    }

    // 计算当前视口中央的歌词行索引（仅 1x 手动滚动模式下使用）
    // 遍历已实例化的 delegate，找到中心点最接近视口中央的行
    function updateManualCenterIdx() {
        if (typeof musicManager === "undefined" || !musicManager) return
        if (musicManager.playbackRate !== 1.0) {
            if (root._manualScrollIdx !== -1)
                root._manualScrollIdx = -1
            root._manualCenterY = -999
            return
        }
        if (lyricsView.count === 0) {
            if (root._manualScrollIdx !== -1)
                root._manualScrollIdx = -1
            root._manualCenterY = -999
            return
        }
        var centerY = lyricsView.contentY + lyricsView.height / 2
        var bestIdx = -1
        var bestDist = Infinity
        for (var i = 0; i < lyricsView.count; ++i) {
            var item = lyricsView.itemAtIndex(i)
            if (!item) continue
            var itemCenter = item.y + item.height / 2
            var dist = Math.abs(itemCenter - centerY)
            if (dist < bestDist) {
                bestDist = dist
                bestIdx = i
            }
        }
        if (bestIdx >= 0) {
            if (bestIdx !== root._manualScrollIdx)
                root._manualScrollIdx = bestIdx
            // 记录居中行中心位置（供歌词列外的悬浮时间层定位）
            var cItem = lyricsView.itemAtIndex(bestIdx)
            if (cItem) {
                var centerInView = cItem.mapToItem(lyricsView, 0, cItem.height / 2).y
                if (Math.abs(centerInView - root._manualCenterY) > 0.5)
                    root._manualCenterY = centerInView
            }
            // 直接按索引取歌词数组的时间，避免经 delegate 上下文访问不可靠
            var arr = (typeof musicManager !== "undefined" && musicManager)
                      ? (musicManager.currentLyrics || []) : []
            if (bestIdx < arr.length && arr[bestIdx]) {
                var t = arr[bestIdx].time || 0
                if (t !== root._manualCenterTime)
                    root._manualCenterTime = t
            }
        } else {
            root._manualCenterY = -999
        }
    }

    onVisibleChanged: {
        if (visible) {
            // 重新显示：取消关闭流程标记，残留 closeAnim 完成时不得隐藏页面
            root._closing = false
            // 先停掉残留的关闭动画，防止其 onFinished 把 visible 设回 false
            closeAnim.stop()
            opening = true
            openAnim.start() // 直接启动动画，不再等待沉浸背景渲染
        } else {
            openAnim.stop()
            closeAnim.stop()
        }
    }

    Connections {
        target: typeof musicManager !== "undefined" && musicManager ? musicManager : null
        function onCurrentLyricsChanged() {
            // 切换歌曲时重置已播索引，避免旧歌的 _pastIdx 污染新歌词的状态
            root._pastIdx = -1
            root._manualScrollIdx = -1  // 切歌时重置手动滚动居中行
            root._manualActive = false  // 切歌时退出手动滚动模式
            _manualExitTimer.stop()
            // 歌词模型已替换（ListView 内容重置），等布局稳定后直接对齐首行
            lyricRecenterTimer.snap = true
            lyricRecenterTimer.restart()
        }
        function onLyricIndexChanged() {
            var idx = musicManager.lyricIndex
            if (idx < 0) return
            // 回退（单曲循环回到开头 / 手动 seek 回退）→ 重置已播状态后重新高亮
            if (idx < root._pastIdx)
                root._pastIdx = -1
            // 正常前进：_pastIdx 跟随当前行（只增大不收缩）
            if (idx > root._pastIdx)
                root._pastIdx = idx
            // 300ms 内连续切行视为拖动进度条（快速 seek），直接落位避免动画追赶不上；
            // 正常播放切行则平滑滚动
            var now = Date.now()
            var rapid = now - root._lastIdxTime < 300
            root._lastIdxTime = now
            // 手动滚动激活时，禁用自动滚动（让用户自由浏览歌词）
            if (!root._manualActive)
                root.centerOnIndex(idx, !rapid)
        }
        function onPlaybackRateChanged() {
            // 变速时禁用手动滚动 UI，恢复原歌词显示；1x 时延迟检测居中行
            root._manualActive = false
            _manualExitTimer.stop()
            if (musicManager.playbackRate !== 1.0) {
                root._manualScrollIdx = -1
            } else {
                _manualCenterTimer.restart()
            }
            // 变速后歌词容器宽度变化（手动模式切换导致换行变化），重新居中当前播放行
            lyricRecenterTimer.snap = true
            lyricRecenterTimer.restart()
        }
    }

    SequentialAnimation {
        id: openAnim
        ParallelAnimation {
            // 透明度：从 0 到 1
            OpacityAnimator { 
                target: root
                to: 1
                duration: 350
                easing.type: Easing.OutCubic // 非线性：先快后慢，平滑刹车
            }
            // 位置：从底部 (root.height) 滑动到正常位置 (0)
            NumberAnimation { 
                target: root
                property: "_slideOffset"
                from: root.height
                to: 0
                duration: 350
                easing.type: Easing.OutCubic
            }
        }
        ScriptAction { script: root.opening = false }
        // 进入详情页后直接对齐当前歌词行（立即居中，不做长滚动）
        ScriptAction { script: root.centerOnIndex((typeof musicManager !== "undefined" && musicManager) ? musicManager.lyricIndex : -1, false) }
    }

    SequentialAnimation {
        id: closeAnim
        ParallelAnimation {
            // 透明度：从 1 到 0
            OpacityAnimator { 
                target: root
                to: 0
                duration: 250
                easing.type: Easing.InCubic // 非线性：先慢后快，加速退出
            }
            // 位置：从 0 滑动回底部 (root.height)
            NumberAnimation { 
                target: root
                property: "_slideOffset"
                to: root.height
                duration: 250
                easing.type: Easing.InCubic 
            }
        }
        onFinished: {
            // 仅当确实是关闭流程时才隐藏页面；否则忽略（页面已被重新打开）
            if (root._closing) {
                root._closing = false
                root.visible = false
            }
        }
    }

    // 全屏事件屏蔽层（阻止所有操作穿透到下层）
    MouseArea {
        anchors.fill: parent
        anchors.bottomMargin: 75 // 放行底部 75px 的鼠标点击事件
        acceptedButtons: Qt.AllButtons
        hoverEnabled: false        // 无 hover 视觉反馈，关闭减少事件开销
        preventStealing: true
        propagateComposedEvents: false
        onWheel: function(w) { w.accepted = true }
        onPressed: function(m) { m.accepted = true }
    }

    // ============================================================
    // 背景：深色背景 / 沉浸背景（提取封面主色调 → 渐变色背景）
    // 深色背景 = 兜底深色单层；沉浸背景额外叠加两层：
    //   C++ 端提取的封面主色调作为底色 → 渐变遮罩（上透下暗）形成渐变色背景
    // ============================================================
    Item {
        id: bgLayer
        anchors.fill: parent
        anchors.bottomMargin: 75 // 让出底部的画面，露出 main.qml 的控制栏
        clip: true

        // 兜底色：深色背景模式下的唯一背景（也是沉浸模式的兜底）
        Rectangle {
            anchors.fill: parent
            color: "#1E1E1E"
        }

        // 沉浸背景层：仅在沉浸背景模式下渲染，淡出结束后自动隐藏以节省性能
        Item {
            anchors.fill: parent
            visible: root._immersiveBg || opacity > 0
            opacity: root._immersiveBg ? 1 : 0

            // 主色调底层：切歌时颜色平滑过渡（ColorAnimation）
            Rectangle {
                id: immersiveBase
                anchors.fill: parent
                color: {
                    var c = (typeof musicManager !== "undefined" && musicManager)
                            ? (musicManager.currentCoverColor || "") : ""
                    return c !== "" ? c : "#1E1E1E"
                }
                Behavior on color { ColorAnimation { duration: 600 } }
            }

            // 渐变遮罩：顶部透出主色调，底部仅轻微加深，避免底部发黑
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.5; color: "#30000000" }
                    GradientStop { position: 1.0; color: "#70000000" }
                }
            }
        }
    }

    // 迷你小窗按钮
    Rectangle {
        anchors.top: parent.top; anchors.right: maxBtn.left
        anchors.topMargin: 14; anchors.rightMargin: 8
        width: 36; height: 36; radius: 18
        color: miniEnterMA.containsMouse ? "#33ffffff" : "transparent"

        Image {
            id: miniEnterIcon
            visible: false
            width: 20; height: 20
            source: "qrc:/qt/qml/JustSolo/data/image/mini-enter.png"
            fillMode: Image.PreserveAspectFit
        }
        MultiEffect {
            anchors.centerIn: parent
            width: miniEnterIcon.width; height: miniEnterIcon.height
            source: miniEnterIcon
            // 染色为白色 #FFFFFF，与关闭按钮统一
            colorizationColor: "#FFFFFF"
            colorization: 1.0
        }

        MouseArea {
            id: miniEnterMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.enterMiniMode()
        }
    }

    // 关闭按钮
    Rectangle {
        id: closeBtn
        anchors.top: parent.top; anchors.right: parent.right
        anchors.topMargin: 14; anchors.rightMargin: 22
        width: 36; height: 36; radius: 18
        color: closeMA.containsMouse ? "#33ffffff" : "transparent"

        Image {
            anchors.centerIn: parent
            width: 23; height: 23
            source: "data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='%23ffffff' stroke-width='2.5' stroke-linecap='round'><path d='M18 6L6 18M6 6l12 12'/></svg>"
            fillMode: Image.PreserveAspectFit
        }

        MouseArea { 
            id: closeMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.close() 
        }
    }

    // 最大化按钮
    Rectangle {
        id: maxBtn
        anchors.top: parent.top; anchors.right: closeBtn.left
        anchors.topMargin: 14; anchors.rightMargin: 8
        width: 36; height: 36; radius: 18
        color: maxBtnMA.containsMouse ? "#33ffffff" : "transparent"

        Image {
            id: maxBtnIcon
            visible: false
            width: 18; height: 18
            source: (typeof mainWindow !== "undefined" && mainWindow && mainWindow.visibility === Window.FullScreen)
                    ? "qrc:/qt/qml/JustSolo/data/image/Biggest-exit.png"
                    : "qrc:/qt/qml/JustSolo/data/image/Biggest-enter.png"
            fillMode: Image.PreserveAspectFit
        }
        MultiEffect {
            anchors.centerIn: parent
            width: maxBtnIcon.width; height: maxBtnIcon.height
            source: maxBtnIcon
            // 染色为白色 #FFFFFF，与迷你小窗/关闭按钮统一
            colorizationColor: "#FFFFFF"
            colorization: 1.0
        }

        MouseArea {
            id: maxBtnMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (typeof mainWindow === "undefined" || !mainWindow) return
                // 等效 F11 全屏切换
                if (mainWindow.visibility === Window.FullScreen)
                    mainWindow.showNormal()
                else
                    mainWindow.showFullScreen()
            }
        }
    }

    // ============================================================
    // 主体
    // ============================================================
    Item {
        id: mainBody
        anchors.top: parent.top; anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        anchors.topMargin: 46; anchors.bottomMargin: 75

        // 左：封面 + 歌名 + 歌手 + 专辑
        Item {
            id: coverArea
            anchors.top: parent.top; anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: parent.width * 4 / 9 // 左右 4:5（左封面 : 右歌词）

            Rectangle {
                id: coverBox
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(0, parent.height * 0.04)
                width: Math.min(parent.width * 0.88, parent.height * root._coverHeightFactor)
                height: width; radius: 12; color: "#222222"

                Image {
                    id: coverImg
                    anchors.fill: parent; anchors.margins: 3
                    source: (typeof musicManager !== "undefined" && musicManager) ? (musicManager.currentCover || "") : ""
                    fillMode: Image.PreserveAspectFit; asynchronous: true
                    sourceSize: Qt.size(640, 640)  // 限制解码尺寸，避免全尺寸封面位图占用内存
                    visible: source !== ""
                    opacity: status === Image.Ready ? 1 : 0

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: ShaderEffectSource {
                            sourceItem: Rectangle {
                                width: coverImg.width
                                height: coverImg.height
                                radius: 9 // 背景的 radius(12) 减去 margins(3)
                            }
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent; font.family: root.fontFamily
                    text: "\u266B"; font.pixelSize: 42; color: "#333333"
                    visible: (typeof musicManager === "undefined" || !musicManager || musicManager.currentCover === "")
                }
            }

            // 歌名（超长时连续滚动：右侧滚入 → 左侧滚出 → 空一小下 → 新文字从右侧滚入）
            Item {
                id: songNameClip
                anchors.top: coverBox.bottom; anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24
                height: songNameText.implicitHeight
                clip: true

                property bool needsScroll: songNameText.contentWidth > width

                Text {
                    id: songNameText
                    text: (typeof musicManager !== "undefined" && musicManager) ? (musicManager.currentTitle || "未在播放") : "未在播放"
                    font.family: root.fontFamily; font.pixelSize: 28; font.bold: true; color: "#f0f0f0"
                    x: songNameClip.needsScroll ? songNameClip.width : (songNameClip.width - songNameText.contentWidth) / 2

                    SequentialAnimation on x {
                        running: songNameClip.needsScroll && root.visible
                        loops: Animation.Infinite
                        // 从右侧视口外滚入 → 匀速滚到左侧滚出
                        NumberAnimation {
                            from: songNameClip.width
                            to: -songNameText.contentWidth
                            duration: Math.max(8000, (songNameClip.width + songNameText.contentWidth) * 10)
                            easing.type: Easing.Linear
                        }
                        // 滚出去了，空一小下
                        PauseAnimation { duration: 1000 }
                        // 瞬间回到右侧准备下一个循环
                        PropertyAnimation { property: "x"; to: songNameClip.width; duration: 0 }
                    }
                }
            }

            Text {
                id: artistName
                anchors.top: songNameClip.bottom; anchors.topMargin: 6
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24
                text: {
                    if (typeof musicManager === "undefined" || !musicManager) return "歌手：未知"
                    var a = (musicManager.currentArtist || "").replace(/[/;｜|]+/g, "、")
                    return a ? ("歌手：" + a) : "歌手：未知"
                }
                font.family: root.fontFamily; font.pixelSize: 18; color: "#f0f0f0"
                elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
            }

            Text {
                anchors.top: artistName.bottom; anchors.topMargin: 4
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24
                text: {
                    if (typeof musicManager === "undefined" || !musicManager) return ""
                    var a = musicManager.currentAlbum || ""
                    return a ? ("专辑：" + a) : ""
                }
                font.family: root.fontFamily; font.pixelSize: 15; color: "#f0f0f0"
                elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                visible: text !== ""
            }
        }

        // 右：歌词（只展示约 5 句；换行按固定字号预先排好，读到某句仅放大不重排）
        Item {
            id: lyricsCol
            anchors.top: parent.top; anchors.bottom: parent.bottom
            anchors.left: coverArea.right; anchors.right: parent.right
            anchors.leftMargin: 20
            clip: true

            Text {
                anchors.centerIn: parent
                text: "暂无歌词"; font.family: root.fontFamily; font.pixelSize: 20; color: "#3B82F6"
                visible: lyricsView.count === 0
            }

            ListView {
                id: lyricsView
                anchors.fill: parent
                model: (typeof musicManager !== "undefined" && musicManager) ? (musicManager.currentLyrics || []) : []
                spacing: 20
                // 上下留白让当前行居中，只展示约 5 句
                topMargin: parent.height * 0.38; bottomMargin: parent.height * 0.38
                clip: true; reuseItems: true
                // 历史原因：歌词行高度不固定（有无翻译/换行不同），曾用超大 cacheBuffer(1000000)
                // 让全部行实例化以保证任意行精确居中，但这会让数千行 delegate 全部常驻内存。
                // 改为约一屏半的合理值，让 reuseItems 真正生效；远处行未实例化时
                // centerOnIndex 会先 positionViewAtIndex 粗略定位，再由 _centerRetryTimer 精确定位
                cacheBuffer: 1500
                // 窗口大小变化后自动重新居中当前歌词（防抖，避免拖动过程中持续触发；平滑滚动）
                onWidthChanged: { lyricRecenterTimer.snap = false; lyricRecenterTimer.restart() }
                onHeightChanged: { lyricRecenterTimer.snap = false; lyricRecenterTimer.restart() }
                // 1x 手动滚动模式下，实时跟踪视口中央行（用于显示时间/播放按钮）
                onContentYChanged: {
                    if (typeof musicManager !== "undefined" && musicManager
                            && musicManager.playbackRate === 1.0) {
                        root.updateManualCenterIdx()
                        // 手动滚动激活时，重置 3s 退出计时
                        if (root._manualActive)
                            _manualExitTimer.restart()
                    }
                }
                // 用户开始手动滚动（拖动/滚轮）时激活手动模式（非自动滚动才触发）
                onMovementStarted: {
                    if (typeof musicManager !== "undefined" && musicManager
                            && musicManager.playbackRate === 1.0
                            && !root._autoScrolling) {
                        root._manualActive = true
                        _manualExitTimer.restart()
                    }
                }
                onMovementEnded: {
                    if (typeof musicManager !== "undefined" && musicManager
                            && musicManager.playbackRate === 1.0)
                        root.updateManualCenterIdx()
                }

                delegate: Item {
                    id: lyricDelegate
                    width: lyricsView.width
                    height: mainContainer.height + 8

                    property bool isCurrent: (typeof musicManager !== "undefined" && musicManager) && index === musicManager.lyricIndex
                    property bool isPast: index < root._pastIdx
                    property bool hasTrans: (modelData.translation || "") !== ""

                    // 放大比例：所有行都按放大后的固定字号布局，非当前行通过 Scale 缩小，当前行放大到原尺寸
                    property real mainScale: isCurrent ? 1.0 : 36 / 58
                    property real transScale: isCurrent ? 1.0 : 24 / 34

                    // 手动滚动模式：仅用户手动滚动激活时显示时间/虚线/按钮（1x 且 _manualActive）
                    property bool _isManualCenter: root._manualActive && index === root._manualScrollIdx

                    // 歌词主体（行高按固定字号布局，换行恒定，仅视觉缩放切换高亮）
                    // 垂直居中于 delegate（delegate 比内容高 8px），保证 ListView.Center
                    // 居中 delegate 时文本块的视觉中心恰好落在视口中心，无 4px 偏移
                    Item {
                        id: mainContainer
                        anchors.left: parent.left; anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: lyricsView.width - 8
                        height: mainCol.implicitHeight

                        Column {
                            id: mainCol
                            spacing: 4

                            // 主歌词行（固定字号布局保证换行稳定，超长自动换行）
                            Item {
                                width: mainContainer.width
                                height: Math.max(52, mainText.implicitHeight)
                                clip: true

                                Text {
                                    id: mainText
                                    anchors.left: parent.left
                                    // 缩小文本在行槽内垂直居中（跟随缩放动画逐帧更新），保证当前行与上下行间距一致
                                    y: (parent.height - height * scale) / 2
                                    width: parent.width
                                    text: modelData.text || ""
                                    font.family: root.lyricFontFamily
                                    font.pixelSize: root.mainFontSize // 固定布局字号，换行在加载时即确定
                                    // 单层文本直接切换高亮色，无需 overlay 叠加
                                    color: lyricDelegate.isPast ? "#FFD700"
                                         : (lyricDelegate.isCurrent ? "#00d4ff" : "#6a9ac0")
                                    horizontalAlignment: Text.AlignLeft
                                    wrapMode: Text.WordWrap
                                    // 仅做视觉缩放（当前行 1.0，非当前行缩至 36/58），不改变换行
                                    // 用 Item.scale 而非 transform:Scale 对象，避免 delegate 复用/销毁时动画崩溃
                                    scale: lyricDelegate.mainScale
                                    transformOrigin: Item.TopLeft
                                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }

                            // 翻译行（固定字号布局，高度自适应）
                            Item {
                                width: mainContainer.width
                                height: hasTrans ? Math.max(38, transText.implicitHeight) : 0
                                visible: hasTrans
                                clip: true

                                Text {
                                    id: transText
                                    anchors.left: parent.left
                                    // 缩小文本在行槽内垂直居中（跟随缩放动画逐帧更新），保证当前行与上下行间距一致
                                    y: (parent.height - height * scale) / 2
                                    width: parent.width
                                    text: modelData.translation || ""
                                    font.family: root.lyricFontFamily
                                    font.pixelSize: root.transFontSize // 固定布局字号
                                    color: lyricDelegate.isPast ? "#b8960f"
                                         : (lyricDelegate.isCurrent ? "#FFD700" : "#4a6a8a")
                                    horizontalAlignment: Text.AlignLeft
                                    wrapMode: Text.WordWrap
                                    // 仅做视觉缩放（当前行 1.0，非当前行缩至 24/34）
                                    scale: lyricDelegate.transScale
                                    transformOrigin: Item.TopLeft
                                    Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                    }

                    // 右侧播放按钮（在行框中垂直居中，仅当前居中行显示；置顶）
                    Rectangle {
                        id: manualPlayBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        visible: lyricDelegate._isManualCenter
                        z: 100  // 置顶：始终渲染在歌词之上
                        width: 25; height: 25; radius: 20
                        color: manualPlayMA.containsMouse ? "#3300d4ff" : "transparent"
                        border.color: "#00d4ff"
                        border.width: 1

                        // 播放图标（三角形，在按钮中居中）
                        Canvas {
                            anchors.horizontalCenterOffset: 1
                            anchors.centerIn: parent
                            width: 13; height: 14
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                ctx.fillStyle = "#00d4ff"
                                ctx.beginPath()
                                ctx.moveTo(0, 0)
                                ctx.lineTo(width, height / 2)
                                ctx.lineTo(0, height)
                                ctx.closePath()
                                ctx.fill()
                            }
                        }

                        MouseArea {
                            id: manualPlayMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (typeof musicManager !== "undefined" && musicManager) {
                                    root._manualActive = false  // 退出手动模式，恢复自动跟随
                                    _manualExitTimer.stop()
                                    musicManager.seek(modelData.time)
                                }
                            }
                        }
                    }
                }
            }

            // 窗口尺寸变化（换行宽度/视口高度改变）后，把当前歌词重新居中。
            // snap=true 表示歌词模型刚替换，需要直接对齐（无滚动）；尺寸变化则平滑滚动。
            Timer {
                id: lyricRecenterTimer
                interval: 150
                property bool snap: false
                onTriggered: {
                    if (lyricsView.count === 0) return
                    var mgr = (typeof musicManager !== "undefined" && musicManager) ? musicManager : null
                    if (mgr && mgr.lyricIndex >= 0)
                        root.centerOnIndex(mgr.lyricIndex, !snap)
                }
            }

            // 歌词滚动动画（手动控制，替代 Behavior on contentY，避免定位时直接跳变）
            // 用 OutCubic（起步即最大速度）：切行途中再次定位会 stop 后重启动画，
            // 若缓动从 0 起步（如 InOutQuad），重启瞬间速度归零，视觉上会"停一下再继续"；
            // OutCubic 重启时直接以高速延续，无停顿感，单次滚动也有平滑减速收尾
            NumberAnimation {
                id: lyricScrollAnim
                target: lyricsView
                property: "contentY"
                duration: 1000
                easing.type: Easing.OutCubic
                onRunningChanged: {
                    // 动画停止时清除自动滚动标志（被 stop 或自然完成）
                    if (!running) root._autoScrolling = false
                }
            }
        }

        // 悬浮时间层：跟随手动滚动的居中行，置顶显示。
        // 放在歌词列外部（不受歌词列/ListView 裁剪），可自由左移
        Rectangle {
            id: manualTimeOverlay
            anchors.left: lyricsCol.left
            anchors.leftMargin: -55
            y: root._manualCenterY - height / 2
            width: manualTimeOverlayText.width + 14
            height: 24
            radius: 12
            color: "#B3000000"  // 半透明深色底，保证清晰可读
            visible: root._manualActive && root._manualScrollIdx >= 0
            z: 100

            Text {
                id: manualTimeOverlayText
                anchors.centerIn: parent
                text: root.fmtTime(root._manualCenterTime)
                font.family: root.fontFamily
                font.pixelSize: 13
                color: "#00d4ff"
            }
        }
    }
}
