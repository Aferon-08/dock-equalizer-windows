import QtQuick
import "ImportedLyrics.js" as ImportedLyrics

QtObject {
    id: app
    required property var mediaSessions
    required property var lyricsAlignment
    required property var batteryStatus
    required property var wifiStatus
    required property var windowsNotifications
    property var localLyrics: null
    property var dockNotification: null
    readonly property var pendingNotifications: []
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
        showNotification(Object.assign({}, fixture, {sentAt: new Date()}))
    }

    function sameSensor(first, second) {
        return (first.liveBattery && second.liveBattery) || (first.liveWifi && second.liveWifi)
    }

    function enqueueNotification(event) {
        const entry = Object.assign({sentAt: new Date()}, event)
        if (!dockNotification || sameSensor(dockNotification, entry)) {
            showNotification(entry)
            return
        }
        const previous = pendingNotifications.findIndex(pending => sameSensor(pending, entry))
        if (previous >= 0)
            pendingNotifications.splice(previous, 1)
        if (pendingNotifications.length >= 20)
            pendingNotifications.shift()
        pendingNotifications.push(entry)
    }

    function showNotification(entry) {
        wifiStatus.active = entry.kind === "wifi"
        dockNotification = entry
        notificationExpiry.restart()
    }

    function dismissNotification() {
        if (pendingNotifications.length) {
            showNotification(pendingNotifications.shift())
            return
        }
        notificationExpiry.stop()
        wifiStatus.active = false
        dockNotification = null
    }

    property Timer notificationExpiry: Timer {
        interval: 30000
        onTriggered: app.dismissNotification()
    }

    property Connections batteryEvents: Connections {
        target: app.batteryStatus
        function onNotification(event) { app.enqueueNotification(event) }
    }
    property Connections wifiEvents: Connections {
        target: app.wifiStatus
        function onNotification(event) { app.enqueueNotification(event) }
    }
    property Connections windowsEvents: Connections {
        target: app.windowsNotifications
        function onNotification(event) { app.enqueueNotification(event) }
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
