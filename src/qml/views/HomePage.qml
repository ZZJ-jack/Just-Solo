import QtQuick
import QtQuick.Controls
import QtQuick.Effects

// ============================================================
// 主页 — 首页封面墙：正方形方块 + 大圆封面
// 方块 210×210 显示歌名/歌手与播放按钮，右缘盖住第一个圆的一半
// 圆形封面 140×140 显示专辑封面，按音乐库顺序向右逐个排开
// 沉浸背景模式下方块跟随当前歌曲主色
// ============================================================
Item {
    id: root

    // 由 main.qml 控制：true=当前显示主页
    property bool active: false
    property string fontFamily

    visible: active && musicManager.library.length > 0

    Row {
        id: homeCoverStrip
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -170   // 整体上移
        anchors.leftMargin: 0 // 与左侧边距
        spacing: -homeCoverStrip.roundSize / 2   // 负间距让第一个圆露出半边

        readonly property int blockSize: 210 // 方块尺寸
        readonly property int roundSize: 140 // 圆尺寸
        readonly property int circleSpacing: 14 // 圆间距

        // 方块展示的歌曲：优先当前播放（且在音乐库中），否则第一首
        readonly property int blockSongIndex: {
            var lib = musicManager.library
            if (lib.length === 0) return -1
            var p = musicManager.currentPath || ""
            for (var i = 0; i < lib.length; i++) {
                if (lib[i].path === p) return i
            }
            return 0
        }

        // 播放/暂停指定下标的歌曲（与封面点击行为一致）
        function toggleOrPlay(idx) {
            if (idx < 0) return
            var song = musicManager.library[idx]
            if (musicManager.currentPath === song.path) {
                if (musicManager.isPlaying) musicManager.pause()
                else musicManager.play()
            } else {
                musicManager.playFromLibrary(idx)
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
                var c = (idx >= 0 && musicManager.library.length > 0)
                        ? musicManager.coverColorOfSong(idx) : ""
                return c !== "" ? c : "#2C2C2C"
            }
            Behavior on color { ColorAnimation { duration: 600 } }

            // ---- 歌名 / 歌手（垂直居中，靠左） ----
            Column {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.rightMargin: 20
                spacing: 8

                Label {
                    width: parent.width
                    text: homeCoverStrip.blockSongIndex >= 0
                          ? (musicManager.library[homeCoverStrip.blockSongIndex].name || "未知歌曲") : ""
                    font.family: root.fontFamily
                    font.pixelSize: 27
                    font.bold: true
                    color: "#ffffff"
                    elide: Text.ElideRight
                }

                Label {
                    width: parent.width
                    text: homeCoverStrip.blockSongIndex >= 0
                          ? (musicManager.library[homeCoverStrip.blockSongIndex].artist || "未知歌手") : ""
                    font.family: root.fontFamily
                    font.pixelSize: 20
                    color: "#dddddd"
                    elide: Text.ElideRight
                }
            }

            // ---- 频谱律动（12 条模拟循环动画，仅播放时律动） ----
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
                        var isCur = idx >= 0 && musicManager.currentPath === musicManager.library[idx].path
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

            property int shiftTarget: -1   // 动画结束后要播放的歌曲真实下标

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
                        musicManager.playFromLibrary(circlesRow.shiftTarget)
                    }
                }
            }

            Repeater {
                // 从方块当前歌曲开始，按音乐库顺序循环排列，最后一首后回到第一首
                model: {
                    var lib = musicManager.library
                    var n = lib.length
                    if (n === 0) return []
                    var start = homeCoverStrip.blockSongIndex
                    if (start < 0) start = 0
                    var arr = []
                    for (var i = 0; i < n; i++) {
                        arr.push(lib[(start + i) % n])
                    }
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

                    Image {
                        anchors.fill: parent
                        anchors.margins: 6
                        source: modelData.cover || ""
                        sourceSize.width: 128
                        sourceSize.height: 128
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: modelData.cover && modelData.cover !== ""
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
                        visible: !modelData.cover || modelData.cover === ""
                    }

                    MouseArea {
                        id: circleHover
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // 圆圈按循环顺序排列，点击时映射回音乐库真实下标
                            var n = musicManager.library.length
                            if (n === 0) return
                            var realIndex = (homeCoverStrip.blockSongIndex + index) % n
                            if (index === 0) {
                                // 第一个圆与封面是同一首歌：当作点击封面，播放/暂停
                                homeCoverStrip.toggleOrPlay(homeCoverStrip.blockSongIndex)
                            } else {
                                // 点击后面的圆：动画滑到封面位置后再播放
                                circlesRow.shiftTarget = realIndex
                                circleShift.x = 0
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
