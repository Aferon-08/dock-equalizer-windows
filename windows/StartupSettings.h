#pragma once

#include <QObject>

class StartupSettings final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT FINAL)
    Q_PROPERTY(bool enabled READ enabled NOTIFY changed FINAL)
    Q_PROPERTY(bool otherCopy READ otherCopy NOTIFY changed FINAL)
    Q_PROPERTY(QString error READ error NOTIFY changed FINAL)

public:
    explicit StartupSettings(bool writable);

    bool available() const { return m_available; }
    bool enabled() const { return !m_registeredCommand.isEmpty(); }
    bool otherCopy() const { return enabled() && m_registeredCommand.compare(m_command, Qt::CaseInsensitive) != 0; }
    QString error() const { return m_error; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void setEnabled(bool enabled);

signals:
    void changed();

private:
    const bool m_available;
    const QString m_command;
    QString m_registeredCommand;
    QString m_error;
};
