import QtQuick

// 频谱律动组件：模拟 12 条柱子跳动的动画效果（不依赖真实音频频谱）。
// 每根柱用多组非公度频率的正弦叠加 + 全局呼吸包络，产生不规则、不重复的律动；
// 高度平滑采用"上升快、回落慢"，模拟真实频谱的攻击/衰减特性。
Row {
    id: root
    height: root.maxBarHeight
    spacing: root.barSpacing

    // 柱子数量（固定 12 条）
    readonly property int barCount: 12
    property int barWidth: 2
    property int barSpacing: 2
    property color barColor: "#ccffffff"
    // 最高柱子的高度（也决定组件整体高度）
    property real maxBarHeight: 36
    // 波谷时的静默高度（避免完全消失）
    property int minBarHeight: 4
    // 是否播放律动动画（页面可见且正在播放时运行）
    property bool running: true

    // 相位：持续递增（不取模），配合非公度频率保证波形不会周期重复
    property real phase: 0

    Timer {
        interval: 33
        repeat: true
        running: root.running && root.visible
        onTriggered: root.phase += 0.15
    }

    Repeater {
        model: root.barCount

        delegate: Rectangle {
            width: root.barWidth
            radius: root.barWidth / 2
            color: root.barColor
            anchors.verticalCenter: parent.verticalCenter

            // 目标值：全局呼吸包络 × 多组非公度频率正弦叠加（每根柱独立相位）
            property real target: {
                var t = root.phase
                var env = 0.5 + 0.5 * Math.sin(t * 0.37 + 2.0)     // 慢速整体呼吸
                var v = 0.30
                v += 0.28 * Math.sin(t * 1.7 + index * 1.3)
                v += 0.20 * Math.sin(t * 2.9 + index * 2.1 + 0.7)
                v += 0.14 * Math.sin(t * 4.3 + index * 3.7 + 1.3)
                v *= 0.4 + 0.6 * env
                return Math.max(0, Math.min(1, v))
            }
            // 平滑：上升直达目标，回落按比例衰减（模拟真实频谱攻击快、衰减慢）
            property real level: 0
            onTargetChanged: {
                if (target > level) level = target
                else level = target + (level - target) * 0.82
            }
            height: root.running ? Math.max(root.minBarHeight, level * root.maxBarHeight) : root.minBarHeight
        }
    }
}
