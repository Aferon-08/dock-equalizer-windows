#pragma once

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
    Q_PROPERTY(bool hasFrame READ hasFrame NOTIFY hasFrameChanged FINAL)
    Q_PROPERTY(bool borderless READ borderless WRITE setBorderless FINAL)
    Q_PROPERTY(bool requestingBorderless READ requestingBorderless NOTIFY borderStatusChanged FINAL)
    Q_PROPERTY(QString borderStatus READ borderStatus NOTIFY borderStatusChanged FINAL)

public:
    explicit MonitorBackdrop(QQuickItem *parent = nullptr);
    ~MonitorBackdrop() override;

    bool active() const { return m_active; }
    void setActive(bool active);
    QString status() const { return m_status; }
    bool hasFrame() const;
    bool borderless() const { return m_borderless; }
    void setBorderless(bool borderless);
    bool requestingBorderless() const;
    QString borderStatus() const { return m_borderStatus; }
    Q_INVOKABLE void requestBorderless();

signals:
    void activeChanged();
    void statusChanged();
    void hasFrameChanged();
    void borderStatusChanged();
    void borderlessGranted();

protected:
    QSGNode *updatePaintNode(QSGNode *node, UpdatePaintNodeData *) override;

private:
    void poll();
    void suspend();
    void setStatus(const QString &status);
    void clearFrame();
    void pollBorderRequest();

#ifdef Q_OS_WIN
    struct Capture;
    std::unique_ptr<Capture> m_capture;
    struct BorderRequest;
    std::unique_ptr<BorderRequest> m_borderRequest;
#endif
    QTimer m_poll;
    QTimer m_borderPoll;
    QString m_status;
    QString m_borderStatus;
    bool m_active = false;
    bool m_borderless = false;
};
