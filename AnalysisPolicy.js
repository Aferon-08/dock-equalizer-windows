.pragma library

var revision = 4
function identity(track) {
    const url = String(track.url || "")
    const spotify = url.match(/(?:spotify:track:|open\.spotify\.com\/(?:intl-[^/]+\/)?track\/)([A-Za-z0-9]{22})/)
    if (spotify) return "spotify:" + spotify[1]
    const video = url.match(/(?:[?&]v=|youtu\.be\/|\/shorts\/|\/embed\/)([A-Za-z0-9_-]{11})(?:[^A-Za-z0-9_-]|$)/)
    if (video && /^https?:\/\/(?:www\.|m\.|music\.)?(?:youtube\.com|youtu\.be)\//i.test(url)) return "youtube:" + video[1]
    return url || [track.artist, track.title, Math.round(track.duration || 0)].join("\u241f")
}
function signature(text) {
    let hash = 2166136261
    const normalized = String(text || "").trim().replace(/\r/g, "")
    for (let i = 0; i < normalized.length; ++i) hash = Math.imul(hash ^ normalized.charCodeAt(i), 16777619)
    return (hash >>> 0).toString(16)
}
function updateReason(result, multivoice, source, modelsReady, modelSnapshots) {
    if (!result || result.status === "error") return ""
    if (result.status === "missing") return "missing"
    const a = result.analysis || {}, voice = result.multivoice || {}
    if (result.status === "partial" || a.timings === "partial") return "timings"
    // User-imported documents are authoritative; manual regeneration is still
    // available from the dialog. A mere review flag is not an incomplete scan.
    if ((!a.revision || a.origin === "import") && !multivoice) return ""
    if (a.revision !== revision && a.origin !== "import") return "revision"
    if (a.origin !== "import" && source && a.sourceSignature !== signature(source)) return "source"
    const inputs = a.fingerprint || {}
    const activeSnapshot = (modelSnapshots || {})[multivoice ? "voices" : "timing"]
    if (a.origin !== "import" && inputs.modelSnapshot && activeSnapshot && inputs.modelSnapshot !== activeSnapshot
        && (!multivoice || modelsReady)) return "models"
    if (!multivoice || !modelsReady) return ""
    if (!a.revision || a.voices === "disabled" || a.voices === "unavailable") return "voices"
    if (a.state === "failed" || a.voices === "failed") return "failed"
    if (a.state === "partial" || voice.budgetLimited === true || voice.fullScan === false || a.textScanComplete === false)
        return "partial"
    return ""
}
function needed(result, multivoice, source, modelsReady, modelSnapshots) {
    return updateReason(result, multivoice, source, modelsReady, modelSnapshots) !== ""
}
