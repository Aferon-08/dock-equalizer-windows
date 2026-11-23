#pragma once

#include <QByteArray>
#include <QJsonArray>
#include <QString>
#include <QUrl>

#include <optional>

struct UpdateRelease
{
    QString tag;
    QUrl page;
    QUrl installer;
    QByteArray sha256;
    qint64 size = 0;

    QString version() const { return tag.mid(1); }
    bool hasInstaller() const { return installer.isValid() && sha256.size() == 32 && size > 0; }

    static int compareVersions(const QString &first, const QString &second);
    static std::optional<UpdateRelease> newest(const QJsonArray &releases, bool prerelease);
};
