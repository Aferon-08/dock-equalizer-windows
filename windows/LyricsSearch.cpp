#include "LyricsSearch.h"
#include "LyricsImport.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJSEngine>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUrlQuery>

#include <cmath>
#include <utility>

namespace {

constexpr qsizetype maxResponseBytes = 2 * 1024 * 1024;
constexpr qsizetype maxLrcChars = 128 * 1024;
constexpr double durationTolerance = 2;
constexpr double maxDuration = 86400;

QString normalized(const QString &value)
{
    static const QRegularExpression separators(QStringLiteral(R"([^\p{L}\p{M}\p{N}]+)"));
    return value.normalized(QString::NormalizationForm_KC).toCaseFolded().replace(separators, QStringLiteral(" ")).trimmed();
}

bool sameDuration(double left, double right)
{
    return std::abs(left - right) <= durationTolerance;
}

QString valueText(const QJsonObject &record, const QString &name)
{
    return record.value(name).toString().simplified().left(300);
}

QString durationText(double duration)
{
    if (duration <= 0)
        return {};
    const int total = qRound(duration);
    return QStringLiteral("%1:%2").arg(total / 60).arg(total % 60, 2, 10, QChar(u'0'));
}

void addQuery(QUrlQuery &query, const QString &name, const QString &value)
{
    if (!value.isEmpty())
        query.addQueryItem(name, QString::fromLatin1(QUrl::toPercentEncoding(value.left(320))));
}

QUrl withQuery(QUrl url, const QUrlQuery &query)
{
    url.setQuery(query);
    return url;
}

} // namespace

LyricsSearch::LyricsSearch(QObject *parent)
    : LyricsSearch(Endpoints{QUrl(QStringLiteral("https://lrclib.net/api/search")),
        QUrl(QStringLiteral("https://lyricsplus.prjktla.workers.dev/v2/lyrics/get")),
        QUrl(QStringLiteral("https://api-lyrics.simpmusic.org/v1/")),
        QUrl(QStringLiteral("https://api.betterlyrics.org/getLyrics"))},
        QDir(QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation)).filePath(QStringLiteral("lyrics/lrclib")),
        LyricsHttp::windowsCurl(), parent)
{
}

LyricsSearch::LyricsSearch(Endpoints endpoints, QString cacheDirectory, QString curlExecutable, QObject *parent)
    : QObject(parent), m_endpoints(std::move(endpoints)), m_cacheDirectory(std::move(cacheDirectory)),
      m_http(std::move(curlExecutable))
{
    m_delay.setSingleShot(true);
    m_delay.setInterval(450);
    connect(&m_delay, &QTimer::timeout, this, &LyricsSearch::request);
}

LyricsSearch::~LyricsSearch()
{
    cancel();
}

void LyricsSearch::setTrack(const QString &key, const QString &title, const QString &artist,
                            const QString &album, double duration)
{
    if (!(duration > 0 && duration <= maxDuration))
        duration = 0;
    if (key == m_key && title == m_title && artist == m_artist && album == m_album
            && (duration == m_duration || (duration > 0 && m_duration > 0 && std::abs(duration - m_duration) < 0.25)))
        return;

    m_key = key;
    m_title = title;
    m_artist = artist;
    m_album = album;
    m_duration = duration;
    reset();
}

void LyricsSearch::setAutomatic(bool enabled)
{
    if (enabled == m_automatic)
        return;
    m_automatic = enabled;
    if (enabled && m_document.isEmpty() && canSearch() && !searching()) {
        m_delay.start();
        m_status = QStringLiteral("Поиск лирики…");
    } else if (!enabled && searching()) {
        cancel();
        m_sourceState.clear();
        m_status = m_document.isEmpty() ? QStringLiteral("Автопоиск выключен")
            : QStringLiteral("Лирика найдена");
    }
    emit automaticChanged();
    emit changed();
}

void LyricsSearch::reset()
{
    cancel();
    m_document.clear();
    m_matches.clear();
    m_choices.clear();
    m_sourceState.clear();
    if (!canSearch()) {
        m_status.clear();
    } else if (loadCache()) {
        m_status = QStringLiteral("Лирика из кеша");
    } else if (m_automatic) {
        m_delay.start();
        m_status = QStringLiteral("Поиск лирики…");
    } else {
        m_status = QStringLiteral("Автопоиск выключен");
    }
    emit changed();
}

void LyricsSearch::cancel()
{
    m_delay.stop();
    m_http.cancel();
}

void LyricsSearch::retry()
{
    if (canSearch() && !searching())
        request();
}

void LyricsSearch::request()
{
    m_status = QStringLiteral("Поиск лирики…");
    m_choices.clear();
    m_matches.clear();
    m_sourceState.clear();
    m_answered = false;
    m_manualChoice = false;
    if (m_endpoints.lrclib.scheme() == QStringLiteral("https") && !m_http.supportsHttps()) {
        m_status = QStringLiteral("HTTPS недоступен. Распакуйте ZIP целиком.");
        emit changed();
        return;
    }

    const auto candidates = transform("candidates", {m_artist, m_title}).toList();
    auto queryMetadata = candidates.value(0).toMap();
    if (m_artist.trimmed().isEmpty() && candidates.size() > 1)
        queryMetadata = candidates.at(1).toMap();
    m_queryTitle = queryMetadata.value(QStringLiteral("title"), m_title).toString();
    m_queryArtist = queryMetadata.value(QStringLiteral("artist"), m_artist).toString();

    QUrlQuery query;
    addQuery(query, QStringLiteral("track_name"), m_queryTitle);
    addQuery(query, QStringLiteral("artist_name"), m_queryArtist);
    if (!m_endpoints.lrclib.isEmpty())
        send(Step::Lrclib, withQuery(m_endpoints.lrclib, query));
    if (!m_endpoints.lyricsPlus.isEmpty()) {
        QUrlQuery plus;
        addQuery(plus, QStringLiteral("title"), m_queryTitle);
        addQuery(plus, QStringLiteral("artist"), m_queryArtist);
        addQuery(plus, QStringLiteral("album"), m_album);
        if (m_duration > 0)
            addQuery(plus, QStringLiteral("duration"), QString::number(qRound(m_duration)));
        addQuery(plus, QStringLiteral("source"), QStringLiteral("apple,lyricsplus,musixmatch,spotify,musixmatch-word"));
        send(Step::LyricsPlus, withQuery(m_endpoints.lyricsPlus, plus));
    }
    if (!m_endpoints.simpMusic.isEmpty()) {
        QUrlQuery simp;
        addQuery(simp, QStringLiteral("q"), (m_queryArtist + u' ' + m_queryTitle).trimmed());
        addQuery(simp, QStringLiteral("limit"), QStringLiteral("10"));
        send(Step::SimpSearch, withQuery(m_endpoints.simpMusic.resolved(QUrl(QStringLiteral("search"))), simp));
    }
    if (!m_endpoints.betterLyrics.isEmpty() && m_duration > 0 && !m_queryArtist.isEmpty()) {
        QUrlQuery better;
        addQuery(better, QStringLiteral("s"), m_queryTitle);
        addQuery(better, QStringLiteral("a"), m_queryArtist);
        addQuery(better, QStringLiteral("al"), m_album);
        addQuery(better, QStringLiteral("d"), QString::number(qRound(m_duration)));
        send(Step::BetterLyrics, withQuery(m_endpoints.betterLyrics, better));
    }
    updateSelection();
}

void LyricsSearch::send(Step step, const QUrl &url, const QString &videoId)
{
    m_sourceState.insert(provider(step), provider(step) + QStringLiteral(" · поиск"));
    m_http.get(url, [this, step, videoId](LyricsHttp::Result response) {
        finish(step, videoId, std::move(response));
    });
}

QString LyricsSearch::provider(Step step)
{
    switch (step) {
    case Step::Lrclib: return QStringLiteral("LRCLIB");
    case Step::LyricsPlus: return QStringLiteral("LyricsPlus");
    case Step::SimpSearch:
    case Step::SimpLyrics: return QStringLiteral("SimpMusic");
    case Step::BetterLyrics: return QStringLiteral("Better Lyrics");
    }
    return {};
}

void LyricsSearch::finish(Step step, const QString &videoId, LyricsHttp::Result response)
{
    const QString name = provider(step);
    const int status = response.status;
    QString result = std::move(response.error);
    if (!result.isEmpty()) {
        m_sourceState.insert(name, name + QStringLiteral(" · ") + result);
        updateSelection();
        return;
    }
    if (status == 404 || (step == Step::BetterLyrics && status == 401)) {
        m_answered = true;
        result = QStringLiteral("нет текста");
    } else if (status < 200 || status >= 300) {
        result = status > 0 ? QStringLiteral("HTTP %1").arg(status) : QStringLiteral("нет HTTP-ответа");
    } else if (const auto json = QJsonDocument::fromJson(response.body); !json.isNull()) {
        m_answered = true;
        const auto before = m_matches.size();
        const auto remaining = m_http.pendingCount();
        receive(step, json, videoId);
        if (m_http.pendingCount() > remaining) {
            updateSelection();
            return;
        }
        result = m_matches.size() > before ? QStringLiteral("найден текст") : QStringLiteral("нет текста");
    } else {
        result = QStringLiteral("неверный ответ");
    }
    m_sourceState.insert(name, name + QStringLiteral(" · ") + result);
    updateSelection();
}

void LyricsSearch::receive(Step step, const QJsonDocument &json, const QString &videoId)
{
    if (step == Step::Lrclib) {
        const auto rows = json.array();
        for (qsizetype i = 0; i < qMin<qsizetype>(20, rows.size()); ++i) {
            auto record = rows.at(i).toObject();
            record.insert(QStringLiteral("source"), provider(step));
            appendMatch(record);
        }
        return;
    }

    const auto object = json.object();
    if (step == Step::SimpSearch) {
        const auto songs = transform("simpmusicSongs", {object.toVariantMap()});
        const auto id = transform("pickWordSong", {songs, m_queryArtist, m_queryTitle, m_duration}).toString();
        static const QRegularExpression videoPattern(QStringLiteral(R"(\A[A-Za-z0-9_-]{11}\z)"));
        if (videoPattern.match(id).hasMatch())
            send(Step::SimpLyrics, m_endpoints.simpMusic.resolved(QUrl(id)), id);
        return;
    }
    if (step == Step::SimpLyrics) {
        const auto data = object.value(QStringLiteral("data"));
        const auto rows = data.isObject() ? QJsonArray{data} : data.toArray();
        for (qsizetype i = 0; i < qMin<qsizetype>(4, rows.size()); ++i) {
            const auto entry = rows.at(i).toObject();
            auto text = transform("richSyncToLrc", {entry.value(QStringLiteral("richSyncLyrics")).toVariant()}).toString();
            if (text.isEmpty())
                text = entry.value(QStringLiteral("syncedLyrics")).toString();
            const double duration = entry.value(QStringLiteral("durationSeconds")).toVariant().toDouble();
            appendMatch({{QStringLiteral("id"), videoId}, {QStringLiteral("source"), provider(step)},
                {QStringLiteral("trackName"), entry.value(QStringLiteral("songTitle")).toString(m_queryTitle)},
                {QStringLiteral("artistName"), entry.value(QStringLiteral("artistName")).toString(m_queryArtist)},
                {QStringLiteral("albumName"), entry.value(QStringLiteral("albumName")).toString()},
                {QStringLiteral("duration"), duration > 0 ? duration
                    : entry.value(QStringLiteral("duration")).toVariant().toDouble()},
                {QStringLiteral("syncedLyrics"), text}});
        }
        return;
    }

    QVariantMap converted;
    if (step == Step::LyricsPlus) {
        converted = transform("lyricsplusToLrc", {object.toVariantMap()}).toMap();
    } else {
        const auto score = object.value(QStringLiteral("score"));
        if (score.isDouble() && score.toDouble() < 0.6)
            return;
        converted = transform("ttmlToLrc", {object.value(QStringLiteral("ttml")).toString()}).toMap();
    }
    const auto metadata = object.value(QStringLiteral("metadata")).toObject();
    appendMatch({{QStringLiteral("id"), QStringLiteral("metadata")},
        {QStringLiteral("source"), provider(step)},
        {QStringLiteral("trackName"), metadata.value(QStringLiteral("title")).toString(m_queryTitle)},
        {QStringLiteral("artistName"), metadata.value(QStringLiteral("artist")).toString(m_queryArtist)},
        {QStringLiteral("albumName"), metadata.value(QStringLiteral("album")).toString(m_album)},
        {QStringLiteral("duration"), m_duration},
        {QStringLiteral("syncedLyrics"), converted.value(QStringLiteral("text")).toString()}});
}

QVariant LyricsSearch::transform(const char *method, const QVariantList &arguments)
{
    if (!m_math) {
        QFile file(QStringLiteral(":/qt/qml/Sekai/Soundbar/LyricsMath.js"));
        if (!file.open(QIODevice::ReadOnly))
            return {};
        auto source = QString::fromUtf8(file.readAll());
        if (source.startsWith(QStringLiteral(".pragma library")))
            source.remove(0, source.indexOf(u'\n') + 1);
        auto engine = std::make_unique<QJSEngine>();
        if (engine->evaluate(source, QStringLiteral("LyricsMath.js")).isError())
            return {};
        m_math = std::move(engine);
    }
    auto function = m_math->globalObject().property(QString::fromLatin1(method));
    if (!function.isCallable())
        return {};
    QJSValueList values;
    auto parse = m_math->globalObject().property(QStringLiteral("JSON")).property(QStringLiteral("parse"));
    for (const auto &argument : arguments) {
        const auto json = QJsonDocument::fromVariant(argument);
        // The shared parsers use Array.isArray, so collections must be native JS arrays.
        values.append(json.isNull() ? m_math->toScriptValue(argument)
            : parse.call({QString::fromUtf8(json.toJson(QJsonDocument::Compact))}));
    }
    const auto result = function.call(values);
    return result.isError() ? QVariant{} : result.toVariant();
}

QVariantMap LyricsSearch::parseLyrics(const QString &lrc, double duration)
{
    static const QRegularExpression timedWord(QStringLiteral(R"(<[0-9]{1,6}:[0-9]{1,2}(?:[.:][0-9]{1,3})?>)"));
    if (!lrc.contains(timedWord))
        return LyricsImport::parseLrc(lrc, duration);

    const auto parsed = transform("parseLrc", {lrc}).toList();
    if (parsed.isEmpty() || parsed.size() > 10000 || transform("isNoLyricsNotice", {parsed}).toBool())
        return {};
    const double limit = duration > 0 ? duration + 0.05 : maxDuration;
    int wordMarks = 0;
    bool hasText = false;
    QVariantList lines;
    for (const auto &entry : parsed) {
        auto line = entry.toMap();
        const auto text = line.value(QStringLiteral("text")).toString();
        const double start = line.value(QStringLiteral("t"), -1).toDouble();
        if (!(start >= 0 && start <= limit) || text.size() > 10000) {
            if (text.isEmpty())
                continue;
            return {};
        }
        auto marks = line.value(QStringLiteral("marks")).toList();
        double previousTime = start;
        int previousCharacter = -1;
        for (const auto &raw : std::as_const(marks)) {
            const auto mark = raw.toMap();
            const double time = mark.value(QStringLiteral("t"), -1).toDouble();
            const int character = mark.value(QStringLiteral("cs"), -1).toInt();
            if (!(time >= previousTime && time <= limit) || character < 0
                    || character < previousCharacter || character >= text.size()) {
                previousCharacter = -1;
                break;
            }
            previousCharacter = character;
            previousTime = time;
        }
        if (previousCharacter < 0)
            marks.clear();
        const auto end = line.value(QStringLiteral("end")).toDouble();
        if (!(end > start && end <= limit && end >= previousTime))
            line.remove(QStringLiteral("end"));
        line.insert(QStringLiteral("marks"), marks);
        line.insert(QStringLiteral("lineOnly"), marks.isEmpty());
        line.insert(QStringLiteral("imported"), !marks.isEmpty());
        wordMarks += marks.size();
        hasText |= !text.isEmpty();
        lines.append(line);
    }
    if (!hasText)
        return {};
    return {{QStringLiteral("ok"), true}, {QStringLiteral("format"), QStringLiteral("enhanced-lrc")},
        {QStringLiteral("status"), wordMarks ? QStringLiteral("ready") : QStringLiteral("partial")},
        {QStringLiteral("wordCount"), wordMarks}, {QStringLiteral("lines"), lines}};
}

void LyricsSearch::appendMatch(const QJsonObject &record)
{
    const auto entry = match(record);
    if (entry.document.isEmpty())
        return;
    const auto title = valueText(entry.record, QStringLiteral("trackName"));
    const auto artist = valueText(entry.record, QStringLiteral("artistName"));
    m_choices.append(QVariantMap{{QStringLiteral("title"), artist.isEmpty() ? title : title + QStringLiteral(" — ") + artist},
        {QStringLiteral("album"), valueText(entry.record, QStringLiteral("albumName"))},
        {QStringLiteral("source"), valueText(entry.record, QStringLiteral("source"))},
        {QStringLiteral("duration"), durationText(entry.record.value(QStringLiteral("duration")).toDouble())}});
    m_matches.append(entry);
}

void LyricsSearch::updateSelection()
{
    const int selected = m_manualChoice ? -1 : automaticMatch();
    if (selected >= 0) {
        use(m_matches.at(selected), !searching());
    } else if (!m_manualChoice) {
        if (searching())
            m_status = QStringLiteral("Поиск лирики…");
        else if (!m_matches.isEmpty())
            m_status = QStringLiteral("Выберите версию лирики в меню дока");
        else if (m_answered)
            m_status = QStringLiteral("Синхронизированная лирика не найдена");
        else
            m_status = QStringLiteral("Поиск недоступен. См. состояние источников.");
    }
    emit changed();
}

LyricsSearch::Match LyricsSearch::match(const QJsonObject &record)
{
    const auto id = record.value(QStringLiteral("id"));
    const auto title = valueText(record, QStringLiteral("trackName"));
    const auto artist = valueText(record, QStringLiteral("artistName"));
    const auto album = valueText(record, QStringLiteral("albumName"));
    const double duration = record.value(QStringLiteral("duration")).toDouble();
    const auto lrc = record.value(QStringLiteral("syncedLyrics")).toString();
    const auto source = record.value(QStringLiteral("source")).toString(provider(Step::Lrclib));
    if ((id.toInteger() <= 0 && id.toString().isEmpty()) || title.isEmpty() || !(duration >= 0 && duration <= maxDuration)
            || lrc.isEmpty() || lrc.size() > maxLrcChars || record.value(QStringLiteral("instrumental")).toBool())
        return {};

    auto document = parseLyrics(lrc, m_duration > 0 ? m_duration : duration);
    if (!document.value(QStringLiteral("ok")).toBool())
        return {};
    document.insert(QStringLiteral("duration"), duration);
    const QJsonObject cleaned{{QStringLiteral("id"), id}, {QStringLiteral("source"), source}, {QStringLiteral("trackName"), title},
        {QStringLiteral("artistName"), artist}, {QStringLiteral("albumName"), album},
        {QStringLiteral("duration"), duration}, {QStringLiteral("syncedLyrics"), lrc}};
    return {cleaned, document};
}

int LyricsSearch::automaticMatch() const
{
    const auto title = normalized(m_queryTitle);
    const auto artist = normalized(m_queryArtist);
    const auto album = normalized(m_album);
    if (title.isEmpty() || artist.isEmpty())
        return -1;
    QList<int> matches, albumMatches;
    for (int i = 0; i < m_matches.size(); ++i) {
        const auto &record = m_matches.at(i).record;
        if (title != normalized(valueText(record, QStringLiteral("trackName")))
                || artist != normalized(valueText(record, QStringLiteral("artistName")))
                || (m_duration > 0 && record.value(QStringLiteral("duration")).toDouble() > 0
                    && !sameDuration(m_duration, record.value(QStringLiteral("duration")).toDouble())))
            continue;
        matches.append(i);
        if (!album.isEmpty() && album == normalized(valueText(record, QStringLiteral("albumName"))))
            albumMatches.append(i);
    }
    const auto &best = albumMatches.isEmpty() ? matches : albumMatches;
    int selected = -1;
    bool selectedHasWords = false;
    for (const auto &name : {provider(Step::BetterLyrics), provider(Step::LyricsPlus),
                            provider(Step::Lrclib), provider(Step::SimpLyrics)}) {
        int candidate = -1;
        for (const int index : best) {
            const auto &record = m_matches.at(index).record;
            if (record.value(QStringLiteral("source")) != name)
                continue;
            if (candidate >= 0 && record.value(QStringLiteral("syncedLyrics")) !=
                    m_matches.at(candidate).record.value(QStringLiteral("syncedLyrics"))) {
                candidate = -1;
                break;
            }
            candidate = index;
        }
        if (candidate < 0)
            continue;
        const bool hasWords = m_matches.at(candidate).document.value(QStringLiteral("wordCount")).toInt() > 0;
        if (selected < 0 || (hasWords && !selectedHasWords)) {
            selected = candidate;
            selectedHasWords = hasWords;
        }
    }
    return selected;
}

bool LyricsSearch::choose(const QString &key, int index)
{
    if (key != m_key || index < 0 || index >= m_matches.size())
        return false;
    m_manualChoice = true;
    use(m_matches.at(index), true);
    emit changed();
    return true;
}

void LyricsSearch::use(const Match &match, bool cache)
{
    m_document = match.document;
    m_status = QStringLiteral("Лирика найдена · %1").arg(valueText(match.record, QStringLiteral("source")));
    if (cache)
        saveCache(match);
}

QString LyricsSearch::cachePath() const
{
    if (m_cacheDirectory.isEmpty() || m_duration <= 0 || normalized(m_artist).isEmpty())
        return {};
    const QJsonArray identity{normalized(m_title), normalized(m_artist), normalized(m_album)};
    const auto hash = QCryptographicHash::hash(QJsonDocument(identity).toJson(QJsonDocument::Compact),
                                              QCryptographicHash::Sha256).toHex();
    return QDir(m_cacheDirectory).filePath(QString::fromLatin1(hash) + QStringLiteral(".json"));
}

bool LyricsSearch::loadCache()
{
    const auto path = cachePath();
    QFile file(path);
    if (path.isEmpty() || !file.open(QIODevice::ReadOnly) || file.size() > maxResponseBytes)
        return false;
    const auto data = QJsonDocument::fromJson(file.read(maxResponseBytes + 1)).object();
    const auto savedDuration = data.value(QStringLiteral("trackDuration")).toDouble();
    if (!(savedDuration > 0 && sameDuration(savedDuration, m_duration)))
        return false;
    const auto cached = match(data.value(QStringLiteral("match")).toObject());
    if (cached.document.isEmpty())
        return false;
    use(cached, false);
    return true;
}

void LyricsSearch::saveCache(const Match &match) const
{
    const auto path = cachePath();
    if (path.isEmpty() || !QDir().mkpath(m_cacheDirectory))
        return;
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return;
    const QJsonObject data{{QStringLiteral("trackDuration"), m_duration}, {QStringLiteral("match"), match.record}};
    const auto bytes = QJsonDocument(data).toJson(QJsonDocument::Compact);
    if (file.write(bytes) == bytes.size())
        file.commit();
}
