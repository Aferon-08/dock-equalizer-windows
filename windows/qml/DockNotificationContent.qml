import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "DockGeometry.js" as Geometry
import "MarkerMotion.js" as Motion

Item {
    id: card
    required property var event
    required property var wifi
    required property color accent
    required property real expansion
    required property bool dismissible
    signal dismissed()

    readonly property string kind: event?.kind ?? "regular"
    readonly property real inset: width >= 330 ? 24 : 16
    readonly property real headerY: Math.max(0, Geometry.mix((height - 38) / 2, 19, expansion))
    readonly property color ink: "#f1f9f5"
    readonly property color secondary: "#c3d8cf"
    readonly property bool wifiConnected: wifi.state === "connected" || wifi.state === "restricted"
    readonly property string wifiTitle: {
        switch (wifi.state) {
        case "loading": return "Получаем данные о сети…"
        case "connected": return wifi.ssid || "Беспроводная сеть"
        case "restricted": return "Windows ограничила доступ к имени сети"
        case "disconnected": return "Wi-Fi не подключён"
        default: return "Состояние Wi-Fi недоступно"
        }
    }
    readonly property string wifiInfo: {
        if (!wifiConnected)
            return wifi.state === "loading" ? "Ожидаем данные от Windows."
                : "Подключение к беспроводной сети сейчас не обнаружено."
        const parts = []
        if (wifi.signal !== undefined)
            parts.push("Сигнал " + wifi.signal + " %")
        if (wifi.linkMbps !== undefined)
            parts.push("Линия " + Math.round(wifi.linkMbps) + " Мбит/с")
        if (wifi.internet === 1)
            parts.push("Есть интернет")
        else if (wifi.internet === 0)
            parts.push("Без доступа в интернет")
        return parts.join(" · ") || "Сведения о сигнале и интернете недоступны."
    }

    clip: true

    Rectangle {
        id: badge
        x: card.inset
        y: card.headerY
        width: 38
        height: width
        radius: 13
        color: Qt.alpha(card.accent, 0.13)
        border.color: Qt.alpha(card.accent, 0.37)
        antialiasing: true

        Canvas {
            id: badgeIcon
            anchors.centerIn: parent
            width: 22
            height: 22
            Connections {
                target: card
                function onAccentChanged() { badgeIcon.requestPaint() }
                function onEventChanged() { badgeIcon.requestPaint() }
            }
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = card.accent
                ctx.fillStyle = card.accent
                ctx.lineWidth = 1.65
                ctx.lineCap = "round"
                ctx.lineJoin = "round"
                ctx.beginPath()
                if (card.kind === "wifi") {
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
                if (card.kind === "battery") {
                    ctx.rect(2.5, 6, 15.5, 10)
                    ctx.moveTo(20, 9)
                    ctx.lineTo(20, 13)
                    ctx.stroke()
                    ctx.fillRect(5, 8.5, 10.5 * Math.min(1, (card.event?.charge ?? 0) / 100), 5)
                    return
                }
                if (card.kind === "system") {
                    ctx.arc(11, 11, 6.8, -0.6, 1.78 * Math.PI, false)
                    ctx.moveTo(17.5, 4)
                    ctx.lineTo(17.5, 8.8)
                    ctx.lineTo(13, 8.8)
                } else {
                    ctx.moveTo(5.2, 11.7)
                    ctx.lineTo(9, 15.4)
                    ctx.lineTo(16.7, 6.6)
                }
                ctx.stroke()
            }
        }
    }

    Column {
        x: badge.x + badge.width + 12
        y: card.headerY
        width: Math.max(1, closeButton.x - x - 8)
        spacing: 3

        Text {
            width: parent.width
            text: card.event?.title ?? ""
            textFormat: Text.PlainText
            font.pixelSize: card.width >= 330 ? 17 : 15
            font.weight: Font.DemiBold
            color: card.ink
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: card.kind === "wifi" ? card.wifiTitle : (card.event?.summary ?? "")
            textFormat: Text.PlainText
            font.pixelSize: 13
            color: card.accent
            elide: Text.ElideRight
        }
    }

    Button {
        id: closeButton
        anchors.right: parent.right
        anchors.rightMargin: card.inset
        anchors.verticalCenter: badge.verticalCenter
        width: 30
        height: width
        padding: 0
        enabled: card.dismissible
        Accessible.name: "Закрыть уведомление"
        background: Rectangle {
            radius: width / 2
            color: closeButton.down ? Qt.alpha(card.accent, 0.28)
                : closeButton.hovered ? Qt.alpha(card.accent, 0.16) : "transparent"
        }
        contentItem: Canvas {
            readonly property color strokeColor: closeButton.hovered ? card.ink : card.secondary
            onStrokeColorChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                const x = width / 2
                const y = height / 2
                const arm = 4
                ctx.clearRect(0, 0, width, height)
                ctx.strokeStyle = strokeColor
                ctx.lineWidth = 1.8
                ctx.lineCap = "round"
                ctx.beginPath()
                ctx.moveTo(x - arm, y - arm)
                ctx.lineTo(x + arm, y + arm)
                ctx.moveTo(x + arm, y - arm)
                ctx.lineTo(x - arm, y + arm)
                ctx.stroke()
            }
        }
        onClicked: card.dismissed()
    }

    Item {
        id: details
        x: card.inset
        y: card.headerY + badge.height + 18
        width: Math.max(1, card.width - 2 * x)
        height: Math.max(0, card.height - y - 19)
        opacity: Motion.smooth((card.expansion - 0.42) / 0.52)
        visible: opacity > 0.001 && height >= 24
        clip: true

        Rectangle {
            height: 1
            width: parent.width
            color: Qt.alpha(card.accent, 0.26)
        }
        Loader {
            id: detailContent
            y: 11
            width: parent.width
            height: Math.max(0, footer.y - y - 9)
            sourceComponent: card.kind === "wifi" ? wifiDetails
                : card.kind === "battery" ? batteryDetails : textDetails
        }
        Text {
            id: footer
            y: details.height - height
            width: parent.width
            text: card.event ? (card.kind === "wifi" && card.wifi.preview ? "Сеть · демоданные"
                : card.event.source) + "  ·  " + Qt.formatTime(card.event.sentAt, "HH:mm") : ""
            color: card.secondary
            font.pixelSize: 12
            elide: Text.ElideRight
        }
    }

    component Description: Text {
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        maximumLineCount: 3
        elide: Text.ElideRight
        color: card.ink
        font.pixelSize: 14
    }

    Component {
        id: textDetails
        Item {
            Description {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                text: card.event?.detail ?? ""
            }
        }
    }
    Component {
        id: batteryDetails
        ColumnLayout {
            spacing: 6
            Description {
                Layout.fillWidth: true
                text: card.event?.detail ?? ""
            }
            Rectangle {
                id: batteryTrack
                Layout.fillWidth: true
                Layout.preferredHeight: 7
                radius: height / 2
                color: Qt.alpha(card.accent, 0.15)
                Rectangle {
                    width: batteryTrack.width * Math.min(1, (card.event?.charge ?? 0) / 100)
                    height: parent.height
                    radius: height / 2
                    color: Qt.alpha(card.accent, 0.90)
                    Behavior on width { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
                }
            }
        }
    }
    Component {
        id: wifiDetails
        ColumnLayout {
            spacing: 5
            Description {
                Layout.fillWidth: true
                font.pixelSize: 13
                maximumLineCount: 2
                text: card.wifiInfo
            }
            WifiThroughput {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 48
                visible: card.wifi.hasCounters === true
                samples: card.wifi.samples ?? []
                accent: card.accent
            }
            Description {
                visible: card.wifiConnected && !card.wifi.hasCounters
                Layout.fillWidth: true
                font.pixelSize: 12
                text: "Windows не предоставила счётчики трафика."
            }
        }
    }
}
