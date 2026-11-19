#include "../LyricsSearch.h"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QHostAddress>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkProxy>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QThread>
#include <QUrlQuery>

#include <cstdio>
#include <functional>

namespace {

bool expect(bool result, const char *message)
{
    if (!result)
        std::fprintf(stderr, "%s\n", message);
    return result;
}

bool until(const std::function<bool()> &test, int limit = 3500)
{
    QElapsedTimer timer;
    timer.start();
    while (!test() && timer.elapsed() < limit) {
        QCoreApplication::processEvents(QEventLoop::AllEvents);
        QThread::msleep(5);
    }
    return test();
}

QJsonObject record(int id, const QString &title, double duration, const QString &lyrics)
{
    return {{QStringLiteral("id"), id}, {QStringLiteral("trackName"), title},
        {QStringLiteral("artistName"), QStringLiteral("Исполнитель")},
        {QStringLiteral("albumName"), QStringLiteral("Альбом")},
        {QStringLiteral("duration"), duration}, {QStringLiteral("syncedLyrics"), lyrics}};
}

QString firstLine(const LyricsSearch &search)
{
    const auto lines = search.document().value(QStringLiteral("lines")).toList();
    return lines.value(0).toMap().value(QStringLiteral("text")).toString();
}

class Fixture
{
public:
    QTcpServer server;
    QString lastArtist;
    QStringList requests;
    QStringList paths;
    bool escapedPlus = false;
    bool lateResponse = false;

    Fixture()
    {
        server.setProxy(QNetworkProxy::NoProxy);
        QObject::connect(&server, &QTcpServer::newConnection, &server, [this] {
            while (auto *socket = server.nextPendingConnection()) {
                QObject::connect(socket, &QTcpSocket::readyRead, socket, [this, socket] {
                    if (socket->property("received").toBool() || !socket->canReadLine())
                        return;
                    const auto request = socket->readLine().split(' ');
                    if (request.size() < 2)
                        return;
                    socket->setProperty("received", true);
                    const auto target = QUrl::fromEncoded(request[1]);
                    paths.append(target.path());
                    const QUrlQuery query(target);
                    const auto title = query.queryItemValue(QStringLiteral("track_name"), QUrl::FullyDecoded);
                    lastArtist = query.queryItemValue(QStringLiteral("artist_name"), QUrl::FullyDecoded);
                    requests.append(title);
                    const auto valid = record(1, title, 180, QStringLiteral("[00:01]Текст ") + title);
                    QJsonArray rows{valid};
                    int status = 200;
                    if (title == QStringLiteral("Песня C++")) {
                        escapedPlus = request[1].contains("C%2B%2B");
                        rows = {record(2, title, 195, QStringLiteral("[00:01]Другая запись")), valid};
                    }
                    if (title == QStringLiteral("Две версии"))
                        rows.append(record(3, title, 181, QStringLiteral("[00:01]Вторая версия")));
                    if (title == QStringLiteral("Без тайминга"))
                        rows = {record(4, title, 180, QString())};
                    if (title == QStringLiteral("Ошибка"))
                        status = 503;
                    auto body = QJsonDocument(rows).toJson(QJsonDocument::Compact);
                    if (target.path() == QStringLiteral("/api/search") && title == QStringLiteral("Через SimpMusic"))
                        status = 403;
                    if (target.path() == QStringLiteral("/plus")) {
                        status = query.queryItemValue(QStringLiteral("title"), QUrl::FullyDecoded) == QStringLiteral("Ошибка")
                            ? 200 : 404;
                        body = R"({"lyrics":[{"time":1000,"duration":2000,"text":"Найдено здесь",
                            "syllabus":[{"time":1000,"duration":1000,"text":"Найдено "},
                                        {"time":2000,"duration":1000,"text":"здесь"}]}]})";
                    }
                    if (target.path() == QStringLiteral("/better")) {
                        status = query.queryItemValue(QStringLiteral("s"), QUrl::FullyDecoded) == QStringLiteral("Через Better")
                            ? 200 : 401;
                        body = R"({"ttml":"<tt><body><p begin='1s' end='3s'><span begin='1s' end='2s'>Слова</span> <span begin='2s' end='3s'>здесь</span></p></body></tt>"})";
                    }
                    if (target.path() == QStringLiteral("/simp/search"))
                        body = R"({"success":true,"data":[{"videoId":"X1234567890","songTitle":"Через SimpMusic",
                            "artistName":"Исполнитель","durationSeconds":180}]})";
                    if (target.path() == QStringLiteral("/simp/X1234567890"))
                        body = R"({"success":true,"data":[{"songTitle":"Через SimpMusic","artistName":"Исполнитель",
                            "durationSeconds":180,"syncedLyrics":"[00:01]Вторая база"}]})";
                    const auto respond = [socket, status, body] {
                        if (socket->state() != QAbstractSocket::ConnectedState)
                            return;
                        socket->write("HTTP/1.1 " + QByteArray::number(status) + " Test\r\nContent-Type: application/json\r\n"
                            "Connection: close\r\nContent-Length: " + QByteArray::number(body.size()) + "\r\n\r\n" + body);
                        socket->disconnectFromHost();
                    };
                    if (title == QStringLiteral("Предыдущий трек"))
                        QTimer::singleShot(1200, socket, [this, respond] { lateResponse = true; respond(); });
                    else
                        respond();
                });
            }
        });
        server.listen(QHostAddress::LocalHost);
    }

    QUrl url(const QString &path = QStringLiteral("/api/search")) const
    {
        return QUrl(QStringLiteral("http://127.0.0.1:%1").arg(server.serverPort()) + path);
    }
};

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    const auto curl = app.arguments().value(1);
    if (!curl.isEmpty()) {
        qputenv("NO_PROXY", qgetenv("NO_PROXY") + ",127.0.0.1");
        qputenv("no_proxy", qgetenv("no_proxy") + ",127.0.0.1");
    }
    QNetworkProxy::setApplicationProxy(QNetworkProxy::NoProxy);
    Fixture fixture;
    QTemporaryDir cache;
    if (!expect(fixture.server.isListening() && cache.isValid(), "Could not start the lyrics test fixture"))
        return 1;

    const auto artist = QStringLiteral("Исполнитель");
    const auto album = QStringLiteral("Альбом");
    const LyricsSearch::Endpoints primary{fixture.url(), {}, {}, {}};
    LyricsSearch search(primary, cache.path(), curl);
    search.setTrack(QStringLiteral("session1:one"), QStringLiteral("Песня C++"), artist, album, 180);
    if (!expect(until([&] { return !search.searching(); })
            && firstLine(search) == QStringLiteral("Текст Песня C++")
            && fixture.requests == QStringList{QStringLiteral("Песня C++")} && fixture.lastArtist == artist
            && fixture.escapedPlus,
            "Automatic match must select by duration and send encoded title and artist"))
        return 1;

    search.setTrack(QStringLiteral("session1:two"), QStringLiteral("Две версии"), artist, album, 180);
    if (!expect(until([&] { return !search.searching(); }) && search.document().isEmpty()
            && search.choices().size() == 2,
            "Different versions with equally plausible metadata require selection")
            || !expect(!search.choose(QStringLiteral("session1:one"), 1)
                && search.choose(QStringLiteral("session1:two"), 1)
                && firstLine(search) == QStringLiteral("Вторая версия"),
                "Selection must reject the previous track and apply the chosen version"))
        return 1;

    const auto requestsBeforeCache = fixture.requests.size();
    LyricsSearch offline(primary, cache.path(), curl);
    offline.setAutomatic(false);
    offline.setTrack(QStringLiteral("session2:cached"), QStringLiteral("Две версии"), artist, album, 180);
    if (!expect(!offline.searching() && firstLine(offline) == QStringLiteral("Вторая версия")
            && fixture.requests.size() == requestsBeforeCache,
            "The cache must survive new sessions and work with online search disabled"))
        return 1;
    offline.setTrack(QStringLiteral("session2:other"), QStringLiteral("Две версии"), artist, album, 220);
    if (!expect(!offline.searching() && offline.document().isEmpty(), "A different version must not reuse the cache"))
        return 1;

    search.setTrack(QStringLiteral("session1:slow"), QStringLiteral("Предыдущий трек"), artist, album, 180);
    if (!expect(until([&] { return fixture.requests.contains(QStringLiteral("Предыдущий трек")); }),
            "A slow request must be in flight before switching tracks"))
        return 1;
    search.setTrack(QStringLiteral("session1:new"), QStringLiteral("Новый трек"), artist, album, 180);
    if (!expect(search.document().isEmpty() && until([&] { return !search.searching() && fixture.lateResponse; })
            && firstLine(search) == QStringLiteral("Текст Новый трек"),
            "The old request must not change the lyrics after switching tracks"))
        return 1;

    search.setTrack(QStringLiteral("session1:missing"), QStringLiteral("Без тайминга"), artist, album, 180);
    if (!expect(until([&] { return !search.searching(); }) && search.document().isEmpty()
            && search.statusText().contains(QStringLiteral("не найдена")),
            "A song with no synced lyrics must report no result"))
        return 1;
    search.setTrack(QStringLiteral("session1:failed"), QStringLiteral("Ошибка"), artist, album, 180);
    if (!expect(until([&] { return !search.searching(); }) && search.document().isEmpty()
            && search.statusText().contains(QStringLiteral("недоступен"))
            && search.sourceDetails().contains(QStringLiteral("LRCLIB · HTTP 503")),
            "Show the HTTP error when no service answers"))
        return 1;

    LyricsSearch multi(LyricsSearch::Endpoints{fixture.url(), fixture.url(QStringLiteral("/plus")),
        fixture.url(QStringLiteral("/simp/")), fixture.url(QStringLiteral("/better"))}, QString(), curl);
    multi.setTrack(QStringLiteral("session1:multi"), QStringLiteral("Ошибка (Official Video)"), artist, album, 180);
    if (!expect(until([&] { return !multi.searching(); }) && firstLine(multi) == QStringLiteral("Найдено здесь")
            && multi.document().value(QStringLiteral("wordCount")).toInt() == 2
            && multi.sourceDetails().contains(QStringLiteral("LRCLIB · HTTP 503")),
            "LyricsPlus must preserve word timing and supply lyrics when LRCLIB fails"))
        return 1;
    multi.setTrack(QStringLiteral("session1:simp"), QStringLiteral("Через SimpMusic"), artist, album, 180);
    if (!expect(until([&] { return !multi.searching(); }) && firstLine(multi) == QStringLiteral("Вторая база")
            && multi.statusText().contains(QStringLiteral("SimpMusic")),
            "SimpMusic must fetch a matching song by its video ID")) {
        std::fprintf(stderr, "%s\n%s\nPaths: %s\n", qPrintable(multi.statusText()),
            qPrintable(multi.sourceDetails()), qPrintable(fixture.paths.join(QStringLiteral(", "))));
        return 1;
    }
    multi.setTrack(QStringLiteral("session1:better"), QStringLiteral("Через Better"), artist, album, 180);
    if (!expect(until([&] { return !multi.searching(); }) && firstLine(multi) == QStringLiteral("Слова здесь")
            && multi.document().value(QStringLiteral("wordCount")).toInt() == 2
            && multi.statusText().contains(QStringLiteral("Better Lyrics")), "Better Lyrics TTML must win with word timing"))
        return 1;

    LyricsSearch fallback(primary, {}, cache.filePath(QStringLiteral("missing-curl.exe")));
    fallback.setTrack(QStringLiteral("session1:fallback"), QStringLiteral("Резерв"), artist, album, 180);
    if (!expect(until([&] { return !fallback.searching(); }) && firstLine(fallback) == QStringLiteral("Текст Резерв"),
                "A curl startup failure must fall back to Qt transport"))
        return 1;

    if (!curl.isEmpty()) {
        QTcpServer closedPort;
        if (!closedPort.listen(QHostAddress::LocalHost))
            return 1;
        const auto port = closedPort.serverPort();
        closedPort.close();
        LyricsHttp http(curl);
        QString error;
        http.get(QUrl(QStringLiteral("http://127.0.0.1:%1/").arg(port)), [&](const LyricsHttp::Result &result) {
            error = result.error;
        });
        if (!expect(until([&] { return !error.isEmpty(); }) && error.contains(QStringLiteral("curl 7")),
                    "A connection failure must expose curl's exit code"))
            return 1;
    }
    return 0;
}
