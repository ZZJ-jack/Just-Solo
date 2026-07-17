import QtQuick
import QtQuick.Controls
import QtQuick.Effects

Item {
    id: root

    required property string fontFamily

    property bool opening: false
    property int _lastScroll: -1
    property real originX: 0
    property real originY: root.height

    opacity: 0
    visible: false

    transform: Scale {
        id: scaler
        origin.x: root.originX; origin.y: root.originY
        xScale: 0.3; yScale: 0.3
    }

    function fmtTime(ms) {
        if (ms <= 0) return "0:00"
        var s = Math.floor(ms / 1000)
        return Math.floor(s / 60) + ":" + ("0" + (s % 60)).slice(-2)
    }

    function close() {
        if (!visible || opening) return
        closeAnim.start()
    }

    onVisibleChanged: {
        if (visible) {
            bgBlur.live = true
            blurFx.blurEnabled = true
            _lastScroll = -1
            opening = true
            openAnim.start()
        } else {
            blurFx.blurEnabled = false
            bgBlur.live = false
            openAnim.stop(); closeAnim.stop()
        }
    }

    Connections {
        target: typeof musicManager !== "undefined" && musicManager ? musicManager : null
        function onLyricIndexChanged() {
            var idx = musicManager.lyricIndex
            if (idx < 0 || idx === root._lastScroll || lyricsView.count === 0) return
            root._lastScroll = idx
            lyricsView.positionViewAtIndex(idx, ListView.Center)
        }
    }

    SequentialAnimation {
        id: openAnim
        ParallelAnimation {
            OpacityAnimator { target: root; to: 1; duration: 250; easing.type: Easing.Linear }
            NumberAnimation { target: scaler; properties: "xScale,yScale"; to: 1; duration: 350; easing.type: Easing.Linear }
        }
        ScriptAction { script: root.opening = false }
    }
    SequentialAnimation {
        id: closeAnim
        ParallelAnimation {
            OpacityAnimator { target: root; to: 0; duration: 200; easing.type: Easing.Linear }
            NumberAnimation { target: scaler; properties: "xScale,yScale"; to: 0.3; duration: 250; easing.type: Easing.Linear }
        }
        onFinished: root.visible = false
    }

    // 全屏事件屏蔽层（阻止所有操作穿透到下层）
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        hoverEnabled: true
        preventStealing: true
        propagateComposedEvents: false
        onWheel: function(w) { w.accepted = true }
        onPressed: function(m) { m.accepted = true }
        onReleased: function(m) { m.accepted = true }
        onPositionChanged: function(m) { m.accepted = true }
    }

    // ============================================================
    // 毛玻璃背景
    // ============================================================
    ShaderEffectSource {
        id: bgBlur
        anchors.fill: parent
        sourceItem: mainWindow.contentItem
        live: false; visible: false
    }
    MultiEffect {
        id: blurFx
        anchors.fill: parent
        source: bgBlur
        blurEnabled: true; blurMax: 48; blur: 0.7
        brightness: 0.15; saturation: 0.1
    }
    Rectangle { anchors.fill: parent; color: Qt.rgba(0.05, 0.05, 0.09, musicManager ? musicManager.detailOpacity : 0.85) }

    // 关闭按钮
    Rectangle {
        anchors.top: parent.top; anchors.right: parent.right
        anchors.topMargin: 14; anchors.rightMargin: 22
        width: 36; height: 36; radius: 18
        color: closeMA.containsMouse ? "#33ffffff" : "transparent"
        Text { anchors.centerIn: parent; text: "\u25BC"; font.family: root.fontFamily; font.pixelSize: 14; color: closeMA.containsMouse ? "#ccc" : "#777" }
        MouseArea { id: closeMA; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.close() }
    }

    // ============================================================
    // 主体
    // ============================================================
    Item {
        id: mainBody
        anchors.top: parent.top; anchors.bottom: bottomBar.top
        anchors.left: parent.left; anchors.right: parent.right
        anchors.topMargin: 46; anchors.bottomMargin: 8
        anchors.leftMargin: 20; anchors.rightMargin: 30

        Rectangle {
            id: divider
            anchors.left: coverArea.right; anchors.leftMargin: 16
            anchors.top: parent.top; anchors.bottom: parent.bottom
            anchors.topMargin: 10; anchors.bottomMargin: 10
            width: 1; color: "#22ffffff"
        }

        // 左：封面 + 歌名 + 歌手 + 专辑
        Item {
            id: coverArea
            anchors.top: parent.top; anchors.bottom: parent.bottom
            anchors.left: parent.left
            width: mainWindow.visibility === Window.Maximized ? parent.width * 0.333 : Math.min(parent.width * 0.38, 360)

            Rectangle {
                id: coverBox
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.max(0, parent.height * 0.04)
                width: Math.min(parent.width * 0.85, parent.height * 0.42)
                height: width; radius: 12; color: "#1e1e35"
                border.color: "#2a2a48"; border.width: 1

                Image {
                    anchors.fill: parent; anchors.margins: 3
                    source: (typeof musicManager !== "undefined" && musicManager) ? (musicManager.currentCover || "") : ""
                    fillMode: Image.PreserveAspectFit; asynchronous: true
                    visible: source !== ""
                    opacity: status === Image.Ready ? 1 : 0
                }
                Text {
                    anchors.centerIn: parent; font.family: root.fontFamily
                    text: "\u266B"; font.pixelSize: 42; color: "#3a3a5a"
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
                font.family: root.fontFamily; font.pixelSize: 18; color: "#999"
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
                font.family: root.fontFamily; font.pixelSize: 15; color: "#bbb"
                elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                visible: text !== ""
            }
        }

        // 右：歌词（只展示 5 句，自动换行）
        Item {
            id: lyricsCol
            anchors.top: parent.top; anchors.bottom: parent.bottom
            anchors.left: divider.right; anchors.right: parent.right
            anchors.leftMargin: 20
            clip: true

            Text {
                anchors.centerIn: parent
                text: "暂无歌词"; font.family: root.fontFamily; font.pixelSize: 20; color: "#555"
                visible: lyricsView.count === 0
            }

            ListView {
                id: lyricsView
                anchors.fill: parent
                model: (typeof musicManager !== "undefined" && musicManager) ? (musicManager.currentLyrics || []) : []
                spacing: 10
                // 上下留白让当前行居中，只展示约 5 句
                topMargin: parent.height * 0.38; bottomMargin: parent.height * 0.38
                clip: true; cacheBuffer: 600; reuseItems: false
                Behavior on contentY { NumberAnimation { duration: 250; easing.type: Easing.Linear } }

                delegate: Item {
                    id: lyricDelegate
                    width: lyricsView.width
                    height: mainContainer.height + 8

                    property bool isCurrent: (typeof musicManager !== "undefined" && musicManager) && index === musicManager.lyricIndex
                    property bool isPast: (typeof musicManager !== "undefined" && musicManager) && index < musicManager.lyricIndex
                    property bool hasTrans: (modelData.translation || "") !== ""
                    property bool highlight: isCurrent || isPast

                    // 歌词+翻译（WordWrap，行高自适应，整段高光）
                    Item {
                        id: mainContainer
                        anchors.left: parent.left; anchors.leftMargin: 4
                        anchors.top: parent.top
                        width: lyricsView.width - 8
                        height: mainCol.implicitHeight

                        Column {
                            id: mainCol
                            spacing: 4

                            // 主歌词行（高度自适应，超长自动换行）
                            Item {
                                width: mainContainer.width
                                height: Math.max(52, mainGray.implicitHeight)
                                clip: true

                                Text {
                                    id: mainGray
                                    anchors.left: parent.left
                                    y: (parent.height - height) / 2
                                    width: parent.width
                                    text: modelData.text || ""
                                    font.family: root.fontFamily
                                    font.pixelSize: lyricDelegate.isCurrent ? 58 : 36
                                    color: lyricDelegate.isPast ? "#3a3a3a"
                                         : (lyricDelegate.isCurrent ? "#555" : "#6a9ac0")
                                    horizontalAlignment: Text.AlignLeft
                                    wrapMode: Text.WordWrap
                                    Behavior on font.pixelSize { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 300 } }
                                }

                                // 整段高亮覆盖层：已播=黄色，当前=青色
                                Text {
                                    anchors.left: parent.left
                                    anchors.top: mainGray.top
                                    width: parent.width
                                    height: mainGray.implicitHeight
                                    visible: lyricDelegate.highlight
                                    text: modelData.text || ""
                                    font.family: root.fontFamily; font.pixelSize: lyricDelegate.isCurrent ? 58 : 36
                                    color: lyricDelegate.isPast ? "#FFD700" : "#00d4ff"
                                    horizontalAlignment: Text.AlignLeft
                                    wrapMode: Text.WordWrap
                                    Behavior on font.pixelSize { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: 250 } }
                                    Behavior on color { ColorAnimation { duration: 300 } }
                                }
                            }

                            // 翻译行（高度自适应）
                            Item {
                                width: mainContainer.width
                                height: hasTrans ? Math.max(38, transGray.implicitHeight) : 0
                                visible: hasTrans
                                clip: true

                                Text {
                                    id: transGray
                                    anchors.left: parent.left
                                    y: (parent.height - height) / 2
                                    width: parent.width
                                    text: modelData.translation || ""
                                    font.family: root.fontFamily
                                    font.pixelSize: lyricDelegate.isCurrent ? 34 : 24
                                    color: lyricDelegate.isPast ? "#2a2a2a"
                                         : (lyricDelegate.isCurrent ? "#333" : "#4a6a8a")
                                    horizontalAlignment: Text.AlignLeft
                                    wrapMode: Text.WordWrap
                                    Behavior on font.pixelSize { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                    Behavior on color { ColorAnimation { duration: 300 } }
                                }

                                // 翻译整段高亮覆盖层：已播=暗金，当前=金色
                                Text {
                                    anchors.left: parent.left
                                    anchors.top: transGray.top
                                    width: parent.width
                                    height: transGray.implicitHeight
                                    visible: lyricDelegate.highlight && lyricDelegate.hasTrans
                                    text: modelData.translation || ""
                                    font.family: root.fontFamily; font.pixelSize: lyricDelegate.isCurrent ? 34 : 24
                                    color: lyricDelegate.isPast ? "#b8960f" : "#FFD700"
                                    horizontalAlignment: Text.AlignLeft
                                    wrapMode: Text.WordWrap
                                    Behavior on font.pixelSize { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: 250 } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ============================================================
    // 底部：三个按钮对齐 + 进度条
    // ============================================================
    Item {
        id: bottomBar
        anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.right: parent.right
        anchors.bottomMargin: 24
        height: 44

        // 三个按钮居中对齐（同一 Y 轴）
        Row {
            id: controls
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 24; spacing: 20
            height: 40

            // 上一首
            Item {
                width: 40; height: 40
                anchors.verticalCenter: parent.verticalCenter
                Image { anchors.centerIn: parent; source: "qrc:/qt/qml/JustSolo/data/image/play.png"; width: 26; height: 26; opacity: 0.4; rotation: 180 }
                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: musicManager.previous() }
            }
            // 播放/暂停
            Rectangle {
                width: 40; height: 40; radius: 20; color: "#444466"
                anchors.verticalCenter: parent.verticalCenter
                Image { source: "qrc:/qt/qml/JustSolo/data/image/play.png"; width: 22; height: 22; anchors.centerIn: parent; opacity: musicManager.isPlaying ? 0 : 1; Behavior on opacity { NumberAnimation { duration: 120 } } }
                Image { source: "qrc:/qt/qml/JustSolo/data/image/playing.png"; width: 22; height: 22; anchors.centerIn: parent; opacity: musicManager.isPlaying ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 120 } } }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { if (musicManager.currentIndex >= 0) musicManager.isPlaying ? musicManager.pause() : musicManager.play() } }
            }
            // 下一首
            Item {
                width: 40; height: 40
                anchors.verticalCenter: parent.verticalCenter
                Image { anchors.centerIn: parent; source: "qrc:/qt/qml/JustSolo/data/image/play.png"; width: 26; height: 26; opacity: 0.4 }
                MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor; onClicked: musicManager.next() }
            }
        }

        // 进度条
        Item {
            anchors.left: controls.right; anchors.right: parent.right
            anchors.leftMargin: 24; anchors.rightMargin: 24
            anchors.verticalCenter: parent.verticalCenter
            height: 20

            Text {
                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                text: root.fmtTime(musicManager.position)
                font.family: root.fontFamily; font.pixelSize: 11; color: "#888"
            }
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right
                anchors.leftMargin: 40; anchors.rightMargin: 40
                anchors.verticalCenter: parent.verticalCenter
                height: 4; radius: 2; color: "#3a3a55"
                Rectangle {
                    height: parent.height; radius: 2; color: "#00d4ff"
                    width: parent.width * (musicManager.duration > 0 ? musicManager.position / musicManager.duration : 0)
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
            }
            Text {
                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                text: root.fmtTime(musicManager.duration)
                font.family: root.fontFamily; font.pixelSize: 11; color: "#888"
            }
        }
    }
}
