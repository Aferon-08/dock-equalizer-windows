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
    QStringList socksTargets;
    QStringList httpProxyTargets;
    bool escapedPlus = false;
    bool lateResponse = false;
    int retryRequests = 0;

    Fixture()
    {
        server.setProxy(QNetworkProxy::NoProxy);
        QObject::connect(&server, &QTcpServer::newConnection, &server, [this] {
            while (auto *socket = server.nextPendingConnection()) {
                QObject::connect(socket, &QTcpSocket::readyRead, socket, [this, socket] {
                    if (socket->property("received").toBool())
                        return;
                    const auto pending = socket->peek(socket->bytesAvailable());
                    if (pending.startsWith('\x05')) {
                        readSocks(socket, pending);
                        return;
                    }
                    if (!pending.contains("\r\n\r\n"))
                        return;
                    const auto request = socket->readLine().split(' ');
                    if (request.size() < 3)
                        return;
                    socket->setProperty("received", true);
                    const auto headers = socket->readAll().toLower().split('\n');
                    if (request[0] == "CONNECT") {
                        socket->write("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
                        socket->disconnectFromHost();
                        return;
                    }
                    const auto target = QUrl::fromEncoded(request[1]);
                    if (!target.host().isEmpty())
                        httpProxyTargets.append(target.host());
                    paths.append(target.path());
                    if (target.path() == QStringLiteral("/hang"))
                        return;
                    if (target.path() == QStringLiteral("/open-json") || target.path() == QStringLiteral("/open-error")
                            || target.path() == QStringLiteral("/broken-json") || target.path() == QStringLiteral("/retry")) {
                        if (request[2].trimmed() != "HTTP/1.1" || !headers.contains("connection: close\r")) {
                            socket->disconnectFromHost();
                            return;
                        }
                        const bool retry = target.path() == QStringLiteral("/retry");
                        const bool retrySucceeded = retry && ++retryRequests == 2;
                        const bool unavailable = target.path() == QStringLiteral("/open-error");
                        QByteArray body;
                        if (!unavailable)
                            body = retrySucceeded || target.path() == QStringLiteral("/open-json") ? R"({"lyrics":[]})" : "{";
                        const auto length = body.size() + (retrySucceeded ? 0 : 32);
                        socket->write(QByteArray(unavailable ? "HTTP/1.1 503 Test" : "HTTP/1.1 200 Test")
                            + "\r\nContent-Type: application/json\r\nContent-Length: " + QByteArray::number(length)
                            + "\r\n\r\n" + body);
                        if (retry || target.path() == QStringLiteral("/broken-json"))
                            socket->disconnectFromHost();
                        return;
                    }
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
                    if (title == QStringLiteral("Ошибка") || title == QStringLiteral("Через NetEase"))
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
                    if (target.path() == QStringLiteral("/netease/search/get/web"))
                        body = R"({"code":200,"result":{"songs":[
                            {"id":801,"name":"Через NetEase","duration":195000,"artists":[{"name":"Исполнитель"}]},
                            {"id":802,"name":"Через NetEase","duration":180000,"artists":[{"name":"Исполнитель"}],
                             "album":{"name":"Альбом"}}]}})";
                    if (target.path() == QStringLiteral("/netease/song/lyric/v1")) {
                        status = query.queryItemValue(QStringLiteral("id")) == QStringLiteral("802") ? 200 : 404;
                        body = R"({"code":200,"yrc":{"lyric":"[1000,1900](1000,900,0)Другой (2000,900,0)каталог"},
                            "lrc":{"lyric":"[00:01]Другой каталог"}})";
                    }
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

private:
    void readSocks(QTcpSocket *socket, const QByteArray &pending)
    {
        if (!socket->property("socksGreeting").toBool()) {
            if (pending.size() < 2 || pending.size() < 2 + quint8(pending[1]))
                return;
            socket->read(2 + quint8(pending[1]));
            socket->setProperty("socksGreeting", true);
            socket->write("\x05\x00", 2);
            return;
        }
        if (pending.size() < 5)
            return;
        if (!pending.startsWith(QByteArray("\x05\x01\x00\x03", 4))) {
            socket->disconnectFromHost();
            return;
        }
        const qsizetype hostLength = quint8(pending[4]);
        if (pending.size() < 7 + hostLength)
            return;
        socksTargets.append(QString::fromLatin1(pending.mid(5, hostLength)));
        socket->read(7 + hostLength);
        socket->write("\x05\x00\x00\x01\x7f\x00\x00\x01\x00\x50", 10);
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
    const LyricsSearch::Endpoints primary{fixture.url(), {}, {}, {}, {}};
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
        fixture.url(QStringLiteral("/simp/")), fixture.url(QStringLiteral("/better")),
        fixture.url(QStringLiteral("/netease/"))}, QString(), curl);
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
    multi.setTrack(QStringLiteral("session1:netease"), QStringLiteral("Через NetEase"), artist, album, 180);
    if (!expect(until([&] { return !multi.searching(); }) && firstLine(multi) == QStringLiteral("Другой каталог")
            && multi.document().value(QStringLiteral("wordCount")).toInt() == 2
            && multi.statusText().contains(QStringLiteral("NetEase Cloud Music"))
            && multi.sourceDetails().contains(QStringLiteral("LRCLIB · HTTP 503")),
            "NetEase must choose by duration and keep YRC timings when LRCLIB fails"))
        return 1;

    LyricsSearch fallback(primary, {}, cache.filePath(QStringLiteral("missing-curl.exe")));
    fallback.setTrack(QStringLiteral("session1:fallback"), QStringLiteral("Резерв"), artist, album, 180);
    if (!expect(until([&] { return !fallback.searching(); }) && firstLine(fallback) == QStringLiteral("Текст Резерв"),
                "A curl startup failure must fall back to Qt transport"))
        return 1;

    qputenv("NO_PROXY", "*");
    qputenv("no_proxy", "*");
    const QUrl origin(QStringLiteral("http://lyrics-test.invalid"));
    const QString socksAddress = QStringLiteral("socks5://127.0.0.1:%1").arg(fixture.server.serverPort());
    const QString httpAddress = fixture.url(QStringLiteral("/")).toString(QUrl::RemovePath);
    LyricsSearch proxied({origin.resolved(QUrl(QStringLiteral("/api/search"))), {}, {}, {}, {}}, {}, curl);
    if (!expect(proxied.configureProxy(socksAddress).isEmpty()
            && proxied.proxyAddress().startsWith(QStringLiteral("socks5h://"))
            && !proxied.configureProxy(QStringLiteral("http://example.invalid:10809")).isEmpty()
            && !proxied.configureProxy(QStringLiteral("http://user:password@127.0.0.1:10809")).isEmpty()
            && proxied.proxyAddress().startsWith(QStringLiteral("socks5h://")),
            "Validate the local address and preserve the current route if an address is rejected"))
        return 1;
    proxied.setTrack(QStringLiteral("proxy:socks"), QStringLiteral("Через SOCKS5"), artist, album, 180);
    if (!expect(until([&] { return !proxied.searching(); }) && firstLine(proxied) == QStringLiteral("Текст Через SOCKS5")
            && fixture.socksTargets == QStringList{origin.host()} && proxied.sourceDetails().contains(proxied.proxyAddress()),
            "The local SOCKS5 proxy must resolve the hostname and be shown in the diagnostics"))
        return 1;
    if (!expect(proxied.configureProxy(httpAddress).isEmpty() && firstLine(proxied) == QStringLiteral("Текст Через SOCKS5"),
            "Changing the proxy must preserve current lyrics"))
        return 1;
    proxied.setTrack(QStringLiteral("proxy:http"), QStringLiteral("Через HTTP"), artist, album, 180);
    if (!expect(until([&] { return !proxied.searching(); }) && firstLine(proxied) == QStringLiteral("Текст Через HTTP")
            && fixture.httpProxyTargets == QStringList{origin.host()} && proxied.configureProxy({}).isEmpty()
            && proxied.proxyAddress().isEmpty(),
            "An explicit HTTP proxy must override proxy exclusions and be clearable"))
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

        LyricsHttp qt(QString{});
        LyricsHttp proxyRetry(curl);
        const auto previousTunnels = fixture.socksTargets.size();
        if (!expect(proxyRetry.setProxyAddress(socksAddress), "Could not configure the proxy for the retry test"))
            return 1;
        LyricsHttp::Result hanging, full, unavailable, broken, recovered, qtFull;
        const auto check = [&](LyricsHttp &client, const char *path, LyricsHttp::Result &result) {
            client.get(fixture.url(QString::fromLatin1(path)), [&result](LyricsHttp::Result reply) {
                result = std::move(reply);
            });
        };
        check(http, "/hang", hanging);
        check(http, "/open-json", full);
        check(http, "/open-error", unavailable);
        check(http, "/broken-json", broken);
        proxyRetry.get(origin.resolved(QUrl(QStringLiteral("/retry"))), [&](LyricsHttp::Result result) {
            recovered = std::move(result);
        });
        check(qt, "/open-json", qtFull);
        if (!expect(until([&] { return http.pendingCount() == 0 && qt.pendingCount() == 0 && proxyRetry.pendingCount() == 0; }, 27000),
                    "Interrupted requests must complete within the two transport deadlines")
                || !expect(hanging.error.contains(QStringLiteral("curl 28"))
                    && hanging.error.contains(QStringLiteral("ожидание HTTP-ответа"))
                    && hanging.error.contains(QStringLiteral("(Qt)")),
                    "A server that never replies must report the HTTP wait and retry failure")
                || !expect(full.error.isEmpty() && full.status == 200 && full.body == R"({"lyrics":[]})"
                    && qtFull.error.isEmpty() && qtFull.status == 200 && qtFull.body == full.body,
                    "An entire JSON document is usable when either transport times out afterwards")
                || !expect(unavailable.error.isEmpty() && unavailable.status == 503,
                    "An HTTP error status is usable even if its response body times out")
                || !expect(broken.error.contains(QStringLiteral("HTTP 200, получено 1 Б")),
                    "A truncated JSON body must be rejected and report the received byte count")
                || !expect(recovered.error.isEmpty() && recovered.status == 200 && recovered.body == full.body
                    && fixture.retryRequests == 2 && fixture.socksTargets.size() == previousTunnels + 2,
                    "An interrupted incomplete JSON response must be retried through Qt and the same SOCKS5 proxy"))
            return 1;

        qunsetenv("NO_PROXY");
        qunsetenv("no_proxy");
        const auto proxy = fixture.url(QStringLiteral("/")).toEncoded(QUrl::RemovePath);
        qputenv("HTTPS_PROXY", proxy);
        qputenv("https_proxy", proxy);
        error.clear();
        http.get(QUrl(QStringLiteral("https://lyrics-test.invalid/")), [&](const LyricsHttp::Result &result) {
            error = result.error;
        });
        if (!expect(until([&] { return !error.isEmpty(); }) && error.contains(QStringLiteral("прокси HTTP 403")),
                    "An HTTPS tunnel error must report the proxy response instead of an origin status"))
            return 1;
    }
    return 0;
}
