#pragma once

#include <QObject>
#include <QUrl>
#include <QVariantMap>

class LyricsImport final : public QObject
{
    Q_OBJECT

public:
    using QObject::QObject;
    Q_INVOKABLE QVariantMap read(const QUrl &file, double trackDuration) const;
    static QVariantMap parseLrc(const QString &text, double duration);
};
