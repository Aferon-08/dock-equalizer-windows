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
    QString proxyAddress() const { return m_proxy.toString(QUrl::FullyEncoded); }
    bool setProxyAddress(const QString &address);
    qsizetype pendingCount() const { return m_curlRequests.size() + m_qtRequests.size(); }
    void get(const QUrl &url, Completion done, const QString &referer = {});
    void cancel();

private:
    struct Request
    {
        Completion done;
        QByteArray bytes;
    };

    void getWithQt(const QUrl &url, Completion done, const QString &referer);
    void getWithCurl(const QUrl &url, Completion done, const QString &referer);
    void finishQt(QNetworkReply *reply);
    void finishCurl(QProcess *process, int exitCode, bool crashed, const QUrl &url, const QString &referer);

    QString m_curl;
    QUrl m_proxy;
    QNetworkAccessManager m_network;
    QHash<QNetworkReply *, Request> m_qtRequests;
    QHash<QProcess *, Request> m_curlRequests;
};
