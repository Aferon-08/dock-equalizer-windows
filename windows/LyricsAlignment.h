#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QObject>
#include <QProcess>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>

#include <memory>

class QLockFile;
class QTemporaryDir;

class LyricsAlignment final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool ready READ ready NOTIFY changed FINAL)
    Q_PROPERTY(bool busy READ busy NOTIFY changed FINAL)
    Q_PROPERTY(bool hasResult READ hasResult NOTIFY changed FINAL)
    Q_PROPERTY(double progress READ progress NOTIFY changed FINAL)
    Q_PROPERTY(QString statusText READ statusText NOTIFY changed FINAL)

public:
    explicit LyricsAlignment(QObject *parent = nullptr);
    LyricsAlignment(QString bundle, QString dataDirectory, QObject *parent = nullptr);
    ~LyricsAlignment() override;

    bool ready() const;
    bool busy() const { return m_work != nullptr; }
    bool hasResult() const { return !m_export.isEmpty(); }
    double progress() const { return m_progress; }
    QString statusText() const { return m_status; }

    Q_INVOKABLE void prepare();
    Q_INVOKABLE void align(const QUrl &audio, const QString &text, const QString &trackKey, double trackDuration);
    Q_INVOKABLE void cancel();
    Q_INVOKABLE QString save(const QUrl &target) const;

signals:
    void changed();
    void aligned(const QString &trackKey, const QVariantMap &document);

private:
    void launch(QJsonObject request);
    void sendRequest();
    void readEvents();
    void stop(const QString &message);
    void finish(bool cleanExit);
    void closeJob();
    void setStatus(const QString &message);

    const QString m_bundle;
    const QString m_data;
    QProcess m_process;
    QTimer m_deadline;
    std::unique_ptr<QLockFile> m_lock;
    std::unique_ptr<QTemporaryDir> m_work;
    QString m_jobId, m_trackKey, m_status, m_stopMessage;
    QByteArray m_request, m_stdout, m_export;
    QJsonObject m_result;
    double m_duration = 0;
    double m_progress = 0;
    bool m_preparing = false;
#ifdef Q_OS_WIN
    void *m_job = nullptr;
#endif
};
