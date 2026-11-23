#pragma once

#include "UpdateRelease.h"

#include <QCryptographicHash>
#include <QFile>
#include <QNetworkAccessManager>
#include <QObject>

#include <memory>

class QNetworkReply;
class QSettings;
class QTemporaryDir;

class SoftwareUpdates final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool canInstall READ canInstall NOTIFY changed)
    Q_PROPERTY(QString channel READ channel WRITE setChannel NOTIFY changed)
    Q_PROPERTY(bool automatic READ automatic WRITE setAutomatic NOTIFY changed)
    Q_PROPERTY(QString currentVersion READ currentVersion CONSTANT)
    Q_PROPERTY(QString updateVersion READ updateVersion NOTIFY changed)
    Q_PROPERTY(QString statusText READ statusText NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool installing READ installing NOTIFY changed)

public:
    SoftwareUpdates(QSettings &settings, QString version, bool enabled);
    ~SoftwareUpdates() override;

    bool available() const { return m_enabled; }
    bool canInstall() const { return !m_installRoot.isEmpty() && m_release && m_release->hasInstaller(); }
    QString channel() const { return m_channel; }
    bool automatic() const { return m_automatic; }
    QString currentVersion() const { return m_version; }
    QString updateVersion() const { return m_release ? m_release->version() : QString(); }
    QString statusText() const { return m_status; }
    bool busy() const { return m_operation != Operation::Idle; }
    bool installing() const { return m_operation == Operation::Launching; }

    void setChannel(const QString &channel);
    void setAutomatic(bool automatic);
    Q_INVOKABLE void check();
    Q_INVOKABLE void install();
    Q_INVOKABLE void openRelease() const;
    void shutdown();

signals:
    void changed();
    void updateAvailable(const QString &version);
    void installationStarted();

private:
    enum class Operation { Idle, Checking, Downloading, Launching };

    void checkPage(int page);
    void acceptRelease(std::optional<UpdateRelease> release);
    void startDownload(bool automatic);
    void startRequest(const QUrl &url);
    void readReply();
    void finishReply();
    void finishDownload();
    void cancelRequest();
    void fail(const QString &error);
    void setStatus(const QString &status, Operation operation = Operation::Idle);
    void announce();

    QSettings &m_settings;
    const QString m_version;
    const bool m_enabled;
    const QString m_installRoot;
    QString m_channel;
    QString m_status;
    QString m_announcedTag;
    bool m_automatic;
    bool m_automaticDownload = false;
    bool m_stopping = false;
    Operation m_operation = Operation::Idle;
    int m_page = 1;
    int m_progress = -1;
    QNetworkAccessManager m_network;
    QNetworkReply *m_reply = nullptr;
    QByteArray m_response;
    std::optional<UpdateRelease> m_release;
    std::unique_ptr<QTemporaryDir> m_staging;
    QFile m_file;
    QCryptographicHash m_hash{QCryptographicHash::Sha256};
};
