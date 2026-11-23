#pragma once

#include <QObject>
#include <QPointer>
#include <QRect>
#include <QRegion>
#include <QWindow>
#include <QVariant>

class QEvent;
class QScreen;

class DesktopOverlay final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QRect screenArea READ screenArea NOTIFY screenAreaChanged FINAL)
    Q_PROPERTY(QRect workArea READ workArea NOTIFY workAreaChanged FINAL)
    Q_PROPERTY(QRect notificationWorkArea READ notificationWorkArea NOTIFY notificationWorkAreaChanged FINAL)
    Q_PROPERTY(bool bottomTaskbarVisible READ bottomTaskbarVisible NOTIFY bottomTaskbarVisibleChanged FINAL)
    Q_PROPERTY(bool fullscreenActive READ fullscreenActive NOTIFY fullscreenActiveChanged FINAL)
    Q_PROPERTY(bool expandedObstructed READ expandedObstructed NOTIFY expandedObstructedChanged FINAL)
    Q_PROPERTY(bool notificationObstructed READ notificationObstructed NOTIFY notificationObstructedChanged FINAL)
    Q_PROPERTY(QRectF compactNotificationArea READ compactNotificationArea NOTIFY compactNotificationAreaChanged FINAL)

public:
    explicit DesktopOverlay(QScreen *screen);

    QRect screenArea() const { return m_screenArea; }
    QRect workArea() const { return m_workArea; }
    QRect notificationWorkArea() const { return m_notificationWorkArea; }
    bool bottomTaskbarVisible() const { return m_bottomTaskbarVisible; }
    bool fullscreenActive() const { return m_fullscreenActive; }
    bool expandedObstructed() const { return m_expandedObstructed; }
    bool notificationObstructed() const { return m_notificationObstructed; }
    QRectF compactNotificationArea() const { return m_compactNotificationArea; }

    Q_INVOKABLE void setPanelRegion(QWindow *window, const QRectF &body, qreal radius,
                                    const QRectF &leftWing, const QRectF &rightWing,
                                    const QRectF &miniPlayer, const QRectF &neck,
                                    const QRectF &sideCall, const QRectF &sideCallNeck,
                                    const QVariantList &notificationParts);
    Q_INVOKABLE void setExpandedRegions(QWindow *window, const QRectF &player, qreal playerRadius,
                                       const QRectF &notification, qreal notificationRadius);
    Q_INVOKABLE void setCompactNotificationZone(QWindow *window, const QRectF &zone, const QSizeF &minimumSize);
    Q_INVOKABLE void setNotificationRegion(QWindow *window, const QRectF &body, qreal radius,
                                           const QVariantList &parts);

signals:
    void screenAreaChanged();
    void workAreaChanged();
    void notificationWorkAreaChanged();
    void bottomTaskbarVisibleChanged();
    void fullscreenActiveChanged();
    void expandedObstructedChanged();
    void notificationObstructedChanged();
    void compactNotificationAreaChanged();
    void showRequested();
    void settingsRequested(const QString &section);

private:
    bool eventFilter(QObject *object, QEvent *event) override;
    void updateScreenGeometry();
    void updateDesktopState();
    void updatePointerPassthrough();
    void updateNotificationWindow(bool promote);

    QPointer<QScreen> m_screen;
    QPointer<QWindow> m_panel;
    QPointer<QWindow> m_notificationWindow;
    QRect m_screenArea;
    QRect m_workArea;
    QRect m_notificationWorkArea;
    QRegion m_panelRegion;
    WId m_foregroundWindow = 0;
    QRectF m_expandedBounds;
    qreal m_expandedRadius = 0;
    QRectF m_notificationBounds;
    qreal m_notificationRadius = 0;
    QRectF m_notificationBody;
    qreal m_notificationBodyRadius = 0;
    QVariantList m_notificationParts;
    QRectF m_compactNotificationZone;
    QSizeF m_compactNotificationMinimum;
    QRectF m_compactNotificationArea;
    bool m_bottomTaskbarVisible = false;
    bool m_fullscreenActive = false;
    bool m_expandedObstructed = false;
    bool m_notificationObstructed = false;
};
