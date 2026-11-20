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

private:
    struct Reading {
        QVariantMap details;
        QString networkId;
        qint64 milliseconds = 0;
        quint64 received = 0;
        quint64 sent = 0;
        bool hasCounters = false;
    };

    static Reading readConnection();
    static Reading previewReading(qint64 milliseconds);
    void sample();
    void accept(Reading reading);

    const bool m_preview;
    bool m_active = false;
    bool m_pending = false;
    quint64 m_generation = 0;
    QTimer m_timer;
    QElapsedTimer m_clock;
    Reading m_previous;
    QVariantList m_samples;
    QVariantMap m_snapshot;
    QThreadPool m_worker;
};
