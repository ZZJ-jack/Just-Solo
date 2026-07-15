import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    // ---- 公开属性 ----
    property string label: ""
    property bool active: false
    property string fontFamily: ""

    signal clicked()

    Layout.fillWidth: true
    Layout.preferredHeight: 40
    radius: 6
    color: active ? "#36365a" : (subNavMouse.containsMouse ? "#2a2a48" : "transparent")

    Label {
        text: label
        font.family: fontFamily
        font.pixelSize: 14
        color: active ? "#cccccc" : "#888"
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 20
    }

    MouseArea {
        id: subNavMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: parent.clicked()
    }
}
