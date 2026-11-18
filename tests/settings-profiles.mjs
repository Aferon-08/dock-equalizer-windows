import assert from "node:assert/strict"
import fs from "node:fs"
import vm from "node:vm"

const read = path => fs.readFileSync(new URL(path, import.meta.url), "utf8")
const plugin = JSON.parse(read("../plugin.json"))
const ctx = vm.createContext({})
vm.runInContext(read("../SettingsProfiles.js").replace(/^\.pragma.*$/m, "")
    + "\nthis.examples = {materials, themes};", ctx)
for (const preset of [...ctx.examples.materials, ...ctx.examples.themes]) {
    const selected = ctx.select(plugin, preset.values, "all")
    assert.equal(selected.skipped, 0, preset.name)
    assert.equal(JSON.stringify(selected.values), JSON.stringify(preset.values), preset.name)
}
const calm = ctx.examples.themes.find(theme => theme.id === "calm")
const personal = {...plugin.settings, glassOpacity: .59, glassRefraction: 1.8, style: "bars", progressStyle: "plassglass"}
const found = ctx.changes(personal, calm.values)
const result = {...personal, ...found.after}
assert(ctx.matches(result, calm.values))
assert.deepEqual({...result, ...found.before}, personal, "Undo restores every touched setting")
const opaque = {...personal, ...ctx.examples.materials.at(-1).values}
assert.equal(opaque.glassOpacity, personal.glassOpacity)
assert.equal(opaque.glassRefraction, personal.glassRefraction)
assert.equal(opaque.dockGlass, false)
assert.equal(ctx.disabledBy("glassOpacity", opaque), "dockGlass")
assert.equal(ctx.disabledBy("dockGlass", opaque), "")
assert.equal(ctx.disabledBy("autoSpotify", {...personal, lyrics: false}), "lyrics")
assert.equal(ctx.disabledBy("voiceWidth", {...personal, expandLyrics: false}), "expandLyrics")
assert.equal(ctx.disabledBy("voiceHeight", {...personal, multivoice: false}), "multivoice")
assert.equal(ctx.disabledBy("progressWavelength", {...personal, expandLyrics: false}), "")
assert.equal(ctx.disabledBy("petTwinDuration", {...personal, petSplit: false}), "petSplit")
assert.equal(ctx.disabledBy("petSpeed", {...personal, proceduralWallpaper: false}), "proceduralWallpaper")
assert.equal(ctx.disabledBy("wallpaperRegenerate", {...personal, proceduralWallpaper: false}), "")

const profile = ctx.profile(plugin, "Мой док", "dock", personal)
assert.equal(profile.version, 1)
assert.equal(profile.values.style, "bars")
assert.equal(profile.values.progressStyle, "plassglass")
assert.equal(plugin.settings.progressStyle, "material")
assert.equal(ctx.value(plugin, "progressStyle", "unknown"), undefined)
for (const key of ["analysisDevice", "autoSpotify", "wallpaperRegenerate", "wallpaperMotion", "musicPalette"])
    assert(!Object.hasOwn(profile.values, key), key)
const payload = JSON.parse(JSON.stringify(profile))
Object.assign(payload.values, {token: "secret", unknownFutureOption: 3, width: 1e6, gap: "not a number"})
const imported = ctx.parse(plugin, payload)
assert.equal(imported.skipped, 3)
assert.equal(imported.profile.values.width, 320)
assert(!Object.hasOwn(imported.profile.values, "token"))
assert.equal(ctx.select(plugin, personal, "glass").values.glassOpacity, personal.glassOpacity)
const translated = {...plugin, settingsInfo: Object.fromEntries(Object.entries(plugin.settingsInfo)
    .map(([key, info]) => [key, {...info, group: "Translated"}]))}
for (const scope of ctx.scopes) {
    assert.equal(JSON.stringify(ctx.select(translated, personal, scope.id)),
        JSON.stringify(ctx.select(plugin, personal, scope.id)), scope.id)
}
const withSecrets = {...plugin, settings: {...plugin.settings, token: ""}, secrets: {token: {env: "TOKEN"}}}
assert(!Object.hasOwn(ctx.select(withSecrets, {...personal, token: "secret"}, "all").values, "token"))
assert.match(ctx.parse(plugin, {...payload, version: 99}).error, /не поддерживается/)
assert.match(ctx.parse(plugin, {settings: {dockGlass: true}}).error, /не профиль/)
console.log("PASS theme ranges, atomic undo, retained glass settings and scoped versioned profiles")
