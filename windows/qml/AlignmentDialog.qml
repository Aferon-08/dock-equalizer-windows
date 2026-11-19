import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs as Dialogs
import QtQuick.Layouts

Dialog {
    id: panel
    required property var controller
    required property var ownerWindow
    property string trackKey: ""
    property real trackDuration: 0
    property url audioFile: ""
    property string saveError: ""

    width: Math.min(520, ownerWindow.width)
    x: Math.round((ownerWindow.width - width) / 2)
    y: 40
    popupType: Popup.Window
    focus: true
    title: "Выравнивание лирики"

    function openForTrack(key, duration, lines) {
        if (!controller.busy && trackKey !== key) {
            trackKey = key
            trackDuration = duration
            audioFile = ""
            lyrics.text = ""
        }
        if (!controller.busy && !lyrics.text)
            lyrics.text = lines.map(line => line.text || "").filter(Boolean).join("\n")
        saveError = ""
        open()
    }

    contentItem: ColumnLayout {
        spacing: 10

        RowLayout {
            Button {
                text: "Выбрать аудиофайл…"
                enabled: !panel.controller.busy
                onClicked: audioPicker.open()
            }
            Label {
                Layout.fillWidth: true
                text: panel.audioFile.toString()
                    ? decodeURIComponent(panel.audioFile.toString().split("/").pop())
                    : "Выберите ту же запись песни"
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
            }
        }

        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(92, Math.min(190, panel.ownerWindow.workArea.height - 270))
            TextArea {
                id: lyrics
                placeholderText: "Вставьте готовый текст песни"
                placeholderTextColor: "#8bb0a4"
                textFormat: TextEdit.PlainText
                readOnly: panel.controller.busy
                wrapMode: TextEdit.Wrap
            }
        }

        Label {
            Layout.fillWidth: true
            text: panel.saveError || panel.controller.statusText
                || (panel.controller.ready ? "" : "При первой подготовке скачиваются модель и CPU-обработчик.")
            visible: text !== ""
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
        }
        ProgressBar {
            Layout.fillWidth: true
            visible: panel.controller.busy
            from: 0
            to: 1
            value: panel.controller.progress
            indeterminate: value <= 0
        }
        RowLayout {
            Button {
                visible: !panel.controller.ready
                text: "Подготовить модуль"
                enabled: !panel.controller.busy
                onClicked: {
                    panel.saveError = ""
                    panel.controller.prepare()
                }
            }
            Button {
                visible: panel.controller.ready
                text: "Выровнять"
                enabled: !panel.controller.busy && panel.audioFile.toString() !== "" && lyrics.text.trim() !== ""
                onClicked: {
                    panel.saveError = ""
                    panel.controller.align(panel.audioFile, lyrics.text, panel.trackKey, panel.trackDuration)
                }
            }
            Button {
                visible: panel.controller.busy
                text: "Отменить задание"
                onClicked: panel.controller.cancel()
            }
            Item { Layout.fillWidth: true }
            Button {
                visible: panel.controller.hasResult && !panel.controller.busy
                text: "Сохранить JSON…"
                onClicked: outputPicker.open()
            }
            Button {
                text: "Закрыть"
                onClicked: panel.close()
            }
        }
    }

    Dialogs.FileDialog {
        id: audioPicker
        parentWindow: panel.ownerWindow
        title: "Выбрать аудиозапись"
        nameFilters: ["Аудиофайлы (*.mp3 *.flac *.wav *.m4a *.ogg *.opus *.aac *.wma)"]
        onAccepted: panel.audioFile = selectedFile
    }
    Dialogs.FileDialog {
        id: outputPicker
        parentWindow: panel.ownerWindow
        title: "Сохранить лирику с таймингами"
        fileMode: Dialogs.FileDialog.SaveFile
        nameFilters: ["JSON Wordtime (*.json)"]
        defaultSuffix: "json"
        onAccepted: panel.saveError = panel.controller.save(selectedFile)
    }
}
