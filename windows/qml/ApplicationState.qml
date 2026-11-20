import QtQuick
import "ImportedLyrics.js" as ImportedLyrics

QtObject {
    id: app
    required property var mediaSessions
    required property var lyricsAlignment
    required property var wifiStatus
    property var localLyrics: null
    property var dockNotification: null
    readonly property string trackKey: mediaSessions.trackKey

    signal alignmentFailed(string message)

    onTrackKeyChanged: if (localLyrics && localLyrics.key !== trackKey) localLyrics = null

    readonly property var testScenarios: ({
        regular: {
            kind: "regular", accent: "#a4e7cc", title: "Тестовое уведомление",
            summary: "Проверка показа в доке", source: "Sekai Soundbar",
            detail: "Уведомление отправлено из настроек. События дока будут появляться в этой области."
        },
        update: {
            kind: "system", accent: "#ffdb91", title: "Доступно обновление Windows",
            summary: "Windows 11 · накопительное обновление", source: "Система · тест",
            detail: "Обновление готово к установке. Для завершения потребуется перезагрузка."
        },
        wifi: {
            kind: "wifi", accent: "#a0dcff", title: "Подключение к Wi-Fi",
            source: "Сеть · тест события"
        },
        charging: {
            kind: "battery", accent: "#a4e7cc", title: "Зарядка подключена",
            summary: "62 % · Заряжается", source: "Батарея · тест", charge: 62,
            detail: "До полного заряда около 46 минут."
        },
        unplugged: {
            kind: "battery", accent: "#a4e7cc", title: "Работа от батареи",
            summary: "62 % · Питание отключено", source: "Батарея · тест", charge: 62,
            detail: "Осталось около 3 ч 15 мин работы."
        },
        charged: {
            kind: "battery", accent: "#a4e7cc", title: "Батарея заряжена",
            summary: "100 % · Подключена к сети", source: "Батарея · тест", charge: 100,
            detail: "Ноутбук заряжен и подключён к питанию."
        }
    })

    function postTestNotification(scenario) {
        const fixture = testScenarios[scenario] ?? testScenarios.regular
        wifiStatus.active = fixture.kind === "wifi"
        dockNotification = Object.assign({}, fixture, {sentAt: new Date()})
        notificationExpiry.restart()
    }

    function dismissNotification() {
        notificationExpiry.stop()
        wifiStatus.active = false
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
