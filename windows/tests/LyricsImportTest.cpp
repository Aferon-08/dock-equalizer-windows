#include "../LyricsImport.h"

#include <QCoreApplication>
#include <QFile>
#include <QTemporaryDir>

#include <cstdio>

namespace {

bool expect(bool condition, const char *message)
{
    if (!condition)
        std::fprintf(stderr, "%s\n", message);
    return condition;
}

} // namespace

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QTemporaryDir directory;
    if (!expect(directory.isValid(), "Could not create a test directory"))
        return 1;
    const LyricsImport importer;
    const auto read = [&](const QString &name, const QByteArray &bytes, double duration = 30) {
        QFile file(directory.filePath(name));
        if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size())
            return QVariantMap{};
        file.close();
        return importer.read(QUrl::fromLocalFile(file.fileName()), duration);
    };

    const auto lrc = read(QStringLiteral("Тестовый файл.LRC"),
        "\xef\xbb\xbf[offset:-500]\r\n[00:09.75][00:02.0]Привет, мир\r\n"
        "[00:00.30]Начало\r\n[00:15]\r\n");
    const auto lines = lrc.value(QStringLiteral("lines")).toList();
    if (!expect(lrc.value(QStringLiteral("ok")).toBool() && lines.size() == 4,
                "A BOM and Cyrillic path must work with multiple stamps per line")
            || !expect(lines[0].toMap().value(QStringLiteral("t")).toDouble() == 0
                    && lines[1].toMap().value(QStringLiteral("t")).toDouble() == 1.5
                    && lines[2].toMap().value(QStringLiteral("t")).toDouble() == 9.25
                    && lines[2].toMap().value(QStringLiteral("end")).toDouble() == 14.5
                    && lines[1].toMap().value(QStringLiteral("text")).toString() == QStringLiteral("Привет, мир"),
                "LRC rows must be sorted and use the signed offset and next line end"))
        return 1;
    if (!expect(!read(QStringLiteral("out.lrc"), "[02:00]Другой трек\n").value(QStringLiteral("ok")).toBool(),
                "LRC outside the current song must be rejected")
            || !expect(!read(QStringLiteral("unmarked.lrc"), "Нет тайминга\n").value(QStringLiteral("ok")).toBool(),
                "An untimed file must not be imported as LRC"))
        return 1;

    const QByteArray wordtime = R"({
        "schema": 2, "duration": 30,
        "voices": [{"id":"a", "label":"Первый"}, {"id":"b", "label":"Второй"}],
        "words": [
            {"word":"Слово", "start":1, "end":1.7, "line":0, "voiceIds":["a"]},
            {"word":"Ответ", "start":1.5, "end":2, "line":0, "voiceIds":["b"], "role":"parallel"}
        ],
        "fallbackLines": [{"line":1, "t":5, "end":6, "text":"Строка", "voiceIds":["a"]}]
    })";
    const auto parsed = read(QStringLiteral("Партии.json"), wordtime);
    if (!expect(parsed.value(QStringLiteral("ok")).toBool()
            && parsed.value(QStringLiteral("status")).toString() == QStringLiteral("partial")
            && parsed.value(QStringLiteral("words")).toList().size() == 2
            && parsed.value(QStringLiteral("voices")).toList().size() == 2
            && parsed.value(QStringLiteral("fallbackLines")).toList().size() == 1,
            "Schema 2 must carry both voice assignments and line timing"))
        return 1;

    auto badVoice = wordtime;
    badVoice.replace("\"voiceIds\":[\"b\"]", "\"voiceIds\":[\"unknown\"]");
    auto badTime = wordtime;
    badTime.replace("\"end\":1.7", "\"end\":0.5");
    auto invalidSchema = wordtime;
    invalidSchema.replace("\"schema\": 2", "\"schema\": 1");
    return expect(!read(QStringLiteral("wrong-duration.json"), wordtime, 50).value(QStringLiteral("ok")).toBool(),
                "The duration of a different track must be rejected")
        && expect(!read(QStringLiteral("invalid-voice.json"), badVoice).value(QStringLiteral("ok")).toBool(),
                "An unknown voice ID must be rejected")
        && expect(!read(QStringLiteral("invalid-time.json"), badTime).value(QStringLiteral("ok")).toBool(),
                "A reversed word range must be rejected")
        && expect(!read(QStringLiteral("invalid-schema.json"), invalidSchema).value(QStringLiteral("ok")).toBool(),
                "Schema 1 cannot contain fallback lines") ? 0 : 1;
}
