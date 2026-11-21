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

    Canvas {
        id: plot
        anchors.top: rates.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4

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
            ctx.strokeStyle = Qt.alpha("#c3d8cf", 0.10)
            ctx.lineWidth = 1
            ctx.beginPath()
            for (const fraction of [1 / 3, 2 / 3]) {
                const y = Math.floor(height * fraction) + 0.5
                ctx.moveTo(0, y)
                ctx.lineTo(width, y)
            }
            ctx.stroke()
            drawCurve(ctx, "down", chart.accent)
            drawCurve(ctx, "up", chart.upload)
        }

        function drawCurve(ctx, key, color) {
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
        }
    }
    Text {
        anchors.right: plot.right
        anchors.top: plot.top
        anchors.rightMargin: 4
        text: chart.rate(chart.ceiling)
        color: "#c3d8cf"
        font.pixelSize: 10
    }
}
