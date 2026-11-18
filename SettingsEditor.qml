import QtQuick
import Quickshell.Io
import "SettingsProfiles.js" as Profiles

QtObject {
    id: root
    property var state: null
    property string libraryPath: ""
    property string readerPath: ""
    property var history: []
    property var gesture: null
    property var personalGlass: null
    property var savedProfiles: []
    property bool libraryRead: false
    property bool libraryWritable: true
    property string message: ""
    readonly property bool ready: !!state && state.loaded !== false && (!libraryPath || libraryRead)
    readonly property bool canUndo: history.length > 0
    readonly property bool importBusy: reader.running
    property string importUrl: ""
    property string exportPath: ""
    signal importReady(var profile, int skipped)

    function attach(next) {
        if (!next || state === next) return
        state = next
        history = []
        gesture = null
    }

    function preservePersonalGlass(patch) {
        if (!Object.keys(patch).some(key => key !== "dockGlass" && Profiles.allowed(state.plugin, key, "glass")))
            return
        const values = Profiles.select(state.plugin, state.settings, "glass").values
        values.dockGlass = true
        if (Profiles.materials.some(preset => Profiles.matches(values, preset.values))
            || (personalGlass && Profiles.matches(personalGlass, values))) return
        personalGlass = values
        storeLibrary()
    }

    function storeLibrary() {
        if (!libraryPath || !libraryRead || !libraryWritable) return
        library.setText(JSON.stringify({version: 1, personalGlass, profiles: savedProfiles}, null, 2) + "\n")
    }

    function push(before, after, label) {
        if (!Object.keys(after).length) return
        history = history.concat([{before, after, label}]).slice(-20)
    }

    function replace(settings) {
        if (typeof state.persist === "function") {
            state.settings = Object.assign({}, state.settings, settings)
            state.persist()
        } else {
            for (const key of Object.keys(settings)) state.setSetting(key, settings[key])
        }
    }

    function apply(values, label, record, preserveMaterial = false) {
        if (!state || state.loaded === false) return false
        const patch = Profiles.select(state.plugin, values, "all").values
        const change = Profiles.changes(state.settings, patch)
        if (!Object.keys(change.after).length) return false
        if (preserveMaterial) preservePersonalGlass(change.after)
        replace(change.after)
        if (record) push(change.before, change.after, label)
        return true
    }

    function applyPreset(preset) {
        if (!ready || !preset) return
        endGesture()
        if (apply(preset.values, preset.name, true, true)) message = "Применён профиль «" + preset.name + "»"
    }

    function applyPersonal() {
        if (!personalGlass) return
        endGesture()
        if (apply(personalGlass, "Пользовательское стекло", true)) message = "Личное стекло восстановлено"
    }

    function change(key, value) {
        if (!state || state.loaded === false) return
        if (key === "wallpaperRegenerate") {
            state.setSetting(key, value)
            return
        }
        const label = state.plugin.settingsInfo?.[key]?.label || key
        apply({[key]: value}, label, gesture?.key !== key)
    }

    function beginGesture(key) {
        if (!state) return
        endGesture()
        gesture = {key, value: state.settings[key]}
    }

    function endGesture() {
        if (!gesture || !state) return
        const key = gesture.key
        if (!Object.is(gesture.value, state.settings[key]))
            push({[key]: gesture.value}, {[key]: state.settings[key]}, state.plugin.settingsInfo?.[key]?.label || key)
        gesture = null
    }

    function reset(values, label) {
        endGesture()
        if (apply(values, label, true, true)) message = label
    }

    function undo() {
        endGesture()
        if (!state || !history.length) return
        const last = history[history.length - 1]
        history = history.slice(0, -1)
        const inverse = {}
        for (const key of Object.keys(last.before)) {
            if (Object.is(state.settings[key], last.after[key])) inverse[key] = last.before[key]
        }
        if (apply(inverse, last.label, false)) message = "Отменено «" + last.label + "»"
    }

    function saveProfile(name, scope) {
        if (!ready || !libraryWritable) return
        const selected = Profiles.profile(state.plugin, name, scope, state.settings)
        if (!selected) return
        const title = selected.name
        let suffix = 2
        while (savedProfiles.some(profile => profile.name === selected.name)) {
            selected.name = title.slice(0, 54) + " (" + suffix + ")"
            ++suffix
        }
        savedProfiles = savedProfiles.concat([selected])
        storeLibrary()
        message = "Сохранён профиль «" + selected.name + "»"
    }

    function readImport(url) {
        if (!ready || !readerPath || reader.running) return
        importUrl = url
        reader.running = true
    }

    function removeProfile(name) {
        if (!libraryWritable) return
        savedProfiles = savedProfiles.filter(profile => profile.name !== name)
        storeLibrary()
        message = "Профиль «" + name + "» удалён"
    }

    function exportProfile(url, profile) {
        if (!ready || !profile) return
        const checked = Profiles.parse(state.plugin, profile)
        if (!checked.profile) {
            message = checked.error
            return
        }
        try {
            const local = String(url)
            if (!local.startsWith("file:///")) throw new Error("local path")
            exportPath = decodeURIComponent(local.slice("file://".length))
        } catch (_) {
            message = "Выберите локальный файл."
            return
        }
        exporter.setText(JSON.stringify(checked.profile, null, 2) + "\n")
    }

    property FileView library: FileView {
        path: root.state ? root.libraryPath : ""
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text())
                if (data.version !== 1) {
                    root.libraryWritable = false
                    root.libraryRead = true
                    root.message = "Версия файла личных профилей " + String(data.version) + " не поддерживается."
                    return
                }
                if (!Array.isArray(data.profiles)) throw new Error("profiles")
                const material = Profiles.select(root.state.plugin, data.personalGlass, "glass").values
                if (Object.keys(material).length) root.personalGlass = material
                root.savedProfiles = data.profiles.map(profile => Profiles.parse(root.state.plugin, profile).profile)
                    .filter(profile => !!profile)
            } catch (_) {
                root.libraryWritable = false
                root.message = "Личные профили не удалось прочитать."
            }
            root.libraryRead = true
        }
        onLoadFailed: error => {
            root.libraryRead = true
            if (error !== FileViewError.FileNotFound) {
                root.libraryWritable = false
                root.message = "Файл личного профиля недоступен."
            }
        }
        onSaveFailed: root.message = "Не удалось сохранить личные профили."
    }
    property FileView exporter: FileView {
        path: root.exportPath
        preload: false
        atomicWrites: true
        printErrors: false
        onSaved: root.message = "JSON профиля сохранён"
        onSaveFailed: root.message = "Не удалось записать JSON профиля."
    }
    property Process reader: Process {
        command: ["python3", root.readerPath, root.importUrl]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const reply = JSON.parse(text)
                    const imported = reply.error ? reply : Profiles.parse(root.state.plugin, reply.document)
                    if (imported.profile) root.importReady(imported.profile, imported.skipped)
                    else root.message = imported.error
                } catch (_) {
                    root.message = "Не удалось прочитать профиль."
                }
            }
        }
    }
}
