.pragma library

// The core manifest API and the optional surface contracts evolve separately.
// A future host may offer multiple revisions by advertising each one it supports.
var required = Object.freeze({
    dock: "native-dock-v1",
    wallpaper: "native-wallpaper-v1",
    settings: "native-settings-v1"
})
function resolve(host) {
    const advertised = host && Array.isArray(host.capabilities) ? host.capabilities : []
    const supported = {}, missing = []
    for (const slot of Object.keys(required)) {
        supported[slot] = advertised.includes(required[slot])
        if (!supported[slot]) missing.push(required[slot])
    }
    const api = host ? host.apiVersion : undefined
    return { api: Number.isInteger(api) && api > 0 ? api : null, supported, missing,
        paletteLease: advertised.includes("transient-palette-v1"),
        state: missing.length === 0 ? "ready" : missing.length < Object.keys(required).length ? "degraded" : "unsupported" }
}
