import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    // ---- 公开属性 ----
    property string iconSource: ""
    property string iconColor: ""
    property string label: ""
    property int iconSrcSize: 20
    property bool active: false
    property string fontFamily: ""

    signal clicked()

    Layout.fillWidth: true
    Layout.preferredHeight: 36
    radius: 6
    color: active ? "#2C2C2C" : (navMouse.containsMouse ? "#222222" : "transparent")

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 12
        spacing: 10

        Rectangle {
            // 图标容器统一 28×28，图标左对齐，保证文字起点固定
            width: 28; height: 28; radius: 4; color: "transparent"

            Image {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                source: iconSource
                sourceSize.width: iconSrcSize
                sourceSize.height: iconSrcSize
                fillMode: Image.PreserveAspectFit
                visible: iconSource !== ""
            }

            Rectangle {
                anchors.centerIn: parent
                width: 12; height: 12; radius: 6
                color: iconColor
                visible: iconSource === "" && iconColor !== ""
            }
        }

        Label {
            text: label
            font.family: fontFamily
            font.pixelSize: 15
            color: active ? "#cccccc" : (navMouse.containsMouse ? "#cccccc" : "#888")
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: navMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: parent.clicked()
    }
}
