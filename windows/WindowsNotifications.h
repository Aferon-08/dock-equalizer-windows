#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantMap>

#include <memory>

class WindowsNotifications final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString status READ status NOTIFY statusChanged FINAL)

public:
    explicit WindowsNotifications(bool enabled);
    ~WindowsNotifications() override;

    QString status() const { return m_status; }
    Q_INVOKABLE void requestAccess();

signals:
    void statusChanged();
    void notification(const QVariantMap &event);

private:
    struct Private;
    void refresh();
    void setStatus(const QString &status);

    std::unique_ptr<Private> m_data;
    QTimer m_timer;
    QString m_status = QStringLiteral("unavailable");
};
