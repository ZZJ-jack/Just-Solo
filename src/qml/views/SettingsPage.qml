import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// 设置页 - 外观 / 软件更新 / 关于 三个子页面
// 通过 Loader 按需加载，切换页面时销毁释放内存
// ============================================================
Rectangle {
    id: settingsRoot
    color: "transparent"

    // ---- 外部注入属性 ----
    property string settingsSubMenu: "appearance"
    property string fontFamily: ""

    // ---- 快捷键捕获（顶层统一处理，绕过 Repeater 焦点域） ----
    property int capturingHkId: -1  // -1 = 不在捕获状态
    focus: false

    Keys.onPressed: function(event) {
        if (capturingHkId < 0) return
        // 纯修饰键忽略
        if (event.key === Qt.Key_Control || event.key === Qt.Key_Alt ||
            event.key === Qt.Key_Shift || event.key === Qt.Key_Meta)
            return
        hotkeyManager.setHotkey(capturingHkId, event.key, event.modifiers)
        capturingHkId = -1
        focus = false
        event.accepted = true
    }

    // ---- 软件更新 ----
    ColumnLayout {
        anchors.fill: parent; spacing: 0
        visible: settingsSubMenu === "update"

        Item { Layout.preferredHeight: 24 }
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 80; radius: 8
            color: "#2e2e4a"; border.color: "#3a3a55"
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "软件版本"; font.family: fontFamily; font.pixelSize: 14; color: "#ccc"; Layout.preferredWidth: 72 }
                    Item { Layout.fillWidth: true }
                    Label { text: APP_VERSION; font.family: fontFamily; font.pixelSize: 14; font.bold: true; color: "#e8e8e8" }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "构建版本"; font.family: fontFamily; font.pixelSize: 13; color: "#999"; Layout.preferredWidth: 72 }
                    Item { Layout.fillWidth: true }
                    Label { text: BUILD_VERSION; font.family: fontFamily; font.pixelSize: 13; color: "#ccc" }
                }
            }
        }
        Item { Layout.preferredHeight: 16 }
        Rectangle {
            Layout.preferredWidth: 160; Layout.preferredHeight: 40
            radius: 8; color: "#2a2a3a"; opacity: 0.5
            Label { anchors.centerIn: parent; text: "检查更新"; font.family: fontFamily; font.pixelSize: 14; color: "#999" }
        }
        Label { text: "请前往以下地址查看更新："; font.family: fontFamily; font.pixelSize: 13; color: "#ccc"; Layout.topMargin: 8 }
        Label { text: `<a href="https://gitcode.com/ZZJ-JACK/Just-Solo">https://gitcode.com/ZZJ-JACK/Just-Solo</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#00d4ff"; Layout.topMargin: 4; onLinkActivated: Qt.openUrlExternally(link) }
        Label { text: `<a href="https://github.com/ZZJ-jack/Just-Solo">https://github.com/ZZJ-jack/Just-Solo</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#00d4ff"; Layout.topMargin: 2; onLinkActivated: Qt.openUrlExternally(link) }
        Item { Layout.fillHeight: true }
    }

    // ---- 播放设置 ----
    ColumnLayout {
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        spacing: 0
        visible: settingsSubMenu === "playback"

        // 歌词延时
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 110; radius: 8
            color: "#2e2e4a"; border.color: "#3a3a55"

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "歌词预读偏移"
                        font.family: fontFamily; font.pixelSize: 14; color: "#e8e8e8"
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: {
                            var off = (musicManager.lyricOffset || 130) - 130
                            if (off === 0) return "0ms (默认)"
                            return (off > 0 ? "+" : "") + off + "ms"
                        }
                        font.family: fontFamily; font.pixelSize: 14; color: "#00d4ff"
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    from: 50; to: 350; stepSize: 5
                    value: musicManager.lyricOffset || 130
                    onMoved: musicManager.lyricOffset = Math.round(value / 5) * 5

                    background: Rectangle {
                        x: 0; y: parent.height / 2 - 2
                        width: parent.width; height: 4; radius: 2; color: "#3a3a55"
                    }
                    contentItem: Rectangle {
                        width: parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from)
                        height: 4; radius: 2; color: "#FFD700"
                        visible: parent.visible
                    }
                    handle: Rectangle {
                        x: parent.leftPadding + parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from) - width / 2
                        y: parent.height / 2 - height / 2
                        width: 16; height: 16; radius: 8; color: "#FFD700"
                    }
                }

                Label {
                    text: {
                        var off = (musicManager.lyricOffset || 130) - 130
                        if (off === 0) return "未调整"
                        return "已调整: " + (off > 0 ? "+" : "") + off + "ms"
                    }
                    font.family: fontFamily; font.pixelSize: 12; color: "#888"
                }
            }
        }

        Item { Layout.preferredHeight: 14 }

        // 跨来源跟踪开关
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 110; radius: 8
            color: "#2e2e4a"; border.color: "#3a3a55"

            ColumnLayout {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20; anchors.topMargin: 12; anchors.bottomMargin: 20; spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "其他列表播放时首页是否显示对应歌曲"; font.family: fontFamily; font.pixelSize: 14; color: "#e8e8e8" }
                    Item { Layout.fillWidth: true }
                    Switch {
                        Layout.alignment: Qt.AlignVCenter
                        checked: musicManager.trackCrossSource || false
                        onToggled: musicManager.trackCrossSource = checked

                        indicator: Rectangle {
                            implicitWidth: 34
                            implicitHeight: 20
                            x: parent.leftPadding
                            y: parent.topPadding + (parent.availableHeight - height) / 2
                            radius: 10
                            color: parent.checked ? "#00d4ff" : "#555"
                            border.color: parent.checked ? "#00b4e0" : "#444"

                            Rectangle {
                                x: parent.checked ? parent.width - width - 3 : 3
                                y: (parent.height - height) / 2
                                width: 14; height: 14; radius: 7
                                color: "#fff"
                            }
                        }
                    }
                }

                Label {
                    text: musicManager.trackCrossSource
                          ? "开启后，在其他列表播放时首页将同步显示当前歌曲。"
                          : "关闭后，在其他列表播放时首页将不再高亮当前曲目。\n点击首页任意歌曲将从首页列表从头播放（含确认弹窗）。"
                    font.family: fontFamily; font.pixelSize: 11; color: "#ccc"
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
        }
    }

    // ---- 快捷键设置 ----
    ColumnLayout {
        anchors.fill: parent; spacing: 0
        visible: settingsSubMenu === "hotkeys"

        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 280
            radius: 8
            color: "#2e2e4a"; border.color: "#3a3a55"

            ColumnLayout {
                id: hotkeyCol
                anchors.fill: parent; anchors.margins: 20; spacing: 10

                Label {
                    text: "全局快捷键"
                    font.family: fontFamily; font.pixelSize: 14; font.bold: true; color: "#f0f0f0"
                }

                // 三行快捷键
                Column {
                    Layout.fillWidth: true
                    spacing: 10

                    Repeater {
                        model: [
                            { label: "播放 / 暂停", id: 0 },
                            { label: "下一首",       id: 1 },
                            { label: "上一首",       id: 2 }
                        ]

                        delegate: Rectangle {
                            id: hotkeyRow
                            width: parent.width
                            height: 38
                            color: "transparent"

                            property int hkId: modelData.id
                            property bool capturing: settingsRoot.capturingHkId === hkId

                            RowLayout {
                                anchors.fill: parent
                                spacing: 8

                                Label {
                                    text: modelData.label
                                    font.family: fontFamily; font.pixelSize: 14; color: "#ccc"
                                    Layout.preferredWidth: 100
                                }

                                // 显示/捕获区域
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    radius: 6
                                    color: hotkeyRow.capturing ? "#3a3a5a" : (hkMA.containsMouse ? "#333350" : "#2a2a48")
                                    border.color: hotkeyRow.capturing ? "#00d4ff" : "#3a3a55"
                                    border.width: hotkeyRow.capturing ? 2 : 1

                                    Label {
                                        anchors.centerIn: parent
                                        text: hotkeyRow.capturing ? "按下快捷键..." : hotkeyRow.buildDisplayText()
                                        font.family: fontFamily; font.pixelSize: 13
                                        color: hotkeyRow.capturing ? "#00d4ff" : "#ddd"
                                    }

                                    MouseArea {
                                        id: hkMA
                                        anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (hotkeyRow.capturing) {
                                                settingsRoot.capturingHkId = -1
                                                settingsRoot.focus = false
                                            } else {
                                                settingsRoot.capturingHkId = hkId
                                                settingsRoot.focus = true
                                                settingsRoot.forceActiveFocus()
                                            }
                                        }
                                    }
                                }

                                // 重置按钮
                                Rectangle {
                                    Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 4
                                    color: resetMA.containsMouse ? "#4a3a3a" : "transparent"
                                    visible: !hotkeyRow.capturing

                                    Text {
                                        anchors.centerIn: parent
                                        text: "↺"
                                        font.family: fontFamily; font.pixelSize: 16; color: "#888"
                                    }
                                    MouseArea {
                                        id: resetMA
                                        anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: hotkeyRow.resetDefault()
                                    }
                                }
                            }

                            function keyName(k) {
                                if (k >= Qt.Key_A && k <= Qt.Key_Z) return String.fromCharCode(k)
                                if (k >= Qt.Key_F1 && k <= Qt.Key_F24) return "F" + (k - Qt.Key_F1 + 1)
                                var map = {
                                    [Qt.Key_Space]: "Space",
                                    [Qt.Key_Left]: "←",
                                    [Qt.Key_Right]: "→",
                                    [Qt.Key_Up]: "↑",
                                    [Qt.Key_Down]: "↓",
                                    [Qt.Key_Escape]: "Esc",
                                    [Qt.Key_Return]: "Enter",
                                    [Qt.Key_Tab]: "Tab",
                                    [Qt.Key_Delete]: "Del",
                                    [Qt.Key_Insert]: "Ins",
                                    [Qt.Key_Home]: "Home",
                                    [Qt.Key_End]: "End",
                                    [Qt.Key_PageUp]: "PgUp",
                                    [Qt.Key_PageDown]: "PgDn",
                                    [Qt.Key_Backspace]: "Back",
                                    [Qt.Key_MediaPlay]: "MediaPlay",
                                    [Qt.Key_MediaNext]: "MediaNext",
                                    [Qt.Key_MediaPrevious]: "MediaPrev",
                                    [Qt.Key_Comma]: ",",
                                    [Qt.Key_Period]: ".",
                                    [Qt.Key_Minus]: "-",
                                    [Qt.Key_Plus]: "+",
                                    [Qt.Key_Semicolon]: ";",
                                    [Qt.Key_Slash]: "/"
                                }
                                return map[k] || ""
                            }

                            function buildDisplayText() {
                                var k = hotkeyManager.hotkeyKey(hkId)
                                var m = hotkeyManager.hotkeyMods(hkId)
                                if (!k) return "点击设置"
                                var parts = []
                                if (m & Qt.ControlModifier) parts.push("Ctrl")
                                if (m & Qt.AltModifier) parts.push("Alt")
                                if (m & Qt.ShiftModifier) parts.push("Shift")
                                if (m & Qt.MetaModifier) parts.push("Win")
                                var n = keyName(k)
                                if (n) parts.push(n)
                                return parts.join(" + ")
                            }

                            function resetDefault() {
                                var mods = Qt.ControlModifier | Qt.AltModifier
                                var defaults = [
                                    { key: Qt.Key_Space, mods: mods },
                                    { key: Qt.Key_Right, mods: mods },
                                    { key: Qt.Key_Left,  mods: mods }
                                ]
                                var d = defaults[hkId]
                                hotkeyManager.setHotkey(hkId, d.key, d.mods)
                            }
                        }
                    }
                }

                Label {
                    text: "修改后实时生效。建议设置带修饰键的组合（如 Ctrl+Alt+P）避免与其他软件冲突。"
                    font.family: fontFamily; font.pixelSize: 11; color: "#999"
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
        }

        Label {
            text: "修改后实时生效，重启后保持设置"
            font.family: fontFamily; font.pixelSize: 12; color: "#999"
            Layout.topMargin: 8
        }
        Item { Layout.fillHeight: true }
    }

    // ---- 外观 ----
    ColumnLayout {
        anchors.fill: parent; spacing: 0
        visible: settingsSubMenu === "appearance"

        // 播放详情页透明度
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 90; radius: 8
            color: "#2e2e4a"; border.color: "#3a3a55"

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "播放详情页透明度"
                        font.family: fontFamily; font.pixelSize: 14; color: "#e8e8e8"
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: Math.round((musicManager.detailOpacity || 0.85) * 100) + "%"
                        font.family: fontFamily; font.pixelSize: 14; color: "#00d4ff"
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    from: 0.3; to: 1.0; stepSize: 0.01
                    value: musicManager.detailOpacity || 0.90
                    onMoved: musicManager.detailOpacity = value

                    background: Rectangle {
                        x: 0; y: parent.height / 2 - 2
                        width: parent.width; height: 4; radius: 2; color: "#3a3a55"
                    }
                    contentItem: Rectangle {
                        width: parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from)
                        height: 4; radius: 2; color: "#00d4ff"
                        visible: parent.visible
                    }
                    handle: Rectangle {
                        x: parent.leftPadding + parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from) - width / 2
                        y: parent.height / 2 - height / 2
                        width: 16; height: 16; radius: 8; color: "#00d4ff"
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 14 }

        // 模式菜单透明度
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 90; radius: 8
            color: "#2e2e4a"; border.color: "#3a3a55"

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "播放详情页循环模式菜单透明度"
                        font.family: fontFamily; font.pixelSize: 14; color: "#e8e8e8"
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: {
                            var op = Number(musicManager.menuOpacity)
                            return Math.round((op > 0 ? op : 0.8) * 100) + "%"
                        }
                        font.family: fontFamily; font.pixelSize: 14; color: "#00d4ff"
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    from: 0.3; to: 1.0; stepSize: 0.01
                    value: {
                        var op = Number(musicManager.menuOpacity)
                        return op > 0 ? op : 0.8
                    }
                    onMoved: musicManager.menuOpacity = value

                    background: Rectangle {
                        x: 0; y: parent.height / 2 - 2
                        width: parent.width; height: 4; radius: 2; color: "#3a3a55"
                    }
                    contentItem: Rectangle {
                        width: parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from)
                        height: 4; radius: 2; color: "#00d4ff"
                        visible: parent.visible
                    }
                    handle: Rectangle {
                        x: parent.leftPadding + parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from) - width / 2
                        y: parent.height / 2 - height / 2
                        width: 16; height: 16; radius: 8; color: "#00d4ff"
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 14 }

        // 关闭窗口行为
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 70; radius: 8
            color: "#2e2e4a"; border.color: "#3a3a55"

            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20; anchors.topMargin: 12; anchors.bottomMargin: 20
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        text: "关闭窗口时最小化到系统托盘"
                        font.family: fontFamily; font.pixelSize: 14; color: "#e8e8e8"
                    }
                    Label {
                        text: "关闭后音乐继续在后台播放，可通过托盘图标恢复"
                        font.family: fontFamily; font.pixelSize: 11; color: "#999"
                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }

                Switch {
                    Layout.alignment: Qt.AlignVCenter
                    checked: musicManager.minimizeToTray
                    onToggled: musicManager.minimizeToTray = checked

                    indicator: Rectangle {
                        implicitWidth: 34
                        implicitHeight: 20
                        x: parent.leftPadding
                        y: parent.topPadding + (parent.availableHeight - height) / 2
                        radius: 10
                        color: parent.checked ? "#00d4ff" : "#555"
                        border.color: parent.checked ? "#00b4e0" : "#444"

                        Rectangle {
                            x: parent.checked ? parent.width - width - 3 : 3
                            y: (parent.height - height) / 2
                            width: 14; height: 14; radius: 7
                            color: "#fff"
                        }
                    }
                }
            }
        }

        Label {
            text: "修改后立即生效，重启后保持设置"
            font.family: fontFamily; font.pixelSize: 12; color: "#999"
            Layout.topMargin: 8
        }
        Item { Layout.fillHeight: true }
    }

    // ---- 关于 ----
    ColumnLayout {
        anchors.fill: parent; spacing: 0
        visible: settingsSubMenu === "about"
        Item { Layout.preferredHeight: 8 }
        Label { text: "Just Solo - 轻量级桌面音乐播放器"; font.family: fontFamily; font.pixelSize: 14; color: "#ccc" }
        Item { Layout.preferredHeight: 4 }
        Label { text: "作者: ZZJ-JACK"; font.family: fontFamily; font.pixelSize: 13; color: "#999" }
        Label { text: `<a href="https://zzjjack.us.kg">https://zzjjack.us.kg</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#00d4ff"; Layout.topMargin: 4; onLinkActivated: Qt.openUrlExternally(link) }
        Item { Layout.preferredHeight: 8 }
        Label { text: "基于 Qt 6.8.3 + QML 构建"; font.family: fontFamily; font.pixelSize: 13; color: "#999" }
        Label { text: "运行环境: " + (typeof OS_VERSION !== "undefined" ? OS_VERSION : "未知"); font.family: fontFamily; font.pixelSize: 13; color: "#999" }
        Item { Layout.preferredHeight: 8 }
        Label { text: "构建版本: " + BUILD_VERSION; font.family: fontFamily; font.pixelSize: 13; color: "#999" }
        Item { Layout.preferredHeight: 12 }
        Label { text: "项目地址"; font.family: fontFamily; font.pixelSize: 13; color: "#ccc" }
        Label { text: `<a href="https://gitcode.com/ZZJ-JACK/Just-Solo">https://gitcode.com/ZZJ-JACK/Just-Solo</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#00d4ff"; Layout.topMargin: 4; onLinkActivated: Qt.openUrlExternally(link) }
        Label { text: `<a href="https://github.com/ZZJ-jack/Just-Solo">https://github.com/ZZJ-jack/Just-Solo</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#00d4ff"; Layout.topMargin: 2; onLinkActivated: Qt.openUrlExternally(link) }
        Item { Layout.preferredHeight: 12 }
        Label { text: "图标来源: 鸿蒙开发者"; font.family: fontFamily; font.pixelSize: 13; color: "#ccc" }
        Label { text: `<a href="https://developer.huawei.com/consumer/cn/">https://developer.huawei.com/consumer/cn</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#00d4ff"; Layout.topMargin: 4; onLinkActivated: Qt.openUrlExternally(link) }
        Item { Layout.fillHeight: true }
    }
}
