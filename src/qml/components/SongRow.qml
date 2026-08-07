import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// SongRow — 共享歌曲行组件
// model / index 由 ListView delegate 自动注入
// ============================================================
Rectangle {
    id: songRow
    width: parent ? parent.width : 200
    // 动态高度：拖拽时若作为放置目标，上方展开 58px 占位（50 灰卡 + 8 间距）
    implicitHeight: 50 + dropGap
    height: implicitHeight
    clip: false                      // 允许灰卡超出边界（初始展开时）

    property real dropGap: showDropAbove ? 58 : 0
    Behavior on dropGap { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    property real placeholderH: showDropAbove ? 50 : 0
    Behavior on placeholderH { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    property real placeholderOpacity: showDropAbove ? 0.9 : 0
    Behavior on placeholderOpacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    radius: 8
    color: isDragged ? "#444444"
         : (isCurrent ? "#2C2C2C"
         : (rowMouse.containsMouse ? "#222222" : "#181818"))
    Behavior on color { ColorAnimation { duration: 150 } }

    // ---- 放置占位灰卡（拖拽时，目标行上方） ----
    Rectangle {
        id: gapPlaceholder
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: placeholderH
        opacity: placeholderOpacity
        color: "#3A3A3A"
        radius: 8
        border.color: "#555555"
        border.width: 1.5
        clip: true

        Label {
            anchors.centerIn: parent
            text: "放置到此处"
            font.family: songRow.fontFamily
            font.pixelSize: 15
            color: "#777"
            visible: parent.height > 20
        }
    }

    // ListView delegate 自动注入
    required property var    model
    required property int    index

    // 外部显式传入
    required property bool   isCurrent
    required property string fontFamily
    required property real   colCover
    required property real   colTitle
    required property real   colAlbum
    required property real   colDuration
    required property real   colIndex
    required property real   colFav
    required property real   colMenu
    required property bool   isDragged
    required property bool   showDropAbove
    required property bool   contextMenuOpen

    // 拖拽信号：通知 MusicListView 开始/移动/结束拖拽
    // 传递全局坐标避免委托位移/回收导致的坐标系偏移
    // localY 是鼠标在 SongRow 内的纵向偏移（用于计算 dragOffsetY）
    signal dragStarted(real globalX, real globalY, real localY)
    signal dragMoved(real globalX, real globalY)
    signal dragEnded()

    signal leftClicked()
    signal rightClicked()

    // ---- 长按拖拽排序（先声明，让 content 在上面接收点击） ----
    MouseArea {
        id: rowMouse
        anchors.fill: parent; hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        property bool _dragTriggered: false
        property bool _isDragging: false
        property real _pressY: 0

        Timer {
            id: longPressTimer
            interval: 400
            onTriggered: {
                rowMouse._dragTriggered = true
                rowMouse._isDragging = true
                rowMouse.preventStealing = true
                var globalPt = rowMouse.mapToGlobal(rowMouse.mouseX, rowMouse.mouseY)
                songRow.dragStarted(globalPt.x, globalPt.y, rowMouse.mouseY)
            }
        }

        onPressed: function(mouse) {
            if (mouse.button === Qt.RightButton) {
                songRow.rightClicked()
            } else {
                _pressY = mouse.y
                _dragTriggered = false
                _isDragging = false
                longPressTimer.restart()
            }
        }

        onPositionChanged: function(mouse) {
            if (_isDragging) {
                var globalPt = rowMouse.mapToGlobal(mouse.x, mouse.y)
                songRow.dragMoved(globalPt.x, globalPt.y)
            } else if (!_dragTriggered && Math.abs(mouse.y - _pressY) > 10) {
                longPressTimer.stop()
            }
        }

        onReleased: function(mouse) {
            longPressTimer.stop()
            if (_isDragging) {
                rowMouse.preventStealing = false
                songRow.dragEnded()
                _isDragging = false
                Qt.callLater(function() { _dragTriggered = false })
            }
        }

        onCanceled: {
            longPressTimer.stop()
            if (_isDragging) {
                rowMouse.preventStealing = false
                songRow.dragEnded()
            }
            _isDragging = false
            _dragTriggered = false
        }

        onDoubleClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton && !_dragTriggered) {
                longPressTimer.stop()
                _dragTriggered = false
                songRow.leftClicked()
            }
        }
    }

    // 歌曲行内容区域（灰卡下方，在 rowMouse 之上接收点击）
    RowLayout {
        id: rowContent
        anchors { top: gapPlaceholder.bottom; topMargin: showDropAbove ? 13 : 5; left: parent.left; leftMargin: 8; right: parent.right; rightMargin: 12; bottom: parent.bottom; bottomMargin: 5 }
        spacing: 0

        // ---- 序号 ----
        Label {
            Layout.preferredWidth: songRow.colIndex
            Layout.alignment: Qt.AlignVCenter
            text: ("0" + (songRow.index + 1)).slice(-2)
            font.family: songRow.fontFamily; font.pixelSize: 13; color: "#777777"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        // ---- 封面 ----
        Rectangle {
            Layout.preferredWidth: Math.min(songRow.colCover, 40)
            Layout.preferredHeight: 40
            Layout.maximumWidth: 40
            Layout.alignment: Qt.AlignVCenter
            radius: 6; color: "#3A3A3A"
            Image {
                anchors.fill: parent; anchors.margins: 2
                sourceSize.width: 40; sourceSize.height: 40
                source: model.cover || ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Label {
                anchors.centerIn: parent
                text: "\u266B"; font.family: songRow.fontFamily; font.pixelSize: 18; color: "#666"
                visible: !model.cover || model.cover === ""
            }
        }

        // ---- 标题 + 歌手 + 音质 ----
        Item {
            id: titleArtistItem
            Layout.fillWidth: true
            Layout.preferredWidth: songRow.colTitle
            Layout.preferredHeight: 40
            Layout.alignment: Qt.AlignVCenter
            Layout.leftMargin: 8
            clip: true

            Label {
                id: titleLabel
                text: model.name || ""
                font.family: songRow.fontFamily; font.pixelSize: 15
                font.bold: true; color: "#FFFFFF"
                elide: Text.ElideRight
                width: parent.width
                anchors.top: parent.top; anchors.left: parent.left
            }

            Row {
                id: bottomRow
                anchors.bottom: parent.bottom; anchors.left: parent.left
                spacing: 3

                Label {
                    id: artistBelowLabel
                    text: model.artist || "未知"
                    font.family: songRow.fontFamily; font.pixelSize: 13; color: "#777777"
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth,
                        titleArtistItem.width - (qualityBadge.visible ? qualityBadge.width + bottomRow.spacing + 2 : 0) - 2)
                    visible: (model.artist || "") !== ""
                }

                Rectangle {
                    id: qualityBadge
                    width: qualityText.contentWidth + 8
                    height: 18
                    radius: 3
                    color: "#CDB800"
                    visible: (model.quality || "") !== ""
                    opacity: 0.8
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    Label {
                        id: qualityText
                        text: model.quality || ""
                        font.family: songRow.fontFamily; font.pixelSize: 10; font.bold: true
                        color: "#FFFFFF"
                        anchors.centerIn: parent
                    }
                }
            }
        }

        // ---- 专辑 ----
        Label {
            text: model.album || ""
            font.family: songRow.fontFamily; font.pixelSize: 15; color: "#777777"
            elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
            Layout.fillWidth: true; Layout.fillHeight: true; Layout.preferredWidth: songRow.colAlbum
            Layout.leftMargin: 8
        }

        // ---- 时长（悬浮时显示播放按钮） ----
        Item {
            Layout.preferredWidth: songRow.colDuration
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter

            Label {
                text: model.durationText || ""
                font.family: songRow.fontFamily; font.pixelSize: 15; color: "#777777"
                verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight
                width: parent.width; height: parent.height
                visible: !rowMouse.containsMouse || contextMenuOpen
            }

            Image {
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                source: (songRow.isCurrent && musicManager.isPlaying)
                    ? "qrc:/qt/qml/JustSolo/data/image/playing.png"
                    : "qrc:/qt/qml/JustSolo/data/image/play.png"
                width: 25; height: 25; opacity: 0.7
                visible: rowMouse.containsMouse && !contextMenuOpen

                MouseArea {
                    id: playMA
                    anchors.fill: parent
                    anchors.margins: -8
                    cursorShape: Qt.PointingHandCursor
                    onClicked: songRow.leftClicked()
                }
            }
        }

        // ---- 收藏按钮（悬浮时显示） ----
        Item {
            Layout.preferredWidth: songRow.colFav
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter

            Image {
                anchors.centerIn: parent
                source: {
                    musicManager.favorites;
                    musicManager.isFavorite(model)
                        ? "qrc:/qt/qml/JustSolo/data/image/mylike-on.png"
                        : "qrc:/qt/qml/JustSolo/data/image/mylike-off.png"
                }
                width: 25; height: 25; opacity: 0.7
                visible: rowMouse.containsMouse && !contextMenuOpen

                MouseArea {
                    id: favMA
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: musicManager.toggleFavorite(model)
                }
            }
        }

        // ---- 菜单按钮（永久显示） ----
        Item {
            Layout.preferredWidth: songRow.colMenu
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignVCenter

            Image {
                anchors.centerIn: parent
                source: "qrc:/qt/qml/JustSolo/data/image/menu.png"
                width: 20; height: 20
                opacity: 0.6

                MouseArea {
                    id: menuMA
                    anchors.fill: parent
                    anchors.margins: -4
                    cursorShape: Qt.PointingHandCursor
                    onClicked: songRow.rightClicked()
                }
            }
        }
    }
}
