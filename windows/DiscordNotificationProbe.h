#pragma once

#include <QHash>
#include <QList>
#include <QRegularExpression>
#include <QString>

#include <utility>

class DiscordNotificationProbe
{
public:
    struct Entry {
        quint32 id;
        qint64 createdAt;
        QString source;
    };

    enum class Action { Present, Added, Removed };
    struct Change {
        Action action;
        Entry entry;
    };

    // These labels locate likely Discord entries for a controlled test.
    static QString source(const QString &appId, const QString &displayName)
    {
        static const QRegularExpression appPattern(QStringLiteral(
            R"((?:^|[.!])Discord(?:Canary|PTB|Development)?(?:$|[.!_]))"),
            QRegularExpression::CaseInsensitiveOption);
        static const QRegularExpression namePattern(QStringLiteral(
            R"(^Discord(?: (?:Canary|PTB|Development))?$)"), QRegularExpression::CaseInsensitiveOption);
        if (appPattern.match(appId).hasMatch() || namePattern.match(displayName).hasMatch())
            return appId.isEmpty() ? displayName : appId;
        return {};
    }

    bool active() const { return m_active; }
    bool hasBaseline() const { return m_hasBaseline; }

    void setActive(bool active)
    {
        m_active = active;
        m_hasBaseline = false;
        m_previous.clear();
    }

    QList<Change> observe(const QList<Entry> &snapshot)
    {
        QList<Change> changes;
        if (!m_active)
            return changes;

        QHash<Key, QString> current;
        for (const auto &entry : snapshot) {
            const Key key{entry.id, entry.createdAt};
            const auto old = m_previous.constFind(key);
            if (old != m_previous.cend()) {
                current.insert(key, old.value());
            } else if (!entry.source.isEmpty() && !current.contains(key)) {
                current.insert(key, entry.source);
                changes.append({m_hasBaseline ? Action::Added : Action::Present, entry});
            }
        }
        for (auto old = m_previous.cbegin(); old != m_previous.cend(); ++old) {
            if (!current.contains(old.key()))
                changes.append({Action::Removed, {old.key().first, old.key().second, old.value()}});
        }
        m_previous.swap(current);
        m_hasBaseline = true;
        return changes;
    }

private:
    using Key = std::pair<quint32, qint64>;
    QHash<Key, QString> m_previous;
    bool m_active = false;
    bool m_hasBaseline = false;
};
