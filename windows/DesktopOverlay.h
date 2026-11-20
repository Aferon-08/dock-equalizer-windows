#pragma once

#include <QObject>
#include <QPointer>
#include <QRect>
#include <QRegion>
#include <QWindow>

class QScreen;

class DesktopOverlay final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QRect workArea READ workArea NOTIFY workAreaChanged FINAL)
    Q_PROPERTY(bool fullscreenActive READ fullscreenActive NOTIFY fullscreenActiveChanged FINAL)
    Q_PROPERTY(bool expandedObstructed READ expandedObstructed NOTIFY expandedObstructedChanged FINAL)

public:
    explicit DesktopOverlay(QScreen *screen);

    QRect workArea() const { return m_workArea; }
    bool fullscreenActive() const { return m_fullscreenActive; }
    bool expandedObstructed() const { return m_expandedObstructed; }

    Q_INVOKABLE void setPanelRegion(QWindow *window, const QRectF &body, qreal radius,
                                    const QRectF &leftWing, const QRectF &rightWing);
    Q_INVOKABLE void setExpandedRegion(QWindow *window, const QRectF &bounds, qreal radius);

signals:
    void workAreaChanged();
    void fullscreenActiveChanged();
    void expandedObstructedChanged();
    void showRequested();
    void settingsRequested(const QString &section);

private:
    void updateWorkArea();
    void updateDesktopState();
    void updatePointerPassthrough();

    QPointer<QScreen> m_screen;
    QPointer<QWindow> m_panel;
    QRect m_workArea;
    QRegion m_panelRegion;
    QRectF m_expandedBounds;
    qreal m_expandedRadius = 0;
    bool m_fullscreenActive = false;
    bool m_expandedObstructed = false;
};
