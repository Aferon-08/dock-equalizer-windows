import QtQuick
import QtQuick.Controls

Rectangle {
    id: card
    required property bool inPlayer
    required property real playerHeight
    readonly property bool presenting: posted || reveal > 0
    readonly property real detailsHeight: 132
    property bool posted: false
    property bool details: false
    property string headline
    property string summary
    property string description
    property date sentAt
    property color accent: "#96dcc0"
    property real reveal: posted ? 1 : 0

    visible: presenting
    opacity: reveal
    height: Math.max(playerHeight, details ? detailsHeight : 69)
    radius: Math.min(30, height / 2)
    color: "#14241f"
    border.color: "#4c7766"
    border.width: 2
    antialiasing: true
    clip: true

    Behavior on height { NumberAnimation { duration: 190; easing.type: Easing.OutCubic } }
    Behavior on reveal { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    function show(title: string, message: string, body: string) {
        headline = title
        summary = message
        description = body
        sentAt = new Date()
        details = false
        posted = true
        expiry.restart()
        if (inPlayer && playerHeight < 90)
            attention.restart()
    }

    function dismiss() {
        posted = false
    }

    Timer {
        id: expiry
        interval: 30000
        running: card.posted && !card.details
        onTriggered: card.dismiss()
    }

    transform: Translate { id: nudge }
    SequentialAnimation {
        id: attention
        NumberAnimation { target: nudge; property: "x"; to: 3; duration: 70 }
        NumberAnimation { target: nudge; property: "x"; to: -3; duration: 100 }
        NumberAnimation { target: nudge; property: "x"; to: 0; duration: 110; easing.type: Easing.OutCubic }
    }

    Button {
        anchors.fill: parent
        anchors.rightMargin: 49
        enabled: card.posted
        background: null
        Accessible.name: card.details ? "Свернуть уведомление" : "Подробнее об уведомлении"
        onClicked: card.details = !card.details
    }

    Rectangle {
        x: 15
        y: 16
        width: 37
        height: 37
        radius: 13
        color: "#274a3d"
        Text {
            anchors.centerIn: parent
            text: "✓"
            font.pixelSize: 19
            color: card.accent
        }
    }

    Column {
        x: 64
        y: 16
        width: card.width - x - 62
        spacing: 4
        Text {
            width: parent.width
            text: card.headline
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: "#e8f4ee"
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }
        Text {
            width: parent.width
            text: card.summary
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: card.accent
            font.pixelSize: 13
        }
        Text {
            visible: card.details
            width: parent.width
            topPadding: 5
            text: card.description
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: "#e8f4ee"
            font.pixelSize: 13
        }
        Text {
            visible: card.details
            text: Qt.formatTime(card.sentAt, "HH:mm:ss")
            color: "#9db7ad"
            font.pixelSize: 12
        }
    }

    Button {
        id: closeButton
        anchors.right: parent.right
        anchors.rightMargin: 13
        y: 18
        width: 32
        height: 32
        enabled: card.posted
        Accessible.name: "Закрыть уведомление"
        contentItem: Text {
            text: "×"
            color: closeButton.hovered ? "#e8f4ee" : "#9db7ad"
            font.pixelSize: 22
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
        background: Rectangle {
            radius: width / 2
            color: closeButton.hovered ? "#274a3d" : "transparent"
        }
        onClicked: card.dismiss()
    }
}
