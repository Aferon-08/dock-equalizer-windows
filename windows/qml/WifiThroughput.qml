import QtQuick

Item {
    id: chart
    required property var samples
    required property color accent

    readonly property color upload: "#d2b7fc"
    readonly property var latest: samples.length ? samples[samples.length - 1] : null
    readonly property real ceiling: {
        let peak = 1
        for (const sample of samples)
            peak = Math.max(peak, sample.down, sample.up)
        const magnitude = Math.pow(10, Math.floor(Math.log10(peak)))
        return Math.ceil(peak / magnitude) * magnitude
    }

    function rate(value) {
        return Number(value).toLocaleString(Qt.locale(), "f", value < 10 ? 1 : 0)
    }

    Row {
        id: rates
        spacing: 10
        Text {
            text: chart.latest ? "↓ " + chart.rate(chart.latest.down) : "Измеряем трафик…"
            color: chart.accent
            font.pixelSize: 12
        }
        Text {
            visible: !!chart.latest
            text: chart.latest ? "↑ " + chart.rate(chart.latest.up) : ""
            color: chart.upload
            font.pixelSize: 12
        }
        Text {
            visible: !!chart.latest
            text: "Мбит/с"
            color: "#c3d8cf"
            font.pixelSize: 11
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Rectangle {
        anchors.top: rates.bottom
        anchors.topMargin: 5
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        radius: 9
        color: "#18101820"
        border.color: Qt.alpha(chart.accent, 0.18)

        Canvas {
            id: plot
            anchors.fill: parent
            anchors.margins: 5
            Connections {
                target: chart
                function onSamplesChanged() { plot.requestPaint() }
                function onAccentChanged() { plot.requestPaint() }
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (width < 4 || height < 4)
                    return
                ctx.strokeStyle = Qt.alpha(chart.accent, 0.18)
                ctx.lineWidth = 1
                ctx.beginPath()
                for (const fraction of [0.25, 0.5, 0.75]) {
                    ctx.moveTo(0, height * fraction)
                    ctx.lineTo(width, height * fraction)
                }
                ctx.stroke()
                drawCurve(ctx, "down", chart.accent, true)
                drawCurve(ctx, "up", chart.upload, false)
            }

            function drawCurve(ctx, key, color, fill) {
                const points = chart.samples
                if (!points.length)
                    return
                ctx.beginPath()
                for (let i = 0; i < points.length; ++i) {
                    const x = 1.5 + (width - 3) * (1 - (points.length - 1 - i) / 19)
                    const y = height - 2 - (height - 4) * points[i][key] / chart.ceiling
                    if (i === 0)
                        ctx.moveTo(x, y)
                    else
                        ctx.lineTo(x, y)
                }
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.lineWidth = 1.7
                ctx.strokeStyle = color
                ctx.stroke()
                if (fill && points.length > 1) {
                    const gradient = ctx.createLinearGradient(0, 1, 0, height)
                    gradient.addColorStop(0, Qt.alpha(color, 0.25))
                    gradient.addColorStop(1, Qt.alpha(color, 0.02))
                    ctx.lineTo(width - 1.5, height)
                    ctx.lineTo(1.5 + (width - 3) * (1 - (points.length - 1) / 19), height)
                    ctx.closePath()
                    ctx.fillStyle = gradient
                    ctx.fill()
                }
            }
        }
        Text {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 5
            text: chart.rate(chart.ceiling)
            color: "#c3d8cf"
            font.pixelSize: 10
        }
    }
}
