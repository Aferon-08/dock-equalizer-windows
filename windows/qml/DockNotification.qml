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
    required property var motionCurve
    required property bool springMotion
    required property bool allowed
    required property bool clearForDetails
    required property bool attached
    required property bool paused
    required property string trackKey
    required property int miniPauseDelay
    required property real topInset
    required property real availableHeight
    required property point callArtworkCenter
    required property real callArtworkSize
    required property real callArtworkAmount
    required property real callMusicSeparation
    property real callSpan: 0
    property bool suspended: false
    property bool transferred: false
    property rect compactSlot: Qt.rect(0, 0, 0, 0)

    signal dismissed(int eventId)

    readonly property bool active: allowed && !suspended && !transferred && !!event
    readonly property string miniProgressRenderer: miniPlayer.progressRenderer
    readonly property real miniProgressSpectrum: miniPlayer.progressSpectrum
    readonly property bool presenting: !transferred
        && (active || (!!lastEvent && (reveal > 0 || splitProgress > 0)) || retiringMini)
    readonly property bool usesCallLayout: callSpan > 0
    readonly property bool hasSideMusic: usesCallLayout && !!media.player
    readonly property bool widePlayer: attached && renderer.lyricsView.wide
    readonly property bool keepPausedMini: !usesCallLayout && !suspended && !transferred && paused && pauseHold.running
    readonly property bool canHoldPausedMini: !usesCallLayout && !suspended && !transferred
        && allowed && paused && splitProgress > 0.92 && !miniPauseExpired
    readonly property bool retiringMini: miniPauseExpired && miniRetreat < 1 && retiringBounds.width > 0
    readonly property bool splittingPlayer: allowed && !transferred && !miniPauseExpired
        && (keepPausedMini || (active && (usesCallLayout || (clearForDetails && widePlayer))))
    readonly property bool movingPlayer: splittingPlayer || (!active && splitProgress > 0)
    readonly property real compactHeight: 76
    readonly property real minimumCompactWidth: Math.min(maxCardWidth, card.minimumWidth)
    readonly property real miniDiameter: 66
    readonly property real miniGap: 16
    readonly property real miniSpan: miniDiameter + miniGap
    readonly property real detailsWidth: card.preferredWidth
    readonly property real detailsHeight: card.preferredHeight
    readonly property real maximumDetailsHeight: Math.max(compactHeight, detailsHeight, expandedHeight) + 16
    readonly property real compactPlayerWidth: Math.min(renderer.host.settings.compactWidth, renderer.lyricsView.maxBody)
    readonly property real maxCardWidth: Math.min(720, Math.max(1, width - 56 - callSpan
        - (widePlayer || hasSideMusic ? miniSpan : 0)))
    readonly property real surfaceWidth: usesCallLayout ? width
        : Math.max(expandedEnvelope.width, expandedWidth + miniSpan + 36)
    readonly property color accent: lastEvent?.accent ?? "#a4e7cc"
    readonly property rect expandedEnvelope: {
        if (usesCallLayout)
            return Qt.rect(cardLeft(detailsWidth), topInset, detailsWidth, detailsHeight)
        const footprintWidth = widePlayer
            ? Math.max(renderer.lyricsView.expandedBodySize.width, detailsWidth + miniSpan) + 36
            : Math.max(attached ? compactPlayerWidth : 0, detailsWidth)
        return Qt.rect((width - footprintWidth) / 2, topInset, footprintWidth, detailsHeight)
    }

    function cardLeft(cardWidth) {
        const centered = (width - cardWidth) / 2
        if (!usesCallLayout)
            return centered
        // Preserve the centered position whenever the left capsule and the
        // optional music control fit on their own sides.
        return Math.min(width - 20 - (hasSideMusic ? miniSpan : 0) - cardWidth,
            Math.max(centered, 20 + callSpan))
    }

    property var lastEvent: null
    property real reveal: active ? 1 : 0
    property real detailProgress: presenting && clearForDetails ? 1 : 0
    property real expandedWidth: detailsWidth
    property real expandedHeight: detailsHeight
    readonly property real splitProgress: transferred ? 0 : splitAmount
    property real splitAmount: 0
    property real mergeWeight: splittingPlayer || miniPauseExpired ? 0 : 1
    property real attachment: attached && !miniPauseExpired ? 1 : 0
    property real nudge: 0
    property bool miniPauseExpired: false
    property rect retiringBounds: Qt.rect(0, 0, 0, 0)
    property rect retiringDeckBounds: Qt.rect(0, 0, 0, 0)
    property real cardRetraction: !active && (keepPausedMini || miniPauseExpired) ? 1 : 0
    property real miniRetreat: miniPauseExpired ? 1 : 0
    Behavior on reveal { DockTransition { duration: notice.active ? 1020 : 560; curve: notice.motionCurve } }
    Behavior on detailProgress {
        DockTransition { duration: notice.clearForDetails ? 840 : 500; curve: notice.motionCurve }
    }
    Behavior on expandedWidth {
        DockTransition { duration: 420; curve: notice.motionCurve; standardEasing: Easing.InOutCubic }
    }
    Behavior on expandedHeight {
        DockTransition { duration: 380; curve: notice.motionCurve; standardEasing: Easing.InOutCubic }
    }
    Behavior on mergeWeight {
        DockTransition { duration: 180; curve: notice.motionCurve; standardEasing: Easing.InOutSine }
    }
    Behavior on attachment {
        DockTransition { duration: 360; curve: notice.motionCurve; standardEasing: Easing.InOutCubic }
    }
    Behavior on cardRetraction {
        DockTransition { duration: 490; curve: notice.motionCurve; standardEasing: Easing.InOutCubic }
    }
    Behavior on miniRetreat {
        DockTransition { duration: 450; curve: notice.motionCurve; standardEasing: Easing.InOutSine }
    }

    onSplittingPlayerChanged: {
        const current = splitAmount
        const target = splittingPlayer ? 1 : 0
        split.stop()
        if (current === target)
            return
        split.from = current
        split.to = target
        split.standardEasing = splittingPlayer ? Easing.InOutSine : Easing.OutQuad
        split.start()
    }
    DockTransition {
        id: split; target: notice; property: "splitAmount"; duration: 1060
        curve: notice.motionCurve
    }

    function beginPauseHold() {
        if (canHoldPausedMini && !pauseHold.running)
            pauseHold.start()
    }

    function resetPauseHold() {
        pauseHold.stop()
        miniPauseExpired = false
    }

    onCanHoldPausedMiniChanged: beginPauseHold()
    onSuspendedChanged: if (suspended) resetPauseHold()
    onUsesCallLayoutChanged: if (usesCallLayout) resetPauseHold()
    onTransferredChanged: {
        if (transferred) {
            resetPauseHold()
            lastEvent = null
        } else if (event) {
            lastEvent = event
        }
    }
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
        if (!event || transferred)
            return
        lastEvent = event
        if (springMotion && active && attached && !widePlayer)
            attention.restart()
    }
    onSpringMotionChanged: if (!springMotion) {
        attention.stop()
        nudge = 0
    }
    SequentialAnimation {
        id: attention
        DockTransition {
            target: notice; property: "nudge"; to: 4; duration: 90
            curve: notice.motionCurve; standardEasing: Easing.OutCubic
        }
        DockTransition {
            target: notice; property: "nudge"; to: -2.5; duration: 120
            curve: notice.motionCurve; standardEasing: Easing.InOutSine
        }
        DockTransition {
            target: notice; property: "nudge"; to: 1.2; duration: 95
            curve: notice.motionCurve; standardEasing: Easing.InOutSine
        }
        DockTransition {
            target: notice; property: "nudge"; to: 0; duration: 115
            curve: notice.motionCurve; standardEasing: Easing.OutCubic
        }
    }

    readonly property real coverAmount: movingPlayer
        ? Motion.smooth((splitProgress - 0.04) / 0.65) : Motion.smooth((reveal - 0.06) / 0.52)
    readonly property real detailAmount: Motion.travel(detailProgress / 0.86)
    readonly property real detailSpring: Geometry.recoil(Geometry.phase(detailProgress, 0.70, 1), springMotion)
    readonly property real extruded: Motion.smooth((splitProgress - 0.10) / 0.68)
    readonly property real extraPlayerWidth: Math.max(0, expandedWidth + miniSpan - renderer.playerHousing.width) * extruded
    readonly property real releaseRecoil: Geometry.recoil((splitProgress - 0.76) / 0.24, springMotion)
    readonly property real mergeRecoil: mergeWeight * Geometry.recoil((0.39 - splitProgress) / 0.39, springMotion)
    readonly property real bodyTaper: usesCallLayout ? renderer.playerTaper * (1 - coverAmount)
        : Math.max(Geometry.taper(cardRetraction),
            Geometry.mix(Geometry.taper(1 - reveal), renderer.playerTaper, attachment))
    readonly property real bodyRadius: {
        const radius = Geometry.mix(compactHeight / 2, 36, detailAmount)
        return usesCallLayout ? Geometry.mix(renderer.radius, radius, coverAmount)
            : Geometry.mix(radius, Geometry.mix(renderer.radius, radius, coverAmount), attachment)
    }
    readonly property rect bodyBounds: {
        const height = Geometry.mix(compactHeight, expandedHeight, detailAmount) + 9 * detailSpring
        const cardWidth = (usesCallLayout ? Math.min(expandedWidth, maxCardWidth) : expandedWidth) + 14 * detailSpring
        const compactWidth = compactSlot.width > 0 ? Math.min(cardWidth, compactSlot.width) : cardWidth
        const compactX = compactSlot.width > 0
            ? Math.max(compactSlot.x, Math.min(cardLeft(compactWidth), compactSlot.x + compactSlot.width - compactWidth))
            : cardLeft(compactWidth)
        const cardBounds = Qt.rect(Geometry.mix(compactX, cardLeft(cardWidth), detailAmount), topInset,
            Geometry.mix(compactWidth, cardWidth, detailAmount), height)
        const body = retiringMini ? retiringDeckBounds : renderer.playerHousing
        if (usesCallLayout) {
            const morph = Geometry.arrival(Geometry.phase(splitProgress, 0.04, 1), springMotion ? 0.08 : 0)
            return Geometry.mixRect(body, cardBounds, morph)
        }
        const solo = Geometry.settleHousing(Geometry.pullToEdge(cardBounds, 1 - reveal, 0, 0), reveal, springMotion)
        const widthTaken = miniSpan * Motion.smooth((splitProgress - 0.1) / 0.78)
        const extra = extraPlayerWidth
            + (widePlayer ? 0 : Math.max(0, cardWidth - body.width) * coverAmount) + 14 * detailSpring * extruded
        const positionCompact = compactSlot.width > 0 && (compactWidth < cardWidth || compactX !== cardLeft(compactWidth))
            ? coverAmount * (1 - detailAmount) : 0
        const playerBounds = Qt.rect(Geometry.mix(body.x - extra / 2 + nudge * coverAmount - 10 * mergeRecoil,
            compactX, positionCompact), body.y,
            Geometry.mix(Math.max(1, body.width + extra - widthTaken - 4 * releaseRecoil + 20 * mergeRecoil),
                compactWidth, positionCompact),
            Geometry.mix(body.height, height, coverAmount) + 9 * mergeRecoil)
        const housing = Geometry.mixRect(solo, playerBounds, attachment)
        return cardRetraction > 0 ? Geometry.pullToEdge(housing, cardRetraction, 0, 0) : housing
    }

    function stretchAt(progress) {
        return Motion.smooth(Geometry.phase(progress, 0.34, 0.58))
            * (1 - Motion.smooth(Geometry.phase(progress, 0.72, 0.98)))
    }

    function blendAt(progress) {
        return 48 * Motion.smooth(Geometry.phase(progress, 0.16, 0.43))
            * (1 - Motion.smooth(Geometry.phase(progress, 0.70, 0.93)))
    }

    readonly property real splitStretch: stretchAt(splitProgress)
    readonly property real splitBlend: blendAt(splitProgress)
    readonly property real miniAmount: usesCallLayout ? callMusicSeparation : splitProgress
    readonly property real miniStretch: stretchAt(miniAmount)
    readonly property real miniRecoil: Geometry.recoil(Geometry.phase(miniAmount, 0.76, 1), springMotion)
    readonly property real callArtworkRoundness: Motion.smooth(Geometry.phase(miniAmount, 0.04, 0.78))
    readonly property point miniCenter: {
        if (usesCallLayout) {
            // The cover starts in the compact track row and stays with the
            // same capsule when an expanded call makes room for a notice.
            const travel = Motion.travel(Geometry.phase(miniAmount, 0.12, 0.94))
            const edge = bodyBounds.x + bodyBounds.width + miniGap + miniDiameter / 2
            return Qt.point(Geometry.mix(callArtworkCenter.x, edge, travel) + 10 * miniRecoil,
                Geometry.mix(callArtworkCenter.y, bodyBounds.y + 35, travel) + 7 * miniStretch - 4 * miniRecoil)
        }
        const body = renderer.playerHousing
        const right = body.x + body.width + extraPlayerWidth / 2
        return Qt.point(right - Geometry.mix(miniDiameter * 0.78, miniDiameter / 2, extruded)
            + 6 * miniStretch + 11 * releaseRecoil,
            body.y + 47 + 6 * miniStretch - 4 * releaseRecoil)
    }
    readonly property rect miniBounds: {
        if (suspended || (!usesCallLayout && (transferred || !lastEvent)))
            return Qt.rect(0, 0, 0, 0)
        if (miniPauseExpired)
            return retiringMini ? Geometry.pullToEdge(retiringBounds, miniRetreat, 0, 0) : Qt.rect(0, 0, 0, 0)
        const growth = Motion.smooth(Geometry.phase(miniAmount, 0.08, 0.63))
        if (growth < 0.001)
            return Qt.rect(0, 0, 0, 0)
        const span = miniDiameter * growth
        const horizontal = span * (1 + 0.17 * miniStretch + 0.095 * miniRecoil)
        const vertical = span * (1 - 0.12 * miniStretch - 0.065 * miniRecoil)
        return Qt.rect(miniCenter.x - horizontal / 2, miniCenter.y - vertical / 2, horizontal, vertical)
    }
    readonly property real miniBlend: miniPauseExpired ? 0 : blendAt(miniAmount) * (1 - cardRetraction)
    readonly property rect neckBounds: connectingNeck(miniBounds, miniBlend, false)

    function connectingNeck(capsule, blend, left) {
        const edge = left ? bodyBounds.x : bodyBounds.x + bodyBounds.width
        const gap = left ? edge - capsule.x - capsule.width : capsule.x - edge
        if (capsule.width <= 0 || blend <= 0 || gap > blend / 2)
            return Qt.rect(0, 0, 0, 0)
        const distance = Math.max(0, gap)
        const height = 2 * Math.max(3, blend * 0.46 - distance * 0.7)
        return Qt.rect(edge - 7 - (left ? distance : 0), capsule.y + (capsule.height - height) / 2,
            distance + 14, height)
    }

    readonly property real playerOpacity: miniPauseExpired ? 0 : (1 - cardRetraction) * (movingPlayer
        ? 1 : 1 - coverAmount)
    readonly property real cardEntrance: usesCallLayout
        ? Math.min(reveal, Geometry.phase(splitProgress, 0.31, 0.97))
        : movingPlayer ? Math.min(reveal, splitProgress) : reveal

    function textLayout() {
        return card.textLayout()
    }

    visible: !suspended && (presenting || (usesCallLayout && callArtworkAmount > 0))

    DockNotificationContent {
        id: card
        motionCurve: notice.motionCurve
        springMotion: notice.springMotion
        x: notice.bodyBounds.x
        y: notice.bodyBounds.y
        width: notice.bodyBounds.width
        height: notice.bodyBounds.height
        opacity: 1 - Motion.smooth(notice.cardRetraction / 0.45)
        visible: !notice.transferred && notice.cardEntrance > 0.27 && opacity > 0.001
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
        onDismissed: eventId => notice.dismissed(eventId)
    }

    DockMiniPlayer {
        id: miniPlayer
        x: (notice.usesCallLayout ? notice.miniCenter.x : notice.miniBounds.x + notice.miniBounds.width / 2) - width / 2
        y: (notice.usesCallLayout ? notice.miniCenter.y : notice.miniBounds.y + notice.miniBounds.height / 2) - height / 2
        scale: notice.usesCallLayout ? Geometry.mix(notice.callArtworkSize / coverSize, 1, notice.callArtworkRoundness)
            : Math.min(notice.miniBounds.width, notice.miniBounds.height) / width
        opacity: notice.usesCallLayout ? Motion.smooth(notice.callArtworkAmount)
            : notice.miniPauseExpired ? 1 - Motion.smooth((notice.miniRetreat - 0.12) / 0.68)
                : Motion.smooth((notice.splitProgress - 0.25) / 0.33)
        visible: opacity > 0.001 && scale > 0
        enabled: notice.miniAmount > 0.92 && !notice.miniPauseExpired
        player: notice.media.player
        artwork: notice.media.artUrl
        artworkOpacity: notice.usesCallLayout || notice.miniPauseExpired ? 1 : 1 - notice.renderer.lyricsView.coverAlpha
        progressOpacity: notice.usesCallLayout ? Motion.smooth(Geometry.phase(notice.miniAmount, 0.30, 0.80))
            : notice.miniPauseExpired ? 1 : 1 - notice.renderer.lyricsView.progressAlpha
        playing: notice.media.playing
        roundArtwork: notice.renderer.shaderAvailable
        artworkRoundness: notice.usesCallLayout ? notice.callArtworkRoundness : 1
        host: notice.renderer.host
        progress: notice.renderer.lyricsView.duration > 0
            ? notice.renderer.lyricsView.position / notice.renderer.lyricsView.duration : 0
        progressPhase: notice.renderer.lyricsView.position / 1.8
        onTogglePlayback: notice.media.togglePlaying()
    }
}
