#pragma once

#include <QImage>
#include <QQuickPaintedItem>
#include <QVariant>
#include <QtQml/qqmlregistration.h>

class DiscordParticipantAvatar : public QQuickPaintedItem
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QVariant source READ source WRITE setSource NOTIFY sourceChanged FINAL)
    Q_PROPERTY(bool loaded READ loaded NOTIFY sourceChanged FINAL)

public:
    explicit DiscordParticipantAvatar(QQuickItem *parent = nullptr);
    QVariant source() const { return m_source; }
    void setSource(const QVariant &source);
    bool loaded() const { return !m_image.isNull(); }
    void paint(QPainter *painter) override;

signals:
    void sourceChanged();

private:
    QVariant m_source;
    QImage m_image;
};
