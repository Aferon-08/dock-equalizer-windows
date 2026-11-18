import QtQuick
import QtQuick.Controls

Button {
    id: root
    required property color ink
    required property color accent
    required property color surface
    property bool selected: false

    horizontalPadding: 12
    verticalPadding: 8
    implicitHeight: Math.max(36, implicitContentHeight + topPadding + bottomPadding)
    font.pixelSize: 13
    opacity: enabled ? 1 : .52
    contentItem: Text {
        text: root.text
        textFormat: Text.PlainText
        font: root.font
        color: root.ink
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
        radius: 11
        color: Qt.alpha(Qt.tint(root.surface, Qt.alpha(root.accent,
            root.selected ? .30 : root.down ? .23 : root.hovered ? .15 : .06)), .90)
        border.color: Qt.alpha(root.accent, root.selected || root.visualFocus ? .72 : .24)
    }
}
