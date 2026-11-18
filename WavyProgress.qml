import QtQuick

Item {
    id: root
    required property real startX
    required property real endX
    required property real positionX
    property real amplitude: 3.5
    property real wavelength: 30
    property real thickness: 3
    property bool playing: true
    property real waveAmount: playing ? 1 : 0
    Behavior on waveAmount { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }
    property real phase: 0
    property color ink: "white"
    property color accent: "#9ce9c2"

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
            if (root.endX <= root.startX || height < 8) return
            const mid = height / 2
            const start = root.startX
            const end = root.positionX
            ctx.lineCap = "round"
            ctx.lineWidth = root.thickness
            ctx.strokeStyle = Qt.alpha(root.ink, 0.16)
            ctx.beginPath()
            ctx.moveTo(Math.min(root.endX, end + 9), mid)
            ctx.lineTo(root.endX, mid)
            ctx.stroke()

            ctx.strokeStyle = root.accent
            ctx.beginPath()
            ctx.moveTo(start, mid)
            const waveHeight = root.amplitude * root.waveAmount
            if (waveHeight > 0.001) {
                const wavelength = Math.max(1, root.wavelength)
                const angle = 2 * Math.PI / wavelength
                const step = Math.min(2, wavelength / 10)
                for (let x = start + step; x < end; x += step) {
                    const envelope = Math.min(1, (x - start) / 12, (end - x) / 12)
                    ctx.lineTo(x, mid + Math.sin(x * angle - root.phase * Math.PI * 2) * waveHeight * envelope)
                }
            }
            ctx.lineTo(end, mid)
            ctx.stroke()

            ctx.fillStyle = root.accent
            ctx.beginPath()
            ctx.arc(end, mid, 3, 0, 2 * Math.PI)
            ctx.fill()
            ctx.fillStyle = root.ink
            ctx.beginPath()
            ctx.arc(root.endX, mid, 1.8, 0, 2 * Math.PI)
            ctx.fill()
        }
    }
    onStartXChanged: canvas.requestPaint()
    onEndXChanged: canvas.requestPaint()
    onPositionXChanged: canvas.requestPaint()
    onAmplitudeChanged: canvas.requestPaint()
    onWavelengthChanged: canvas.requestPaint()
    onThicknessChanged: canvas.requestPaint()
    onWaveAmountChanged: canvas.requestPaint()
    onPhaseChanged: if (waveAmount > 0.001) canvas.requestPaint()
    onInkChanged: canvas.requestPaint()
    onAccentChanged: canvas.requestPaint()
}
