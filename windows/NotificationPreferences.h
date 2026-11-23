#pragma once

#include <QObject>
#include <QString>

class QSettings;

class NotificationPreferences final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool aboveWindows READ aboveWindows WRITE setAboveWindows NOTIFY changed FINAL)
    Q_PROPERTY(QString notificationPosition READ notificationPosition WRITE setNotificationPosition NOTIFY changed FINAL)

public:
    explicit NotificationPreferences(QSettings *settings);

    bool aboveWindows() const { return m_aboveWindows; }
    QString notificationPosition() const { return m_position; }
    void setAboveWindows(bool enabled);
    void setNotificationPosition(const QString &position);

signals:
    void changed();

private:
    QSettings *const m_settings;
    bool m_aboveWindows = false;
    QString m_position;
};
