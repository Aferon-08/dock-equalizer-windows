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
    property int foldedEventId: 0

    // The current event changes at the start of a handoff. The surfaces keep
    // rendering the outgoing event until it has folded into its icon.
    property var handoff: null
    property real progress: 1
    readonly property int queuedCount: pending.length + (resumeNotice ? 1 : 0)
    readonly property var displayedEvent: handoff && progress < 0.43
        ? handoff.outgoing : current ?? handoff?.outgoing ?? null
    readonly property int displayedCount: handoff && progress < 0.43 ? handoff.counter : queuedCount
    readonly property real cardAmount: !handoff ? 1 : progress < 0.43
        ? (handoff.outgoing ? 1 - Motion.smooth(Geometry.phase(progress, 0.01, 0.25)) : 0)
        : (handoff.incoming ? Motion.smooth(Geometry.phase(progress, 0.74, 0.99)) : 0)
    readonly property real iconAmount: handoff ? Geometry.phase(progress, 0.92, 1) : 1

    onSuspendedChanged: updateExpiry()
    onRecallsChanged: scheduleRecallExpiry()

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
        } else if (current && !handoff && !expiry.running) {
            expiry.interval = Math.max(1, remaining)
            expiresAt = Date.now() + expiry.interval
            expiry.start()
        }
    }

    function shortenForQueue() {
        if (!current || reviewing || preserveRemaining || timeLeft() <= timeFor(current))
            return
        pauseExpiry()
        remaining = timeFor(current)
        updateExpiry()
    }

    function replace(entry) {
        slide.stop()
        handoff = null
        progress = 1
        requestedRecall = 0
        resumeNotice = null
        pauseExpiry()
        current = makeEvent(entry)
        reviewing = false
        preserveRemaining = false
        remaining = pending.length > 0 ? timeFor(current) : 30000
        updateExpiry()
    }

    function enqueue(entry) {
        if (!current && !handoff) {
            replace(entry)
            return
        }
        if (current && !handoff && !reviewing && sharesSensor(current, entry)) {
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
        current = next?.event ?? null
        remaining = next?.remaining ?? 0
        preserveRemaining = next?.preserve ?? false
        reviewing = recalled
    }

    function beginHandoff(outgoing, next, count, archive, recallIndex) {
        pauseExpiry()
        const start = outgoing ? 0 : 0.43
        progress = start
        handoff = {outgoing, incoming: next?.event ?? null, counter: count,
            archiveId: archive ? outgoing.eventId : 0, recallIndex}
        setCurrent(next, recallIndex >= 0)
        if (archive) {
            const first = {event: outgoing, expires: Date.now() + recallDuration + 650}
            recalls = [first].concat(recalls.filter(entry => entry.event.eventId !== outgoing.eventId)).slice(0, 3)
        }
        if (recallIndex >= 0)
            removeRecall(next.event.eventId)
        slide.from = start
        slide.to = next ? 1 : 0.44
        slide.duration = outgoing ? (next ? 1560 : 660) : 870
        slide.start()
    }

    function advance(expectedId, remember, animate) {
        if (!current || (expectedId !== undefined && current.eventId !== expectedId))
            return
        if (handoff) {
            if (animate)
                return
            slide.stop()
            handoff = null
        }
        const outgoing = current
        const count = queuedCount
        const archive = remember && !reviewing
        const next = nextNotice()
        if (animate && (archive || next)) {
            beginHandoff(outgoing, next, count, archive, -1)
        } else {
            pauseExpiry()
            setCurrent(next, false)
            updateExpiry()
        }
    }

    function restore(eventId) {
        const index = recalls.findIndex(entry => entry.event.eventId === eventId && entry.expires > Date.now())
        if (index < 0)
            return
        if (handoff) {
            requestedRecall = eventId
            return
        }
        const count = queuedCount
        const event = recalls[index].event
        if (current && !reviewing)
            resumeNotice = {event: current, remaining: timeLeft()}
        beginHandoff(current, {event, remaining: timeFor(event)}, count, false, index)
    }

    function removeRecall(eventId) {
        recalls = recalls.filter(entry => entry.event.eventId !== eventId)
    }

    function scheduleRecallExpiry() {
        recallExpiry.stop()
        if (recalls.length) {
            recallExpiry.interval = Math.max(1, Math.ceil(Math.min(...recalls.map(entry => entry.expires)) - Date.now()))
            recallExpiry.start()
        }
    }

    readonly property Timer expiry: Timer {
        onTriggered: queue.advance(queue.current?.eventId, true, true)
    }

    readonly property Timer recallExpiry: Timer {
        onTriggered: queue.recalls = queue.recalls.filter(entry => entry.expires > Date.now())
    }

    readonly property DockTransition slide: DockTransition {
        target: queue
        property: "progress"
        curve: queue.motionCurve
        onFinished: {
            if (!queue.current)
                queue.foldedEventId = queue.handoff?.outgoing?.eventId ?? 0
            queue.handoff = null
            queue.progress = 1
            if (!queue.current)
                queue.setCurrent(queue.nextNotice(), false)
            queue.updateExpiry()
            const requested = queue.requestedRecall
            queue.requestedRecall = 0
            if (requested)
                queue.restore(requested)
        }
    }
}
