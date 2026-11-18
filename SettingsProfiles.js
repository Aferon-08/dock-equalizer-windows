.pragma library

const format = "dock-equalizer.settings"
const version = 1
var scopes = [
    {id: "all", name: "Все настройки"},
    {id: "dock", name: "Музыкальный док"},
    {id: "glass", name: "Стекло дока"},
    {id: "wallpaper", name: "Обои и питомец"}
]

const glassKeys = ["dockGlass", "glassOpacity", "glassRefraction", "glassBlur", "glassDarkening", "glassLight"]
const wallpaperKeys = [
    "proceduralWallpaper", "wallpaperMotion", "wallpaperDensity", "wallpaperGlass", "wallpaperIntro",
    "wallpaperMotionAmount", "paletteDuration", "wallpaperTexture", "wallpaperPet", "petSpeed", "petSplit",
    "petTwinDuration", "petTrailNear", "petTrailFar"
]
const expandedKeys = ["lyricsWidth", "voiceWidth", "voiceHeight", "expandDuration", "playerSpring"]
const lyricKeys = expandedKeys.concat(["compactWidth", "expandLyrics", "multivoice", "lyricFontSize", "lyricFade",
    "followDelay", "trailDelay", "mistDelay", "orbitRadius", "progressAmplitude", "progressWavelength", "progressThickness"])
const dockKeys = glassKeys.concat([
    "enabled", "width", "height", "gap", "sensitivity", "style", "mirrorLeft", "spectrumFade",
    "collapseDelay", "openDuration", "closeDuration", "spring", "fusionDuration", "outlineDuration",
    "lightFade", "lyrics"
], lyricKeys)

var materials = [
    {id: "clear", name: "Чистое стекло", description: "Прозрачный корпус и выраженное преломление",
        values: {dockGlass: true, glassOpacity: .18, glassRefraction: 1.5, glassBlur: 1.4, glassDarkening: .1, glassLight: 1.15}},
    {id: "matte", name: "Матовое стекло", description: "Рассеянный свет и мягкое размытие фона",
        values: {dockGlass: true, glassOpacity: .37, glassRefraction: .65, glassBlur: 6.4, glassDarkening: .24, glassLight: .75}},
    {id: "dark", name: "Тёмное стекло", description: "Глубокая тонировка и яркий музыкальный свет",
        values: {dockGlass: true, glassOpacity: .50, glassRefraction: .90, glassBlur: 3.8, glassDarkening: .60, glassLight: 1.2}},
    {id: "opaque", name: "Непрозрачное", description: "Сплошной корпус с обычным визуализатором",
        values: {dockGlass: false}}
]

var themes = [
    {id: "living", name: "Живое стекло", description: "Светлая линза, пружинный док и насыщенные обои",
        values: Object.assign({}, materials[0].values, {style: "wave", spring: 1.8, playerSpring: 1.5,
            progressAmplitude: 3.5, wallpaperDensity: "rich", wallpaperMotion: true,
            wallpaperMotionAmount: 1.15, wallpaperGlass: .82, petSpeed: 1, petSplit: true})},
    {id: "calm", name: "Тихий рабочий стол", description: "Матовый док, редкие фигуры и меньше движения",
        values: Object.assign({}, materials[1].values, {style: "wave", spring: .6, playerSpring: .55,
            progressAmplitude: 1.5, wallpaperDensity: "calm", wallpaperMotion: false,
            wallpaperMotionAmount: .45, wallpaperGlass: .65, petSpeed: .65, petSplit: false})},
    {id: "concert", name: "Вечерний концерт", description: "Тёмная линза и заметная реакция на музыку",
        values: Object.assign({}, materials[2].values, {style: "wave", sensitivity: 1.55, spring: 1.8,
            playerSpring: 1.3, progressAmplitude: 4.5, wallpaperDensity: "rich", wallpaperMotion: true,
            wallpaperGlass: .75, wallpaperMotionAmount: 1, petSpeed: 1.2, petSplit: true})}
]

function object(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value)
}

function owns(values, key) {
    return Object.prototype.hasOwnProperty.call(values || {}, key)
}

function allowed(plugin, key, scope) {
    if (!owns(plugin.settings, key) || key === "wallpaperRegenerate" || owns(plugin.secrets, key))
        return false
    if (scope === "glass") return glassKeys.includes(key)
    if (scope === "wallpaper") return wallpaperKeys.includes(key)
    if (scope === "dock") return dockKeys.includes(key)
    return scope === "all"
}

function disabledBy(key, settings) {
    if (key !== "dockGlass" && glassKeys.includes(key) && settings.dockGlass === false)
        return "dockGlass"
    if ((lyricKeys.includes(key) || key === "autoSpotify") && settings.lyrics === false)
        return "lyrics"
    if (expandedKeys.includes(key) && settings.expandLyrics === false)
        return "expandLyrics"
    if ((key === "voiceWidth" || key === "voiceHeight") && settings.multivoice === false)
        return "multivoice"
    if (key !== "proceduralWallpaper" && wallpaperKeys.includes(key) && settings.proceduralWallpaper === false)
        return "proceduralWallpaper"
    if (key === "wallpaperMotionAmount" && settings.wallpaperMotion === false)
        return "wallpaperMotion"
    if (key.startsWith("pet") && settings.wallpaperPet === false)
        return "wallpaperPet"
    if (key === "petTwinDuration" && settings.petSplit === false)
        return "petSplit"
    if (key === "musicPaletteStopDelay" && settings.musicPalette === false)
        return "musicPalette"
    return ""
}

function value(plugin, key, input) {
    if (!allowed(plugin, key, "all") || typeof input !== typeof plugin.settings[key]) return undefined
    const info = plugin.settingsInfo?.[key] || {}
    if (typeof input === "number") {
        if (!Number.isFinite(input)) return undefined
        return Math.max(info.min ?? -Infinity, Math.min(info.max ?? Infinity, input))
    }
    if (typeof input === "string") {
        return Array.isArray(info.choices) && info.choices.some(choice => choice.value === input)
            ? input : undefined
    }
    return typeof input === "boolean" ? input : undefined
}

function select(plugin, raw, scope) {
    const values = {}
    let skipped = 0
    if (!object(raw)) return {values, skipped}
    for (const key of Object.keys(raw)) {
        if (!allowed(plugin, key, scope)) {
            ++skipped
            continue
        }
        const normalized = value(plugin, key, raw[key])
        if (normalized === undefined) ++skipped
        else values[key] = normalized
    }
    return {values, skipped}
}

function profile(plugin, name, scope, raw) {
    const label = String(name || "").replace(/[\u0000-\u001f\u007f]+/g, " ").trim().slice(0, 60)
    const values = select(plugin, raw, scope).values
    return label && Object.keys(values).length ? {format, version, name: label, scope, values} : null
}

function parse(plugin, raw) {
    if (!object(raw) || raw.format !== format)
        return {error: "Это не профиль Dock Equalizer."}
    if (raw.version !== version)
        return {error: "Версия профиля " + String(raw.version) + " не поддерживается."}
    if (!scopes.some(scope => scope.id === raw.scope))
        return {error: "В профиле указана неизвестная область."}
    if (typeof raw.name !== "string")
        return {error: "У профиля отсутствует название."}
    const imported = profile(plugin, raw.name, raw.scope, raw.values)
    if (!imported) return {error: "В профиле нет подходящих настроек."}
    return {profile: imported, skipped: select(plugin, raw.values, raw.scope).skipped}
}

function matches(settings, values) {
    return Object.keys(values).every(key => Object.is(settings?.[key], values[key]))
}

function changes(current, proposed) {
    const before = {}, after = {}
    for (const key of Object.keys(proposed)) {
        if (Object.is(current[key], proposed[key])) continue
        before[key] = current[key]
        after[key] = proposed[key]
    }
    return {before, after}
}
