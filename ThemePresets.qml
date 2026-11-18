pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "SettingsProfiles.js" as Profiles

ColumnLayout {
    id: root
    required property var editor
    required property var settings
    required property color accent
    required property color ink
    required property color surface
    spacing: 8

    Label {
        text: "Темы оформления"
        color: root.accent
        font.pixelSize: 18
        font.bold: true
    }
    GridLayout {
        Layout.fillWidth: true
        columns: width >= 660 ? 3 : 1
        columnSpacing: 8
        rowSpacing: 8
        Repeater {
            model: Profiles.themes
            Button {
                id: themeButton
                required property var modelData
                readonly property var values: modelData.values
                readonly property bool selected: Profiles.matches(root.settings, values)
                Layout.fillWidth: true
                implicitHeight: 100
                padding: 14
                text: modelData.name
                enabled: root.editor.ready
                onClicked: root.editor.applyPreset(modelData)
                background: Rectangle {
                    radius: 16
                    color: Qt.alpha(Qt.tint(root.surface, Qt.alpha(root.accent,
                        themeButton.selected ? .24 : themeButton.hovered ? .16 : .06)), .83)
                    border.color: Qt.alpha(root.accent, themeButton.selected || themeButton.visualFocus ? .70 : .26)
                }
                contentItem: ColumnLayout {
                    spacing: 6
                    Rectangle {
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: 8
                        radius: 4
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0; color: root.accent }
                            GradientStop {
                                position: 1
                                color: Qt.tint(root.surface, Qt.alpha(root.accent, 1 - themeButton.values.glassDarkening))
                            }
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: themeButton.text
                        color: root.ink
                        font.bold: true
                        wrapMode: Text.Wrap
                    }
                    Label {
                        Layout.fillWidth: true
                        text: themeButton.modelData.description
                        color: Qt.alpha(root.ink, .72)
                        font.pixelSize: 12
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
    }
    Label {
        text: "Материал дока"
        color: root.ink
        font.bold: true
        Layout.topMargin: 4
    }
    Flow {
        Layout.fillWidth: true
        Layout.preferredHeight: childrenRect.height
        spacing: 6
        Repeater {
            model: Profiles.materials
            SettingsAction {
                id: materialButton
                required property var modelData
                text: modelData.name
                enabled: root.editor.ready
                selected: Profiles.matches(root.settings, modelData.values)
                ink: root.ink; accent: root.accent; surface: root.surface
                ToolTip.visible: hovered
                ToolTip.text: modelData.description
                onClicked: root.editor.applyPreset(modelData)
            }
        }
        SettingsAction {
            text: "Пользовательское"
            enabled: root.editor.ready && !!root.editor.personalGlass
            ink: root.ink; accent: root.accent; surface: root.surface
            selected: root.settings.dockGlass !== false
                && !Profiles.materials.some(preset => Profiles.matches(root.settings, preset.values))
            onClicked: root.editor.applyPersonal()
        }
    }
    Label {
        Layout.fillWidth: true
        text: "Режим «Непрозрачное» сохраняет параметры стекла."
        color: Qt.alpha(root.ink, .72)
        font.pixelSize: 12
        wrapMode: Text.Wrap
    }
    ProfileControls { Layout.fillWidth: true; editor: root.editor; ink: root.ink; accent: root.accent; surface: root.surface }
    Label {
        Layout.fillWidth: true
        visible: text !== ""
        text: root.editor.message
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: root.accent
    }
}
