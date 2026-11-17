.pragma library

// Deterministic selection. A preference is retained while a plugin is disabled,
// and the returned reason makes the temporary fallback explicit to the user.
function resolve(slot, candidates, preferred) {
    if (!["dock", "wallpaper", "settings"].includes(slot))
        return {selected:"", preferred:"", state:"unsupported", candidates:[], message:"Unknown extension slot"}
    const ordered = candidates.slice().sort((a,b)=>a.id < b.id ? -1 : a.id > b.id ? 1 : 0)
    const ready = ordered.filter(c=>c.ready && c.enabled)
    const chosen = ready.find(c=>c.id===preferred) || ready[0]
    const selected = chosen ? chosen.id : ""
    const requested = preferred || ""
    const state = requested && requested!==selected ? "preferred-unavailable"
        : !selected ? "unavailable" : requested ? "selected" : ready.length>1 ? "conflict" : "automatic"
    const message = state==="preferred-unavailable" ? "Preferred plugin is unavailable; using " + (selected || "the shell default")
        : state==="conflict" ? "Several plugins request this surface. Automatic choice: " + selected + ". Choose a provider below."
        : selected ? "Active provider: " + selected : "No enabled provider; using the shell default"
    return {selected, preferred:requested, state, candidates:ordered, message}
}
