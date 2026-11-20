#pragma once

#include <QObject>
#include <QElapsedTimer>
#include <QThreadPool>
#include <QTimer>
#include <QVariantMap>

class WifiStatus final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged FINAL)
    Q_PROPERTY(QVariantMap snapshot READ snapshot NOTIFY snapshotChanged FINAL)

public:
    explicit WifiStatus(bool preview);
    ~WifiStatus() override;

    bool active() const { return m_active; }
    QVariantMap snapshot() const { return m_snapshot; }
    void setActive(bool active);

signals:
    void activeChanged();
    void snapshotChanged();
    void notification(const QVariantMap &event);

private:
    struct Reading {
        QVariantMap details;
        QString networkId;
        qint64 milliseconds = 0;
        quint64 received = 0;
        quint64 sent = 0;
        bool hasCounters = false;
    };

    static Reading readConnection(bool includeTraffic);
    static Reading previewReading(qint64 milliseconds);
    void sample();
    void accept(Reading reading);
    void reportConnection(const QString &state, const QString &adapter, const QString &ssid);

    const bool m_preview;
    bool m_active = false;
    bool m_pending = false;
    bool m_hasBaseline = false;
    bool m_connected = false;
    int m_disconnectedSamples = 0;
    QString m_adapter;
    QString m_ssid;
    QTimer m_timer;
    QElapsedTimer m_clock;
    Reading m_previous;
    QVariantList m_samples;
    QVariantMap m_snapshot{{QStringLiteral("state"), QStringLiteral("unavailable")}};
    QThreadPool m_worker;
};
