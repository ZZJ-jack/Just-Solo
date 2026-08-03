import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtCore

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
    property string selectedDownloadUrl: ""

    // 当前歌词字体选择键 → 展示名称
    function lyricFontLabel() {
        var key = musicManager.lyricFont
        if (!key) return "鸿蒙字体（默认）"
        if (key.indexOf("builtin:") === 0) {
            var file = key.substring(8)
            var list = musicManager.builtinLyricFonts()
            for (var i = 0; i < list.length; i++) {
                if (list[i].file === file) return list[i].label
            }
            return "鸿蒙字体（默认）"
        }
        if (key.indexOf("system:") === 0)
            return key.substring(7)
        return "鸿蒙字体（默认）"
    }

    FontLoader {
        id: updateFont
        source: "qrc:/qt/qml/JustSolo/data/font/HarmonyOS_Sans_SC_Regular.ttf"
    }

    function checkUpdate() {
        checkingLabel.visible = true
        statusLabel.text = ""
        statusLabel.color = "#ffffff"
        updateChecker.checkForUpdates()
    }

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
        id: updateSection
        anchors.fill: parent
        spacing: 0
        visible: settingsSubMenu === "update"

        // 顶部固定区域：版本卡片 + 检查更新按钮 + 最新版本信息（锁死，不随更新数据变化移动）
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: 0

            // 软件版本卡片
            Rectangle {
                Layout.fillWidth: true; Layout.maximumWidth: 520
                Layout.preferredHeight: 80; radius: 8
                color: "#222222"; border.color: "#3A3A3A"
                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 20; spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "软件版本"; font.family: updateFont.name; font.pixelSize: 15; color: "#ffffff"; Layout.preferredWidth: 72 }
                        Item { Layout.fillWidth: true }
                        Label { text: APP_VERSION; font.family: updateFont.name; font.pixelSize: 15; font.bold: true; color: "#ffffff" }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "构建版本"; font.family: updateFont.name; font.pixelSize: 13; color: "#777777"; Layout.preferredWidth: 72 }
                        Item { Layout.fillWidth: true }
                        Label { text: BUILD_VERSION; font.family: updateFont.name; font.pixelSize: 13; color: "#ffffff" }
                    }
                }
            }

            Item { Layout.preferredHeight: 12 }

            // 检查更新按钮 + 最新版本信息（横排）
            RowLayout {
                Layout.fillWidth: true
                spacing: 20

                // 检查更新按钮
                Rectangle {
                    Layout.preferredWidth: 160; Layout.preferredHeight: 40
                    radius: 8; color: "#333333"
                    Label { anchors.centerIn: parent; text: "检查更新"; font.family: updateFont.name; font.pixelSize: 15; color: "#ffffff" }
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: checkUpdate()
                        onEntered: parent.color = "#4A4A4A"
                        onExited: parent.color = "#333333"
                    }
                }

                // 最新版本信息
                GridLayout {
                    columns: 2
                    columnSpacing: 10
                    rowSpacing: 4
                    visible: latestVerLabel.text.length > 0

                    Label { text: "最新版本："; font.family: updateFont.name; font.pixelSize: 13; color: "#777777" }
                    Label {
                        id: latestVerLabel
                        text: ""
                        font.family: updateFont.name; font.pixelSize: 13; font.bold: true
                        color: updateChecker.isNewer ? "#3B82F6" : "#ffffff"
                    }

                    Label { text: "发布日期："; font.family: updateFont.name; font.pixelSize: 12; color: "#777777"; visible: dateLabel.text.length > 0 }
                    Label {
                        id: dateLabel
                        text: ""
                        font.family: updateFont.name; font.pixelSize: 12; color: "#ffffff"
                        visible: text.length > 0
                    }
                }

                // 下载安装程序按钮
                Rectangle {
                    id: downloadBtn
                    Layout.preferredWidth: 140; Layout.preferredHeight: 38; radius: 8
                    visible: updateChecker.isNewer && !updateChecker.downloading
                    color: dlBtnMA.containsMouse ? "#5B9EF6" : "#3B82F6"
                    Label { anchors.centerIn: parent; text: "下载安装程序"; font.family: updateFont.name; font.pixelSize: 15; color: "#ffffff" }
                    MouseArea {
                        id: dlBtnMA
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: downloadSourceDialog.open()
                    }
                }

                // 取消下载按钮（下载中替换下载按钮）
                Rectangle {
                    id: cancelBtn
                    Layout.preferredWidth: 140; Layout.preferredHeight: 38; radius: 8
                    visible: updateChecker.downloading
                    color: cancelBtnMA.containsMouse ? "#5B9EF6" : "#3B82F6"
                    Label { anchors.centerIn: parent; text: "取消下载"; font.family: updateFont.name; font.pixelSize: 15; color: "#ffffff" }
                    MouseArea {
                        id: cancelBtnMA
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            progressRow.visible = false
                            updateChecker.cancelDownload()
                        }
                    }
                }

                // 检查中提示（已有更新信息时显示在下载按钮右边）
                Label {
                    id: checkingLabel
                    text: "正在检查更新…"
                    font.family: updateFont.name; font.pixelSize: 13; color: "#ffffff"
                    visible: false
                }

                Item { Layout.fillWidth: true }
            }

            // 状态提示
            Label {
                id: statusLabel
                text: ""
                font.family: updateFont.name; font.pixelSize: 13; color: "#ffffff"
                Layout.topMargin: 8
                visible: text.length > 0
            }
        }

        // 占位撑开（有更新日志时收缩，让日志区向上拉伸）
        Item {
            Layout.fillHeight: true
            visible: changelogArea.text.length === 0
        }

        // 下方内容区域（底部锚定，向上拉伸）
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignBottom
            spacing: 0

            // 更新日志标题
            Label {
                text: "更新日志"
                font.family: updateFont.name; font.pixelSize: 18; font.bold: true
                color: "#ffffff"
                Layout.topMargin: 10
                Layout.bottomMargin: 6
                visible: changelogArea.text.length > 0
            }

            // 更新日志内容（自适应拉伸）
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120
                color: "#1E1E1E"
                radius: 8
                border.color: "#3A3A3A"
                visible: changelogArea.text.length > 0

                ScrollView {
                    id: changelogScroll
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                    Text {
                        id: changelogArea
                        width: changelogScroll.width
                        text: ""
                        font.family: updateFont.name
                        font.pixelSize: 13
                        color: "#ffffff"
                        linkColor: "#3B82F6"
                        wrapMode: Text.WordWrap
                        textFormat: Text.RichText
                    }
                }
            }

            // 项目链接
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                visible: latestVerLabel.text.length > 0

                Item { Layout.fillWidth: true }
                Label { text: "官方网站"; font.family: updateFont.name; font.pixelSize: 13; color: "#3B82F6"; Layout.rightMargin: 12
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally("https://justsolo.zzjjack.us.kg") } }
                Label { text: "GitCode"; font.family: updateFont.name; font.pixelSize: 13; color: "#3B82F6"; Layout.rightMargin: 12
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally("https://gitcode.com/ZZJ-JACK/Just-Solo") } }
                Label { text: "GitHub"; font.family: updateFont.name; font.pixelSize: 13; color: "#3B82F6"
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally("https://github.com/ZZJ-jack/Just-Solo") } }
            }

            // 下载进度条
            RowLayout {
                id: progressRow
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 10
                visible: false

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 6
                    radius: 3
                    color: "#3A3A3A"

                    Rectangle {
                        width: (updateChecker.downloadTotal > 0)
                               ? parent.width * (updateChecker.downloadProgress / updateChecker.downloadTotal) : 0
                        height: parent.height; radius: 3
                        color: "#3B82F6"
                        Behavior on width { NumberAnimation { duration: 200 } }
                    }
                }
                Label {
                    id: progressLabel
                    text: "0%"
                    font.family: updateFont.name; font.pixelSize: 12; color: "#777777"
                    Layout.preferredWidth: 48
                }
            }

            // 下载完成提示
            Label {
                id: downloadsLabel
                text: "安装程序已下载完成，请前往保存文件夹运行安装程序。"
                font.family: updateFont.name; font.pixelSize: 13
                color: "#3B82F6"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                Layout.topMargin: 4
                visible: false
            }

            // 操作按钮行
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 12
                spacing: 10

                Item { Layout.fillWidth: true }

                Rectangle {
                    id: openFolderBtn
                    Layout.preferredWidth: 160; Layout.preferredHeight: 38; radius: 8
                    visible: false
                    color: ofBtnMA.containsMouse ? "#5B9EF6" : "#3B82F6"
                    Label { anchors.centerIn: parent; text: "打开文件夹"; font.family: updateFont.name; font.pixelSize: 15; color: "#ffffff" }
                    MouseArea {
                        id: ofBtnMA
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: updateChecker.openDownloadFolder()
                    }
                }
            }

            Item { Layout.preferredHeight: 12 }
        }

        // 首次创建时（进入设置已选中软件更新）也加载缓存数据
        Component.onCompleted: syncCachedData()
        onVisibleChanged: { if (visible) syncCachedData() }

        function syncCachedData() {
            if (!updateChecker.latestVersion) return
            latestVerLabel.text = updateChecker.latestVersion
            var rawDate = updateChecker.releaseDate
            if (rawDate) {
                var d = new Date(rawDate)
                dateLabel.text = d.toLocaleDateString(Qt.locale("zh_CN"), "yyyy-MM-dd")
            }
            changelogArea.text = updateChecker.changelogHtml
        }
    }

    // ---- 绑定 C++ 更新信号 ----
    Connections {
        target: updateChecker
        enabled: settingsSubMenu === "update"

        function onInfoChanged() {
            checkingLabel.visible = false
            statusLabel.text = ""
            latestVerLabel.text = updateChecker.latestVersion
            var rawDate = updateChecker.releaseDate
            if (rawDate) {
                var d = new Date(rawDate)
                dateLabel.text = d.toLocaleDateString(Qt.locale("zh_CN"), "yyyy-MM-dd")
            }
            changelogArea.text = updateChecker.changelogHtml
        }

        function onDownloadProgressChanged() {
            var received = updateChecker.downloadProgress
            var total = updateChecker.downloadTotal
            var pct = total > 0 ? Math.round(received / total * 100) : 0
            progressLabel.text = pct + "%"
        }

        function onDownloadFinished(success, filePath, folderPath) {
            progressRow.visible = false
            if (success) {
                downloadsLabel.visible = true
                openFolderBtn.visible = true
                updateChecker.openDownloadFolder()
            }
        }

        function onNotifyMessage(title, message) {
            checkingLabel.visible = false
            statusLabel.text = title + "：" + message
            statusLabel.color = "#3B82F6"
        }
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
            color: "#222222"; border.color: "#3A3A3A"

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "歌词预读偏移"
                        font.family: fontFamily; font.pixelSize: 15; color: "#ffffff"
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: {
                            var off = (musicManager.lyricOffset || 130) - 130
                            if (off === 0) return "0ms (默认)"
                            return (off > 0 ? "+" : "") + off + "ms"
                        }
                        font.family: fontFamily; font.pixelSize: 15; color: "#3B82F6"
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    from: 50; to: 350; stepSize: 5
                    value: musicManager.lyricOffset || 130
                    onMoved: musicManager.lyricOffset = Math.round(value / 5) * 5

                    background: Rectangle {
                        x: 0; y: parent.height / 2 - 2
                        width: parent.width; height: 4; radius: 2; color: "#3A3A3A"
                    }
                    contentItem: Rectangle {
                        width: parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from)
                        height: 4; radius: 2; color: "#3B82F6"
                        visible: parent.visible
                    }
                    handle: Rectangle {
                        x: parent.leftPadding + parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from) - width / 2
                        y: parent.height / 2 - height / 2
                        width: 16; height: 16; radius: 8; color: "#3B82F6"
                    }
                }

                Label {
                    text: {
                        var off = (musicManager.lyricOffset || 130) - 130
                        if (off === 0) return "未调整"
                        return "已调整: " + (off > 0 ? "+" : "") + off + "ms"
                    }
                    font.family: fontFamily; font.pixelSize: 12; color: "#777777"
                }
            }
        }

        Item { Layout.preferredHeight: 14 }

        // 音频输出模式（WASAPI 独占/共享）
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 130; radius: 8
            color: "#222222"; border.color: "#3A3A3A"

            ColumnLayout {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20; anchors.topMargin: 12; anchors.bottomMargin: 20; spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "WASAPI 独占模式"; font.family: fontFamily; font.pixelSize: 15; color: "#ffffff" }
                    Item { Layout.fillWidth: true }
                    Switch {
                        Layout.alignment: Qt.AlignVCenter
                        checked: musicManager.wasapiExclusive || false
                        onToggled: musicManager.wasapiExclusive = checked

                        indicator: Rectangle {
                            implicitWidth: 38
                            implicitHeight: 22
                            x: parent.leftPadding
                            y: parent.topPadding + (parent.availableHeight - height) / 2
                            radius: 11
                            color: parent.checked ? "#3B82F6" : "#555"
                            border.color: parent.checked ? "#3B82F6" : "#444"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Rectangle {
                                x: parent.checked ? parent.width - width - 2 : 2
                                y: (parent.height - height) / 2
                                width: 18; height: 18; radius: 9
                                color: "#fff"
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }

                Label {
                    text: musicManager.wasapiExclusive
                          ? "已开启：独占音频输出设备，延迟更低、音质更稳定，但其他应用将无法使用该设备发声。（热插拔自动暂停/恢复播放）"
                          : "关闭时使用共享模式（默认），可与其他应用同时发声。切换后立即生效并自动恢复播放。（热插拔不影响播放）"
                    font.family: fontFamily; font.pixelSize: 11; color: "#777777"
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
        }

        Item { Layout.preferredHeight: 14 }

        // 跨来源跟踪开关
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 110; radius: 8
            color: "#222222"; border.color: "#3A3A3A"

            ColumnLayout {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20; anchors.topMargin: 12; anchors.bottomMargin: 20; spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "其他列表播放时首页是否显示对应歌曲"; font.family: fontFamily; font.pixelSize: 15; color: "#ffffff" }
                    Item { Layout.fillWidth: true }
                    Switch {
                        Layout.alignment: Qt.AlignVCenter
                        checked: musicManager.trackCrossSource || false
                        onToggled: musicManager.trackCrossSource = checked

                        indicator: Rectangle {
                            implicitWidth: 38
                            implicitHeight: 22
                            x: parent.leftPadding
                            y: parent.topPadding + (parent.availableHeight - height) / 2
                            radius: 11
                            color: parent.checked ? "#3B82F6" : "#555"
                            border.color: parent.checked ? "#3B82F6" : "#444"
                            Behavior on color { ColorAnimation { duration: 150 } }

                            Rectangle {
                                x: parent.checked ? parent.width - width - 2 : 2
                                y: (parent.height - height) / 2
                                width: 18; height: 18; radius: 9
                                color: "#fff"
                                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }

                Label {
                    text: musicManager.trackCrossSource
                          ? "开启后，在其他列表播放时首页将同步显示当前歌曲。"
                          : "关闭后，在其他列表播放时首页将不再高亮当前曲目。\n点击首页任意歌曲将从首页列表从头播放（含确认弹窗）。"
                    font.family: fontFamily; font.pixelSize: 11; color: "#777777"
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
            color: "#222222"; border.color: "#3A3A3A"

            ColumnLayout {
                id: hotkeyCol
                anchors.fill: parent; anchors.margins: 20; spacing: 10

                Label {
                    text: "全局快捷键"
                    font.family: fontFamily; font.pixelSize: 15; font.bold: true; color: "#ffffff"
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
                                    font.family: fontFamily; font.pixelSize: 15; color: "#ffffff"
                                    Layout.preferredWidth: 100
                                }

                                // 显示/捕获区域
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    radius: 6
                                    color: hotkeyRow.capturing ? "#333333" : (hkMA.containsMouse ? "#1E1E1E" : "#222222")
                                    border.color: hotkeyRow.capturing ? "#3B82F6" : "#3A3A3A"
                                    border.width: hotkeyRow.capturing ? 2 : 1

                                    Label {
                                        anchors.centerIn: parent
                                        text: hotkeyRow.capturing ? "按下快捷键..." : hotkeyRow.buildDisplayText()
                                        font.family: fontFamily; font.pixelSize: 13
                                        color: hotkeyRow.capturing ? "#3B82F6" : "#ffffff"
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
                                    color: resetMA.containsMouse ? "#3A3A3A" : "transparent"
                                    visible: !hotkeyRow.capturing

                                    Text {
                                        anchors.centerIn: parent
                                        text: "↺"
                                        font.family: fontFamily; font.pixelSize: 16; color: "#777777"
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
                    font.family: fontFamily; font.pixelSize: 11; color: "#777777"
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
        }

        Label {
            text: "修改后实时生效，重启后保持设置"
            font.family: fontFamily; font.pixelSize: 12; color: "#777777"
            Layout.topMargin: 8
        }
        Item { Layout.fillHeight: true }
    }

    // ---- 外观（卡片较多，内容超出时滚动） ----
    ScrollView {
        id: appearanceScroll
        anchors.fill: parent
        visible: settingsSubMenu === "appearance"
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded

        ColumnLayout {
            width: appearanceScroll.availableWidth
            spacing: 0

            Item { Layout.preferredHeight: 14 }

        // 歌词字体
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 126; radius: 8
            color: "#222222"; border.color: "#3A3A3A"

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 10

                Label {
                    text: "歌词字体"
                    font.family: fontFamily; font.pixelSize: 15; color: "#ffffff"
                }

                // 字体选择下拉按钮
                Rectangle {
                    id: lyricFontBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 36; radius: 8
                    color: lyricFontBtnMA.containsMouse ? "#2A2A2A" : "#1E1E1E"
                    border.color: lyricFontPopup.visible ? "#3B82F6" : "#3A3A3A"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                        spacing: 8
                        Label {
                            Layout.fillWidth: true
                            text: settingsRoot.lyricFontLabel()
                            font.family: fontFamily; font.pixelSize: 14; color: "#ffffff"
                            elide: Text.ElideRight
                        }
                        Label { text: "▾"; font.family: fontFamily; font.pixelSize: 12; color: "#888" }
                    }

                    MouseArea {
                        id: lyricFontBtnMA
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: lyricFontPopup.open()
                    }

                    // 字体选择弹窗：内置字体 + 系统字体
                    Popup {
                        id: lyricFontPopup
                        x: 0
                        y: parent.height + 6
                        width: parent.width
                        padding: 0
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

                        // 当前选择为系统字体时，打开后自动滚动到该字体位置
                        onOpened: {
                            var key = musicManager.lyricFont
                            if (!key || key.indexOf("system:") !== 0) return
                            var fam = key.substring(7)
                            var list = musicManager.systemLyricFonts()
                            for (var i = 0; i < list.length; i++) {
                                if (list[i].family === fam) {
                                    Qt.callLater(function() {
                                        sysFontList.positionViewAtIndex(i, ListView.Center)
                                    })
                                    break
                                }
                            }
                        }

                        background: Rectangle {
                            color: "#222222"; border.color: "#3A3A3A"; radius: 8
                        }

                        contentItem: Column {
                            width: lyricFontPopup.width
                            spacing: 0

                            Label {
                                text: "内置字体"
                                font.family: fontFamily; font.pixelSize: 12; color: "#777777"
                                leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 4
                            }

                            Repeater {
                                model: musicManager.builtinLyricFonts()

                                delegate: Rectangle {
                                    width: lyricFontPopup.width
                                    height: 34
                                    color: builtinItemMA.containsMouse ? "#2C2C2C" : "transparent"

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                                        spacing: 8
                                        Label {
                                            Layout.fillWidth: true
                                            text: modelData.label
                                            font.family: fontFamily; font.pixelSize: 13
                                            color: musicManager.lyricFont === modelData.key ? "#3B82F6" : "#dddddd"
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            text: "✓"
                                            font.family: fontFamily; font.pixelSize: 12; color: "#3B82F6"
                                            visible: musicManager.lyricFont === modelData.key
                                        }
                                    }

                                    MouseArea {
                                        id: builtinItemMA
                                        anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            musicManager.lyricFont = modelData.key
                                            lyricFontPopup.close()
                                        }
                                    }
                                }
                            }

                            Rectangle { width: lyricFontPopup.width; height: 1; color: "#3A3A3A" }

                            Label {
                                text: "系统字体"
                                font.family: fontFamily; font.pixelSize: 12; color: "#777777"
                                leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 4
                            }

                            ListView {
                                id: sysFontList
                                width: lyricFontPopup.width
                                height: Math.min(216, count * 34)
                                clip: true
                                model: musicManager.systemLyricFonts()

                                ScrollBar.vertical: ScrollBar {
                                    policy: ScrollBar.AsNeeded
                                    width: 8
                                    minimumSize: 0.15  // 滑块最短长度，防止字体多时滑块过短
                                    background: Rectangle { implicitWidth: 8; radius: 4; color: "#222222" }
                                    contentItem: Rectangle {
                                        implicitWidth: 8; radius: 4
                                        color: sysFontScrollHover.containsMouse ? "#777777" : "#3A3A3A"
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                        MouseArea {
                                            id: sysFontScrollHover
                                            hoverEnabled: true; acceptedButtons: Qt.NoButton
                                            propagateComposedEvents: true
                                        }
                                    }
                                }

                                delegate: Rectangle {
                                    width: sysFontList.width
                                    height: 34
                                    color: sysFontItemMA.containsMouse ? "#2C2C2C" : "transparent"

                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 20
                                        spacing: 8
                                        Label {
                                            Layout.fillWidth: true
                                            text: modelData.family
                                            font.family: fontFamily; font.pixelSize: 13
                                            color: musicManager.lyricFont === modelData.key ? "#3B82F6" : "#dddddd"
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            text: "✓"
                                            font.family: fontFamily; font.pixelSize: 12; color: "#3B82F6"
                                            visible: musicManager.lyricFont === modelData.key
                                        }
                                    }

                                    MouseArea {
                                        id: sysFontItemMA
                                        anchors.fill: parent; hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            musicManager.lyricFont = modelData.key
                                            lyricFontPopup.close()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Label {
                    text: "选择歌词显示字体，默认鸿蒙字体，也可从内置字体或系统中选择其他字体，修改后立即生效。"
                    font.family: fontFamily; font.pixelSize: 11; color: "#777777"
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
        }

        Item { Layout.preferredHeight: 14 }

        // 循环模式菜单透明度
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 90; radius: 8
            color: "#222222"; border.color: "#3A3A3A"

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "循环模式菜单透明度"
                        font.family: fontFamily; font.pixelSize: 15; color: "#ffffff"
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: {
                            var op = Number(musicManager.menuOpacity)
                            return Math.round((op > 0 ? op : 0.8) * 100) + "%"
                        }
                        font.family: fontFamily; font.pixelSize: 15; color: "#3B82F6"
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
                        width: parent.width; height: 4; radius: 2; color: "#3A3A3A"
                    }
                    contentItem: Rectangle {
                        width: parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from)
                        height: 4; radius: 2; color: "#3B82F6"
                        visible: parent.visible
                    }
                    handle: Rectangle {
                        x: parent.leftPadding + parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from) - width / 2
                        y: parent.height / 2 - height / 2
                        width: 16; height: 16; radius: 8; color: "#3B82F6"
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 14 }

        // 音量控制条透明度
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 90; radius: 8
            color: "#222222"; border.color: "#3A3A3A"

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "音量控制条透明度"
                        font.family: fontFamily; font.pixelSize: 15; color: "#ffffff"
                    }
                    Item { Layout.fillWidth: true }
                    Label {
                        text: {
                            var op = Number(musicManager.volumeMenuOpacity)
                            return Math.round((op > 0 ? op : 0.8) * 100) + "%"
                        }
                        font.family: fontFamily; font.pixelSize: 15; color: "#3B82F6"
                    }
                }

                Slider {
                    Layout.fillWidth: true
                    from: 0.3; to: 1.0; stepSize: 0.01
                    value: {
                        var op = Number(musicManager.volumeMenuOpacity)
                        return op > 0 ? op : 0.8
                    }
                    onMoved: musicManager.volumeMenuOpacity = value

                    background: Rectangle {
                        x: 0; y: parent.height / 2 - 2
                        width: parent.width; height: 4; radius: 2; color: "#3A3A3A"
                    }
                    contentItem: Rectangle {
                        width: parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from)
                        height: 4; radius: 2; color: "#3B82F6"
                        visible: parent.visible
                    }
                    handle: Rectangle {
                        x: parent.leftPadding + parent.availableWidth * (parent.value - parent.from) / (parent.to - parent.from) - width / 2
                        y: parent.height / 2 - height / 2
                        width: 16; height: 16; radius: 8; color: "#3B82F6"
                    }
                }
            }
        }

        Item { Layout.preferredHeight: 14 }

        // 播放背景
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 150; radius: 8
            color: "#222222"; border.color: "#3A3A3A"

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 12

                Label {
                    text: "播放背景"
                    font.family: fontFamily; font.pixelSize: 15; color: "#ffffff"
                }

                // 两种背景模式
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40; radius: 8
                        color: bgDarkMA.containsMouse ? "#3a3a3a"
                              : (musicManager.playbackBackground === 0 ? "#3B82F6" : "#2a2a2a")
                        border.color: musicManager.playbackBackground === 0 ? "#3B82F6" : "#3A3A3A"
                        Label {
                            anchors.centerIn: parent
                            text: "深色背景"
                            font.family: fontFamily; font.pixelSize: 14
                            color: musicManager.playbackBackground === 0 ? "#ffffff" : "#bbbbbb"
                        }
                        MouseArea {
                            id: bgDarkMA
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: musicManager.playbackBackground = 0
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40; radius: 8
                        color: bgImmersiveMA.containsMouse ? "#3a3a3a"
                              : (musicManager.playbackBackground === 1 ? "#3B82F6" : "#2a2a2a")
                        border.color: musicManager.playbackBackground === 1 ? "#3B82F6" : "#3A3A3A"
                        Label {
                            anchors.centerIn: parent
                            text: "沉浸背景"
                            font.family: fontFamily; font.pixelSize: 14
                            color: musicManager.playbackBackground === 1 ? "#ffffff" : "#bbbbbb"
                        }
                        MouseArea {
                            id: bgImmersiveMA
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: musicManager.playbackBackground = 1
                        }
                    }
                }

                Label {
                    text: "沉浸背景可能比较占用性能，默认/歌曲无封面将使用深色背景"
                    font.family: fontFamily; font.pixelSize: 11; color: "#777777"
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
        }

        Item { Layout.preferredHeight: 14 }

        // 关闭窗口行为
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 70; radius: 8
            color: "#222222"; border.color: "#3A3A3A"

            RowLayout {
                anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20; anchors.topMargin: 12; anchors.bottomMargin: 20
                spacing: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label {
                        text: "关闭窗口时最小化到系统托盘"
                        font.family: fontFamily; font.pixelSize: 15; color: "#ffffff"
                    }
                    Label {
                        text: "关闭后音乐继续在后台播放，可通过托盘图标恢复"
                        font.family: fontFamily; font.pixelSize: 11; color: "#777777"
                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }

                Switch {
                    Layout.alignment: Qt.AlignVCenter
                    checked: musicManager.minimizeToTray
                    onToggled: musicManager.minimizeToTray = checked

                    indicator: Rectangle {
                        implicitWidth: 38
                        implicitHeight: 22
                        x: parent.leftPadding
                        y: parent.topPadding + (parent.availableHeight - height) / 2
                        radius: 11
                        color: parent.checked ? "#3B82F6" : "#555"
                        border.color: parent.checked ? "#3B82F6" : "#444"
                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            x: parent.checked ? parent.width - width - 2 : 2
                            y: (parent.height - height) / 2
                            width: 18; height: 18; radius: 9
                            color: "#fff"
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }
                    }
                }
            }
        }

        Label {
            text: "修改后立即生效，重启后保持设置"
            font.family: fontFamily; font.pixelSize: 12; color: "#777777"
            Layout.topMargin: 8
        }
        Item { Layout.preferredHeight: 14 }
        }
    }
    // ---- 关于 ----
    ColumnLayout {
        anchors.fill: parent; spacing: 0
        visible: settingsSubMenu === "about"
        Item { Layout.preferredHeight: 8 }
        Label { text: "Just Solo - 轻量级桌面音乐播放器"; font.family: fontFamily; font.pixelSize: 15; color: "#ffffff" }
        Item { Layout.preferredHeight: 4 }
        Label { text: "作者: ZZJ-JACK"; font.family: fontFamily; font.pixelSize: 13; color: "#777777" }
        Label { text: `<a href="https://zzjjack.us.kg">https://zzjjack.us.kg</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#3B82F6"; Layout.topMargin: 4; onLinkActivated: Qt.openUrlExternally(link) }
        Label { text: `<a href="https://justsolo.zzjjack.us.kg">官方网站: https://justsolo.zzjjack.us.kg</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#3B82F6"; Layout.topMargin: 4; onLinkActivated: Qt.openUrlExternally(link) }
        Item { Layout.preferredHeight: 8 }
        Label { text: "基于 Qt 6.8.3 + QML 构建"; font.family: fontFamily; font.pixelSize: 13; color: "#777777" }
        Label { text: "运行环境: " + (typeof OS_VERSION !== "undefined" ? OS_VERSION : "未知"); font.family: fontFamily; font.pixelSize: 13; color: "#777777" }
        Item { Layout.preferredHeight: 8 }

        // ---- Just Solo LyricServer 协议状态 ----
        Rectangle {
            Layout.fillWidth: true; Layout.maximumWidth: 520
            Layout.preferredHeight: 120; radius: 10
            color: "#222222"; border.color: "#3A3A3A"

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 18; spacing: 8

                // 标题行：协议名称 + 状态徽章
                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "Just Solo LyricServer"
                        font.family: fontFamily; font.pixelSize: 15; font.bold: true; color: "#ffffff"
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        Layout.preferredWidth: 58; Layout.preferredHeight: 22; radius: 11
                        color: "#222222"
                        border.color: "#3A3A3A"
                        RowLayout {
                            anchors.centerIn: parent; spacing: 4
                            Rectangle {
                                width: 7; height: 7; radius: 3.5
                                color: (typeof lyricServer !== "undefined" && lyricServer && lyricServer.running) ? "#3B82F6" : "#3B82F6"
                            }
                            Label {
                                text: (typeof lyricServer !== "undefined" && lyricServer && lyricServer.running) ? "已启用" : "未启用"
                                font.family: fontFamily; font.pixelSize: 11; color: (typeof lyricServer !== "undefined" && lyricServer && lyricServer.running) ? "#3B82F6" : "#3B82F6"
                            }
                        }
                    }
                }

                // 版本 + 端点
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    Rectangle {
                        Layout.preferredWidth: 68; Layout.preferredHeight: 22; radius: 6
                        color: "#3A3A3A"
                        Label {
                            anchors.centerIn: parent
                            text: LYRICSERVER_VERSION || "v1.0.0"
                            font.family: fontFamily; font.pixelSize: 11; font.bold: true; color: "#3B82F6"
                        }
                    }
                    Label {
                        text: "ws://127.0.0.1:47290"
                        font.family: "Cascadia Code, Consolas, monospace"; font.pixelSize: 12; color: "#777777"
                    }
                }

                // 协议简述
                Label {
                    text: "单向实时歌词推送：初始化(init) · 进度(progress) · 状态(playback)"
                    font.family: fontFamily; font.pixelSize: 11; color: "#777777"
                    elide: Text.ElideRight; Layout.fillWidth: true
                }
            }
        }

        Item { Layout.preferredHeight: 12 }
        Label { text: "项目地址"; font.family: fontFamily; font.pixelSize: 13; color: "#ffffff" }
        Label { text: `<a href="https://gitcode.com/ZZJ-JACK/Just-Solo">https://gitcode.com/ZZJ-JACK/Just-Solo</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#3B82F6"; Layout.topMargin: 4; onLinkActivated: Qt.openUrlExternally(link) }
        Label { text: `<a href="https://github.com/ZZJ-jack/Just-Solo">https://github.com/ZZJ-jack/Just-Solo</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#3B82F6"; Layout.topMargin: 2; onLinkActivated: Qt.openUrlExternally(link) }
        Item { Layout.preferredHeight: 12 }
        Label { text: "图标来源: 鸿蒙开发者"; font.family: fontFamily; font.pixelSize: 13; color: "#ffffff" }
        Label { text: `<a href="https://developer.huawei.com/consumer/cn/">https://developer.huawei.com/consumer/cn</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#3B82F6"; Layout.topMargin: 4; onLinkActivated: Qt.openUrlExternally(link) }
        Item { Layout.fillHeight: true }
    }

    // ---- 文件夹选择对话框（下载用） ----
    FolderDialog {
        id: folderDialog
        title: "选择保存安装程序的文件夹"
        currentFolder: StandardPaths.writableLocation(StandardPaths.DownloadLocation)

        onAccepted: {
            var path = folderDialog.selectedFolder.toString()
            if (path.startsWith("file:///")) path = path.substring(8)
            else if (path.startsWith("file://")) path = path.substring(7)
            progressRow.visible = true
            if (selectedDownloadUrl) {
                updateChecker.downloadInstaller(path, selectedDownloadUrl)
                selectedDownloadUrl = ""
            } else {
                updateChecker.downloadInstaller(path)
            }
        }
    }

    // ---- 下载源选择弹窗 ----
    Dialog {
        id: downloadSourceDialog
        parent: Overlay.overlay
        modal: true
        standardButtons: Dialog.NoButton

        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 360

        Overlay.modal: Rectangle {
            color: "#80000000"
        }

        background: Rectangle {
            radius: 10
            color: "#222222"
            border.color: "#333333"
        }

        header: Label {
            text: "选择下载源"
            font.family: fontFamily
            font.pixelSize: 16
            font.bold: true
            color: "#ffffff"
            padding: 16
        }

        contentItem: ColumnLayout {
            spacing: 12

            Label {
                text: "请选择安装程序下载来源："
                font.family: fontFamily; font.pixelSize: 13; color: "#ffffff"
                Layout.fillWidth: true; wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 44; radius: 8
                color: giteeMA.containsMouse ? "#3a5a3a" : "#2a4a2a"
                border.color: "#3a6a3a"
                Label {
                    anchors.centerIn: parent
                    text: "Gitcode 国内下载（推荐）"
                    font.family: fontFamily; font.pixelSize: 15; color: "#3B82F6"
                }
                MouseArea {
                    id: giteeMA
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        selectedDownloadUrl = ""
                        downloadSourceDialog.close()
                        folderDialog.open()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 44; radius: 8
                color: githubMA.containsMouse ? "#333333" : "#222222"
                border.color: "#3A3A3A"
                Label {
                    anchors.centerIn: parent
                    text: "GitHub 国际下载"
                    font.family: fontFamily; font.pixelSize: 15; color: "#3B82F6"
                }
                MouseArea {
                    id: githubMA
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        selectedDownloadUrl = updateChecker.githubDownloadUrl
                        downloadSourceDialog.close()
                        folderDialog.open()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; Layout.preferredHeight: 36; radius: 8
                color: cancelMA.containsMouse ? "#3a3a4a" : "#222222"
                border.color: "#3a3a4a"
                Label {
                    anchors.centerIn: parent
                    text: "取消"
                    font.family: fontFamily; font.pixelSize: 13; color: "#777777"
                }
                MouseArea {
                    id: cancelMA
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: downloadSourceDialog.close()
                }
            }
        }
    }

}
