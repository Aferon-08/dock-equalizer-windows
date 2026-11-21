import QtQuick
import "DockGeometry.js" as Geometry
import "MarkerMotion.js" as Motion

Item {
    id: notice
    required property var event
    required property var wifi
    required property var battery
    required property var renderer
    required property var media
    required property bool allowed
    required property bool clearForDetails
    required property bool attached
    required property bool paused
    required property string trackKey
    required property int miniPauseDelay
    required property real topInset
    required property real availableHeight

    signal dismissed()

    readonly property bool active: allowed && !!event
    readonly property string miniProgressRenderer: miniPlayer.progressRenderer
    readonly property real miniProgressSpectrum: miniPlayer.progressSpectrum
    readonly property bool presenting: active || reveal > 0 || splitProgress > 0 || retiringMini
    readonly property bool widePlayer: attached && renderer.lyricsView.wide
    readonly property bool keepPausedMini: paused && pauseHold.running
    readonly property bool canHoldPausedMini: allowed && paused && splitProgress > 0.92 && !miniPauseExpired
    readonly property bool retiringMini: miniPauseExpired && miniRetreat < 1 && retiringBounds.width > 0
    readonly property bool splittingPlayer: allowed && !miniPauseExpired
        && (keepPausedMini || (active && clearForDetails && widePlayer))
    readonly property bool movingPlayer: splittingPlayer || (!active && splitProgress > 0)
    readonly property real compactHeight: 76
    readonly property real miniDiameter: 66
    readonly property real miniGap: 16
    readonly property real miniSpan: miniDiameter + miniGap
    readonly property real detailsWidth: card.preferredWidth
    readonly property real detailsHeight: card.preferredHeight
    readonly property real maximumDetailsHeight: Math.max(compactHeight, detailsHeight, expandedHeight) + 16
    readonly property real compactPlayerWidth: Math.min(renderer.host.settings.compactWidth, renderer.lyricsView.maxBody)
    readonly property real maxCardWidth: Math.min(720, Math.max(1, width - 56 - (widePlayer ? miniSpan : 0)))
    readonly property real surfaceWidth: Math.max(expandedEnvelope.width, expandedWidth + miniSpan + 36)
    readonly property color accent: lastEvent?.accent ?? "#a4e7cc"
    readonly property rect expandedEnvelope: {
        const footprintWidth = widePlayer
            ? Math.max(renderer.lyricsView.expandedBodySize.width, detailsWidth + miniSpan) + 36
            : Math.max(attached ? compactPlayerWidth : 0, detailsWidth)
        return Qt.rect((width - footprintWidth) / 2, topInset, footprintWidth, detailsHeight)
    }

    property var lastEvent: null
    property real reveal: active ? 1 : 0
    property real detailProgress: presenting && clearForDetails ? 1 : 0
    property real expandedWidth: detailsWidth
    property real expandedHeight: detailsHeight
    property real splitProgress: 0
    property real mergeWeight: splittingPlayer || miniPauseExpired ? 0 : 1
    property real attachment: attached && !miniPauseExpired ? 1 : 0
    property real nudge: 0
    property bool miniPauseExpired: false
    property rect retiringBounds: Qt.rect(0, 0, 0, 0)
    property rect retiringDeckBounds: Qt.rect(0, 0, 0, 0)
    property real cardRetraction: !active && (keepPausedMini || miniPauseExpired) ? 1 : 0
    property real miniRetreat: miniPauseExpired ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: notice.active ? 1020 : 560 } }
    Behavior on detailProgress {
        NumberAnimation { duration: notice.clearForDetails ? 840 : 500 }
    }
    Behavior on expandedWidth { NumberAnimation { duration: 420; easing.type: Easing.InOutCubic } }
    Behavior on expandedHeight { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
    Behavior on mergeWeight { NumberAnimation { duration: 180; easing.type: Easing.InOutSine } }
    Behavior on attachment { NumberAnimation { duration: 360; easing.type: Easing.InOutCubic } }
    Behavior on cardRetraction { NumberAnimation { duration: 490; easing.type: Easing.InOutCubic } }
    Behavior on miniRetreat { NumberAnimation { duration: 450; easing.type: Easing.InOutSine } }

    onSplittingPlayerChanged: {
        const current = splitProgress
        const target = splittingPlayer ? 1 : 0
        split.stop()
        if (current === target)
            return
        split.from = current
        split.to = target
        split.easing.type = splittingPlayer ? Easing.InOutSine : Easing.OutQuad
        split.start()
    }
    NumberAnimation { id: split; target: notice; property: "splitProgress"; duration: 1060 }

    function beginPauseHold() {
        if (canHoldPausedMini && !pauseHold.running)
            pauseHold.start()
    }

    function resetPauseHold() {
        pauseHold.stop()
        miniPauseExpired = false
    }

    onCanHoldPausedMiniChanged: beginPauseHold()
    onPausedChanged: if (!paused) resetPauseHold()
    onTrackKeyChanged: {
        resetPauseHold()
        beginPauseHold()
    }

    Timer {
        id: pauseHold
        interval: notice.miniPauseDelay
        onTriggered: {
            notice.retiringBounds = notice.miniBounds
            notice.retiringDeckBounds = notice.renderer.playerHousing
            notice.miniPauseExpired = true
        }
    }

    onEventChanged: {
        if (!event)
            return
        lastEvent = event
        if (active && attached && !widePlayer)
            attention.restart()
    }
    SequentialAnimation {
        id: attention
        NumberAnimation { target: notice; property: "nudge"; to: 4; duration: 90; easing.type: Easing.OutCubic }
        NumberAnimation { target: notice; property: "nudge"; to: -2.5; duration: 120; easing.type: Easing.InOutSine }
        NumberAnimation { target: notice; property: "nudge"; to: 1.2; duration: 95; easing.type: Easing.InOutSine }
        NumberAnimation { target: notice; property: "nudge"; to: 0; duration: 115; easing.type: Easing.OutCubic }
    }

    readonly property real coverAmount: movingPlayer
        ? Motion.smooth((splitProgress - 0.04) / 0.65) : Motion.smooth((reveal - 0.06) / 0.52)
    readonly property real detailAmount: Motion.travel(detailProgress / 0.86)
    readonly property real detailSpring: Geometry.recoil(Geometry.phase(detailProgress, 0.70, 1))
    readonly property real extruded: Motion.smooth((splitProgress - 0.10) / 0.68)
    readonly property real extraPlayerWidth: Math.max(0, expandedWidth + miniSpan - renderer.playerHousing.width) * extruded
    readonly property real releaseRecoil: Geometry.recoil((splitProgress - 0.76) / 0.24)
    readonly property real mergeRecoil: mergeWeight * Geometry.recoil((0.39 - splitProgress) / 0.39)
    readonly property real bodyTaper: Math.max(Geometry.taper(cardRetraction),
        Geometry.mix(Geometry.taper(1 - reveal), renderer.playerTaper, attachment))
    readonly property real bodyRadius: {
        const radius = Geometry.mix(compactHeight / 2, 36, detailAmount)
        return Geometry.mix(radius, Geometry.mix(renderer.radius, radius, coverAmount), attachment)
    }
    readonly property rect bodyBounds: {
        const height = Geometry.mix(compactHeight, expandedHeight, detailAmount) + 9 * detailSpring
        const cardWidth = expandedWidth + 14 * detailSpring
        const solo = Geometry.settleHousing(Geometry.pullToEdge(
            Qt.rect((width - cardWidth) / 2, topInset, cardWidth, height), 1 - reveal, 0, 0), reveal)
        const body = retiringMini ? retiringDeckBounds : renderer.playerHousing
        const widthTaken = miniSpan * Motion.smooth((splitProgress - 0.1) / 0.78)
        const extra = extraPlayerWidth
            + (widePlayer ? 0 : Math.max(0, cardWidth - body.width) * coverAmount) + 14 * detailSpring * extruded
        const playerBounds = Qt.rect(body.x - extra / 2 + nudge * coverAmount - 10 * mergeRecoil, body.y,
            Math.max(1, body.width + extra - widthTaken - 4 * releaseRecoil + 20 * mergeRecoil),
            Geometry.mix(body.height, height, coverAmount) + 9 * mergeRecoil)
        const housing = Geometry.mixRect(solo, playerBounds, attachment)
        return cardRetraction > 0 ? Geometry.pullToEdge(housing, cardRetraction, 0, 0) : housing
    }

    readonly property real miniStretch: Motion.smooth((splitProgress - 0.34) / 0.24)
        * (1 - Motion.smooth((splitProgress - 0.72) / 0.26))
    readonly property point miniCenter: {
        const body = renderer.playerHousing
        const right = body.x + body.width + extraPlayerWidth / 2
        return Qt.point(right - Geometry.mix(miniDiameter * 0.78, miniDiameter / 2, extruded)
            + 6 * miniStretch + 11 * releaseRecoil,
            body.y + 47 + 6 * miniStretch - 4 * releaseRecoil)
    }
    readonly property rect miniBounds: {
        if (miniPauseExpired)
            return retiringMini ? Geometry.pullToEdge(retiringBounds, miniRetreat, 0, 0) : Qt.rect(0, 0, 0, 0)
        const growth = Motion.smooth((splitProgress - 0.08) / 0.55)
        if (growth < 0.001)
            return Qt.rect(0, 0, 0, 0)
        const span = miniDiameter * growth
        const horizontal = span * (1 + 0.17 * miniStretch + 0.095 * releaseRecoil)
        const vertical = span * (1 - 0.12 * miniStretch - 0.065 * releaseRecoil)
        return Qt.rect(miniCenter.x - horizontal / 2, miniCenter.y - vertical / 2, horizontal, vertical)
    }
    readonly property real miniBlend: miniPauseExpired ? 0 : 48 * Motion.smooth((splitProgress - 0.16) / 0.27)
        * (1 - Motion.smooth((splitProgress - 0.70) / 0.23)) * (1 - cardRetraction)
    readonly property rect neckBounds: {
        const edge = bodyBounds.x + bodyBounds.width
        const gap = miniBounds.x - edge
        if (miniBounds.width <= 0 || miniBlend <= 0 || gap > miniBlend / 2)
            return Qt.rect(0, 0, 0, 0)
        const span = Math.max(0, gap) + 14
        const height = 2 * Math.max(3, miniBlend * 0.46 - Math.max(0, gap) * 0.7)
        return Qt.rect(edge - 7, miniBounds.y + (miniBounds.height - height) / 2, span, height)
    }

    readonly property real playerOpacity: miniPauseExpired ? 0 : (1 - cardRetraction) * (movingPlayer
        ? 1 : 1 - coverAmount)
    readonly property real cardEntrance: movingPlayer ? Math.min(reveal, splitProgress) : reveal

    function textLayout() {
        return card.textLayout()
    }

    visible: presenting

    DockNotificationContent {
        id: card
        x: notice.bodyBounds.x
        y: notice.bodyBounds.y
        width: notice.bodyBounds.width
        height: notice.bodyBounds.height
        opacity: 1 - Motion.smooth(notice.cardRetraction / 0.45)
        visible: notice.cardEntrance > 0.27 && opacity > 0.001
        event: notice.lastEvent
        wifi: notice.wifi
        battery: notice.battery
        accent: notice.accent
        availableWidth: notice.maxCardWidth
        minimumWidth: notice.widePlayer
            ? Math.max(404, notice.renderer.lyricsView.expandedBodySize.width - notice.miniSpan)
            : notice.attached ? notice.compactPlayerWidth : 404
        availableHeight: notice.availableHeight
        entrance: notice.cardEntrance
        expansion: notice.detailAmount
        detailProgress: notice.detailProgress
        dismissible: notice.active && opacity > 0.75
        onDismissed: notice.dismissed()
    }

    DockMiniPlayer {
        id: miniPlayer
        x: notice.miniBounds.x + (notice.miniBounds.width - width) / 2
        y: notice.miniBounds.y + (notice.miniBounds.height - height) / 2
        scale: Math.min(notice.miniBounds.width, notice.miniBounds.height) / width
        opacity: notice.miniPauseExpired ? 1 - Motion.smooth((notice.miniRetreat - 0.12) / 0.68)
            : Motion.smooth((notice.splitProgress - 0.25) / 0.33)
        visible: opacity > 0.001
        enabled: notice.splitProgress > 0.92 && !notice.miniPauseExpired
        player: notice.media.player
        artwork: notice.media.artUrl
        artworkOpacity: notice.miniPauseExpired ? 1 : 1 - notice.renderer.lyricsView.coverAlpha
        progressOpacity: notice.miniPauseExpired ? 1 : 1 - notice.renderer.lyricsView.progressAlpha
        playing: notice.media.playing
        roundArtwork: notice.renderer.shaderAvailable
        host: notice.renderer.host
        progress: notice.renderer.lyricsView.duration > 0
            ? notice.renderer.lyricsView.position / notice.renderer.lyricsView.duration : 0
        progressPhase: notice.renderer.lyricsView.position / 1.8
        onTogglePlayback: notice.media.togglePlaying()
    }
}
