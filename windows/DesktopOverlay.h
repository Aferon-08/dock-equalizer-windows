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

public:
    explicit DesktopOverlay(QObject *parent = nullptr);

    QRect workArea() const { return m_workArea; }
    bool fullscreenActive() const { return m_fullscreenActive; }

    Q_INVOKABLE void setPanelRegion(QWindow *window, const QRectF &body, qreal radius,
                                    const QRectF &leftWing, const QRectF &rightWing);

signals:
    void workAreaChanged();
    void fullscreenActiveChanged();

private:
    void trackPrimaryScreen(QScreen *screen);
    void updateWorkArea();
    void updateFullscreenState();
    void updatePointerPassthrough();

    QPointer<QScreen> m_screen;
    QPointer<QWindow> m_panel;
    QRect m_workArea;
    QRegion m_panelRegion;
    bool m_fullscreenActive = false;
};
