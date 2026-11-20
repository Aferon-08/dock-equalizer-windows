import QtQuick
import "ImportedLyrics.js" as ImportedLyrics

QtObject {
    id: app
    required property var mediaSessions
    required property var lyricsAlignment
    property var localLyrics: null
    property var dockNotification: null
    readonly property string trackKey: mediaSessions.trackKey

    signal alignmentFailed(string message)

    onTrackKeyChanged: if (localLyrics && localLyrics.key !== trackKey) localLyrics = null

    function postTestNotification() {
        dockNotification = {
            title: "Тестовое уведомление",
            summary: "Проверка показа в доке",
            detail: "Уведомление отправлено из настроек. События дока будут появляться в этой области.",
            source: "Sekai Soundbar",
            sentAt: new Date()
        }
        notificationExpiry.restart()
    }

    function dismissNotification() {
        notificationExpiry.stop()
        dockNotification = null
    }

    property Timer notificationExpiry: Timer {
        interval: 30000
        onTriggered: app.dismissNotification()
    }

    function applyLyrics(track, result) {
        if (!result.ok)
            return result.message
        let document = result
        if (result.format === "wordtime") {
            try {
                document = Object.assign({}, result, {
                    lines: ImportedLyrics.convert(result),
                    voices: ImportedLyrics.voices(result)
                })
            } catch (error) {
                return String(error.message)
            }
        }
        localLyrics = {key: track, document: document}
        return ""
    }

    property Connections alignmentResult: Connections {
        target: app.lyricsAlignment
        function onAligned(trackKey, document) {
            if (trackKey === "" || trackKey !== app.trackKey)
                return
            const message = app.applyLyrics(trackKey, document)
            if (message)
                app.alignmentFailed(message)
        }
    }
}
