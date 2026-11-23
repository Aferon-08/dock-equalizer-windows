#include "NotificationPreferences.h"

#include <QSettings>

namespace {

const auto enabledKey = QStringLiteral("notifications/aboveWindows");
const auto positionKey = QStringLiteral("notifications/position");
const auto topCenter = QStringLiteral("top-center");

bool validPosition(const QString &position)
{
    return position == topCenter || position == QStringLiteral("bottom-right")
        || position == QStringLiteral("bottom-center");
}

}

NotificationPreferences::NotificationPreferences(QSettings *settings)
    : m_settings(settings), m_position(topCenter)
{
    if (!m_settings)
        return;
    m_aboveWindows = m_settings->value(enabledKey, false).toBool();
    const auto savedPosition = m_settings->value(positionKey).toString();
    if (validPosition(savedPosition))
        m_position = savedPosition;
}

void NotificationPreferences::setAboveWindows(bool enabled)
{
    if (m_aboveWindows == enabled)
        return;
    m_aboveWindows = enabled;
    if (m_settings)
        m_settings->setValue(enabledKey, enabled);
    emit changed();
}

void NotificationPreferences::setNotificationPosition(const QString &position)
{
    if (m_position == position || !validPosition(position))
        return;
    m_position = position;
    if (m_settings)
        m_settings->setValue(positionKey, position);
    emit changed();
}
