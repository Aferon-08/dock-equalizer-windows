import QtQuick
import "ImportedLyrics.js" as ImportedLyrics

QtObject {
    id: app
    required property var mediaSessions
    required property var lyricsAlignment
    required property var batteryStatus
    required property var wifiStatus
    required property var windowsNotifications
    required property var discordVoice
    required property var notificationPreferences
    property var localLyrics: null
    required property var appearance
    readonly property NotificationQueue notifications: NotificationQueue {
        suspended: app.discordCall?.ringing ?? false
        motionCurve: app.appearance.values.motionCurve
    }
    readonly property var dockNotification: notifications.current
    readonly property real notificationExpiresAt: notifications.expiresAt
    readonly property Timer notificationExpiry: notifications.expiry
    onDockNotificationChanged: if (wifiStatus) wifiStatus.active = dockNotification?.kind === "wifi"
    readonly property string trackKey: mediaSessions.trackKey
    readonly property DiscordCallPreview discordPreview: DiscordCallPreview {}
    readonly property DiscordCall discordCall: DiscordCall {
        live: app.discordVoice
        testCall: app.discordPreview
    }

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

    function postTestNotification(scenario, queued) {
        const fixture = testScenarios[scenario] ?? testScenarios.regular
        if (queued)
            enqueueNotification(fixture)
        else
            showNotification(fixture)
    }

    function enqueueNotification(event) { notifications.enqueue(event) }
    function showNotification(event) { notifications.replace(event) }
    function dismissNotification(eventId) { notifications.advance(eventId, false, eventId !== undefined) }

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
