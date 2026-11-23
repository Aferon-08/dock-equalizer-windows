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
    required property var motionCurve
    required property bool springMotion
    property bool toastLayout: false
    property bool compactPopup: false
    property int queuedCount: 0
    property real contentAmount: 1
    property real badgeVisibility: 1
    property real counterVisibility: 1
    signal dismissed(int eventId)

    readonly property real counterWidth: Math.max(40, Math.ceil(counterText.implicitWidth) + 18)
    readonly property real counterSpace: queuedCount > 0 ? counterWidth + 9 : 0
    readonly property rect badgeRect: Qt.rect(inset, headerY - (wrappedLayout ? 0 : viewport.contentY), badgeSize, badgeSize)
    readonly property rect counterRect: Qt.rect(width - inset - closeSize - counterWidth - 9
        - (showsAction ? closeSize + 3 : 0), headerY + (badgeSize - 28) / 2, counterWidth, 28)

    readonly property string kind: event?.kind ?? "regular"
    readonly property var batteryDetailsData: event?.liveBattery && battery.state === event.state ? battery : event
    readonly property bool wrappedLayout: toastLayout || compactPopup
    readonly property real inset: toastLayout || compactPopup ? 16 : 24
    readonly property real badgeSize: toastLayout ? 26 : compactPopup ? 34 : 38
    readonly property real closeSize: 30
    readonly property real headerTextX: inset + badgeSize + (wrappedLayout ? 8 : 12)
    readonly property real headerSpace: headerTextX + 8 + closeSize + inset + counterSpace
    readonly property real centeredHeaderSpace: 2 * Math.max(headerTextX, inset + closeSize + counterSpace)
    readonly property real expandedTop: wrappedLayout ? 13 : 19
    readonly property real headerY: wrappedLayout ? expandedTop
        : Math.max(0, Geometry.mix((height - badgeSize) / 2, expandedTop, expansion))
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

    readonly property string headline: oneLine(event?.title ?? "")
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
    readonly property string preview: oneLine(summary || fullMessage)
    readonly property string wrappedMessage: detail && summary && !movesSummary && summary !== detail
        ? summary + "\n" + detail : fullMessage || summary
    readonly property string source: event?.source ?? ""
    readonly property string actionLabel: kind === "wifi" ? "Открыть настройки Wi-Fi"
        : kind === "battery" ? "Открыть параметры питания" : ""
    readonly property url actionUrl: kind === "wifi" ? "ms-settings:network-wifi"
        : kind === "battery" ? "ms-settings:powersleep" : ""
    readonly property bool showsAction: toastLayout && actionLabel !== "" && availableHeight >= 130
    readonly property real actionHeight: showsAction ? 38 : 0
    readonly property real wrappedHeaderHeight: toastLayout ? expandedTop + badgeSize + 12 : 0
    readonly property real wrappedTextX: toastLayout ? inset : headerTextX
    readonly property real wrappedGutters: toastLayout ? 2 * inset : headerSpace
    readonly property bool showGraph: kind === "wifi" && wifi.hasCounters === true
    readonly property bool showCharge: kind === "battery" && (batteryDetailsData?.charge ?? -1) >= 0
    readonly property real accessoryHeight: showGraph ? 99 : showCharge ? 14 : 0
    readonly property real preferredWidth: Math.min(availableWidth, Math.ceil(Math.max(minimumWidth,
        (wrappedLayout ? wrappedGutters : centeredHeaderSpace) + titleMeasure.implicitWidth,
        (movesSummary ? headerSpace : centeredHeaderSpace) + summaryMeasure.implicitWidth,
        (wrappedLayout ? wrappedGutters : 2 * inset) + detailMeasure.implicitWidth,
        toastLayout ? headerSpace + sourceText.implicitWidth + (showsAction ? closeSize + 3 : 0) : 0)))
    readonly property real idealHeight: expandedTop
        + Math.max(badgeSize, titleMeasure.implicitHeight + (movesSummary || !summary ? 0 : 3 + summaryMeasure.implicitHeight))
        + 34 + (fullMessage ? detailMeasure.implicitHeight : 0) + accessoryHeight + 16 + footer.implicitHeight + 19
    readonly property real wrappedIdealHeight: wrappedHeaderHeight + (compactPopup ? expandedTop : 0)
        + wrappedTitleMeasure.implicitHeight + (wrappedMessage !== "" ? 6 + wrappedMessageMeasure.implicitHeight : 0)
        + (toastLayout ? accessoryHeight : 0) + inset + (showsAction ? actionHeight + inset : 0)
    readonly property real preferredHeight: Math.min(availableHeight, wrappedLayout
        ? Math.min(compactPopup ? 134 : availableHeight, Math.max(compactPopup ? 68 : 94, Math.ceil(wrappedIdealHeight)))
        : Math.max(showGraph || (kind === "wifi" && wifi.state === "loading") ? 236 : 176, Math.ceil(idealHeight)))
    readonly property bool multiline: expansion > 0.42
    readonly property real messageMove: movesSummary ? Motion.smooth(Geometry.phase(expansion, 0.15, 0.88)) : 0
    readonly property bool messageInBody: movesSummary && messageMove > 0.74
    readonly property real headerWidth: Math.max(1, width - headerSpace)
    readonly property real centeredHeaderWidth: Math.max(1, width - Geometry.mix(headerSpace, centeredHeaderSpace, expansion))
    readonly property real headerGroupHeight: headlineFrame.height + (messageInBody || !summaryText.text
        ? 0 : (3 + summaryText.height) * (1 - messageMove))
    readonly property real headerHeight: Math.max(badgeSize, headerGroupHeight)
    readonly property real bodyWidth: Math.max(1, width - 2 * inset)
    readonly property real expandedEntrance: Math.min(entrance, detailProgress)
    readonly property real contentOpacity: Motion.smooth(Geometry.phase(contentAmount, 0.05, 0.75))
    readonly property real dividerY: headerY + headerHeight + 16
    readonly property real detailY: wrappedLayout ? headlineFrame.y + headlineFrame.height + 6 : dividerY + 18
    readonly property real accessoryY: detailY + (wrappedLayout ? (wrappedMessage ? description.height : 0)
        : fullMessage ? (movesSummary ? summaryText.height : description.height) : 0)
    readonly property real footerY: Math.max(accessoryY + accessoryHeight + 16, height - 19 - footer.height)

    onEventChanged: {
        viewport.contentY = 0
        actionsPopup.close()
    }
    onExpansionChanged: if (!expansion) viewport.contentY = 0
    onDismissibleChanged: if (!dismissible) actionsPopup.close()

    function oneLine(text) {
        return text.replace(/[\s\u0085]+/g, " ").trim()
    }

    function dismiss() {
        if (event && dismissible)
            dismissed(event.eventId)
    }

    function runAction() {
        actionsPopup.close()
        if (dismissible && actionLabel !== "" && Qt.openUrlExternally(actionUrl))
            dismiss()
    }

    function textLayout() {
        const message = wrappedLayout ? description : summaryText
        return { titleOverflow: headlineFrame.overflow, titleScroll: headlineFrame.scroll,
            titleCenterOffset: Qt.point(headlineFrame.x + headlineFrame.width / 2 - width / 2,
                headlineFrame.y + headlineFrame.height / 2 - headerY - headerHeight / 2),
            messageTruncated: message.truncated, messageLines: message.lineCount,
            message: message.text, messageY: message.y, messageHeight: message.height,
            detailY, duplicateVisible: description.visible, messageColor: summaryText.color,
            scrollRange: viewport.contentHeight - viewport.height }
    }

    component Arrival: Translate {
        required property real progress
        required property point offset
        readonly property real alpha: Motion.smooth(progress / 0.72)
        readonly property real remaining: 1 - Geometry.arrival(progress, card.springMotion ? 0.22 : 0)
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
        text: card.wrappedLayout ? card.wrappedMessage : card.fullMessage
        font: !card.wrappedLayout && card.movesSummary ? summaryText.font : description.font
        width: Math.max(1, card.preferredWidth - 2 * card.inset)
        wrapMode: Text.Wrap
    }
    NoticeText {
        id: wrappedTitleMeasure
        visible: false
        text: card.headline
        font: headlineText.font
        width: Math.max(1, card.preferredWidth - card.wrappedGutters)
        wrapMode: Text.Wrap
    }
    NoticeText {
        id: wrappedMessageMeasure
        visible: false
        text: card.wrappedMessage
        font: description.font
        width: wrappedTitleMeasure.width
        wrapMode: Text.Wrap
    }

    Flickable {
        id: viewport
        y: card.wrappedHeaderHeight
        width: parent.width
        height: Math.max(0, parent.height - y - (card.showsAction ? card.actionHeight + card.inset : 0))
        contentWidth: width
        contentHeight: card.wrappedLayout
            ? Math.max(height, card.accessoryY + (card.toastLayout ? card.accessoryHeight : 0) + card.inset)
            : card.multiline ? Math.max(height, card.footerY + footer.height + 19) : height
        clip: card.wrappedLayout
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: card.contentAmount === 1
            && (card.wrappedLayout ? card.entrance > 0.91 && card.dismissible : card.expansion >= 0.99)
            && contentHeight > height + 1
        ScrollBar.vertical: ScrollBar {
            policy: viewport.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        }
    }

    Item {
        id: messageLayer
        parent: viewport.contentItem
        width: viewport.width
        height: viewport.contentHeight
        opacity: card.contentOpacity
        transform: Scale {
            origin.x: card.inset + card.badgeSize / 2
            origin.y: card.headerY + card.badgeSize / 2 - viewport.y
            xScale: Geometry.mix(0.14, 1, card.contentAmount)
            yScale: Geometry.mix(0.62, 1, card.contentAmount)
        }
    }

    Rectangle {
        id: badge
        parent: card.wrappedLayout ? card : viewport.contentItem
        x: card.inset
        y: card.headerY
        width: card.badgeSize
        height: width
        radius: 13
        color: Qt.alpha(card.accent, 0.13)
        border.color: Qt.alpha(card.accent, 0.37)
        antialiasing: true
        opacity: card.badgeVisibility * badgeArrival.alpha
        transform: Arrival {
            id: badgeArrival
            progress: Geometry.phase(card.entrance, 0.28, 0.77)
            offset: Qt.point(-28, -3)
        }

        DockNotificationIcon {
            anchors.centerIn: parent
            tint: card.accent
            kind: card.kind
            charge: card.batteryDetailsData?.charge ?? -1
        }

    }

    NoticeText {
        id: sourceText
        x: Geometry.mix(card.inset + card.badgeSize / 2, card.headerTextX, card.contentAmount)
        y: card.headerY + (card.badgeSize - height) / 2
        width: Math.max(1, card.headerWidth - (card.showsAction ? card.closeSize + 3 : 0))
        visible: card.toastLayout
        text: card.source
        color: card.secondary
        elide: Text.ElideRight
        font.pixelSize: 12
        font.weight: Font.DemiBold
        opacity: badgeArrival.alpha * card.contentOpacity
    }

    Item {
        id: headlineFrame
        parent: messageLayer
        x: card.wrappedLayout ? card.wrappedTextX
            : Geometry.mix(card.headerTextX, (card.width - width) / 2, card.expansion)
        y: card.wrappedLayout ? (card.toastLayout ? 0 : card.expandedTop)
            : card.headerY + (Geometry.mix(card.badgeSize, card.headerHeight, card.expansion) - card.headerGroupHeight) / 2
        width: card.wrappedLayout ? Math.max(1, card.width - card.wrappedGutters)
            : Math.max(1, Math.min(card.centeredHeaderWidth, Math.ceil(titleMeasure.implicitWidth)))
        height: headlineText.implicitHeight
        clip: overflow > 0.5
        opacity: titleArrival.alpha
        property real scroll: 0
        readonly property real overflow: card.wrappedLayout ? 0 : Math.max(0, headlineText.implicitWidth - width)
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
            x: card.wrappedLayout ? 0 : headlineFrame.overflow > 0.5 ? -headlineFrame.overflow * headlineFrame.scroll
                : (headlineFrame.width - width) / 2
            width: card.wrappedLayout ? headlineFrame.width : implicitWidth
            wrapMode: card.wrappedLayout ? Text.Wrap : Text.NoWrap
            text: card.headline
            font.pixelSize: 17
            font.weight: Font.DemiBold
            color: card.ink
        }
        SequentialAnimation {
            id: marquee
            loops: Animation.Infinite
            PauseAnimation { duration: 700 }
            DockTransition {
                target: headlineFrame; property: "scroll"; from: 0; to: 1
                duration: headlineFrame.scrollDuration; curve: card.motionCurve; standardEasing: Easing.InOutSine
            }
            PauseAnimation { duration: 850 }
            DockTransition {
                target: headlineFrame; property: "scroll"; from: 1; to: 0
                duration: headlineFrame.scrollDuration; curve: card.motionCurve; standardEasing: Easing.InOutSine
            }
        }
    }

    NoticeText {
        id: summaryText
        parent: messageLayer
        readonly property bool wraps: card.messageInBody || (!card.movesSummary && card.multiline)
        x: card.movesSummary ? Geometry.mix(card.headerTextX, card.inset, card.messageMove)
            : Geometry.mix(card.headerTextX, (card.width - width) / 2, card.expansion)
        y: Geometry.mix(headlineFrame.y + headlineFrame.height + 3, card.detailY, card.messageMove)
        width: card.movesSummary ? Geometry.mix(card.headerWidth, card.bodyWidth, card.messageMove)
            : Math.max(1, Math.min(card.centeredHeaderWidth, Math.ceil(implicitWidth)))
        horizontalAlignment: card.movesSummary ? Text.AlignLeft : Text.AlignHCenter
        text: card.messageInBody ? card.fullMessage : wraps ? card.summary : card.preview
        font.pixelSize: 13
        color: card.accent
        visible: !card.wrappedLayout
        wrapMode: wraps ? Text.Wrap : Text.NoWrap
        maximumLineCount: wraps ? undefined : 1
        elide: wraps ? Text.ElideNone : Text.ElideRight
        clip: !wraps
        opacity: messageArrival.alpha
        transform: Arrival {
            id: messageArrival
            progress: Geometry.phase(card.entrance, 0.48, 0.97)
            offset: Qt.point(-13 * (1 - card.messageMove), 10 + 6 * card.messageMove)
        }
    }

    Rectangle {
        id: queueCounter
        x: card.counterRect.x
        y: card.counterRect.y
        width: card.counterRect.width
        height: card.counterRect.height
        radius: height / 2
        color: Qt.alpha(card.accent, 0.10)
        border.color: Qt.alpha(card.accent, 0.26)
        visible: card.queuedCount > 0 && opacity > 0.001
        opacity: closeArrival.alpha * card.counterVisibility
        antialiasing: true
        Accessible.role: Accessible.StaticText
        Accessible.name: "В очереди " + card.queuedCount

        Text {
            id: counterText
            anchors.centerIn: parent
            color: card.accent
            text: "+" + card.queuedCount
            font.pixelSize: 14
            font.weight: Font.DemiBold
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
        opacity: closeArrival.alpha * card.contentOpacity
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
        onClicked: card.dismiss()
    }

    Rectangle {
        parent: messageLayer
        x: card.inset
        y: card.dividerY
        width: card.bodyWidth
        height: 1
        color: Qt.alpha(card.accent, 0.26)
        visible: !card.wrappedLayout
        opacity: Motion.smooth(Geometry.phase(card.expandedEntrance, 0.38, 0.85))
    }

    NoticeText {
        id: description
        parent: messageLayer
        x: card.wrappedLayout ? card.wrappedTextX : card.inset
        y: card.detailY
        width: card.wrappedLayout ? Math.max(1, card.width - card.wrappedGutters) : card.bodyWidth
        text: card.wrappedLayout ? card.wrappedMessage : card.movesSummary ? "" : card.detail
        wrapMode: Text.Wrap
        color: card.compactPopup ? card.accent : card.ink
        font.pixelSize: card.kind === "wifi" ? 13 : 14
        visible: text !== "" && opacity > 0.001
        opacity: bodyArrival.alpha
        transform: Arrival {
            id: bodyArrival
            progress: Geometry.phase(card.wrappedLayout ? card.entrance : card.expandedEntrance, 0.48, 0.95)
            offset: Qt.point(0, 19)
        }
    }

    Loader {
        parent: messageLayer
        x: card.inset
        y: card.accessoryY + 6
        width: card.bodyWidth
        height: Math.max(0, card.accessoryHeight - 6)
        active: !card.compactPopup && (card.showGraph || card.showCharge)
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
                Behavior on width { DockTransition { duration: 360; curve: card.motionCurve; standardEasing: Easing.OutCubic } }
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
        parent: messageLayer
        x: card.inset
        y: card.footerY
        width: card.bodyWidth
        text: card.event ? (card.kind === "wifi" && card.wifi.preview ? "Сеть · демоданные"
            : card.event.source) + "  ·  " + Qt.formatTime(card.event.sentAt, "HH:mm") : ""
        color: card.secondary
        font.pixelSize: 12
        elide: Text.ElideRight
        visible: !card.wrappedLayout
        opacity: footerArrival.alpha
        transform: Arrival {
            id: footerArrival
            progress: Geometry.phase(card.expandedEntrance, 0.59, 1)
            offset: Qt.point(10, 15)
        }
    }

    Button {
        id: actionsButton
        anchors.right: closeButton.left
        anchors.rightMargin: 3
        y: closeButton.y
        width: card.closeSize
        height: width
        padding: 0
        visible: card.showsAction
        enabled: closeButton.enabled
        opacity: closeButton.opacity
        Accessible.name: "Действия уведомления"
        background: Rectangle {
            radius: width / 2
            color: actionsButton.hovered || actionsButton.down ? Qt.alpha(card.accent, 0.16) : "transparent"
        }
        contentItem: NoticeText {
            text: "⋯"
            color: card.secondary
            font.pixelSize: 20
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        onClicked: actionsPopup.open()
    }

    component NoticeAction: Button {
        id: action
        implicitHeight: 38
        text: card.actionLabel
        font.pixelSize: 13
        font.weight: Font.DemiBold
        contentItem: NoticeText {
            text: action.text
            color: card.ink
            font: action.font
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: 8
            color: Qt.alpha(card.accent, action.down ? 0.25 : action.hovered ? 0.19 : 0.11)
            border.color: Qt.alpha(card.accent, 0.23)
        }
        onClicked: card.runAction()
    }

    NoticeAction {
        x: card.inset
        y: card.height - height - card.inset
        width: card.bodyWidth
        height: card.actionHeight
        visible: card.showsAction
        opacity: Motion.smooth(Geometry.phase(card.entrance, 0.64, 1)) * card.contentOpacity
        enabled: card.dismissible && opacity > 0.75
    }

    Popup {
        id: actionsPopup
        parent: card
        popupType: Popup.Item
        padding: 6
        x: card.width - card.inset - width
        y: actionsButton.y + actionsButton.height + 5
        width: Math.min(242, Math.max(1, card.bodyWidth))
        height: contentItem.implicitHeight + 2 * padding
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            radius: 10
            color: "#182d26"
            border.color: Qt.alpha(card.accent, 0.32)
        }
        contentItem: NoticeAction { }
    }
}
