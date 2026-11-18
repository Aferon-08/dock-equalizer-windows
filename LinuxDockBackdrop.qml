// Convert the standalone view's global coordinates into the Linux compositor's monitor space.
import QtQuick

SettingsUnderlay {
    property rect globalViewport: Qt.rect(0, 0, width, height)
    viewport: Qt.rect(globalViewport.x - (monitor?.lastIpcObject?.x || 0),
        globalViewport.y - (monitor?.lastIpcObject?.y || 0), globalViewport.width, globalViewport.height)
    intersectOnly: true
    refreshInterval: 125
}
