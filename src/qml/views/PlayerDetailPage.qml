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
        if (ms <= 0) return "0:00"
        var s = Math.floor(ms / 1000)
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
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
        } else if (animate === false) {
            // 直接落位（进入页面 / 快速 seek / 从后台恢复）
            // 原实现缺少此分支，导致从后台恢复时歌词不对齐
            lyricsView.contentY = to
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
            }
            // 若 delegate 仍未实例化，放弃（避免无限重试，等下次 lyricIndex 变化时自然对齐）
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
            root.centerOnIndex(idx, !rapid)
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

            // 渐变遮罩：顶部透出主色调，底部过渡到深色，形成渐变色背景
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 0.4; color: "#50181818" }
                    GradientStop { position: 1.0; color: "#D8181818" }
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
            width: 18; height: 18
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
            width: 20; height: 20
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
                // cacheBuffer 调大：歌词行高度不固定（有无翻译/换行不同），
                // 只实例化可视区的行时，Qt 对远处行按平均行高估算，居中会累计偏移；
                // 全部行实例化后几何信息始终真实，任意行都能精确居中
                cacheBuffer: 1000000
                // 窗口大小变化后自动重新居中当前歌词（防抖，避免拖动过程中持续触发；平滑滚动）
                onWidthChanged: { lyricRecenterTimer.snap = false; lyricRecenterTimer.restart() }
                onHeightChanged: { lyricRecenterTimer.snap = false; lyricRecenterTimer.restart() }

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
            }
        }
    }
}
