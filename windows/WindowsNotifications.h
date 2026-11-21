#pragma once

#include <QObject>
#include <QTimer>
#include <QVariantMap>
#include <QWindow>

#include <memory>

class QSettings;

class WindowsNotifications final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString status READ status NOTIFY statusChanged FINAL)
    Q_PROPERTY(QString diagnostic READ diagnostic NOTIFY statusChanged FINAL)
    Q_PROPERTY(QString testResult READ testResult NOTIFY testChanged FINAL)
    Q_PROPERTY(bool testing READ testing NOTIFY testChanged FINAL)
    Q_PROPERTY(bool bannerControlAvailable READ bannerControlAvailable NOTIFY bannerSettingsChanged FINAL)
    Q_PROPERTY(bool bannersHidden READ bannersHidden NOTIFY bannerSettingsChanged FINAL)
    Q_PROPERTY(int suppressedBannerCount READ suppressedBannerCount NOTIFY bannerSettingsChanged FINAL)
    Q_PROPERTY(QString bannerError READ bannerError NOTIFY bannerSettingsChanged FINAL)

public:
    WindowsNotifications(bool enabled, QSettings &settings);
    ~WindowsNotifications() override;

    QString status() const { return m_status; }
    QString diagnostic() const { return m_diagnostic; }
    QString testResult() const { return m_testResult; }
    bool testing() const { return m_testing; }
    bool bannerControlAvailable() const { return m_bannerControlAvailable; }
    bool bannersHidden() const { return m_bannersHidden; }
    int suppressedBannerCount() const { return m_suppressedBannerCount; }
    QString bannerError() const { return m_bannerError; }
    static bool hasPackageIdentity();
    void setDockAvailable(bool available);
    Q_INVOKABLE void requestAccess(QWindow *owner);
    Q_INVOKABLE void sendTestNotification();
    Q_INVOKABLE void setBannersHidden(bool hidden);

signals:
    void statusChanged();
    void testChanged();
    void bannerSettingsChanged();
    void notification(const QVariantMap &event);

private:
    struct Private;
    void refresh();
    void refreshBannerSettings();
    void setStatus(const QString &status, const QString &diagnostic = {});
    void setTestResult(const QString &result, bool testing = false);

    std::unique_ptr<Private> m_data;
    QTimer m_timer;
    QString m_status = QStringLiteral("unavailable");
    QString m_diagnostic;
    QString m_testResult;
    bool m_testing = false;
    bool m_bannerControlAvailable = false;
    bool m_bannersHidden = false;
    int m_suppressedBannerCount = 0;
    QString m_bannerError;
};
