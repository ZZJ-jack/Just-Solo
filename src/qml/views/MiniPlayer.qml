// ============================================================
// MiniPlayer — 迷你播放小窗（300×100，无边框，独立于主窗口）
// ============================================================
import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

Window {
    id: miniWindow
    width: 350
    height: 100
    minimumWidth: 350
    minimumHeight: 100
    maximumWidth: 350
    maximumHeight: 100
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint
    color: "transparent"
    title: "Just Solo"

    required property string fontFamily

    // 播放背景模式：0=深色背景，1=沉浸背景（与设置页联动）
    readonly property bool _immersiveBg: (typeof musicManager !== "undefined" && musicManager)
                                         ? musicManager.playbackBackground === 1 : false

    // 退出小窗信号
    signal exitMiniMode()

    // ============================================================
    // 字体加载
    // ============================================================
    FontLoader {
        id: miniFont
        source: "qrc:/qt/qml/JustSolo/data/font/HarmonyOS_Sans_SC_Regular.ttf"
    }
    readonly property string _font: miniFont.name || fontFamily

    // ============================================================
    // 背景：深色背景 / 沉浸背景（与播放详情页一致）
    // 深色背景 = 兜底深色单层；沉浸背景额外叠加两层：
    //   C++ 端提取的封面主色调作为底色 → 渐变遮罩（上透下暗）形成渐变色背景
    // 每层自带 radius: 8，对齐外层圆角
    // ============================================================

    // 兜底色：深色背景模式下的唯一背景（也是沉浸模式的兜底）
    Rectangle {
        anchors.fill: parent
        radius: 8
        color: "#181818"
    }

    // 沉浸背景层：仅在沉浸背景模式下渲染，淡出结束后自动隐藏以节省性能
    Item {
        anchors.fill: parent
        visible: miniWindow._immersiveBg || opacity > 0
        opacity: miniWindow._immersiveBg ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }

        // 主色调底层：切歌时颜色平滑过渡（ColorAnimation）
        Rectangle {
            id: immersiveBase
            anchors.fill: parent
            radius: 8
            color: {
                var c = (typeof musicManager !== "undefined" && musicManager)
                        ? (musicManager.currentCoverColor || "") : ""
                return c !== "" ? c : "#181818"
            }
            Behavior on color { ColorAnimation { duration: 600 } }
        }

        // 渐变遮罩：顶部透出主色调，底部过渡到深色，形成渐变色背景
        Rectangle {
            anchors.fill: parent
            radius: 8
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 0.4; color: "#50181818" }
                GradientStop { position: 1.0; color: "#D8181818" }
            }
        }
    }

    // ============================================================
    // 全窗口拖动（置于底层，按钮等交互元素不受影响）
    // ============================================================
    MouseArea {
        id: dragArea
        anchors.fill: parent
        z: -1
        cursorShape: Qt.OpenHandCursor
        onPressed: { miniWindow.startSystemMove() }
    }

    // ============================================================
    // 主布局
    // ============================================================
    RowLayout {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 8

        // ---- 左侧：封面（上下顶格） ----
        Rectangle {
            Layout.preferredWidth: 88
            Layout.fillHeight: true
            radius: 6
            color: "#3A3A3A"

            Image {
                id: coverImg
                anchors.fill: parent
                source: (typeof musicManager !== "undefined" && musicManager) ? (musicManager.currentCover || "") : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: source !== ""
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }

                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: ShaderEffectSource {
                        sourceItem: Rectangle {
                            width: coverImg.width; height: coverImg.height; radius: 5
                        }
                    }
                }
            }
            Label {
                anchors.centerIn: parent
                text: "\u266B"
                font.family: _font; font.pixelSize: 32; color: "#666"
                visible: (typeof musicManager === "undefined" || !musicManager || !musicManager.currentCover)
            }
        }

        // ---- 右侧：标题 + 歌手 + 进度条 + 控制按钮 ----
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 2
            spacing: 2

            // ---- 歌曲标题（居中） ----
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                Layout.topMargin: 2
                clip: true

                property bool needsScroll: titleText.contentWidth > width

                Text {
                    id: titleText
                    text: (typeof musicManager !== "undefined" && musicManager) ? (musicManager.currentTitle || "未在播放") : "未在播放"
                    font.family: _font; font.pixelSize: 18; font.bold: true; color: "#f0f0f0"
                    y: (parent.height - contentHeight) / 2
                    x: parent.needsScroll ? parent.width : (parent.width - contentWidth) / 2

                    SequentialAnimation on x {
                        running: titleText.parent && titleText.parent.needsScroll && miniWindow.visible
                        loops: Animation.Infinite
                        NumberAnimation {
                            from: titleText.parent ? titleText.parent.width : 0
                            to: -titleText.contentWidth
                            duration: Math.max(5000, ((titleText.parent ? titleText.parent.width : 0) + titleText.contentWidth) * 10)
                            easing.type: Easing.Linear
                        }
                        PauseAnimation { duration: 600 }
                        PropertyAnimation { property: "x"; to: titleText.parent ? titleText.parent.width : 0; duration: 0 }
                    }
                }
            }

            // ---- 歌手（居中） ----
            Label {
                text: {
                    if (typeof musicManager === "undefined" || !musicManager) return ""
                    var a = (musicManager.currentArtist || "").replace(/[/;｜|]+/g, "、")
                    return a || ""
                }
                font.family: _font; font.pixelSize: 11; color: "#FFFFFF"
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: text !== ""
            }

            // ---- 进度条 ----
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                Layout.topMargin: 4
                Layout.bottomMargin: 2

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width; height: 3
                    radius: 1.5; color: "#3A3A3A"

                    Rectangle {
                        width: parent.width * (musicManager.duration > 0 ? musicManager.position / musicManager.duration : 0)
                        height: parent.height; radius: 1.5; color: "#3B82F6"
                        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                    }
                }

                MouseArea {
                    anchors.fill: parent; anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    function seek(mx) {
                        var ratio = Math.max(0, Math.min(1, mx / width))
                        if (musicManager.duration > 0) {
                            musicManager.seek(ratio * musicManager.duration)
                            if (!musicManager.isPlaying) musicManager.play()
                        }
                    }
                    onClicked: function(m) { seek(m.x) }
                    onPressed: function(m) { seek(m.x) }
                    onPositionChanged: function(m) { if (pressed) seek(m.x) }
                }
            }

            Item { Layout.fillHeight: true }

            // ---- 底部控制栏（三大按钮居中） ----
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 1
                spacing: 0

                // ---- 左侧：循环模式 ----
                RowLayout {
                    spacing: 10

                    // 循环模式（带弹出菜单）
                    Item {
                        id: modeItem
                        Layout.preferredWidth: 22; Layout.preferredHeight: 22

                        property var modeIcons: ["mode_sequential.png", "mode_loop.png", "mode_single.png", "mode_shuffle.png", "mode_stop.png"]

                        Image {
                            anchors.centerIn: parent
                            source: {
                                var m = (typeof musicManager !== "undefined" && musicManager) ? musicManager.playMode : 0
                                return "qrc:/qt/qml/JustSolo/data/image/" + modeItem.modeIcons[m]
                            }
                            sourceSize.width: musicManager.playMode === 0 ? 22 : (musicManager.playMode === 1 ? 20 : (musicManager.playMode === 4 ? 15 : 18))
                            sourceSize.height: musicManager.playMode === 0 ? 22 : (musicManager.playMode === 1 ? 20 : (musicManager.playMode === 4 ? 15 : 18))
                            width: musicManager.playMode === 0 ? 22 : (musicManager.playMode === 1 ? 20 : (musicManager.playMode === 4 ? 15 : 18))
                            height: musicManager.playMode === 0 ? 22 : (musicManager.playMode === 1 ? 20 : (musicManager.playMode === 4 ? 15 : 18))
                            // 强制图标为纯白 #FFFFFF
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                brightness: 1.0
                            }
                        }

                        // 轮询检查，鼠标离开按钮和菜单 450ms 后关闭
                        Timer {
                            id: modeCloseTimer
                            interval: 150
                            repeat: true
                            running: false
                            property int missCount: 0
                            onTriggered: {
                                if (modeBgMA.containsMouse || modeBtnMA.containsMouse) {
                                    missCount = 0
                                } else {
                                    missCount++
                                    if (missCount >= 3) {
                                        missCount = 0
                                        stop()
                                        modePopup.close()
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: modeBtnMA
                            anchors.fill: parent; anchors.margins: -4
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onEntered: {
                                modeCloseTimer.stop()
                                modeCloseTimer.missCount = 0
                                modeCloseTimer.start()
                                modePopup.open()
                            }
                            onExited: {
                                // 不立即动作，让轮询定时器判断
                            }
                        }

                        Popup {
                            id: modePopup
                            x: parent.width / 2 - width / 2
                            y: -height - 8
                            padding: 4
                            closePolicy: Popup.CloseOnEscape

                            background: Rectangle {
                                radius: 6
                                color: {
                                    var cc = (typeof musicManager !== "undefined" && musicManager)
                                            ? (musicManager.currentCoverColor || "") : ""
                                    return cc !== "" ? Qt.darker(cc, 3.5) : "#222222"
                                }
                                Behavior on color { ColorAnimation { duration: 600 } }
                                border.color: {
                                    var cc = (typeof musicManager !== "undefined" && musicManager)
                                            ? (musicManager.currentCoverColor || "") : ""
                                    return cc !== "" ? cc : "#3A3A3A"
                                }
                                Behavior on border.color { ColorAnimation { duration: 600 } }
                                border.width: 1
                                opacity: (typeof musicManager !== "undefined" && musicManager) ? (musicManager.menuOpacity || 0.8) : 0.8
                                Behavior on opacity { NumberAnimation { duration: 120 } }

                                // 菜单框内任意位置保持打开
                                MouseArea {
                                    id: modeBgMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                }
                            }

                            contentItem: Row {
                                spacing: 4
                                height: 24  // 固定高度，以最大图标为基准
                                Repeater {
                                    model: 5
                                    Image {
                                        source: "qrc:/qt/qml/JustSolo/data/image/" + modeItem.modeIcons[index]
                                        // index 0=顺序播放 最大，1=列表循环 次大，4=关闭循环 最小，2=单曲 3=随机 默认
                                        sourceSize.width: index === 0 ? 24 : (index === 1 ? 22 : (index === 4 ? 18 : 20))
                                        sourceSize.height: index === 0 ? 24 : (index === 1 ? 22 : (index === 4 ? 18 : 20))
                                        width: index === 0 ? 24 : (index === 1 ? 22 : (index === 4 ? 18 : 20))
                                        height: index === 0 ? 24 : (index === 1 ? 22 : (index === 4 ? 18 : 20))
                                        y: (24 - height) / 2 - (index === 3 ? 1 : 0)  // 垂直居中，随机播放上移 1px
                                        fillMode: Image.PreserveAspectFit
                                        opacity: (itemMA.containsMouse || musicManager.playMode === index) ? 1.0 : 0.65
                                        // 选中项加亮度提升
                                        layer.enabled: musicManager.playMode === index
                                        layer.effect: MultiEffect { brightness: 0.12 }
                                        Behavior on opacity { NumberAnimation { duration: 120 } }

                                        MouseArea {
                                            id: itemMA
                                            anchors.fill: parent; anchors.margins: -3
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof musicManager !== "undefined" && musicManager)
                                                    musicManager.playMode = index
                                                modePopup.close()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- 左侧弹性占位 ----
                Item { Layout.fillWidth: true }

                // ---- 中央：三大播放控制按钮 ----
                RowLayout {
                    spacing: 10
                    Layout.alignment: Qt.AlignHCenter

                    // 上一首
                    Item {
                        Layout.preferredWidth: 20; Layout.preferredHeight: 20
                        Image {
                            anchors.centerIn: parent
                            source: "qrc:/qt/qml/JustSolo/data/image/prve.png"
                            width: 20; height: 20; opacity: 0.8
                        }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { if (typeof musicManager !== "undefined" && musicManager) musicManager.previous() }
                        }
                    }

                    // 播放/暂停
                    Rectangle {
                        Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 14
                        color: "#3A3A3A"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Image {
                            anchors.centerIn: parent
                            source: {
                                if (typeof musicManager === "undefined" || !musicManager) return ""
                                return musicManager.isPlaying
                                    ? "qrc:/qt/qml/JustSolo/data/image/playing.png"
                                    : "qrc:/qt/qml/JustSolo/data/image/play.png"
                            }
                            width: 16; height: 16; anchors.horizontalCenterOffset: (!musicManager || !musicManager.isPlaying) ? 1 : 0
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (typeof musicManager === "undefined" || !musicManager) return
                                if (musicManager.currentIndex < 0) return
                                if (musicManager.isPlaying) musicManager.pause()
                                else musicManager.play()
                            }
                        }
                    }

                    // 下一首
                    Item {
                        Layout.preferredWidth: 20; Layout.preferredHeight: 20
                        Image {
                            anchors.centerIn: parent
                            source: "qrc:/qt/qml/JustSolo/data/image/next.png"
                            width: 20; height: 20; opacity: 0.8
                        }
                        MouseArea {
                            anchors.fill: parent; anchors.margins: -4
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { if (typeof musicManager !== "undefined" && musicManager) musicManager.next() }
                        }
                    }
                }

                // ---- 右侧弹性占位 ----
                Item { Layout.fillWidth: true }

                // ---- 右侧：退出小窗 ----
                Item {
                    Layout.preferredWidth: 20; Layout.preferredHeight: 20
                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/qt/qml/JustSolo/data/image/mini-exit.png"
                        width: 18; height: 18
                        opacity: exitMA.containsMouse ? 1.0 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 120 } }
                    }
                    MouseArea {
                        id: exitMA
                        anchors.fill: parent; anchors.margins: -4
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: miniWindow.exitMiniMode()
                    }
                }
            }
        }
    }
}
