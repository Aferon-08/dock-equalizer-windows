#pragma once

#include <QAbstractListModel>
#include <QPointer>
#include <QScreen>
#include <QVariantMap>

class QSettings;

class DisplaySettings final : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY displaysChanged FINAL)
    Q_PROPERTY(int enabledCount READ enabledCount NOTIFY enabledScreensChanged FINAL)

public:
    explicit DisplaySettings(QSettings *settings);

    int count() const { return int(m_displays.size()); }
    int enabledCount() const { return int(enabledScreens().size()); }
    QList<QScreen *> enabledScreens() const;
    Q_INVOKABLE void setDockEnabled(const QString &id, bool enabled);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

signals:
    void displaysChanged();
    void enabledScreensChanged();

private:
    enum Role { Id = Qt::UserRole + 1, Name, Details, DockEnabled };

    struct Display {
        QPointer<QScreen> screen;
        QString id;
        QString name;
        QString details;
        int number = 0;
        bool enabled = false;
    };

    void watch(QScreen *screen);
    void refresh();

    QSettings *const m_settings;
    QVariantMap m_preferences;
    QList<Display> m_displays;
};
