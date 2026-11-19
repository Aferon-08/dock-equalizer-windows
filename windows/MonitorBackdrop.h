#pragma once

#include <QImage>
#include <QQuickItem>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

#include <memory>

class MonitorBackdrop : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged FINAL)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged FINAL)

public:
    explicit MonitorBackdrop(QQuickItem *parent = nullptr);
    ~MonitorBackdrop() override;

    bool active() const { return m_active; }
    void setActive(bool active);
    QString status() const { return m_status; }

signals:
    void activeChanged();
    void statusChanged();

protected:
    QSGNode *updatePaintNode(QSGNode *node, UpdatePaintNodeData *) override;

private:
    void poll();
    void suspend();
    void setStatus(const QString &status);
    void clearFrame();

#ifdef Q_OS_WIN
    struct Capture;
    std::unique_ptr<Capture> m_capture;
#endif
    QTimer m_poll;
    QImage m_frame;
    QRectF m_frameSceneRect;
    QString m_status;
    bool m_active = false;
};
