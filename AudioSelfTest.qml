import QtQuick
import Quickshell.Io

QtObject {
    id: root
    required property list<string> command
    readonly property bool running: worker.running
    property var result: null
    property var reply: null
    property string diagnostic: ""

    function start() {
        if (running) return false
        result = null
        reply = null
        diagnostic = ""
        worker.running = true
        deadline.restart()
        return true
    }

    property Timer deadline: Timer {
        interval: 8000
        onTriggered: {
            root.result = {ok: false, reason: "Проверка звука не ответила вовремя."}
            if (root.worker.processId > 0) root.worker.signal(9)
            else root.worker.running = false
        }
    }
    property Process worker: Process {
        command: root.command
        stdout: SplitParser {
            onRead: data => {
                try {
                    const response = JSON.parse(data)
                    if (typeof response?.ok === "boolean") root.reply = response
                } catch (_) {}
            }
        }
        stderr: SplitParser {
            onRead: data => {
                if (data.trim()) root.diagnostic = data.trim().slice(0, 500)
            }
        }
        onExited: code => {
            root.deadline.stop()
            if (root.result) return
            root.result = code === 0 && root.reply ? root.reply : {
                ok: false,
                reason: root.diagnostic || "Проверка звука завершилась (код " + code + ")."
            }
        }
    }
}
