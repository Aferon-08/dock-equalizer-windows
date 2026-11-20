import QtQuick

Item {
    id: root
    property real amplitude: 3.5
    property real wavelength: 30
    property real thickness: 3
    onAmplitudeChanged: canvas.requestPaint()
    onWavelengthChanged: canvas.requestPaint()
    onThicknessChanged: canvas.requestPaint()
    property real fraction: 0
    property bool indeterminate: false
    property bool playing: true
    property bool circular: false
    property real waveAmount: playing ? 1 : 0
    Behavior on waveAmount { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }
    property real phase: 0
    property bool seekable: false
    property color ink: "white"
    property color accent: "#9ce9c2"
    signal seek(real fraction)

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Threaded
        onAvailableChanged: if (available) requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width < 8 || height < 8) return
            if (root.circular) {
                paintCircle(ctx)
                return
            }
            const mid = height / 2
            const end = Math.max(3, Math.min(width - 5, (root.indeterminate ? 0.45 + 0.35 * Math.sin(root.phase * 2) : root.fraction) * (width - 8) + 4))
            ctx.lineCap = "round"
            ctx.lineWidth = root.thickness
            ctx.strokeStyle = Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.16)
            ctx.beginPath(); ctx.moveTo(Math.min(width - 4, end + 9), mid); ctx.lineTo(width - 4, mid); ctx.stroke()
            ctx.strokeStyle = root.accent
            ctx.beginPath()
            for (let x = 4; x <= end; x += 1) {
                const y = mid + waveOffset(x, x - 4, end - x)
                if (x === 4) ctx.moveTo(x, y); else ctx.lineTo(x, y)
            }
            ctx.stroke()
            ctx.fillStyle = root.accent
            ctx.beginPath(); ctx.arc(end, mid, 3, 0, 2 * Math.PI); ctx.fill()
            ctx.fillStyle = root.ink
            ctx.beginPath(); ctx.arc(width - 4, mid, 1.8, 0, 2 * Math.PI); ctx.fill()
        }

        function waveOffset(distance, fromStart, toEnd) {
            const envelope = Math.max(0, Math.min(1, fromStart / 12, toEnd / 12))
            return Math.sin(2 * Math.PI * (distance / root.wavelength - root.phase))
                * root.amplitude * root.waveAmount * envelope
        }

        function paintCircle(ctx) {
            const cx = width / 2
            const cy = height / 2
            const radius = Math.min(width, height) / 2 - 4
            const start = -Math.PI / 2
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.lineWidth = 1
            ctx.strokeStyle = Qt.alpha(root.ink, 0.23)
            ctx.beginPath()
            ctx.arc(cx, cy, radius, start, start + 2 * Math.PI, false)
            ctx.stroke()

            const fraction = Math.max(0, Math.min(1, root.fraction))
            if (!isFinite(fraction) || fraction === 0)
                return
            const distance = fraction * 2 * Math.PI * radius
            const steps = Math.max(1, Math.ceil(distance))
            ctx.strokeStyle = root.accent
            ctx.lineWidth = root.thickness
            ctx.beginPath()
            for (let i = 0; i <= steps; ++i) {
                const arc = i * distance / steps
                const angle = start + arc / radius
                const r = radius + waveOffset(arc, arc, distance - arc)
                const x = cx + Math.cos(angle) * r
                const y = cy + Math.sin(angle) * r
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
            }
            ctx.stroke()
            const end = start + distance / radius
            ctx.fillStyle = root.accent
            ctx.beginPath()
            ctx.arc(cx + Math.cos(end) * radius, cy + Math.sin(end) * radius, root.thickness * 0.66,
                0, 2 * Math.PI, false)
            ctx.fill()
        }
    }
    onWaveAmountChanged: canvas.requestPaint()
    onCircularChanged: canvas.requestPaint()
    onIndeterminateChanged: canvas.requestPaint()
    onFractionChanged: canvas.requestPaint()
    onPhaseChanged: canvas.requestPaint()
    onInkChanged: canvas.requestPaint()
    onAccentChanged: canvas.requestPaint()
    MouseArea {
        anchors.fill: parent
        enabled: root.seekable
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => root.seek(Math.max(0, Math.min(1, mouse.x / width)))
    }
}
