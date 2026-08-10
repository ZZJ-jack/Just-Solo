import QtQuick
import QtQuick.Controls

// 自定义小号圆球滑动开关（左右滑动动画 + 变色过渡）
Item {
    id: root
    implicitWidth: 36
    implicitHeight: 20

    property bool checked: false
    signal toggled()

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? "#3B82F6" : "#555"
        border.color: root.checked ? "#3B82F6" : "#444"
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Rectangle {
        width: 16; height: 16; radius: 8
        color: "#fff"
        y: (parent.height - height) / 2
        x: root.checked ? parent.width - width - 2 : 2
        Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root.checked = !root.checked
            root.toggled()
        }
    }
}
