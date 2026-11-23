#pragma once

#include <QByteArray>
#include <QString>

namespace UpdateInstaller {

QString installedRoot(const QString &executable);
bool verifyPublisher(const QString &installer);
bool start(const QString &installer, const QByteArray &sha256, const QString &installRoot);

} // namespace UpdateInstaller
