import QtQuick
import "DockGeometry.js" as Geometry
import "MarkerMotion.js" as Motion

Item {
    id: notice
    required property var event
    required property var wifi
    required property var renderer
    required property var media
    required property bool allowed
    required property bool clearForDetails
    required property bool attached
    required property bool paused
    required property string trackKey
    required property int miniPauseDelay
    required property real topInset

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
    readonly property real maximumDetailsHeight: 236
    readonly property real detailsHeight: lastEvent?.kind === "wifi" && (wifi.hasCounters || wifi.state === "loading")
        ? maximumDetailsHeight : 176
    readonly property real soloWidth: Math.min(450, width - 48)
    readonly property real miniDiameter: 66
    readonly property real miniGap: 16
    readonly property color accent: lastEvent?.accent ?? "#a4e7cc"
    readonly property rect expandedEnvelope: {
        const view = renderer.lyricsView
        const footprintWidth = widePlayer ? view.expandedBodySize.width + 36
            : attached ? Math.min(renderer.host.settings.compactWidth, view.maxBody) : soloWidth
        return Qt.rect((width - footprintWidth) / 2, topInset, footprintWidth, detailsHeight)
    }

    property var lastEvent: null
    property real reveal: active ? 1 : 0
    property real detailProgress: presenting && clearForDetails ? 1 : 0
    property real expandedHeight: detailsHeight
    property real splitProgress: splittingPlayer ? 1 : 0
    property real attachment: attached && !miniPauseExpired ? 1 : 0
    property real nudge: 0
    property bool miniPauseExpired: false
    property rect retiringBounds: Qt.rect(0, 0, 0, 0)
    property rect retiringDeckBounds: Qt.rect(0, 0, 0, 0)
    property real cardRetraction: !active && (keepPausedMini || miniPauseExpired) ? 1 : 0
    property real miniRetreat: miniPauseExpired ? 1 : 0
    Behavior on reveal { NumberAnimation { duration: 560; easing.type: Easing.InOutCubic } }
    Behavior on detailProgress { NumberAnimation { duration: 460; easing.type: Easing.InOutCubic } }
    Behavior on expandedHeight { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
    Behavior on splitProgress { NumberAnimation { duration: 1060; easing.type: Easing.InOutSine } }
    Behavior on attachment { NumberAnimation { duration: 360; easing.type: Easing.InOutCubic } }
    Behavior on cardRetraction { NumberAnimation { duration: 490; easing.type: Easing.InOutCubic } }
    Behavior on miniRetreat { NumberAnimation { duration: 450; easing.type: Easing.InOutSine } }

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
    readonly property real detailAmount: Motion.smooth(detailProgress)
    readonly property real releaseRecoil: Geometry.recoil((splitProgress - 0.76) / 0.24)
    readonly property real mergeRecoil: splittingPlayer ? 0 : Geometry.recoil((0.30 - splitProgress) / 0.30)
    readonly property real bodyTaper: Math.max(Geometry.taper(cardRetraction),
        Geometry.mix(Geometry.taper(1 - reveal), renderer.playerTaper, attachment))
    readonly property real bodyRadius: {
        const radius = Geometry.mix(compactHeight / 2, 36, detailAmount)
        return Geometry.mix(radius, Geometry.mix(renderer.radius, radius, coverAmount), attachment)
    }
    readonly property rect bodyBounds: {
        const height = Geometry.mix(compactHeight, expandedHeight, detailAmount)
        const solo = Geometry.pullToEdge(Qt.rect((width - soloWidth) / 2, topInset, soloWidth, height),
            1 - reveal, 0, 0)
        const body = retiringMini ? retiringDeckBounds : renderer.playerHousing
        const widthTaken = (miniDiameter + miniGap) * Motion.smooth((splitProgress - 0.1) / 0.78)
        const playerBounds = Qt.rect(body.x + nudge * coverAmount - 3 * mergeRecoil, body.y,
            Math.max(1, body.width - widthTaken - 4 * releaseRecoil + 8 * mergeRecoil),
            Geometry.mix(body.height, height, coverAmount) + 4 * Math.abs(mergeRecoil))
        const housing = Geometry.mixRect(solo, playerBounds, attachment)
        return cardRetraction > 0 ? Geometry.pullToEdge(housing, cardRetraction, 0, 0) : housing
    }

    readonly property rect miniBounds: {
        if (miniPauseExpired)
            return retiringMini ? Geometry.pullToEdge(retiringBounds, miniRetreat, 0, 0) : Qt.rect(0, 0, 0, 0)
        const growth = Motion.smooth((splitProgress - 0.08) / 0.55)
        if (growth < 0.001)
            return Qt.rect(0, 0, 0, 0)
        const extruded = Motion.smooth((splitProgress - 0.10) / 0.68)
        const stretch = Motion.smooth((splitProgress - 0.34) / 0.24)
            * (1 - Motion.smooth((splitProgress - 0.72) / 0.26))
        const body = renderer.playerHousing
        const span = miniDiameter * growth
        const horizontal = span * (1 + 0.17 * stretch + 0.095 * releaseRecoil)
        const vertical = span * (1 - 0.12 * stretch - 0.065 * releaseRecoil)
        const centerX = body.x + body.width - Geometry.mix(miniDiameter * 0.78, miniDiameter / 2, extruded)
            + 6 * stretch + 11 * releaseRecoil
        const centerY = body.y + 47 + 6 * stretch - 4 * releaseRecoil
        return Qt.rect(centerX - horizontal / 2, centerY - vertical / 2, horizontal, vertical)
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

    readonly property real squeeze: Motion.smooth((splitProgress - 0.04) / 0.55)
    readonly property real playerOpacity: miniPauseExpired ? 0 : (1 - cardRetraction) * (movingPlayer
        ? 1 - Motion.smooth((splitProgress - 0.42) / 0.28) : 1 - coverAmount)
    readonly property size playerScale: Qt.size(Geometry.mix(1, 0.078, squeeze), Geometry.mix(1, 0.22, squeeze))
    readonly property point playerOffset: {
        if (miniBounds.width <= 0)
            return Qt.point(0, 0)
        const body = renderer.playerHousing
        const towardEdge = Motion.travel((splitProgress - 0.12) / 0.63)
        return Qt.point((miniBounds.x + miniBounds.width / 2 - body.x - body.width / 2) * towardEdge,
            (miniBounds.y + miniBounds.height / 2 - body.y - body.height / 2) * towardEdge)
    }
    readonly property real textOpacity: (1 - Motion.smooth(cardRetraction / 0.45)) * (movingPlayer
        ? Motion.smooth((splitProgress - 0.56) / 0.35) : Motion.smooth((reveal - 0.39) / 0.51))

    visible: presenting

    DockNotificationContent {
        x: notice.bodyBounds.x
        y: notice.bodyBounds.y
        width: notice.bodyBounds.width
        height: notice.bodyBounds.height
        opacity: notice.textOpacity
        visible: opacity > 0.001
        event: notice.lastEvent
        wifi: notice.wifi
        accent: notice.accent
        expansion: notice.detailAmount
        dismissible: notice.active && opacity > 0.75
        onDismissed: notice.dismissed()
    }

    DockMiniPlayer {
        id: miniPlayer
        x: notice.miniBounds.x + (notice.miniBounds.width - width) / 2
        y: notice.miniBounds.y + (notice.miniBounds.height - height) / 2
        scale: Math.min(notice.miniBounds.width, notice.miniBounds.height) / width
        opacity: notice.miniPauseExpired ? 1 - Motion.smooth((notice.miniRetreat - 0.12) / 0.68)
            : Motion.smooth((notice.splitProgress - 0.58) / 0.26)
        visible: opacity > 0.001
        enabled: notice.splitProgress > 0.92 && !notice.miniPauseExpired
        player: notice.media.player
        artwork: notice.media.artUrl
        playing: notice.media.playing
        roundArtwork: notice.renderer.shaderAvailable
        host: notice.renderer.host
        progress: notice.renderer.lyricsView.duration > 0
            ? notice.renderer.lyricsView.position / notice.renderer.lyricsView.duration : 0
        progressPhase: notice.renderer.lyricsView.position / 1.8
        onTogglePlayback: notice.media.togglePlaying()
    }
}
