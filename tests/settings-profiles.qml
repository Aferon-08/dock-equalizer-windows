pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "." as Plugin

ShellRoot {
    id: test
    settings.watchFiles: false
    readonly property string scenario: Quickshell.env("PROFILE_SCENARIO")
    readonly property string folder: Quickshell.env("PROFILE_FIXTURE")
    property int step: 0
    property var imported: null
    property int skipped: -1

    function check(condition, label) {
        if (!condition) throw new Error(label)
    }

    function find(item, condition) {
        if (condition(item)) return item
        for (const child of item.children || []) {
            const result = find(child, condition)
            if (result) return result
        }
        return null
    }

    function click(item, label) {
        const button = find(item, child => child.text === label && typeof child.clicked === "function")
        check(button?.visible && button.enabled, "Button unavailable: " + label)
        button.clicked()
    }

    FileView {
        path: test.folder + "/plugin.json"
        onLoaded: {
            model.plugin = JSON.parse(text())
            model.settings = Object.assign({}, model.plugin.settings, {
                glassOpacity: .56, glassRefraction: 1.8, autoSpotify: false, futureSetting: 42
            })
            model.loaded = true
        }
    }

    QtObject {
        id: model
        property bool loaded: false
        property var plugin: ({settings: {}, settingsInfo: {}, groups: []})
        property var settings: ({})
        property int writes: 0
        property int notifications: 0
        onSettingsChanged: ++notifications
        function persist() { ++writes }
        function setSetting(key, value) {
            settings = Object.assign({}, settings, {[key]: value})
            persist()
            return true
        }
        property QtObject service: QtObject {
            property bool settingsPanelOpen: model.loaded
            property Plugin.SettingsEditor settingsEditor: Plugin.SettingsEditor {
                id: editor
                libraryPath: test.folder + "/state/sekaipop/profiles.json"
                readerPath: test.folder + "/settings-profile-read.py"
                onImportReady: (profile, count) => {
                    test.imported = profile
                    test.skipped = count
                }
            }
        }
    }

    Window {
        id: window
        width: 1140
        height: 940
        visible: true
        Plugin.SettingsPanel {
            id: panel
            anchors.fill: parent
            pst: model
            theme: ({surface: Qt.color("#152322"), ink: Qt.color("#ffffff"), accentCyan: Qt.color("#90ddcd")})
        }
    }

    Timer {
        interval: 30
        repeat: true
        running: true
        onTriggered: {
            if (!editor.ready || panel.mode !== "open") return
            try {
                if (test.scenario === "restore") {
                    test.check(editor.savedProfiles.length === 2, "Both rapid saves survived relaunch")
                    test.check(editor.savedProfiles[1].name === "Личный (2)", "Duplicate profile names are distinct")
                    test.check(editor.personalGlass?.glassOpacity === .56, "Personal glass survived relaunch")
                } else if (test.scenario === "future") {
                    test.check(!editor.libraryWritable, "Future library is not writable")
                    test.check(editor.message.includes("99"), "Unavailable version explained")
                    editor.saveProfile("Попытка замены", "all")
                    test.check(!editor.savedProfiles.length, "Incompatible library not replaced")
                } else if (test.step === 0) {
                    const row = test.find(panel, item => item.settingKey === "progressStyle")
                    const picker = test.find(row, item => item.valueRole === "value")
                    test.check(picker.currentValue === "material", "Material is the default with an old settings file")
                    picker.currentIndex = 1
                    picker.activated(1)
                    test.check(model.settings.progressStyle === "plassglass", "Progress style selected in the settings panel")
                    editor.undo()
                    test.check(model.settings.progressStyle === "material", "Undo restores progress style")
                    editor.change("dockGlass", false)
                    const original = model.settings
                    const writes = model.writes
                    const notifications = model.notifications
                    test.click(panel, "Матовое стекло")
                    test.check(model.settings.dockGlass && model.settings.glassBlur === 6.4
                        && model.settings.glassOpacity === .37, "Full material applied by the card")
                    test.check(model.writes === writes + 1 && model.notifications === notifications + 1,
                        "One host state change and persist for a preset")
                    test.check(editor.personalGlass.glassOpacity === .56, "Personal coefficients saved while glass was off")
                    test.click(panel, "↶")
                    test.check(model.settings.dockGlass === false && model.settings.glassOpacity === original.glassOpacity,
                        "One undo restored the prior material")

                    const opacity = test.find(panel, item => item.settingKey === "glassOpacity")
                    test.check(opacity?.disabledBy === "dockGlass", "Disabled reason exposed by the control")
                    test.click(opacity, "↺")
                    test.check(!model.settings.dockGlass && model.settings.glassOpacity === model.plugin.settings.glassOpacity,
                        "Individual reset usable with glass off")
                    editor.undo()
                    test.check(model.settings.glassOpacity === .56, "Individual reset can be undone")
                    test.click(panel, "Живое стекло")
                    test.click(panel, "Непрозрачное")
                    test.check(!model.settings.dockGlass && model.settings.glassOpacity === .18, "Opaque preset retains values")
                    test.click(panel, "Пользовательское")
                    test.check(model.settings.dockGlass && model.settings.glassOpacity === .56
                        && model.settings.glassRefraction === 1.8, "Custom glass back after multiple presets")

                    editor.beginGesture("sensitivity")
                    editor.change("sensitivity", 1.5)
                    editor.change("sensitivity", 1.7)
                    editor.change("sensitivity", 2)
                    editor.endGesture()
                    editor.undo()
                    test.check(model.settings.sensitivity === model.plugin.settings.sensitivity, "Whole drag undone")
                    const glass = test.find(panel, item => item.Accessible?.name === "Сбросить группу «Стекло дока»")
                    test.check(glass?.enabled, "Group reset available")
                    glass.clicked()
                    test.check(model.settings.glassRefraction === model.plugin.settings.glassRefraction, "Group reset applied")
                    editor.undo()
                    test.check(model.settings.glassRefraction === 1.8 && model.settings.glassOpacity === .56, "Group reset undone")

                    editor.saveProfile("Личный", "glass")
                    editor.saveProfile("Личный", "dock")
                    editor.exportProfile(Quickshell.env("EXPORT_PROFILE_URL"), editor.savedProfiles[0])
                    test.step = 1
                    return
                } else if (test.step === 1) {
                    if (editor.message !== "JSON профиля сохранён") return
                    const writes = model.writes
                    editor.readImport(Quickshell.env("IMPORT_PROFILE_URL"))
                    test.check(model.writes === writes, "Reading a file cannot apply it")
                    test.step = 2
                    return
                } else if (test.step === 2) {
                    if (!test.imported) return
                    test.check(test.skipped === 3 && !Object.prototype.hasOwnProperty.call(test.imported.values, "token"),
                        "Only recognized scoped settings imported")
                    test.check(model.settings.glassOpacity === .56, "Imported data only staged for comparison")
                    const review = test.find(window.contentItem, item => typeof item.text === "string"
                        && item.text.includes("Изменится настроек") && item.text.includes("пропущено полей"))
                    test.check(review?.visible, "Import opens a comparison with rejected field count")
                    test.click(window.contentItem, "Apply")
                    test.check(model.settings.glassOpacity === .34 && model.settings.futureSetting === 42
                        && !model.settings.autoSpotify && !model.settings.wallpaperRegenerate, "Scoped apply retains other values")
                    editor.undo()
                    test.check(model.settings.glassOpacity === .56, "Imported profile can be undone")
                }
                console.log("PASS profile " + test.scenario)
            } catch (error) {
                console.error("FAIL profile " + test.scenario + ": " + error)
            }
            Qt.quit()
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.error("FAIL profile timeout at " + test.step + ": " + panel.mode + " / " + editor.message)
            Qt.quit()
        }
    }
}
