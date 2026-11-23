#pragma once

#include <QQuickItem>
#include <QTimer>
#include <QtQml/qqmlregistration.h>

#include <memory>

class VoicePreview : public QQuickItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(bool active READ active WRITE setActive NOTIFY activeChanged FINAL)
    Q_PROPERTY(bool available READ available CONSTANT FINAL)
    Q_PROPERTY(bool opened READ opened NOTIFY openedChanged FINAL)
    Q_PROPERTY(bool hasFrame READ hasFrame NOTIFY hasFrameChanged FINAL)
    Q_PROPERTY(bool selecting READ selecting NOTIFY selectingChanged FINAL)
    Q_PROPERTY(bool retryable READ retryable NOTIFY statusChanged FINAL)
    Q_PROPERTY(QString status READ status NOTIFY statusChanged FINAL)

public:
    explicit VoicePreview(QQuickItem *parent = nullptr);
    ~VoicePreview() override;

    bool active() const { return m_active; }
    void setActive(bool active);
    bool available() const;
    bool opened() const { return m_opened; }
    bool hasFrame() const;
    bool selecting() const;
    bool retryable() const { return m_retryable; }
    QString status() const { return m_status; }
    Q_INVOKABLE void chooseSource();
    Q_INVOKABLE void closePreview();

signals:
    void activeChanged();
    void openedChanged();
    void hasFrameChanged();
    void selectingChanged();
    void statusChanged();

protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    QSGNode *updatePaintNode(QSGNode *node, UpdatePaintNodeData *) override;
#ifdef Q_OS_WIN
    void itemChange(ItemChange change, const ItemChangeData &value) override;
#endif

private:
#ifdef Q_OS_WIN
    void poll();
    void suspend();
    void clearFrame();
    void failSource(const QString &status);
    void setStatus(const QString &status, bool retryable = false);

    struct Capture;
    std::unique_ptr<Capture> m_capture;
    QTimer m_poll;
#endif
    QString m_status;
    bool m_active = false;
    bool m_opened = false;
    bool m_retryable = false;
};
