pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Window {
    id: panel
    objectName: "soundbarSettingsWindow"
    required property var appearance
    required property var displays
    required property var startup
    required property var lyricsSearch
    required property var appState
    property var previewDock: null
    property string section: "general"

    title: "Настройки — Sekai Soundbar"
    flags: Qt.Window | Qt.FramelessWindowHint | Qt.WindowSystemMenuHint
    color: "transparent"
    minimumWidth: 350
    minimumHeight: 300
    width: 760
    height: 580

    readonly property color ink: "#e8f4ee"
    readonly property color muted: "#9db7ad"
    readonly property color mint: "#96dcc0"
    readonly property color line: "#34584a"
    readonly property color warning: "#ffb8ad"
    readonly property bool wide: width >= 600
    readonly property bool effectsAvailable: shell.GraphicsInfo.api !== GraphicsInfo.Software
        && shell.GraphicsInfo.api !== GraphicsInfo.Unknown
    readonly property bool desktopGlassAvailable: shell.GraphicsInfo.api === GraphicsInfo.Direct3D11
    readonly property bool glassEnabled: appearance.values.dockGlass

    onActiveChanged: if (active) startup.refresh()

    Shortcut { sequence: "Escape"; onActivated: panel.close() }

    component Copy: Label {
        color: panel.muted
        font.pixelSize: 13
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        Layout.fillWidth: true
    }

    component FieldLabel: Copy {
        color: panel.ink
        font.pixelSize: 15
        font.weight: Font.DemiBold
    }

    component Surface: Rectangle {
        id: surface
        default property alias entries: fields.data
        Layout.fillWidth: true
        implicitHeight: fields.implicitHeight + 32
        radius: 17
        color: "#ba172a25"
        border.color: "#36584a"

        property Item contents: ColumnLayout {
            parent: surface
            id: fields
            x: 16
            y: 16
            width: surface.width - 32
            spacing: 12
        }
    }

    component Action: Button {
        id: control
        onPressed: forceActiveFocus(Qt.MouseFocusReason)
        padding: 9
        topPadding: 7
        bottomPadding: 7
        implicitHeight: 36
        font.pixelSize: 13
        font.weight: Font.DemiBold
        property bool emphasized: false

        contentItem: Label {
            text: control.text
            font: control.font
            color: !control.enabled ? panel.muted : control.emphasized ? "#11261e" : panel.ink
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: 10
            color: control.emphasized && control.enabled
                ? (control.down ? "#79c7a7" : control.hovered ? "#b0ead3" : panel.mint)
                : (control.down ? "#314f43" : control.hovered ? "#2b493e" : "#213a31")
            border.color: control.visualFocus ? panel.mint : panel.line
        }
    }

    component Option: Switch {
        id: control
        implicitWidth: 51
        implicitHeight: 40
        padding: 0

        indicator: Rectangle {
            x: Math.round((control.width - width) / 2)
            y: Math.round((control.height - height) / 2)
            width: 45
            height: 25
            radius: height / 2
            opacity: control.enabled ? 1 : 0.54
            color: control.checked ? (control.hovered ? "#b2ead4" : panel.mint) : "#223b32"
            border.color: control.visualFocus ? panel.ink : control.checked ? panel.mint : "#567769"

            Rectangle {
                x: control.checked ? 24 : 4
                anchors.verticalCenter: parent.verticalCenter
                width: 17
                height: width
                radius: width / 2
                color: control.checked ? "#193a2e" : "#b0c8be"
                Behavior on x { NumberAnimation { duration: 135; easing.type: Easing.OutCubic } }
            }
        }
        contentItem: Item {}
    }

    component NavButton: Button {
        id: link
        required property string destination
        readonly property bool selected: panel.section === destination
        Layout.fillWidth: true
        implicitHeight: 40
        leftPadding: 14
        rightPadding: 9
        font.pixelSize: 14
        font.weight: selected ? Font.DemiBold : Font.Normal
        onClicked: panel.section = destination

        contentItem: Label {
            text: link.text
            font: link.font
            color: link.selected ? panel.mint : panel.ink
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: 10
            color: link.selected ? "#29483c" : link.hovered ? "#243d34" : "transparent"
            border.color: link.visualFocus ? panel.mint : link.selected ? panel.line : "transparent"

            Rectangle {
                width: 3
                height: 16
                anchors.left: parent.left
                anchors.leftMargin: 3
                anchors.verticalCenter: parent.verticalCenter
                radius: 2
                color: panel.mint
                visible: link.selected
            }
        }
    }

    component Amount: ColumnLayout {
        id: field
        required property var spec
        Layout.fillWidth: true
        spacing: 3
        enabled: panel.effectsAvailable && panel.glassEnabled

        RowLayout {
            Layout.fillWidth: true
            Copy { text: field.spec.label; color: panel.ink }
            Copy {
                Layout.fillWidth: false
                text: field.spec.pixels
                    ? valueSlider.value.toLocaleString(Qt.locale(), "f", 1) + " пкс"
                    : Math.round(valueSlider.value * 100) + " %"
                horizontalAlignment: Text.AlignRight
            }
        }
        Slider {
            id: valueSlider
            Layout.fillWidth: true
            implicitHeight: 28
            from: field.spec.minimum
            to: field.spec.maximum
            stepSize: field.spec.step
            snapMode: Slider.SnapAlways
            value: panel.appearance.values[field.spec.key]
            Accessible.name: field.spec.label
            onMoved: panel.appearance.setNumber(field.spec.key, value)

            background: Rectangle {
                x: valueSlider.leftPadding
                y: Math.round((valueSlider.height - height) / 2)
                width: valueSlider.availableWidth
                height: 4
                radius: 2
                color: "#3d5d50"
                opacity: valueSlider.enabled ? 1 : 0.5

                Rectangle {
                    width: valueSlider.visualPosition * parent.width
                    height: parent.height
                    radius: 2
                    color: panel.mint
                }
            }
            handle: Rectangle {
                x: valueSlider.leftPadding + valueSlider.visualPosition * (valueSlider.availableWidth - width)
                y: Math.round((valueSlider.height - height) / 2)
                width: 16
                height: width
                radius: width / 2
                color: valueSlider.pressed ? "#d0f9e8" : panel.mint
                border.color: valueSlider.visualFocus ? panel.ink : panel.line
                opacity: valueSlider.enabled ? 1 : 0.5
            }
        }
    }

    MonitorBackdrop {
        id: permission
        visible: false
        onBorderlessGranted: panel.appearance.setCaptureBorderless(true)
    }

    Rectangle {
        id: shell
        anchors.fill: parent
        radius: 24
        antialiasing: true
        color: "#12211c"
        border.color: "#628877"
        gradient: Gradient {
            GradientStop { position: 0; color: "#2a4337" }
            GradientStop { position: 0.28; color: "#182b24" }
            GradientStop { position: 1; color: "#101b18" }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: shell.radius - 2
            color: "transparent"
            border.color: "#274a3d"
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 12

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 38

                DragHandler {
                    target: null
                    onActiveChanged: if (active) panel.startSystemMove()
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 7
                    spacing: 10

                    Rectangle {
                        width: 34
                        height: 24
                        radius: height / 2
                        color: "#25483a"
                        border.color: "#578673"

                        Rectangle {
                            width: 12
                            height: 8
                            radius: 4
                            anchors.centerIn: parent
                            color: panel.mint
                        }
                    }

                    Label {
                        text: "Настройки"
                        font.pixelSize: 21
                        font.weight: Font.DemiBold
                        color: panel.ink
                    }
                    Label {
                        visible: panel.wide
                        text: "Sekai Soundbar"
                        color: panel.muted
                        font.pixelSize: 13
                    }

                    Item { Layout.fillWidth: true }

                    Action {
                        Layout.preferredWidth: 38
                        text: "−"
                        Accessible.name: "Свернуть настройки"
                        onClicked: panel.showMinimized()
                    }
                    Action {
                        Layout.preferredWidth: 38
                        text: "×"
                        Accessible.name: "Закрыть настройки"
                        onClicked: panel.close()
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: panel.line }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: panel.wide ? 2 : 1
                columnSpacing: 18
                rowSpacing: 12

                GridLayout {
                    columns: panel.wide ? 1 : 2
                    rowSpacing: 5
                    columnSpacing: 5
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: panel.wide ? 156 : -1
                    Layout.fillWidth: !panel.wide

                    NavButton { text: "Общие"; destination: "general" }
                    NavButton { text: "Мониторы"; destination: "displays" }
                    NavButton { text: "Оформление"; destination: "appearance" }
                    NavButton { text: "Лирика"; destination: "lyrics" }
                    NavButton { text: "Уведомления"; destination: "notifications" }
                    NavButton { text: "Discord"; destination: "discord"; visible: panel.appState.discordVoice.available }
                }

                ScrollView {
                    id: scroll
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    contentHeight: page.height
                    rightPadding: 10
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical: ScrollBar {
                        id: scrollBar
                        policy: ScrollBar.AsNeeded
                        width: 8
                        padding: 1
                        minimumSize: 0.08
                        contentItem: Rectangle {
                            radius: 3
                            color: scrollBar.pressed ? panel.mint : "#638777"
                        }
                    }

                    Loader {
                        id: page
                        width: scroll.availableWidth
                        sourceComponent: {
                            switch (panel.section) {
                            case "displays": return displaysPage
                            case "appearance": return appearancePage
                            case "lyrics": return lyricsPage
                            case "notifications": return notificationsPage
                            case "discord": return discordPage
                            default: return generalPage
                            }
                        }
                        onLoaded: scroll.contentItem.contentY = 0
                    }
                }
            }
        }

        MouseArea {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 15
            height: 15
            cursorShape: Qt.SizeFDiagCursor
            onPressed: panel.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
        }
    }

    Component {
        id: generalPage
        ColumnLayout {
            spacing: 14

            FieldLabel { text: "Общие"; font.pixelSize: 23 }
            Surface {
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        FieldLabel { text: "Запускать вместе с Windows" }
                        Copy { text: "Sekai Soundbar запустится при входе в вашу учётную запись." }
                    }
                    Option {
                        objectName: "startupOption"
                        Accessible.name: "Запускать вместе с Windows"
                        enabled: panel.startup.available
                        checked: panel.startup.enabled
                        onToggled: panel.startup.setEnabled(checked)
                    }
                }
                Copy {
                    visible: text !== ""
                    text: panel.startup.error || (panel.startup.otherCopy
                        ? "Сейчас в автозапуске указан другой файл Sekai Soundbar." : "")
                    color: panel.startup.error ? panel.warning : panel.muted
                }
            }
        }
    }

    Component {
        id: displaysPage
        ColumnLayout {
            spacing: 12

            FieldLabel { text: "Мониторы"; font.pixelSize: 23 }
            Copy { text: "Выберите экраны, на которых будет появляться док." }

            Repeater {
                model: panel.displays
                delegate: Surface {
                    id: monitor
                    required property string monitorId
                    required property string monitorName
                    required property string monitorDetails
                    required property bool dockEnabled

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Rectangle {
                            Layout.alignment: Qt.AlignVCenter
                            width: 36
                            height: 26
                            radius: 6
                            color: monitor.dockEnabled ? "#294a3c" : "#23372f"
                            border.color: monitor.dockEnabled ? panel.mint : "#597468"

                            Rectangle {
                                width: 13
                                height: 2
                                radius: 1
                                color: parent.border.color
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.bottom
                                anchors.topMargin: 3
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            FieldLabel { text: monitor.monitorName }
                            Copy { text: monitor.monitorDetails }
                        }
                        Option {
                            Accessible.name: "Показывать док · " + monitor.monitorName
                            checked: monitor.dockEnabled
                            onToggled: panel.displays.setDockEnabled(monitor.monitorId, checked)
                        }
                    }
                }
            }
            Copy {
                visible: panel.displays.enabledCount === 0
                text: panel.displays.count === 0 ? "Подключённых мониторов нет." : "Док скрыт на всех мониторах."
            }
        }
    }

    Component {
        id: appearancePage
        ColumnLayout {
            spacing: 14

            FieldLabel { text: "Оформление"; font.pixelSize: 23 }
            Surface {
                FieldLabel { text: "Анимации дока" }
                Copy { text: "Перетащите точки, чтобы настроить темп переходов." }
                MotionCurveEditor {
                    objectName: "motionCurveEditor"
                    Layout.fillWidth: true
                    curve: panel.appearance.values.motionCurve
                    accent: panel.mint
                    mutedInk: panel.muted
                    lineColor: panel.line
                    onEdited: points => panel.appearance.setMotionCurve(points)
                }
                RowLayout {
                    Layout.fillWidth: true
                    FieldLabel { text: "Пружинность интерфейса" }
                    Option {
                        objectName: "springMotionSwitch"
                        Accessible.name: "Пружинность интерфейса"
                        checked: panel.appearance.values.springMotion
                        onToggled: panel.appearance.setSpringMotion(checked)
                    }
                }
                Rectangle {
                    id: motionPreview
                    property real progress: 0
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: 9
                    color: "#101f1b"
                    border.color: panel.line

                    Rectangle {
                        anchors.centerIn: parent
                        width: 24 + Math.max(1, Math.min(176, motionPreview.width - 52)) * motionPreview.progress
                        height: 13 + 5 * motionPreview.progress
                        radius: height / 2
                        color: "#294b3e"
                        border.color: panel.mint
                    }
                    DockTransition {
                        id: previewMotion
                        target: motionPreview
                        property: "progress"
                        from: 0
                        to: 1
                        duration: 850
                        curve: panel.appearance.values.motionCurve
                        spring: panel.appearance.values.springMotion ? 1.2 : 0
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Action {
                        text: "Предпросмотр"
                        onClicked: previewMotion.restart()
                    }
                    Action {
                        text: "Сбросить кривую"
                        enabled: panel.appearance.values.motionCurve.length === 4
                        onClicked: panel.appearance.setMotionCurve([])
                    }
                }
            }
            Surface {
                FieldLabel { text: "Стиль прогресса" }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Action {
                        Layout.fillWidth: true
                        text: "Материал"
                        emphasized: panel.appearance.values.progressStyle === "material"
                        onClicked: panel.appearance.setProgressStyle("material")
                    }
                    Action {
                        Layout.fillWidth: true
                        text: "Плассгласс"
                        emphasized: panel.appearance.values.progressStyle === "plassglass"
                        onClicked: panel.appearance.setProgressStyle("plassglass")
                    }
                }
            }
            Surface {
                RowLayout {
                    Layout.fillWidth: true
                    FieldLabel { text: "Цвет дока по обложке" }
                    Option {
                        Accessible.name: "Цвет дока по обложке"
                        checked: panel.appearance.values.artworkColors
                        onToggled: panel.appearance.setArtworkColors(checked)
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    FieldLabel { text: "Стеклянный корпус" }
                    Option {
                        Accessible.name: "Стеклянный корпус"
                        enabled: panel.effectsAvailable
                        checked: panel.glassEnabled
                        onToggled: panel.appearance.setGlassEnabled(checked)
                    }
                }
                Copy {
                    visible: !panel.effectsAvailable
                    text: "Используется упрощённое оформление."
                }
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        FieldLabel { text: "Преломлять фон рабочего стола" }
                        Copy {
                            text: !panel.desktopGlassAvailable ? "Для преломления фона нужен Direct3D 11."
                                : (panel.appearance.values.desktopGlass && panel.previewDock?.captureBackdrop?.status)
                                    || "Использует изображение рабочего стола за доком."
                        }
                    }
                    Option {
                        Accessible.name: "Преломлять фон рабочего стола"
                        enabled: panel.desktopGlassAvailable && panel.glassEnabled
                        checked: panel.appearance.values.desktopGlass
                        onToggled: panel.appearance.setDesktopGlass(checked)
                    }
                }
                Action {
                    visible: panel.desktopGlassAvailable && panel.glassEnabled && panel.appearance.values.desktopGlass
                    enabled: !permission.requestingBorderless
                    text: panel.appearance.values.captureBorderless ? "Показывать рамку Windows" : "Скрыть жёлтую рамку"
                    onClicked: {
                        if (panel.appearance.values.captureBorderless)
                            panel.appearance.setCaptureBorderless(false)
                        else
                            permission.requestBorderless()
                    }
                }
                Copy {
                    visible: panel.desktopGlassAvailable && panel.glassEnabled
                        && panel.appearance.values.desktopGlass && text !== ""
                    text: permission.borderStatus
                }
            }
            Surface {
                FieldLabel { text: "Стекло и подсветка" }
                Repeater {
                    model: panel.appearance.sliders
                    delegate: Amount {
                        required property var modelData
                        spec: modelData
                    }
                }
            }
            Action {
                Layout.alignment: Qt.AlignRight
                text: "Сбросить оформление"
                onClicked: panel.appearance.reset()
            }
        }
    }

    Component {
        id: notificationsPage
        ColumnLayout {
            id: notifications
            spacing: 14
            readonly property var windowsSource: panel.appState.windowsNotifications
            readonly property string listenerStatus: windowsSource.status
            readonly property bool receivesWindows: listenerStatus === "active" && panel.displays.enabledCount > 0

            function sendTest(scenario) {
                if (panel.displays.enabledCount === 0) {
                    notificationStatus.text = "Включите док хотя бы на одном мониторе."
                    return
                }
                panel.appState.postTestNotification(scenario)
                notificationStatus.text = "Уведомление отправлено на включённые мониторы."
            }

            FieldLabel { text: "Уведомления"; font.pixelSize: 23 }
            Surface {
                RowLayout {
                    Layout.fillWidth: true
                    FieldLabel { text: "Уведомления поверх окон" }
                    Option {
                        objectName: "notificationsAboveWindowsSwitch"
                        Accessible.name: "Уведомления поверх окон"
                        checked: panel.appState.notificationPreferences.aboveWindows
                        onToggled: panel.appState.notificationPreferences.aboveWindows = checked
                    }
                }
                Copy { text: "Если у верхней кромки мало места или включён полноэкранный режим, уведомление появится поверх окон." }
                FieldLabel { text: "Позиция отдельного уведомления" }
                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= 440 ? 3 : 1
                    rowSpacing: 8
                    columnSpacing: 8
                    Repeater {
                        model: [
                            {value: "top-center", label: "Сверху по центру"},
                            {value: "bottom-right", label: "Справа внизу"},
                            {value: "bottom-center", label: "Снизу по центру"}
                        ]
                        delegate: Action {
                            required property var modelData
                            Layout.fillWidth: true
                            text: modelData.label
                            checkable: true
                            autoExclusive: true
                            checked: panel.appState.notificationPreferences.notificationPosition === modelData.value
                            emphasized: checked
                            onClicked: panel.appState.notificationPreferences.notificationPosition = modelData.value
                        }
                    }
                }
            }
            Surface {
                FieldLabel { text: "Автоматические события" }
                Copy {
                    text: {
                        const battery = panel.appState.batteryStatus.snapshot
                        if (battery.state === "noBattery") return "Батарея · отсутствует"
                        return "Батарея · " + (battery.summary ?? "нет данных")
                    }
                }
                Copy {
                    text: {
                        const wifi = panel.appState.wifiStatus.snapshot
                        switch (wifi.state) {
                        case "connected": return "Wi-Fi · " + (wifi.ssid || "подключён")
                        case "restricted": return "Wi-Fi · подключён, имя сети скрыто Windows"
                        case "disconnected": return "Wi-Fi · отключён"
                        default: return "Wi-Fi · нет данных"
                        }
                    }
                }
                Copy {
                    text: {
                        switch (notifications.listenerStatus) {
                        case "packageRequired": return "Для чтения уведомлений приложений Windows нужна сборка с подписанным пакетом доступа."
                        case "permissionRequired": return "Разрешите доку читать уведомления приложений Windows."
                        case "requesting": return "Ожидаем ответ на запрос Windows."
                        case "connecting": return "Читаем Центр уведомлений Windows."
                        case "denied": return "Доступ к уведомлениям приложений отключён в настройках Windows."
                        case "active": return "Уведомления приложений подключены."
                        default: return "Источник уведомлений приложений Windows недоступен."
                        }
                    }
                }
                Copy {
                    visible: text !== ""
                    text: notifications.windowsSource.diagnostic
                }
                Action {
                    Layout.fillWidth: true
                    visible: notifications.listenerStatus === "permissionRequired"
                    text: "Разрешить уведомления приложений"
                    onClicked: notifications.windowsSource.requestAccess(panel)
                }
                Action {
                    Layout.fillWidth: true
                    visible: notifications.listenerStatus === "denied"
                    text: "Открыть разрешения Windows"
                    onClicked: Qt.openUrlExternally("ms-settings:privacy-notifications")
                }
            }
            Surface {
                visible: notifications.listenerStatus === "active" || notifications.windowsSource.bannersHidden
                FieldLabel { text: "Только в доке" }
                Copy {
                    text: "Док отключает баннеры приложений. Их уведомления остаются в Центре уведомлений и появляются в доке."
                }
                Action {
                    Layout.fillWidth: true
                    visible: notifications.windowsSource.bannerControlAvailable || notifications.windowsSource.bannersHidden
                    enabled: notifications.receivesWindows || notifications.windowsSource.bannersHidden
                    text: notifications.windowsSource.bannersHidden ? "Вернуть баннеры Windows" : "Скрыть баннеры Windows"
                    emphasized: !notifications.windowsSource.bannersHidden
                    onClicked: notifications.windowsSource.setBannersHidden(!notifications.windowsSource.bannersHidden)
                }
                Copy {
                    visible: !notifications.windowsSource.bannerControlAvailable
                        && notifications.windowsSource.bannerError === ""
                    text: "Показ баннеров можно настроить отдельно для каждого приложения в параметрах Windows."
                }
                Copy {
                    visible: text !== ""
                    text: notifications.windowsSource.bannerError
                    color: panel.warning
                }
                Copy {
                    visible: notifications.windowsSource.bannersHidden && notifications.receivesWindows
                    text: "Приложений с отключёнными баннерами · " + notifications.windowsSource.suppressedBannerCount
                }
                Copy {
                    visible: !notifications.receivesWindows
                    text: "Для показа в доке нужен доступ к уведомлениям и хотя бы один включённый монитор."
                }
                Action {
                    Layout.fillWidth: true
                    text: "Открыть параметры уведомлений Windows"
                    onClicked: Qt.openUrlExternally("ms-settings:notifications")
                }
                Action {
                    Layout.fillWidth: true
                    visible: notifications.listenerStatus === "active"
                    enabled: notifications.receivesWindows && !notifications.windowsSource.testing
                    text: "Проверить через Центр уведомлений Windows"
                    onClicked: notifications.windowsSource.sendTestNotification()
                }
                Copy {
                    visible: text !== ""
                    text: notifications.windowsSource.testResult
                }
                Copy {
                    text: "Системные предупреждения и будильники обрабатывает Windows. Док возвращает прежние настройки при выходе."
                }
            }
            Surface {
                RowLayout {
                    Layout.fillWidth: true
                    FieldLabel { text: "Участники в тестовом звонке" }
                    Label {
                        text: panel.appState.discordPreview.participantCount.toString()
                        color: panel.mint
                    }
                }
                Slider {
                    id: testParticipantCount
                    objectName: "testDiscordParticipantCount"
                    Layout.fillWidth: true
                    from: 1
                    to: 8
                    stepSize: 1
                    snapMode: Slider.SnapAlways
                    value: panel.appState.discordPreview.participantCount
                    Accessible.name: "Участники в тестовом звонке"
                    onMoved: panel.appState.discordPreview.participantCount = Math.round(value)
                }
                Action {
                    objectName: "testDiscordCallButton"
                    Layout.fillWidth: true
                    text: "Тестовый звонок Discord"
                    enabled: !panel.appState.discordCall.active
                    onClicked: {
                        if (panel.displays.enabledCount === 0) {
                            notificationStatus.text = "Включите док хотя бы на одном мониторе."
                            return
                        }
                        notificationStatus.text = ""
                        panel.appState.discordPreview.start()
                    }
                }
                Copy { text: "Тестовые карточки раскрываются, когда в верхней части экрана есть место." }
                Action {
                    Layout.fillWidth: true
                    text: "Показать тестовую карточку дока"
                    emphasized: true
                    onClicked: notifications.sendTest("regular")
                }
                Action {
                    Layout.fillWidth: true
                    text: "Обновление Windows"
                    onClicked: notifications.sendTest("update")
                }
                Action {
                    Layout.fillWidth: true
                    text: "Подключение к Wi-Fi"
                    onClicked: notifications.sendTest("wifi")
                }
            }
            Surface {
                FieldLabel { text: "Входящие звонки Discord" }
                Copy { text: "Отвечайте на входящие в Discord. Док показывает голосовую сессию после подключения." }
                Action {
                    Layout.fillWidth: true
                    text: "Открыть Discord"
                    onClicked: {
                        if (Qt.openUrlExternally("discord://-/channels/@me")
                                || Qt.openUrlExternally("https://discord.com/channels/@me"))
                            notificationStatus.text = ""
                        else
                            notificationStatus.text = "Не удалось открыть Discord. Запустите его из меню «Пуск»."
                    }
                }
                Action {
                    Layout.fillWidth: true
                    visible: notifications.listenerStatus === "active" || notifications.windowsSource.discordProbeActive
                    text: notifications.windowsSource.discordProbeActive
                        ? "Остановить проверку уведомлений Discord" : "Проверить уведомления Discord"
                    onClicked: notifications.windowsSource.setDiscordProbeActive(!notifications.windowsSource.discordProbeActive)
                }
                Copy {
                    visible: notifications.windowsSource.discordProbeLog !== ""
                    text: "Временный журнал показывает источник, ID и время уведомления."
                }
                ScrollView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 140
                    visible: notifications.windowsSource.discordProbeLog !== ""
                    clip: true
                    contentWidth: availableWidth
                    background: Rectangle { color: "#172a25"; radius: 10; border.color: panel.line }

                    TextArea {
                        readOnly: true
                        selectByMouse: true
                        textFormat: TextEdit.PlainText
                        wrapMode: TextEdit.Wrap
                        text: notifications.windowsSource.discordProbeLog
                        color: panel.ink
                        padding: 9
                        Accessible.name: "Журнал проверки уведомлений Discord"
                    }
                }
            }
            Surface {
                FieldLabel { text: "Батарея" }
                GridLayout {
                    Layout.fillWidth: true
                    columns: width >= 465 ? 3 : 1
                    rowSpacing: 8
                    columnSpacing: 8
                    Action {
                        Layout.fillWidth: true
                        text: "Зарядка подключена"
                        onClicked: notifications.sendTest("charging")
                    }
                    Action {
                        Layout.fillWidth: true
                        text: "Питание отключено"
                        onClicked: notifications.sendTest("unplugged")
                    }
                    Action {
                        Layout.fillWidth: true
                        text: "Полный заряд"
                        onClicked: notifications.sendTest("charged")
                    }
                }
            }
            Copy {
                id: notificationStatus
                visible: text !== ""
            }
        }
    }

    Component {
        id: discordPage
        ColumnLayout {
            id: connection
            spacing: 14
            readonly property var discord: panel.appState.discordVoice

            FieldLabel { text: "Discord"; font.pixelSize: 23 }
            Surface {
                FieldLabel { text: "Подключение голосовых сессий" }
                Copy { text: connection.discord.statusText }
                Copy {
                    visible: !connection.discord.linked
                    text: "Запустите настольный Discord и подтвердите доступ в браузере."
                }
                Action {
                    objectName: "connectDiscord"
                    Layout.fillWidth: true
                    text: "Подключить Discord"
                    emphasized: true
                    visible: !connection.discord.authorized
                    enabled: !connection.discord.signingIn
                    onClicked: connection.discord.connectDiscord()
                }
                Action {
                    Layout.fillWidth: true
                    visible: connection.discord.linked
                    text: connection.discord.signingIn ? "Отменить вход" : "Отключить Discord"
                    onClicked: connection.discord.disconnectDiscord()
                }
            }
            Surface {
                FieldLabel { text: "Соединение для входа" }
                Flow {
                    Layout.fillWidth: true
                    spacing: 7
                    enabled: !connection.discord.signingIn
                    ButtonGroup { id: discordRoutes }
                    Repeater {
                        model: [
                            { mode: "system", label: "Системное" },
                            { mode: "incy-socks5", label: "INCY SOCKS5" },
                            { mode: "incy-http", label: "INCY HTTP" }
                        ]
                        Action {
                            required property var modelData
                            text: modelData.label
                            checkable: true
                            ButtonGroup.group: discordRoutes
                            checked: connection.discord.proxyMode === modelData.mode
                            emphasized: checked
                            onClicked: connection.discord.proxyMode = modelData.mode
                        }
                    }
                }
            }
        }
    }

    Component {
        id: lyricsPage
        ColumnLayout {
            id: lyrics
            property string proxyError: ""
            spacing: 14

            function saveProxy() {
                proxyError = panel.lyricsSearch.configureProxy(proxy.text)
                if (!proxyError)
                    proxy.text = panel.lyricsSearch.proxyAddress
            }

            FieldLabel { text: "Лирика"; font.pixelSize: 23 }
            Surface {
                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        FieldLabel { text: "Искать лирику автоматически" }
                        Copy { text: "Поиск запускается при смене трека." }
                    }
                    Option {
                        Accessible.name: "Искать лирику автоматически"
                        checked: panel.lyricsSearch.automatic
                        onToggled: panel.lyricsSearch.automatic = checked
                    }
                }
            }
            Surface {
                FieldLabel { text: "Прокси поиска" }
                Copy { text: "Укажите локальный адрес HTTP или SOCKS5. Пустое поле включает обычное подключение." }
                TextField {
                    id: proxy
                    Layout.fillWidth: true
                    implicitHeight: 38
                    maximumLength: 120
                    selectByMouse: true
                    color: panel.ink
                    selectionColor: panel.line
                    selectedTextColor: panel.ink
                    placeholderTextColor: panel.muted
                    placeholderText: "socks5h://127.0.0.1:10808"
                    text: panel.lyricsSearch.proxyAddress
                    Accessible.name: "Адрес прокси для лирики"
                    onAccepted: lyrics.saveProxy()
                    background: Rectangle {
                        radius: 9
                        color: "#13241d"
                        border.color: proxy.activeFocus ? panel.mint : panel.line
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 7
                    Action { text: "INCY SOCKS5"; onClicked: proxy.text = "socks5h://127.0.0.1:10808" }
                    Action { text: "INCY HTTP"; onClicked: proxy.text = "http://127.0.0.1:10809" }
                    Action { text: "Сохранить"; emphasized: true; onClicked: lyrics.saveProxy() }
                }
                Copy {
                    visible: text !== ""
                    text: lyrics.proxyError
                    color: panel.warning
                }
            }
        }
    }
}
