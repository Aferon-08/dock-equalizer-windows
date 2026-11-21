import QtQuick
import QtQuick.Controls
import "DockGeometry.js" as Geometry
import "MarkerMotion.js" as Motion

Item {
    id: card
    required property var event
    required property var wifi
    required property var battery
    required property color accent
    required property real availableWidth
    required property real minimumWidth
    required property real availableHeight
    required property real entrance
    required property real expansion
    required property real detailProgress
    required property bool dismissible
    signal dismissed()

    readonly property string kind: event?.kind ?? "regular"
    readonly property var batteryDetailsData: event?.liveBattery && battery.state === event.state ? battery : event
    readonly property real inset: 24
    readonly property real badgeSize: 38
    readonly property real closeSize: 30
    readonly property real headerTextX: inset + badgeSize + 12
    readonly property real headerSpace: headerTextX + 8 + closeSize + inset
    readonly property real centeredHeaderSpace: 2 * headerTextX
    readonly property real expandedTop: 19
    readonly property real headerY: Math.max(0, Geometry.mix((height - badgeSize) / 2, expandedTop, expansion))
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

    readonly property string headline: (event?.title ?? "").replace(/[\r\n]+/g, " ")
    readonly property string summary: kind === "wifi" ? wifiTitle : kind === "battery"
        ? (batteryDetailsData?.summary ?? "") : (event?.summary ?? "")
    readonly property string detail: {
        if (kind === "wifi")
            return wifiInfo + (wifiConnected && !wifi.hasCounters
                ? "\nWindows не предоставила счётчики трафика." : "")
        if (kind === "battery")
            return batteryDetailsData?.detail ?? ""
        return event?.detail ?? ""
    }
    readonly property bool movesSummary: kind === "app" || (summary !== "" && kind !== "battery" && kind !== "wifi"
        && (detail === summary || detail.startsWith(summary + "\n")))
    readonly property string fullMessage: detail || (movesSummary ? summary : "")
    readonly property bool showGraph: kind === "wifi" && wifi.hasCounters === true
    readonly property bool showCharge: kind === "battery" && (batteryDetailsData?.charge ?? -1) >= 0
    readonly property real accessoryHeight: showGraph ? 99 : showCharge ? 14 : 0
    readonly property real preferredWidth: Math.ceil(Math.min(availableWidth, Math.max(minimumWidth,
        centeredHeaderSpace + titleMeasure.implicitWidth,
        (movesSummary ? headerSpace : centeredHeaderSpace) + summaryMeasure.implicitWidth,
        2 * inset + detailMeasure.implicitWidth)))
    readonly property real idealHeight: expandedTop
        + Math.max(badgeSize, titleMeasure.implicitHeight + (movesSummary || !summary ? 0 : 3 + summaryMeasure.implicitHeight))
        + 34 + (fullMessage ? detailMeasure.implicitHeight : 0) + accessoryHeight + 16 + footer.implicitHeight + 19
    readonly property real preferredHeight: Math.min(availableHeight,
        Math.max(showGraph || (kind === "wifi" && wifi.state === "loading") ? 236 : 176, Math.ceil(idealHeight)))
    readonly property bool multiline: expansion > 0.42
    readonly property real messageMove: movesSummary ? Motion.smooth(Geometry.phase(expansion, 0.15, 0.88)) : 0
    readonly property real headerWidth: Math.max(1, width - headerSpace)
    readonly property real centeredHeaderWidth: Math.max(1, width - Geometry.mix(headerSpace, centeredHeaderSpace, expansion))
    readonly property real headerGroupHeight: headlineFrame.height + (movesSummary || !summary ? 0 : 3 + summaryText.height)
    readonly property real headerHeight: Math.max(badgeSize, headerGroupHeight)
    readonly property real bodyWidth: Math.max(1, width - 2 * inset)
    readonly property real expandedEntrance: Math.min(entrance, detailProgress)
    readonly property real dividerY: headerY + headerHeight + 16
    readonly property real detailY: dividerY + 18
    readonly property real accessoryY: detailY + (fullMessage ? (movesSummary ? summaryText.height : description.height) : 0)
    readonly property real footerY: Math.max(accessoryY + accessoryHeight + 16, height - 19 - footer.height)

    onEventChanged: viewport.contentY = 0
    onExpansionChanged: if (!expansion) viewport.contentY = 0

    function textLayout() {
        return { titleOverflow: headlineFrame.overflow, titleScroll: headlineFrame.scroll,
            titleCenterOffset: Qt.point(headlineFrame.x + headlineFrame.width / 2 - width / 2,
                headlineFrame.y + headlineFrame.height / 2 - headerY - headerHeight / 2),
            messageTruncated: summaryText.truncated,
            messageLines: summaryText.lineCount, message: summaryText.text, messageY: summaryText.y,
            detailY, duplicateVisible: description.visible, messageColor: summaryText.color,
            scrollRange: viewport.contentHeight - viewport.height }
    }

    component Arrival: Translate {
        required property real progress
        required property point offset
        readonly property real alpha: Motion.smooth(progress / 0.72)
        readonly property real remaining: 1 - Geometry.arrival(progress, 0.22)
        x: offset.x * remaining
        y: offset.y * remaining
    }
    component NoticeText: Text { textFormat: Text.PlainText }

    clip: true

    NoticeText {
        id: titleMeasure
        visible: false
        text: card.headline
        font: headlineText.font
    }
    NoticeText {
        id: summaryMeasure
        visible: false
        text: card.summary
        font: summaryText.font
        width: Math.max(1, card.preferredWidth - card.centeredHeaderSpace)
        wrapMode: Text.Wrap
    }
    NoticeText {
        id: detailMeasure
        visible: false
        text: card.fullMessage
        font: card.movesSummary ? summaryText.font : description.font
        width: Math.max(1, card.preferredWidth - 2 * card.inset)
        wrapMode: Text.Wrap
    }

    Flickable {
        id: viewport
        anchors.fill: parent
        contentWidth: width
        contentHeight: card.multiline ? Math.max(height, card.footerY + footer.height + 19) : height
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: card.expansion >= 0.99 && contentHeight > height + 1
        ScrollBar.vertical: ScrollBar {
            policy: viewport.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }
    }

    Rectangle {
        id: badge
        parent: viewport.contentItem
        x: card.inset
        y: card.headerY
        width: card.badgeSize
        height: width
        radius: 13
        color: Qt.alpha(card.accent, 0.13)
        border.color: Qt.alpha(card.accent, 0.37)
        antialiasing: true
        opacity: badgeArrival.alpha
        transform: Arrival {
            id: badgeArrival
            progress: Geometry.phase(card.entrance, 0.28, 0.77)
            offset: Qt.point(-28, -3)
        }

        Canvas {
            id: badgeIcon
            anchors.centerIn: parent
            width: 22
            height: 22
            Connections {
                target: card
                function onAccentChanged() { badgeIcon.requestPaint() }
                function onEventChanged() { badgeIcon.requestPaint() }
                function onBatteryDetailsDataChanged() { badgeIcon.requestPaint() }
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
                    const charge = card.batteryDetailsData?.charge ?? -1
                    if (charge >= 0)
                        ctx.fillRect(5, 8.5, 10.5 * Math.min(1, charge / 100), 5)
                    return
                }
                if (card.kind === "system") {
                    ctx.arc(11, 11, 6.8, -0.6, 1.78 * Math.PI, false)
                    ctx.moveTo(17.5, 4)
                    ctx.lineTo(17.5, 8.8)
                    ctx.lineTo(13, 8.8)
                } else if (card.kind === "app") {
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
    }

    Item {
        id: headlineFrame
        parent: viewport.contentItem
        x: Geometry.mix(card.headerTextX, (card.width - width) / 2, card.expansion)
        y: card.headerY + (card.headerHeight - card.headerGroupHeight) / 2 * card.expansion
        width: Math.max(1, Math.min(card.centeredHeaderWidth, Math.ceil(titleMeasure.implicitWidth)))
        height: headlineText.implicitHeight
        clip: overflow > 0.5
        opacity: titleArrival.alpha
        property real scroll: 0
        readonly property real overflow: Math.max(0, headlineText.implicitWidth - width)
        readonly property bool shouldScroll: overflow > 0.5 && card.visible && card.entrance === 1
            && (card.detailProgress === 0 || card.detailProgress === 1)
        readonly property int scrollDuration: Math.round(Math.max(1400, Math.min(6800, overflow * 14)))

        function updateScroll() {
            marquee.stop()
            scroll = 0
            if (shouldScroll)
                marquee.start()
        }
        onShouldScrollChanged: updateScroll()
        Connections {
            target: card
            function onHeadlineChanged() { headlineFrame.updateScroll() }
        }

        transform: Arrival {
            id: titleArrival
            progress: Geometry.phase(card.entrance, 0.37, 0.88)
            offset: Qt.point(0, -16)
        }
        NoticeText {
            id: headlineText
            x: headlineFrame.overflow > 0.5 ? -headlineFrame.overflow * headlineFrame.scroll
                : (headlineFrame.width - width) / 2
            text: card.headline
            font.pixelSize: 17
            font.weight: Font.DemiBold
            color: card.ink
        }
        SequentialAnimation {
            id: marquee
            loops: Animation.Infinite
            PauseAnimation { duration: 700 }
            NumberAnimation {
                target: headlineFrame; property: "scroll"; from: 0; to: 1
                duration: headlineFrame.scrollDuration; easing.type: Easing.InOutSine
            }
            PauseAnimation { duration: 850 }
            NumberAnimation {
                target: headlineFrame; property: "scroll"; from: 1; to: 0
                duration: headlineFrame.scrollDuration; easing.type: Easing.InOutSine
            }
        }
    }

    NoticeText {
        id: summaryText
        parent: viewport.contentItem
        x: card.movesSummary ? Geometry.mix(card.headerTextX, card.inset, card.messageMove)
            : Geometry.mix(card.headerTextX, (card.width - width) / 2, card.expansion)
        y: Geometry.mix(headlineFrame.y + headlineFrame.height + 3, card.detailY, card.messageMove)
        width: card.movesSummary ? Geometry.mix(card.headerWidth, card.bodyWidth, card.messageMove)
            : Math.max(1, Math.min(card.centeredHeaderWidth, Math.ceil(summaryMeasure.implicitWidth)))
        horizontalAlignment: card.movesSummary ? Text.AlignLeft : Text.AlignHCenter
        text: card.movesSummary && card.messageMove > 0.74 ? card.fullMessage : card.summary
        font.pixelSize: 13
        color: card.accent
        wrapMode: card.multiline ? Text.Wrap : Text.NoWrap
        elide: card.multiline ? Text.ElideNone : Text.ElideRight
        opacity: messageArrival.alpha
        transform: Arrival {
            id: messageArrival
            progress: Geometry.phase(card.entrance, 0.48, 0.97)
            offset: Qt.point(-13 * (1 - card.messageMove), 10 + 6 * card.messageMove)
        }
    }

    Button {
        id: closeButton
        anchors.right: parent.right
        anchors.rightMargin: card.inset
        y: card.headerY + (card.badgeSize - height) / 2
        width: card.closeSize
        height: width
        padding: 0
        opacity: closeArrival.alpha
        enabled: card.dismissible && opacity > 0.75
        transform: Arrival {
            id: closeArrival
            progress: Geometry.phase(card.entrance, 0.48, 0.9)
            offset: Qt.point(19, 0)
        }
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

    Rectangle {
        parent: viewport.contentItem
        x: card.inset
        y: card.dividerY
        width: card.bodyWidth
        height: 1
        color: Qt.alpha(card.accent, 0.26)
        opacity: Motion.smooth(Geometry.phase(card.expandedEntrance, 0.38, 0.85))
    }

    NoticeText {
        id: description
        parent: viewport.contentItem
        x: card.inset
        y: card.detailY
        width: card.bodyWidth
        text: card.movesSummary ? "" : card.detail
        wrapMode: Text.Wrap
        color: card.ink
        font.pixelSize: card.kind === "wifi" ? 13 : 14
        visible: text !== "" && opacity > 0.001
        opacity: bodyArrival.alpha
        transform: Arrival {
            id: bodyArrival
            progress: Geometry.phase(card.expandedEntrance, 0.48, 0.95)
            offset: Qt.point(0, 19)
        }
    }

    Loader {
        parent: viewport.contentItem
        x: card.inset
        y: card.accessoryY + 6
        width: card.bodyWidth
        height: Math.max(0, card.accessoryHeight - 6)
        active: card.showGraph || card.showCharge
        opacity: accessoryArrival.alpha
        visible: opacity > 0.001
        transform: Arrival {
            id: accessoryArrival
            progress: Geometry.phase(card.expandedEntrance, 0.55, 0.98)
            offset: Qt.point(0, 18)
        }
        sourceComponent: card.showGraph ? traffic : chargeBar
    }
    Component {
        id: chargeBar
        Rectangle {
            id: batteryTrack
            radius: height / 2
            color: Qt.alpha(card.accent, 0.15)
            Rectangle {
                width: batteryTrack.width * Math.max(0, Math.min(1, (card.batteryDetailsData?.charge ?? 0) / 100))
                height: parent.height
                radius: height / 2
                color: Qt.alpha(card.accent, 0.90)
                Behavior on width { NumberAnimation { duration: 360; easing.type: Easing.OutCubic } }
            }
        }
    }
    Component {
        id: traffic
        WifiThroughput {
            samples: card.wifi.samples ?? []
            accent: card.accent
        }
    }
    NoticeText {
        id: footer
        parent: viewport.contentItem
        x: card.inset
        y: card.footerY
        width: card.bodyWidth
        text: card.event ? (card.kind === "wifi" && card.wifi.preview ? "Сеть · демоданные"
            : card.event.source) + "  ·  " + Qt.formatTime(card.event.sentAt, "HH:mm") : ""
        color: card.secondary
        font.pixelSize: 12
        elide: Text.ElideRight
        opacity: footerArrival.alpha
        transform: Arrival {
            id: footerArrival
            progress: Geometry.phase(card.expandedEntrance, 0.59, 1)
            offset: Qt.point(10, 15)
        }
    }
}
