#include "LyricsImport.h"

#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSet>
#include <QStringConverter>

#include <algorithm>
#include <cmath>
#include <limits>

namespace {

constexpr qsizetype maxBytes = 4 * 1024 * 1024;
constexpr qsizetype maxEntries = 10000;
constexpr double maxDuration = 86400;
constexpr double timeTolerance = 0.05;

QVariantMap error(const QString &message)
{
    return {{QStringLiteral("ok"), false}, {QStringLiteral("message"), message}};
}

struct LyricLine
{
    double start;
    QString text;
};

QVariantMap readLrc(const QString &text, double duration)
{
    static const QRegularExpression offsetTag(QStringLiteral(R"(^[ \t]*\[offset[ \t]*:[ \t]*([+-]?[0-9]+)[ \t]*\])"),
        QRegularExpression::CaseInsensitiveOption | QRegularExpression::MultilineOption);
    static const QRegularExpression timestamp(QStringLiteral(R"(\[([0-9]{1,6}):([0-9]{1,2})(?:[.:]([0-9]{1,3}))?\][ \t]*)"));

    qint64 offset = 0;
    if (const auto match = offsetTag.match(text); match.hasMatch()) {
        bool ok = false;
        offset = match.capturedView(1).toLongLong(&ok);
        if (!ok || offset < -maxDuration * 1000 || offset > maxDuration * 1000)
            return error(QStringLiteral("Некорректное смещение offset в LRC."));
    }

    QList<LyricLine> lines;
    for (const auto raw : QStringView(text).tokenize(u'\n')) {
        const auto row = raw.trimmed();
        qsizetype next = 0;
        QList<double> times;
        while (true) {
            const auto match = timestamp.matchView(row, next, QRegularExpression::NormalMatch,
                QRegularExpression::AnchorAtOffsetMatchOption);
            if (!match.hasMatch())
                break;
            const int seconds = match.capturedView(2).toInt();
            const qint64 milliseconds = match.capturedView(1).toLongLong() * 60000 + seconds * 1000
                + match.captured(3).leftJustified(3, u'0').toInt();
            const double start = std::max(qint64(0), milliseconds + offset) / 1000.0;
            if (seconds >= 60 || start > maxDuration)
                return error(QStringLiteral("Отметка LRC выходит за границы трека."));
            times.append(start);
            if (lines.size() + times.size() > maxEntries)
                return error(QStringLiteral("В LRC допускается до 10 000 временных отметок."));
            next = match.capturedEnd();
        }
        if (times.isEmpty())
            continue;
        const QString lyric = row.sliced(next).trimmed().toString();
        if (lyric.size() > maxEntries)
            return error(QStringLiteral("Слишком длинная строка LRC."));
        for (double start : times) {
            if (duration > 0 && start > duration + timeTolerance) {
                if (lyric.isEmpty())
                    continue;
                return error(QStringLiteral("Отметка LRC выходит за границы трека."));
            }
            lines.append({start, lyric});
        }
    }
    if (std::none_of(lines.cbegin(), lines.cend(), [](const LyricLine &line) { return !line.text.isEmpty(); }))
        return error(QStringLiteral("В LRC нет строк с временными отметками."));

    std::stable_sort(lines.begin(), lines.end(), [](const auto &left, const auto &right) {
        return left.start < right.start;
    });
    QVariantList result;
    for (qsizetype i = 0; i < lines.size();) {
        const auto &line = lines.at(i);
        qsizetype endOfGroup = i + 1;
        while (endOfGroup < lines.size() && lines.at(endOfGroup).start == line.start)
            ++endOfGroup;
        double end = endOfGroup < lines.size() ? lines.at(endOfGroup).start : line.start + 4;
        if (duration > line.start)
            end = std::min(end, duration);
        for (; i < endOfGroup; ++i) {
            result.append(QVariantMap{{QStringLiteral("t"), line.start}, {QStringLiteral("end"), end},
                {QStringLiteral("text"), lines.at(i).text}, {QStringLiteral("lineOnly"), true}});
        }
    }
    return {{QStringLiteral("ok"), true}, {QStringLiteral("format"), QStringLiteral("lrc")},
        {QStringLiteral("status"), QStringLiteral("partial")}, {QStringLiteral("duration"), 0},
        {QStringLiteral("wordCount"), 0}, {QStringLiteral("lines"), result}};
}

bool validText(const QJsonValue &value, qsizetype limit, bool requireWord)
{
    const auto text = value.toString();
    if (text.trimmed().isEmpty() || text.size() > limit
            || std::any_of(text.begin(), text.end(), [](QChar c) { return c.unicode() < 32; }))
        return false;
    if (!requireWord)
        return true;
    const auto characters = text.toUcs4();
    return std::any_of(characters.begin(), characters.end(), [](uint c) { return QChar::isLetterOrNumber(c); });
}

bool validVoiceList(const QJsonValue &value, const QSet<QString> &voices)
{
    if (!value.isArray() || value.toArray().size() > 16)
        return false;
    QSet<QString> assigned;
    for (const auto item : value.toArray()) {
        const QString id = item.toString();
        if (!voices.contains(id) || assigned.contains(id))
            return false;
        assigned.insert(id);
    }
    return true;
}

bool validRole(const QJsonValue &value)
{
    return value == QStringLiteral("lead") || value == QStringLiteral("parallel")
        || value == QStringLiteral("backing") || value == QStringLiteral("unison");
}

bool validGroup(const QJsonObject &item, const QJsonArray &assigned)
{
    static const QRegularExpression groupId(QStringLiteral(R"(\A[A-Za-z0-9_.-]{1,80}\z)"));
    const auto group = item.value(QStringLiteral("unisonId"));
    return group.isUndefined() || group.isNull()
        || (!assigned.isEmpty() && groupId.match(group.toString()).hasMatch());
}

bool validRange(double start, double end, double duration)
{
    return start >= 0 && start < end && end <= duration + timeTolerance;
}

QVariantMap readWordtime(const QString &text, double trackDuration)
{
    const QJsonDocument json = QJsonDocument::fromJson(text.toUtf8());
    if (!json.isObject())
        return error(QStringLiteral("Не удалось прочитать JSON Wordtime."));
    const auto document = json.object();
    const auto schema = document.value(QStringLiteral("schema"));
    if (!schema.isUndefined() && (schema.toInt() != 1 && schema.toInt() != 2))
        return error(QStringLiteral("Поддерживаются схемы JSON Wordtime 1 и 2."));

    const double duration = document.value(QStringLiteral("duration")).toDouble();
    if (!(duration > 0 && duration <= maxDuration))
        return error(QStringLiteral("В JSON нужна корректная длительность аудио."));
    if (trackDuration > 0 && std::abs(trackDuration - duration) > std::clamp(duration * .01, 2.0, 5.0))
        return error(QStringLiteral("Длительность JSON не совпадает с треком."));

    const auto wordSource = document.value(QStringLiteral("words"));
    const auto fallbackSource = document.value(QStringLiteral("fallbackLines"));
    const auto voiceSource = document.value(QStringLiteral("voices"));
    const auto wordList = wordSource.toArray();
    const auto fallbackList = fallbackSource.toArray();
    const auto voiceList = voiceSource.toArray();
    if (!wordSource.isArray() || wordList.size() > maxEntries
            || (!fallbackSource.isUndefined() && !fallbackSource.isArray()) || fallbackList.size() > maxEntries
            || (wordList.isEmpty() && fallbackList.isEmpty()))
        return error(QStringLiteral("В JSON нужны слова или построчные тайминги, до 10 000 каждого вида."));
    if (!fallbackList.isEmpty() && schema.toInt() == 1)
        return error(QStringLiteral("Построчные фрагменты требуют схему JSON 2."));
    if ((!voiceSource.isUndefined() && !voiceSource.isArray()) || voiceList.size() > 16)
        return error(QStringLiteral("В JSON допускается до 16 вокальных партий."));

    static const QRegularExpression voiceId(QStringLiteral(R"(\A[A-Za-z0-9_.-]{1,64}\z)"));
    QSet<QString> voices;
    QJsonArray voiceResult;
    for (const auto entry : voiceList) {
        const auto voice = entry.toObject();
        const QString id = voice.value(QStringLiteral("id")).toString();
        const auto label = voice.value(QStringLiteral("label"));
        if (!voiceId.match(id).hasMatch() || voices.contains(id) || !validText(label, 80, false))
            return error(QStringLiteral("Проверьте идентификаторы и названия вокальных партий в JSON."));
        voices.insert(id);
        voiceResult.append(QJsonObject{{QStringLiteral("id"), id},
            {QStringLiteral("label"), label.toString().trimmed()}});
    }

    QJsonArray words, fallback;
    QHash<QString, double> previousStart;
    QSet<int> wordLines, fallbackLines;
    constexpr double missingTime = std::numeric_limits<double>::quiet_NaN();
    for (qsizetype i = 0; i < wordList.size(); ++i) {
        auto item = wordList.at(i).toObject();
        const QString prefix = QStringLiteral("Слово №%1. ").arg(i + 1);
        const auto word = item.value(QStringLiteral("word"));
        const auto lineValue = item.value(QStringLiteral("line"));
        const int line = lineValue.isUndefined() ? 0 : lineValue.toInt(-1);
        if (!validText(word, 500, true) || line < 0 || line > 50000)
            return error(prefix + QStringLiteral("Некорректный текст или номер строки."));
        if (item.value(QStringLiteral("status")) == QStringLiteral("unresolved"))
            return error(prefix + QStringLiteral("Сначала разметьте это слово в Wordtime."));

        const auto assignments = item.value(QStringLiteral("voiceIds"));
        const auto assigned = assignments.toArray();
        const auto role = item.value(QStringLiteral("role"));
        if ((!assignments.isUndefined() && !validVoiceList(assignments, voices))
                || (!role.isUndefined() && !validRole(role)) || !validGroup(item, assigned))
            return error(prefix + QStringLiteral("Некорректная вокальная партия или роль."));
        QString group = QString::number(line);
        for (const auto id : assigned)
            group += u',' + id.toString();
        const double start = item.value(QStringLiteral("start")).toDouble(missingTime);
        const double end = item.value(QStringLiteral("end")).toDouble(missingTime);
        if (!validRange(start, end, duration) || start < previousStart.value(group, -1))
            return error(prefix + QStringLiteral("Время вне песни или нарушен порядок слов."));
        previousStart.insert(group, start);
        wordLines.insert(line);

        if (!assigned.isEmpty()) {
            const auto confidence = item.value(QStringLiteral("voiceConfidence"));
            const auto source = item.value(QStringLiteral("voiceSource"));
            const double amount = confidence.isUndefined() ? 1 : confidence.toDouble(missingTime);
            if (!(amount >= 0 && amount <= 1) || (!source.isUndefined()
                    && source != QStringLiteral("annotation") && source != QStringLiteral("acoustic")
                    && source != QStringLiteral("unassigned") && source != QStringLiteral("manual")
                    && source != QStringLiteral("import")))
                return error(prefix + QStringLiteral("Некорректные сведения о разметке голоса."));
        }
        item.insert(QStringLiteral("word"), word.toString().trimmed());
        item.insert(QStringLiteral("line"), line);
        if (!voices.contains(item.value(QStringLiteral("hostVoiceId")).toString()))
            item.remove(QStringLiteral("hostVoiceId"));
        words.append(item);
    }
    for (qsizetype i = 0; i < fallbackList.size(); ++i) {
        auto item = fallbackList.at(i).toObject();
        const QString prefix = QStringLiteral("Строка №%1. ").arg(i + 1);
        const int line = item.value(QStringLiteral("line")).toInt(-1);
        if (line < 0 || line > 50000 || wordLines.contains(line) || fallbackLines.contains(line))
            return error(prefix + QStringLiteral("Некорректный или повторяющийся номер строки."));
        const auto lyric = item.value(QStringLiteral("text"));
        const double start = item.value(QStringLiteral("t")).toDouble(missingTime);
        const double end = item.value(QStringLiteral("end")).toDouble(missingTime);
        if (!validText(lyric, maxEntries, true) || !validRange(start, end, duration))
            return error(prefix + QStringLiteral("Некорректный текст или время вне песни."));
        const auto assignments = item.value(QStringLiteral("voiceIds"));
        if (!validVoiceList(assignments, voices) || !validGroup(item, assignments.toArray()))
            return error(prefix + QStringLiteral("Некорректная вокальная партия."));
        if (!validRole(item.value(QStringLiteral("role"))))
            item.remove(QStringLiteral("role"));
        if (!voices.contains(item.value(QStringLiteral("hostVoiceId")).toString()))
            item.remove(QStringLiteral("hostVoiceId"));
        item.insert(QStringLiteral("text"), lyric.toString().trimmed());
        fallbackLines.insert(line);
        fallback.append(item);
    }

    const auto analysis = document.value(QStringLiteral("analysis"));
    const auto voiceMetadata = document.value(QStringLiteral("multivoice"));
    if ((!analysis.isUndefined() && !analysis.isNull()
            && (!analysis.isObject() || QJsonDocument(analysis.toObject()).toJson(QJsonDocument::Compact).size() > 8192))
            || (!voices.isEmpty() && !voiceMetadata.isUndefined()
                && (!voiceMetadata.isObject() || QJsonDocument(voiceMetadata.toObject()).toJson(QJsonDocument::Compact).size() > 8192)))
        return error(QStringLiteral("Некорректные сведения об анализе в JSON."));

    return QJsonObject{{QStringLiteral("ok"), true}, {QStringLiteral("format"), QStringLiteral("wordtime")},
        {QStringLiteral("status"), fallback.isEmpty() ? QStringLiteral("ready") : QStringLiteral("partial")},
        {QStringLiteral("duration"), duration}, {QStringLiteral("wordCount"), words.size()},
        {QStringLiteral("words"), words}, {QStringLiteral("voices"), voiceResult},
        {QStringLiteral("fallbackLines"), fallback}, {QStringLiteral("analysis"), analysis.toObject()}}.toVariantMap();
}

} // namespace

QVariantMap LyricsImport::parseLrc(const QString &text, double duration)
{
    return readLrc(text, duration);
}

QVariantMap LyricsImport::read(const QUrl &url, double trackDuration) const
{
    if (!url.isLocalFile())
        return error(QStringLiteral("Выберите локальный файл лирики."));
    const QFileInfo info(url.toLocalFile());
    const QString suffix = info.suffix().toLower();
    if (suffix != QStringLiteral("lrc") && suffix != QStringLiteral("json"))
        return error(QStringLiteral("Выберите файл .lrc или JSON Wordtime."));
    QFile file(info.filePath());
    if (!info.isFile() || !file.open(QIODevice::ReadOnly))
        return error(QStringLiteral("Не удалось открыть файл лирики."));
    if (info.size() > maxBytes)
        return error(QStringLiteral("Размер файла лирики должен быть не больше 4 МБ."));
    const QByteArray bytes = file.read(maxBytes + 1);
    if (file.error() != QFileDevice::NoError || bytes.size() > maxBytes)
        return error(QStringLiteral("Не удалось прочитать файл размером до 4 МБ."));

    const auto encoding = QStringConverter::encodingForData(bytes).value_or(QStringConverter::Utf8);
    QStringDecoder decoder(encoding, QStringConverter::Flag::Stateless);
    const QString text = decoder(bytes);
    if (decoder.hasError())
        return error(QStringLiteral("Сохраните текстовый файл в UTF-8 или UTF-16 с BOM."));
    return suffix == QStringLiteral("lrc") ? parseLrc(text, trackDuration) : readWordtime(text, trackDuration);
}
