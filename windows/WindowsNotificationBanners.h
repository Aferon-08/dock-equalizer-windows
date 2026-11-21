#pragma once

#include <QSet>
#include <QString>
#include <QVariantMap>

class QSettings;

class WindowsNotificationBanners final
{
public:
    struct Result {
        int hidden = 0;
        bool complete = true;
    };

    explicit WindowsNotificationBanners(QSettings &settings, QString registryPath = QStringLiteral(
        "Software\\Microsoft\\Windows\\CurrentVersion\\Notifications\\Settings"));

    bool available() const;
    Result suppress(const QSet<QString> &knownSenders);
    bool restore();

private:
    bool save(const QVariantMap &previous);

    QSettings &m_settings;
    const QString m_registryPath;
    QVariantMap m_previous;
    QSet<QString> m_changed;
};
