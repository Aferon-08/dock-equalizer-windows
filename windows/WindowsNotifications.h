#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantMap>
#include <QWindow>

#include <memory>

class WindowsNotifications final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString status READ status NOTIFY statusChanged FINAL)
    Q_PROPERTY(QString diagnostic READ diagnostic NOTIFY statusChanged FINAL)
    Q_PROPERTY(QString testResult READ testResult NOTIFY testChanged FINAL)
    Q_PROPERTY(bool testing READ testing NOTIFY testChanged FINAL)

public:
    explicit WindowsNotifications(bool enabled);
    ~WindowsNotifications() override;

    QString status() const { return m_status; }
    QString diagnostic() const { return m_diagnostic; }
    QString testResult() const { return m_testResult; }
    bool testing() const { return m_testing; }
    static bool hasPackageIdentity();
    Q_INVOKABLE void requestAccess(QWindow *owner);
    Q_INVOKABLE void sendTestNotification();

signals:
    void statusChanged();
    void testChanged();
    void notification(const QVariantMap &event);

private:
    struct Private;
    void refresh();
    void setStatus(const QString &status, const QString &diagnostic = {});
    void setTestResult(const QString &result, bool testing = false);

    std::unique_ptr<Private> m_data;
    QTimer m_timer;
    QString m_status = QStringLiteral("unavailable");
    QString m_diagnostic;
    QString m_testResult;
    bool m_testing = false;
};
