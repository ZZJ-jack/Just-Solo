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
            color: "#dddddd"
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
                    Label { text: "软件版本"; font.family: fontFamily; font.pixelSize: 14; color: "#888"; Layout.preferredWidth: 72 }
                    Item { Layout.fillWidth: true }
                    Label { text: APP_VERSION; font.family: fontFamily; font.pixelSize: 14; font.bold: true; color: "#cccccc" }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "构建版本"; font.family: fontFamily; font.pixelSize: 13; color: "#666"; Layout.preferredWidth: 72 }
                    Item { Layout.fillWidth: true }
                    Label { text: BUILD_VERSION; font.family: fontFamily; font.pixelSize: 13; color: "#888" }
                }
            }
        }
        Item { Layout.preferredHeight: 16 }
        Rectangle {
            Layout.preferredWidth: 160; Layout.preferredHeight: 40
            radius: 8; color: "#2a2a3a"; opacity: 0.5
            Label { anchors.centerIn: parent; text: "检查更新"; font.family: fontFamily; font.pixelSize: 14; color: "#666" }
        }
        Label { text: "请前往以下地址查看更新："; font.family: fontFamily; font.pixelSize: 13; color: "#888"; Layout.topMargin: 8 }
        Label { text: `<a href="https://gitcode.com/ZZJ-JACK/Just-Solo">https://gitcode.com/ZZJ-JACK/Just-Solo</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#00d4ff"; Layout.topMargin: 4; onLinkActivated: Qt.openUrlExternally(link) }
        Label { text: `<a href="https://github.com/ZZJ-jack/Just-Solo">https://github.com/ZZJ-jack/Just-Solo</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#00d4ff"; Layout.topMargin: 2; onLinkActivated: Qt.openUrlExternally(link) }
        Item { Layout.fillHeight: true }
    }

    // ---- 外观 ----
    ColumnLayout {
        anchors.fill: parent; spacing: 0
        visible: settingsSubMenu === "appearance"
        Label { text: "外观"; font.family: fontFamily; font.pixelSize: 18; font.bold: true; color: "#dddddd" }
        Item { Layout.preferredHeight: 16 }
        Label { text: "外观设置（开发中）"; font.family: fontFamily; font.pixelSize: 14; color: "#666" }
        Item { Layout.fillHeight: true }
    }

    // ---- 关于 ----
    ColumnLayout {
        anchors.fill: parent; spacing: 0
        visible: settingsSubMenu === "about"
        Label { text: "关于"; font.family: fontFamily; font.pixelSize: 18; font.bold: true; color: "#dddddd" }
        Item { Layout.preferredHeight: 16 }
        Label { text: "Just Solo - 轻量级桌面音乐播放器"; font.family: fontFamily; font.pixelSize: 14; color: "#888" }
        Item { Layout.preferredHeight: 4 }
        Label { text: "作者: ZZJ-JACK"; font.family: fontFamily; font.pixelSize: 13; color: "#666" }
        Label { text: `<a href="https://zzjjack.us.kg">https://zzjjack.us.kg</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#00d4ff"; Layout.topMargin: 4; onLinkActivated: Qt.openUrlExternally(link) }
        Item { Layout.preferredHeight: 8 }
        Label { text: "基于 Qt 6.8.3 + QML 构建"; font.family: fontFamily; font.pixelSize: 13; color: "#666" }
        Item { Layout.preferredHeight: 8 }
        Label { text: "构建版本: " + BUILD_VERSION; font.family: fontFamily; font.pixelSize: 13; color: "#666" }
        Item { Layout.preferredHeight: 12 }
        Label { text: "项目地址"; font.family: fontFamily; font.pixelSize: 13; color: "#888" }
        Label { text: `<a href="https://gitcode.com/ZZJ-JACK/Just-Solo">https://gitcode.com/ZZJ-JACK/Just-Solo</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#00d4ff"; Layout.topMargin: 4; onLinkActivated: Qt.openUrlExternally(link) }
        Label { text: `<a href="https://github.com/ZZJ-jack/Just-Solo">https://github.com/ZZJ-jack/Just-Solo</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#00d4ff"; Layout.topMargin: 2; onLinkActivated: Qt.openUrlExternally(link) }
        Item { Layout.preferredHeight: 12 }
        Label { text: "图标来源: 鸿蒙开发者"; font.family: fontFamily; font.pixelSize: 13; color: "#888" }
        Label { text: `<a href="https://developer.huawei.com/consumer/cn/">https://developer.huawei.com/consumer/cn</a>`; textFormat: Text.RichText; font.family: fontFamily; font.pixelSize: 13; color: "#00d4ff"; Layout.topMargin: 4; onLinkActivated: Qt.openUrlExternally(link) }
        Item { Layout.fillHeight: true }
    }
}
