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

    // ---- 软件更新 ----
    ColumnLayout {
        anchors.fill: parent; spacing: 0
        visible: settingsSubMenu === "update"

        Label {
            text: "软件更新"
            font.family: fontFamily; font.pixelSize: 18; font.bold: true
            color: "#f4f4f4"
        }
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
        anchors.fill: parent; spacing: 0
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
