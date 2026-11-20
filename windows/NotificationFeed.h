#pragma once

#include <QSet>
#include <QtTypes>

#include <utility>

class NotificationFeed
{
public:
    void reset(qint64 startedAt)
    {
        m_startedAt = startedAt;
        m_first = true;
        m_previous.clear();
        m_current.clear();
    }

    bool observe(quint32 id, qint64 createdAt)
    {
        const auto key = std::make_pair(id, createdAt);
        const bool alreadySeen = m_previous.contains(key) || m_current.contains(key);
        m_current.insert(key);
        const bool fresh = createdAt > 0 ? createdAt >= m_startedAt : !m_first;
        return !alreadySeen && fresh;
    }

    void finish()
    {
        m_previous.swap(m_current);
        m_current.clear();
        m_first = false;
    }

private:
    using Key = std::pair<quint32, qint64>;
    qint64 m_startedAt = 0;
    bool m_first = true;
    QSet<Key> m_previous;
    QSet<Key> m_current;
};
