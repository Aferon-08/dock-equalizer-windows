#pragma once

#include "LyricsHttp.h"

#include <QJsonObject>
#include <QMap>
#include <QObject>
#include <QStringList>
#include <QTimer>
#include <QVariantList>
#include <QVariantMap>

#include <memory>

class QJSEngine;
class QJsonDocument;

class LyricsSearch final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool automatic READ automatic WRITE setAutomatic NOTIFY automaticChanged FINAL)
    Q_PROPERTY(QString proxyAddress READ proxyAddress NOTIFY proxyAddressChanged FINAL)
    Q_PROPERTY(bool canSearch READ canSearch NOTIFY changed FINAL)
    Q_PROPERTY(bool searching READ searching NOTIFY changed FINAL)
    Q_PROPERTY(QString trackKey READ trackKey NOTIFY changed FINAL)
    Q_PROPERTY(QString statusText READ statusText NOTIFY changed FINAL)
    Q_PROPERTY(QString sourceDetails READ sourceDetails NOTIFY changed FINAL)
    Q_PROPERTY(QVariantMap document READ document NOTIFY changed FINAL)
    Q_PROPERTY(QVariantList choices READ choices NOTIFY changed FINAL)

public:
    struct Endpoints
    {
        QUrl lrclib;
        QUrl lyricsPlus;
        QUrl simpMusic;
        QUrl betterLyrics;
        QUrl netEase;
    };

    explicit LyricsSearch(QObject *parent = nullptr);
    LyricsSearch(Endpoints endpoints, QString cacheDirectory, QString curlExecutable = {}, QObject *parent = nullptr);
    ~LyricsSearch() override;

    void setTrack(const QString &key, const QString &title, const QString &artist,
                  const QString &album, double duration);
    bool automatic() const { return m_automatic; }
    void setAutomatic(bool enabled);
    QString proxyAddress() const { return m_http.proxyAddress(); }
    bool canSearch() const { return !m_key.isEmpty() && !m_title.isEmpty(); }
    bool searching() const { return m_http.pendingCount() > 0 || m_delay.isActive(); }
    QString trackKey() const { return m_key; }
    QString statusText() const { return m_status; }
    QString sourceDetails() const;
    QVariantMap document() const { return m_document; }
    QVariantList choices() const { return m_choices; }

    Q_INVOKABLE void retry();
    Q_INVOKABLE bool choose(const QString &key, int index);
    Q_INVOKABLE QString configureProxy(const QString &address);

signals:
    void changed();
    void automaticChanged();
    void proxyAddressChanged();

private:
    enum class Step { Lrclib, LyricsPlus, SimpSearch, SimpLyrics, BetterLyrics, NetEaseSearch, NetEaseLyrics };

    struct Match
    {
        QJsonObject record;
        QVariantMap document;
    };

    void reset();
    void cancel();
    void request();
    void send(Step step, const QUrl &url, const QJsonObject &track = {});
    void finish(Step step, const QJsonObject &track, LyricsHttp::Result response);
    void receive(Step step, const QJsonDocument &json, const QJsonObject &track);
    void netEaseSearchResult(const QJsonObject &response);
    void appendMatch(const QJsonObject &record);
    void updateSelection();
    Match match(const QJsonObject &record);
    QVariant transform(const char *method, const QVariantList &arguments);
    QVariantMap parseLyrics(const QString &lrc, double duration);
    static QString provider(Step step);
    int automaticMatch() const;
    void use(const Match &match, bool cache);
    QString cachePath() const;
    bool loadCache();
    void saveCache(const Match &match) const;

    const Endpoints m_endpoints;
    const QString m_cacheDirectory;
    LyricsHttp m_http;
    std::unique_ptr<QJSEngine> m_math;
    QTimer m_delay;
    QString m_key, m_title, m_artist, m_album;
    QString m_queryTitle, m_queryArtist;
    double m_duration = 0;
    QString m_status;
    QVariantMap m_document;
    QList<Match> m_matches;
    QVariantList m_choices;
    QMap<QString, QString> m_sourceState;
    bool m_answered = false;
    bool m_manualChoice = false;
    bool m_automatic = true;
};
