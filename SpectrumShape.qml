import QtQuick

Item {
    id: root
    required property var bands
    required property var palette
    required property color secondary
    property int channel: 0
    property bool mirrored: false
    property bool playing: false
    property bool drawBaseline: true
    property bool allowShader: true
    property string style: "wave"
    property real sensitivity: 1
    property real glowStrength: 0
    property real clock: 0
    property int fadeDuration: 280

    readonly property bool useRibbon: allowShader && style !== "bars"
        && GraphicsInfo.api !== GraphicsInfo.Software && GraphicsInfo.api !== GraphicsInfo.Null
        && ribbon.status !== ShaderEffect.Error
    readonly property var inputBands: visible && playing ? bands : []
    property var heldBands: []
    property real level: 0
    readonly property var amplitudes: {
        if (!visible || heldBands.length === 0 || level <= 0) return []
        const gain = Math.max(0.1, Math.min(5, sensitivity))
        const values = []
        for (let i = 0; i < 32; ++i) {
            const raw = channel < 0
                ? Math.max(heldBands[31 - i] || 0, heldBands[32 + i] || 0)
                : heldBands[channel * 32 + i] || 0
            values.push(Math.min(1, raw / 1000 * gain) * level)
        }
        return values
    }
    readonly property real peak: Math.max(0, ...amplitudes)

    function sync() {
        if (!visible) {
            fade.stop()
            level = 0
            heldBands = []
        } else if (inputBands.length > 0) {
            fade.stop()
            heldBands = inputBands
            level = 1
        } else if (level > 0 && !fade.running) {
            fade.from = level
            fade.start()
        }
    }
    onInputBandsChanged: sync()
    onVisibleChanged: sync()
    Component.onCompleted: sync()
    NumberAnimation {
        id: fade
        target: root
        property: "level"
        to: 0
        duration: root.fadeDuration
        easing.type: Easing.OutCubic
        onFinished: root.heldBands = []
    }

    SpectrumRibbon {
        id: ribbon
        anchors.fill: parent
        visible: root.useRibbon && root.peak > 0.002
        // Lift quiet bands while keeping an actual zero dark.
        amplitudes: visible ? Array.from({length: 16}, (_, i) =>
            Math.pow(Math.max(root.amplitudes[i * 2], root.amplitudes[i * 2 + 1]), 0.62)) : []
        palette: root.palette
        secondary: root.secondary
        clock: visible ? root.clock : 0
        mirrored: root.mirrored
        glowStrength: root.glowStrength
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: root.drawBaseline ? 1 : 0
        visible: !root.useRibbon && (root.drawBaseline || root.peak > 0.002)
        renderStrategy: Canvas.Threaded
        transform: Scale {
            origin.x: canvas.width / 2
            xScale: root.mirrored ? -1 : 1
        }
        function redraw() { if (visible && available) requestPaint() }
        onAvailableChanged: redraw()
        onVisibleChanged: redraw()
        onWidthChanged: redraw()
        onHeightChanged: redraw()
        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (width < 2 || height < 2) return
            const mid = height / 2
            if (root.drawBaseline) {
                ctx.lineWidth = 1
                ctx.strokeStyle = Qt.alpha(root.palette.ink, 0.35)
                ctx.beginPath()
                ctx.moveTo(0, mid)
                ctx.lineTo(width, mid)
                ctx.stroke()
            }
            const a = root.amplitudes
            if (root.peak <= 0.002 || a.length < 2) return
            const gradient = ctx.createLinearGradient(0, 0, width, 0)
            gradient.addColorStop(0, root.palette.accent)
            gradient.addColorStop(1, root.palette.ink)
            ctx.fillStyle = gradient
            if (root.style === "bars") {
                const count = Math.min(a.length, Math.max(1, Math.floor(width / 3)))
                const step = width / count
                for (let i = 0; i < count; ++i) {
                    let value = 0
                    for (let j = Math.floor(i * a.length / count); j < Math.floor((i + 1) * a.length / count); ++j)
                        value = Math.max(value, a[j])
                    const h = Math.max(1, value * (height - 2))
                    ctx.fillRect(i * step, mid - h / 2, Math.min(step, Math.max(1, step - 2)), h)
                }
                return
            }
            const step = width / (a.length - 1)
            const spread = i => Math.max(0.4, a[i] * (mid - 1) * (Math.sin(Math.PI * i / (a.length - 1)) * 0.85 + 0.15))
            ctx.beginPath()
            ctx.moveTo(0, mid)
            for (let i = 0; i < a.length; ++i) {
                const x = i * step
                const prev = i === 0 ? mid : mid - spread(i - 1)
                ctx.bezierCurveTo(x - step * 0.5, prev, x - step * 0.5, mid - spread(i), x, mid - spread(i))
            }
            for (let i = a.length - 1; i >= 0; --i)
                ctx.lineTo(i * step, mid + spread(i))
            ctx.closePath()
            ctx.fill()
        }
    }
    onAmplitudesChanged: canvas.redraw()
    onStyleChanged: canvas.redraw()
    onPaletteChanged: canvas.redraw()
}
