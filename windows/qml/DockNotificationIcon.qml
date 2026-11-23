import QtQuick

Canvas {
    id: icon
    required property color tint
    required property string kind
    property real charge: -1
    implicitWidth: 22
    implicitHeight: 22
    onTintChanged: requestPaint()
    onKindChanged: requestPaint()
    onChargeChanged: requestPaint()
    onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.strokeStyle = icon.tint
        ctx.fillStyle = icon.tint
        ctx.lineWidth = 1.65
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.beginPath()
        if (icon.kind === "wifi") {
            for (const radius of [11.5, 8, 4.5]) {
                ctx.moveTo(11 - radius / Math.SQRT2, 17 - radius / Math.SQRT2)
                ctx.arc(11, 17, radius, -3 * Math.PI / 4, -Math.PI / 4, false)
            }
            ctx.stroke()
            ctx.beginPath()
            ctx.arc(11, 17, 1.05, 0, 2 * Math.PI, false)
            ctx.fill()
            return
        }
        if (icon.kind === "battery") {
            ctx.rect(2.5, 6, 15.5, 10)
            ctx.moveTo(20, 9)
            ctx.lineTo(20, 13)
            ctx.stroke()
            const charge = icon.charge
            if (charge >= 0)
                ctx.fillRect(5, 8.5, 10.5 * Math.min(1, charge / 100), 5)
            return
        }
        if (icon.kind === "system") {
            ctx.arc(11, 11, 6.8, -0.6, 1.78 * Math.PI, false)
            ctx.moveTo(17.5, 4)
            ctx.lineTo(17.5, 8.8)
            ctx.lineTo(13, 8.8)
        } else if (icon.kind === "app") {
            ctx.moveTo(5, 5.5)
            ctx.lineTo(17, 5.5)
            ctx.lineTo(17, 14)
            ctx.lineTo(10, 14)
            ctx.lineTo(6, 17)
            ctx.lineTo(6, 14)
            ctx.lineTo(5, 14)
            ctx.closePath()
        } else {
            ctx.moveTo(5.2, 11.7)
            ctx.lineTo(9, 15.4)
            ctx.lineTo(16.7, 6.6)
        }
        ctx.stroke()
    }
}
