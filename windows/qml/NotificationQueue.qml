import QtQuick
import "DockGeometry.js" as Geometry
import "MarkerMotion.js" as Motion

QtObject {
    id: queue
    required property bool suspended
    required property var motionCurve

    readonly property int recallDuration: 25000
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
    readonly property bool closing: closeGroup.running
    property real closeProgress: 0

    // The current event changes at the start of a handoff. The surfaces keep
    // rendering the outgoing event until it has folded into its icon.
    property var handoff: null
    property real progress: 1
    readonly property real swapPoint: 0.4
    readonly property int queuedCount: pending.length + (resumeNotice ? 1 : 0)
    readonly property var displayedEvent: handoff && progress < swapPoint ? handoff.outgoing : current
    readonly property int displayedCount: handoff && progress < swapPoint ? handoff.counter : queuedCount
    readonly property real contentAmount: !handoff ? 1 : progress < swapPoint
        ? 1 - Motion.smooth(Geometry.phase(progress, 0.01, 0.28))
        : Motion.smooth(Geometry.phase(progress, 0.65, 1))
    readonly property real iconAmount: !handoff ? 1 : progress < swapPoint
        ? 1 - Motion.smooth(Geometry.phase(progress, 0.06, 0.16))
        : Motion.smooth(Geometry.phase(progress, 0.85, 0.98))
    readonly property real counterAmount: !handoff ? 1 : progress < swapPoint
        ? 1 - Motion.smooth(Geometry.phase(progress, 0.30, swapPoint))
        : Motion.smooth(Geometry.phase(progress, 0.78, 0.97))

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
        closeGroup.stop()
        closeProgress = 0
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
        if (waitingForRecalls)
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
            const first = {event: outgoing, expires: Date.now() + recallDuration + 650}
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
        closeProgress = 0
        closeGroup.start()
    }

    function advance(expectedId, remember, animate) {
        if (!current || (expectedId !== undefined && current.eventId !== expectedId))
            return
        if (handoff || closing) {
            if (animate)
                return
            slide.stop()
            closeGroup.stop()
            handoff = null
            closeProgress = 0
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
        duration: 1340
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

    readonly property DockTransition closeGroup: DockTransition {
        target: queue
        property: "closeProgress"
        from: 0
        to: 1
        duration: 310
        curve: queue.motionCurve
        onFinished: {
            const count = queue.queuedCount
            const next = queue.nextNotice()
            queue.recalls = []
            if (next)
                queue.beginHandoff(queue.current, next, count, false, -1)
            else
                queue.setCurrent(null, false)
            queue.closeProgress = 0
        }
    }
}
