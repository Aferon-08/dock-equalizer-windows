import QtQuick
DockWings {
 surfaceSupported:!!host.service && host.service.extensionEnabled("dock")
 readonly property real widthExtra:lyricsWidthExtra
 readonly property real heightExtra:lyricsHeightExtra
 readonly property real headerHeight:lyricsHeaderHeight
}
