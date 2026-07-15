import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    // ---- 公开属性 ----
    property string iconSource: ""
    property string iconColor: ""
    property string label: ""
    property int iconW: 34
    property int iconH: 34
    property int iconSrcSize: 26
    property bool active: false
    property string fontFamily: ""

    signal clicked()

    Layout.fillWidth: true
    Layout.preferredHeight: 50
    radius: 6
    color: active ? "#36365a" : (navMouse.containsMouse ? "#2a2a48" : "transparent")

    Row {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 12
        spacing: 10

        Rectangle {
            width: iconW; height: iconH; radius: 4; color: "transparent"

            Image {
                anchors.centerIn: parent
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
            font.pixelSize: 17
            color: active ? "#cccccc" : "#888"
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
