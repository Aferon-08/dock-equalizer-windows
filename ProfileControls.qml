pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import "SettingsProfiles.js" as Profiles

ColumnLayout {
    id: root
    required property var editor
    required property color ink
    required property color accent
    required property color surface

    Label {
        text: "Личные профили"
        color: root.ink
        font.bold: true
        Layout.topMargin: 6
    }
    RowLayout {
        Layout.fillWidth: true
        SettingsAction {
            ink: root.ink; accent: root.accent; surface: root.surface
            text: "Сохранить текущие"
            enabled: root.editor.ready && root.editor.libraryWritable
            onClicked: { profileName.text = ""; saveDialog.open() }
        }
        SettingsAction {
            ink: root.ink; accent: root.accent; surface: root.surface
            text: root.editor.importBusy ? "Читаем профиль…" : "Импортировать JSON"
            enabled: root.editor.ready && !!root.editor.readerPath && !root.editor.importBusy
            onClicked: openFile.open()
        }
    }
    RowLayout {
        Layout.fillWidth: true
        visible: saved.count > 0
        ComboBox {
            id: saved
            Layout.fillWidth: true
            Layout.minimumWidth: 90
            model: root.editor.savedProfiles
            textRole: "name"
            Accessible.name: "Сохранённый профиль"
            readonly property var doc: currentIndex >= 0 ? root.editor.savedProfiles[currentIndex] : null
        }
        SettingsAction {
            ink: root.ink; accent: root.accent; surface: root.surface
            text: "Сравнить"
            enabled: !!saved.doc
            onClicked: comparison.showProfile(saved.doc, 0)
        }
        SettingsAction {
            ink: root.ink; accent: root.accent; surface: root.surface
            text: "Экспортировать"
            enabled: !!saved.doc
            onClicked: { saveFile.doc = saved.doc; saveFile.open() }
        }
        ToolButton {
            text: "×"
            font.pixelSize: 22
            Accessible.name: "Удалить сохранённый профиль"
            ToolTip.visible: hovered
            ToolTip.text: Accessible.name
            enabled: !!saved.doc && root.editor.libraryWritable
            onClicked: { removeDialog.profileName = saved.doc.name; removeDialog.open() }
        }
    }

    FileDialog {
        id: openFile
        title: "Импортировать профиль Dock Equalizer"
        nameFilters: ["Профиль JSON (*.json)"]
        onAccepted: root.editor.readImport(String(selectedFile))
    }
    FileDialog {
        id: saveFile
        property var doc: null
        title: "Сохранить профиль Dock Equalizer"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "json"
        nameFilters: ["Профиль JSON (*.json)"]
        onAccepted: root.editor.exportProfile(String(selectedFile), doc)
    }
    Dialog {
        id: saveDialog
        anchors.centerIn: Overlay.overlay
        width: Math.min(450, (parent?.width || 490) - 32)
        title: "Сохранить личный профиль"
        modal: true
        standardButtons: Dialog.Save | Dialog.Cancel
        onAccepted: root.editor.saveProfile(profileName.text, saveScope.currentValue)

        contentItem: ColumnLayout {
            spacing: 10
            TextField {
                id: profileName
                Layout.fillWidth: true
                placeholderText: "Название профиля"
                maximumLength: 60
                onAccepted: { if (text.trim()) saveDialog.accept() }
            }
            ComboBox {
                id: saveScope
                Layout.fillWidth: true
                model: Profiles.scopes
                textRole: "name"
                valueRole: "id"
                Accessible.name: "Область сохранения"
            }
        }
    }
    Dialog {
        id: comparison
        property var doc: null
        property int skipped: 0
        readonly property var values: doc
            ? Profiles.select(root.editor.state.plugin, doc.values, applyScope.currentValue || doc.scope).values : ({})
        readonly property var difference: doc ? Profiles.changes(root.editor.state.settings, values) : ({before:{},after:{}})
        readonly property var keys: Object.keys(difference.after)
        anchors.centerIn: Overlay.overlay
        width: Math.min(600, (parent?.width || 640) - 32)
        title: doc?.name || "Сравнение профиля"
        modal: true
        standardButtons: Dialog.Apply | Dialog.Cancel
        onApplied: {
            root.editor.applyPreset({name: doc.name, values})
            close()
        }

        function showProfile(profile, ignored) {
            doc = profile
            skipped = ignored
            applyScope.currentIndex = Profiles.scopes.findIndex(scope => scope.id === profile.scope)
            open()
        }

        function summary(key, value) {
            const info = root.editor.state.plugin.settingsInfo[key] || {}
            if (typeof value === "boolean") return value ? "Вкл." : "Выкл."
            if (typeof value === "number") return value.toLocaleString(Qt.locale(), "f", info.step < 1 ? 2 : 0)
                + (info.unit ? " " + info.unit : "")
            return info.choices?.find(choice => choice.value === value)?.label || String(value ?? "—")
        }

        contentItem: ColumnLayout {
            spacing: 10
            ComboBox {
                id: applyScope
                Layout.fillWidth: true
                model: Profiles.scopes
                textRole: "name"
                valueRole: "id"
                Accessible.name: "Область применения"
            }
            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: (comparison.keys.length ? "Изменится настроек: " + comparison.keys.length : "Текущие настройки совпадают")
                    + (comparison.skipped ? " · пропущено полей: " + comparison.skipped : "")
                color: root.accent
            }
            ListView {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(280, comparison.keys.length * 42)
                clip: true
                model: comparison.keys
                delegate: Label {
                    required property string modelData
                    width: ListView.view.width
                    height: 42
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    text: (root.editor.state.plugin.settingsInfo[modelData]?.label || modelData) + "\n"
                        + comparison.summary(modelData, comparison.difference.before[modelData]) + " → "
                        + comparison.summary(modelData, comparison.difference.after[modelData])
                }
            }
        }
    }
    Dialog {
        id: removeDialog
        property string profileName: ""
        anchors.centerIn: Overlay.overlay
        title: "Удалить сохранённый профиль?"
        modal: true
        standardButtons: Dialog.Yes | Dialog.Cancel
        Label { text: removeDialog.profileName; textFormat: Text.PlainText }
        onAccepted: root.editor.removeProfile(profileName)
    }
    Connections {
        target: root.editor
        function onImportReady(profile, skipped) { comparison.showProfile(profile, skipped) }
    }
}
