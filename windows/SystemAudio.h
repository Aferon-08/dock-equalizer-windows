#pragma once

#include <QObject>
#include <QVariantList>

#include <memory>

class SystemAudio final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList bands READ bands NOTIFY changed FINAL)
    Q_PROPERTY(bool audible READ audible NOTIFY changed FINAL)

public:
    explicit SystemAudio(bool enabled);
    ~SystemAudio() override;

    QVariantList bands() const { return m_bands; }
    bool audible() const { return m_audible; }

signals:
    void changed();

private:
    QVariantList m_bands;
    bool m_audible = false;
#ifdef Q_OS_WIN
    class Capture;
    std::unique_ptr<Capture> m_capture;
#endif
};
