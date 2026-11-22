pragma ComponentBehavior: Bound
import QtQuick

Rectangle {
    id: editor
    required property var curve
    required property color accent
    required property color mutedInk
    required property color lineColor
    signal edited(var points)

    implicitHeight: 152
    radius: 10
    color: "#101f1b"
    border.color: lineColor

    readonly property var points: curve.length === 4 ? curve : [0.25, 0.25, 0.75, 0.75]
    readonly property real plotX: 34
    readonly property real plotY: 16
    readonly property real plotWidth: Math.max(1, width - plotX - 16)
    readonly property real plotHeight: height - plotY - 23
    readonly property color secondColor: "#c6baff"
    onPointsChanged: graph.requestPaint()

    function point(x, y) {
        return Qt.point(plotX + x * plotWidth, plotY + (1 - y) * plotHeight)
    }

    function movePoint(index, x, y) {
        const values = Array.from(points)
        values[index * 2] = Math.round(Math.max(0, Math.min(1, x)) * 100) / 100
        values[index * 2 + 1] = Math.round(Math.max(0, Math.min(1, y)) * 100) / 100
        edited(values)
    }

    Canvas {
        id: graph
        anchors.fill: parent
        onAvailableChanged: if (available) requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            const start = editor.point(0, 0)
            const end = editor.point(1, 1)
            const first = editor.point(editor.points[0], editor.points[1])
            const second = editor.point(editor.points[2], editor.points[3])

            ctx.lineWidth = 1
            ctx.strokeStyle = editor.lineColor
            ctx.beginPath()
            for (let i = 0; i <= 4; ++i) {
                const vertical = editor.point(i / 4, 0)
                const horizontal = editor.point(0, i / 4)
                ctx.moveTo(vertical.x, start.y)
                ctx.lineTo(vertical.x, end.y)
                ctx.moveTo(start.x, horizontal.y)
                ctx.lineTo(end.x, horizontal.y)
            }
            ctx.stroke()

            ctx.globalAlpha = 0.55
            ctx.strokeStyle = editor.accent
            ctx.beginPath()
            ctx.moveTo(start.x, start.y)
            ctx.lineTo(first.x, first.y)
            ctx.stroke()
            ctx.strokeStyle = editor.secondColor
            ctx.beginPath()
            ctx.moveTo(end.x, end.y)
            ctx.lineTo(second.x, second.y)
            ctx.stroke()

            ctx.globalAlpha = 1
            ctx.strokeStyle = editor.accent
            ctx.lineWidth = 2.5
            ctx.beginPath()
            ctx.moveTo(start.x, start.y)
            ctx.bezierCurveTo(first.x, first.y, second.x, second.y, end.x, end.y)
            ctx.stroke()
        }
    }

    Text {
        x: 7
        y: editor.plotY - 6
        text: "Ход"
        color: editor.mutedInk
        font.pixelSize: 10
    }
    Text {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 7
        text: "Время"
        color: editor.mutedInk
        font.pixelSize: 10
    }
    Repeater {
        model: 2
        delegate: Rectangle {
            id: handle
            required property int index
            readonly property real u: editor.points[index * 2]
            readonly property real v: editor.points[index * 2 + 1]
            readonly property point center: editor.point(u, v)
            width: 15
            height: width
            radius: width / 2
            x: center.x - width / 2
            y: center.y - height / 2
            color: index === 0 ? editor.accent : editor.secondColor
            border.color: activeFocus ? "white" : editor.color
            border.width: 2
            z: activeFocus ? 1 : 0
            activeFocusOnTab: true
            Accessible.role: Accessible.Slider
            Accessible.name: index === 0 ? "Первая точка кривой" : "Вторая точка кривой"
            Accessible.description: "Время " + Math.round(u * 100) + " %, ход " + Math.round(v * 100) + " %"
            Keys.onPressed: event => {
                const step = event.modifiers & Qt.ShiftModifier ? 0.1 : 0.02
                switch (event.key) {
                case Qt.Key_Left: editor.movePoint(index, u - step, v); break
                case Qt.Key_Right: editor.movePoint(index, u + step, v); break
                case Qt.Key_Up: editor.movePoint(index, u, v + step); break
                case Qt.Key_Down: editor.movePoint(index, u, v - step); break
                default: return
                }
                event.accepted = true
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                preventStealing: true
                property point grabOffset
                onPressed: mouse => {
                    handle.forceActiveFocus(Qt.MouseFocusReason)
                    grabOffset = Qt.point(mouse.x - width / 2, mouse.y - height / 2)
                }
                onPositionChanged: mouse => {
                    if (!pressed)
                        return
                    const pos = mapToItem(editor, mouse.x - grabOffset.x, mouse.y - grabOffset.y)
                    editor.movePoint(handle.index, (pos.x - editor.plotX) / editor.plotWidth,
                        1 - (pos.y - editor.plotY) / editor.plotHeight)
                }
            }
        }
    }
}
