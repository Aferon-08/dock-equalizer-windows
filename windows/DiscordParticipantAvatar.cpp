#include "DiscordParticipantAvatar.h"

#include <QPainter>
#include <QPainterPath>
#include <QUrl>

DiscordParticipantAvatar::DiscordParticipantAvatar(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    setAntialiasing(true);
}

void DiscordParticipantAvatar::setSource(const QVariant &source)
{
    if (m_source == source)
        return;
    m_source = source;
    m_image = source.value<QImage>();
    const auto url = source.toUrl();
    if (m_image.isNull() && url.scheme() == QStringLiteral("qrc"))
        m_image.load(QLatin1Char(':') + url.path());
    emit sourceChanged();
    update();
}

void DiscordParticipantAvatar::paint(QPainter *painter)
{
    if (m_image.isNull())
        return;

    const QRectF target = boundingRect();
    if (target.isEmpty())
        return;
    const qreal span = qMin(m_image.width(), m_image.height());
    const QRectF crop((m_image.width() - span) / 2, (m_image.height() - span) / 2, span, span);
    QPainterPath circle;
    circle.addEllipse(target);
    painter->setRenderHint(QPainter::SmoothPixmapTransform);
    painter->setClipPath(circle);
    painter->drawImage(target, m_image, crop);
}
