#pragma once

#include <QHash>
#include <QNetworkAccessManager>
#include <QUrl>

#include <functional>

class QNetworkReply;
class QProcess;

class LyricsHttp final : public QObject
{
public:
    struct Result
    {
        int status = 0;
        QByteArray body;
        QString error;
    };
    using Completion = std::function<void(Result)>;

    explicit LyricsHttp(QString curlExecutable);
    ~LyricsHttp() override;

    static QString windowsCurl();
    bool supportsHttps() const;
    qsizetype pendingCount() const { return m_curlRequests.size() + m_qtRequests.size(); }
    void get(const QUrl &url, Completion done);
    void cancel();

private:
    struct Request
    {
        Completion done;
        QByteArray bytes;
    };

    void getWithQt(const QUrl &url, Completion done);
    void getWithCurl(const QUrl &url, Completion done);
    void finishQt(QNetworkReply *reply);
    void finishCurl(QProcess *process, int exitCode, bool crashed);

    QString m_curl;
    QNetworkAccessManager m_network;
    QHash<QNetworkReply *, Request> m_qtRequests;
    QHash<QProcess *, Request> m_curlRequests;
};
