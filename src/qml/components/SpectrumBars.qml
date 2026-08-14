import QtQuick

// 频谱律动组件：显示真实音频频谱（musicManager.spectrum，12 个频段电平 0~1）。
// 数据来自 AudioEngine 对实际输出帧做 FFT 得到的对数频段能量。
// 高度平滑采用"上升快、回落慢"，模拟真实频谱的攻击/衰减特性。
Row {
    id: root
    height: root.maxBarHeight
    spacing: root.barSpacing

    // 柱子数量（固定 12 条，与 C++ 频谱频段数一致）
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

    // 真实频谱数据（随 spectrumChanged 更新）
    property var levels: (typeof musicManager !== "undefined" && musicManager)
                         ? musicManager.spectrum : []

    Repeater {
        model: root.barCount

        delegate: Rectangle {
            width: root.barWidth
            radius: root.barWidth / 2
            color: root.barColor
            anchors.verticalCenter: parent.verticalCenter

            // 目标值：对应频段的真实电平（0~1），未播放/数据缺失时为 0
            property real target: {
                var s = root.levels
                if (!root.running || !s || index >= s.length) return 0
                var v = s[index]
                if (typeof v !== "number" || !isFinite(v)) return 0
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
