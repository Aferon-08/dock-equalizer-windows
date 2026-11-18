import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    required property var service
    required property color ink
    required property color accent
    property var status: ({})
    readonly property var result: service.audioSelfTest.result
    readonly property bool busy: service.audioSelfTest.running

    implicitHeight: content.implicitHeight + 24
    radius: 14
    color: Qt.alpha(accent, 0.07)
    border.color: Qt.alpha(accent, 0.16)

    function refresh() { status = service.audioStatus() }
    function signalState() {
        if (status.reason) return status.reason
        if (status.state === "idle") return "Захват включится при воспроизведении музыки."
        if (status.signal === "silence") return "Захват работает. На выходе тишина."
        if (status.signal === "audible") return "Захват получает звук."
        return "Ожидаем спектр с системного выхода."
    }

    Component.onCompleted: refresh()
    Timer {
        interval: 600
        repeat: true
        running: root.visible
        onTriggered: root.refresh()
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: 12
        spacing: 6

        Label {
            text: "Диагностика звука"
            color: root.ink
            font.bold: true
        }
        Label {
            Layout.fillWidth: true
            color: root.ink
            wrapMode: Text.Wrap
            text: root.signalState()
        }
        Label {
            Layout.fillWidth: true
            visible: text !== ""
            color: root.accent
            wrapMode: Text.Wrap
            text: root.status.output?.label || root.status.output?.monitor || ""
        }
        Label {
            Layout.fillWidth: true
            visible: text !== ""
            color: root.accent
            wrapMode: Text.Wrap
            text: root.status.packetAgeMs === null || root.status.packetAgeMs === undefined ? ""
                : root.status.bands + " полос · пакет " + root.status.packetAgeMs + " мс назад"
                    + (root.status.gain ? " · усиление ×" + root.status.gain : "")
                    + (root.status.output?.pid ? " · CAVA PID " + root.status.output.pid : "")
        }
        Button {
            text: root.busy ? "Проверяем звук…" : "Бесшумная проверка"
            enabled: !root.busy
            onClicked: root.service.audioSelfTest.start()
        }
        Label {
            Layout.fillWidth: true
            visible: root.result !== null
            color: root.ink
            wrapMode: Text.Wrap
            text: !root.result ? "" : root.result.ok
                ? "Монитор выхода доступен · " + root.result.bands + " полос"
                    + (root.result.label ? " · " + root.result.label : "")
                : root.result.reason
        }
    }
}
