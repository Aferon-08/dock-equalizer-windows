import QtQuick
import "DockGeometry.js" as Geometry
import "MarkerMotion.js" as Motion

QtObject {
    id: queue
    required property bool suspended
    required property var motionCurve

    readonly property int recallDuration: 25000
    readonly property int archiveHandoffDuration: 1900
    readonly property int groupCloseDelay: 3500
    property var current: null
    property var pending: []
    property var recalls: []
    property var resumeNotice: null
    property bool reviewing: false
    property bool preserveRemaining: false
    property int remaining: 0
    property real expiresAt: 0
    property int nextId: 0
    property int requestedRecall: 0
    property bool waitingForRecalls: false
    property bool closing: false
    property real mergeProgress: 0

    // The current event changes at the start of a handoff. The surfaces keep
    // rendering the outgoing event until it has folded into its icon.
    property var handoff: null
    property real progress: 1
    readonly property bool archiving: (handoff?.archiveId ?? 0) > 0
    readonly property real archiveLanding: 0.55
    readonly property real swapPoint: archiving ? 0.52 : 0.4
    readonly property real incomingLanding: archiving ? 0.89 : 0.86
    readonly property int queuedCount: pending.length + (resumeNotice ? 1 : 0)
    readonly property var displayedEvent: handoff && progress < swapPoint ? handoff.outgoing : current
    readonly property int displayedCount: handoff && progress < swapPoint ? handoff.counter : queuedCount
    readonly property real contentAmount: !handoff ? 1 : progress < swapPoint
        ? 1 - Motion.smooth(Geometry.phase(progress, 0.01, 0.28))
        : Motion.smooth(Geometry.phase(progress, archiving ? 0.73 : 0.65, 1))
    readonly property real iconAmount: !handoff ? 1 : progress < swapPoint
        ? 1 - Motion.smooth(Geometry.phase(progress, 0.06, 0.16))
        : Motion.smooth(Geometry.phase(progress, incomingLanding - 0.01, 0.98))
    readonly property real counterAmount: !handoff ? 1 : progress < swapPoint
        ? 1 - Motion.smooth(Geometry.phase(progress, swapPoint - 0.10, swapPoint))
        : Motion.smooth(Geometry.phase(progress, incomingLanding - 0.08, 0.97))

    onSuspendedChanged: updateExpiry()
    onRecallsChanged: {
        scheduleRecallExpiry()
        if (waitingForRecalls && recalls.length === 0)
            updateExpiry()
    }

    function makeEvent(entry) {
        return Object.assign({sentAt: new Date()}, entry, {eventId: ++nextId})
    }

    function sharesSensor(first, second) {
        return (first.liveBattery && second.liveBattery) || (first.liveWifi && second.liveWifi)
    }

    function timeFor(event) {
        return event.kind === "app" || event.kind === "regular" ? 7000 : 9000
    }

    function timeLeft() {
        return expiresAt > 0 ? Math.max(1, Math.ceil(expiresAt - Date.now())) : remaining
    }

    function pauseExpiry() {
        remaining = timeLeft()
        expiry.stop()
        expiresAt = 0
    }

    function updateExpiry() {
        if (suspended) {
            pauseExpiry()
            return
        }
        if (!current || handoff || closing || expiry.running)
            return
        if (waitingForRecalls) {
            if (queuedCount > 0)
                advance(current.eventId, true, true)
            else if (recalls.length === 0)
                startClosing()
            return
        }
        expiry.interval = Math.max(1, remaining)
        expiresAt = Date.now() + expiry.interval
        expiry.start()
    }

    function shortenForQueue() {
        if (!current || !queuedCount || reviewing || preserveRemaining || timeLeft() <= timeFor(current))
            return
        pauseExpiry()
        remaining = timeFor(current)
        updateExpiry()
    }

    function replace(entry) {
        slide.stop()
        stopClosing()
        handoff = null
        requestedRecall = 0
        resumeNotice = null
        pauseExpiry()
        const event = makeEvent(entry)
        setCurrent({event, remaining: pending.length > 0 ? timeFor(event) : 30000}, false)
        scheduleRecallExpiry()
        updateExpiry()
    }

    function enqueue(entry) {
        if (!current && !handoff) {
            replace(entry)
            return
        }
        if (current && !handoff && !closing && !reviewing && sharesSensor(current, entry)) {
            current = Object.assign({}, current, entry, {eventId: current.eventId})
            return
        }
        if (resumeNotice && sharesSensor(resumeNotice.event, entry)) {
            resumeNotice = {event: Object.assign({}, resumeNotice.event, entry,
                {eventId: resumeNotice.event.eventId}), remaining: resumeNotice.remaining}
            return
        }
        const next = pending.filter(event => !sharesSensor(event, entry))
        next.push(makeEvent(entry))
        pending = next.slice(-20)
        if (closeDelay.running)
            finishClosing()
        else if (waitingForRecalls)
            updateExpiry()
        else if (!handoff && !closing)
            shortenForQueue()
    }

    function nextNotice() {
        if (resumeNotice) {
            const next = {event: resumeNotice.event, remaining: resumeNotice.remaining, preserve: true}
            resumeNotice = null
            return next
        }
        if (!pending.length)
            return null
        const event = pending[0]
        pending = pending.slice(1)
        return {event: event, remaining: timeFor(event), preserve: false}
    }

    function setCurrent(next, recalled) {
        waitingForRecalls = false
        current = next?.event ?? null
        remaining = next?.remaining ?? 0
        preserveRemaining = next?.preserve ?? false
        reviewing = recalled
    }

    function beginHandoff(outgoing, next, count, archive, recallIndex) {
        pauseExpiry()
        progress = 0
        handoff = {outgoing, incoming: next.event, counter: count,
            archiveId: archive ? outgoing.eventId : 0, recallIndex}
        setCurrent(next, recallIndex >= 0)
        if (archive) {
            const arrival = Math.round(archiveHandoffDuration * archiveLanding)
            const first = {event: outgoing, expires: Date.now() + recallDuration + arrival}
            recalls = [first].concat(recalls.filter(entry => entry.event.eventId !== outgoing.eventId)).slice(0, 3)
        }
        if (recallIndex >= 0)
            removeRecall(next.event.eventId)
        slide.start()
    }

    function startClosing() {
        pauseExpiry()
        waitingForRecalls = false
        recallExpiry.stop()
        mergeProgress = 0
        closing = true
        mergePucks.start()
    }

    function stopClosing() {
        mergePucks.stop()
        closeDelay.stop()
        closing = false
        mergeProgress = 0
    }

    function finishClosing() {
        const count = queuedCount
        const next = nextNotice()
        stopClosing()
        if (next)
            beginHandoff(current, next, count, false, -1)
        else
            setCurrent(null, false)
    }

    function advance(expectedId, remember, animate) {
        if (!current || (expectedId !== undefined && current.eventId !== expectedId))
            return
        if (handoff || closing) {
            if (animate)
                return
            slide.stop()
            stopClosing()
            handoff = null
        }
        const count = queuedCount
        const next = nextNotice()
        if (animate && next) {
            beginHandoff(current, next, count, remember && !reviewing, -1)
        } else if (animate && recalls.length > 0) {
            if (remember) {
                pauseExpiry()
                remaining = 0
                waitingForRecalls = true
            } else {
                startClosing()
            }
        } else {
            pauseExpiry()
            setCurrent(next, false)
            if (!next)
                recalls = []
            else
                scheduleRecallExpiry()
            updateExpiry()
        }
    }

    function restore(eventId) {
        const index = recalls.findIndex(entry => entry.event.eventId === eventId && entry.expires > Date.now())
        if (index < 0 || closing)
            return
        if (handoff) {
            requestedRecall = eventId
            return
        }
        const count = queuedCount
        const event = recalls[index].event
        if (current && !reviewing)
            resumeNotice = {event: current, remaining: waitingForRecalls ? timeFor(current) : timeLeft()}
        beginHandoff(current, {event, remaining: timeFor(event)}, count, false, index)
    }

    function removeRecall(eventId) {
        recalls = recalls.filter(entry => entry.event.eventId !== eventId)
    }

    function scheduleRecallExpiry() {
        recallExpiry.stop()
        if (!closing && recalls.length) {
            recallExpiry.interval = Math.max(1, Math.ceil(Math.min(...recalls.map(entry => entry.expires)) - Date.now()))
            recallExpiry.start()
        }
    }

    readonly property Timer expiry: Timer {
        onTriggered: queue.advance(queue.current?.eventId, true, true)
    }

    readonly property Timer recallExpiry: Timer {
        onTriggered: {
            const now = Date.now()
            const live = queue.recalls.filter(entry => entry.expires > now)
            if (live.length === 0 && queue.waitingForRecalls && !queue.suspended)
                queue.startClosing()
            else
                queue.recalls = live
        }
    }

    readonly property DockTransition slide: DockTransition {
        target: queue
        property: "progress"
        from: 0
        to: 1
        duration: queue.archiving ? queue.archiveHandoffDuration : 1340
        curve: queue.motionCurve
        onFinished: {
            queue.handoff = null
            queue.shortenForQueue()
            queue.updateExpiry()
            const requested = queue.requestedRecall
            queue.requestedRecall = 0
            if (requested)
                queue.restore(requested)
        }
    }

    readonly property DockTransition mergePucks: DockTransition {
        target: queue
        property: "mergeProgress"
        from: 0
        to: 1
        duration: 1560
        curve: queue.motionCurve
        onFinished: {
            queue.recalls = []
            if (queue.queuedCount)
                queue.finishClosing()
            else
                closeDelay.start()
        }
    }

    readonly property Timer closeDelay: Timer {
        interval: queue.groupCloseDelay - queue.mergePucks.duration
        onTriggered: queue.finishClosing()
    }
}
