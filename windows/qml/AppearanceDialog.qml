import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: panel
    required property var appearance
    required property var ownerWindow
    required property bool effectsAvailable
    required property bool desktopGlassAvailable
    required property string desktopGlassStatus
    readonly property bool glassEnabled: appearance.values.dockGlass

    width: Math.min(460, ownerWindow.width)
    height: Math.min(implicitHeight, Math.max(160, ownerWindow.workArea.height - 56))
    x: Math.round((ownerWindow.width - width) / 2)
    y: Math.max(32, Math.min(ownerWindow.height + 8, ownerWindow.workArea.height - height - 16))
    popupType: Popup.Window
    focus: true
    closePolicy: Popup.CloseOnEscape
    title: "Оформление дока"
    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 140 } }
    exit: Transition { NumberAnimation { property: "opacity"; to: 0; duration: 110 } }

    contentItem: ScrollView {
        id: scroll
        clip: true
        contentWidth: availableWidth
        implicitHeight: fields.implicitHeight
        ColumnLayout {
            id: fields
            width: scroll.availableWidth
            spacing: 10

            Switch {
                text: "Стеклянное оформление"
                checked: panel.glassEnabled
                enabled: panel.effectsAvailable
                onToggled: panel.appearance.setGlassEnabled(checked)
            }
            Label {
                Layout.fillWidth: true
                text: "Используется упрощённое оформление."
                visible: !panel.effectsAvailable
                wrapMode: Text.WordWrap
            }
            Switch {
                text: "Преломлять фон рабочего стола"
                checked: panel.appearance.values.desktopGlass
                visible: panel.desktopGlassAvailable
                enabled: panel.glassEnabled
                onToggled: panel.appearance.setDesktopGlass(checked)
            }
            Label {
                Layout.fillWidth: true
                visible: panel.desktopGlassAvailable && panel.glassEnabled
                text: panel.appearance.values.desktopGlass && panel.desktopGlassStatus !== ""
                    ? panel.desktopGlassStatus
                    : "Windows может показать рамку захвата. Док исключается из снимков экрана, пока эффект активен."
                wrapMode: Text.WordWrap
                opacity: 0.8
            }
            Repeater {
                model: panel.appearance.sliders
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 2
                    enabled: panel.effectsAvailable && panel.glassEnabled

                    RowLayout {
                        Label {
                            Layout.fillWidth: true
                            text: modelData.label
                            wrapMode: Text.WordWrap
                        }
                        Label {
                            text: modelData.pixels
                                ? amount.value.toLocaleString(Qt.locale(), "f", 1) + " пкс"
                                : Math.round(amount.value * 100) + " %"
                            opacity: 0.8
                        }
                    }
                    Slider {
                        id: amount
                        Layout.fillWidth: true
                        from: modelData.minimum
                        to: modelData.maximum
                        stepSize: modelData.step
                        value: panel.appearance.values[modelData.key]
                        snapMode: Slider.SnapAlways
                        Accessible.name: modelData.label
                        onMoved: panel.appearance.setNumber(modelData.key, value)
                    }
                }
            }
        }
    }

    footer: DialogButtonBox {
        alignment: Qt.AlignRight
        Button {
            text: "Сбросить"
            DialogButtonBox.buttonRole: DialogButtonBox.ResetRole
            onClicked: panel.appearance.reset()
        }
        Button {
            text: "Закрыть"
            DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
        }
    }
}
