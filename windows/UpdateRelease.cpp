#include "UpdateRelease.h"

#include <QJsonObject>
#include <QRegularExpression>
#include <QVersionNumber>

namespace {

const auto repository = QStringLiteral("https://github.com/Aferon-08/dock-equalizer-windows");
constexpr qint64 maxInstallerBytes = 512 * 1024 * 1024;

struct Version
{
    QVersionNumber number;
    QStringList suffix;
};

Version parseVersion(const QString &text)
{
    static const QRegularExpression tag(QStringLiteral(
        R"(^v?([0-9]{1,9}(?:\.[0-9]{1,9}){1,2})(?:-([a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*))?$)"));
    if (text.size() > 96)
        return {};
    const auto match = tag.match(text);
    if (!match.hasMatch())
        return {};
    return {QVersionNumber::fromString(match.captured(1)).normalized(),
        match.captured(2).split(u'.', Qt::SkipEmptyParts)};
}

int compareIdentifiers(const QString &first, const QString &second)
{
    static const QRegularExpression digits(QStringLiteral("^[0-9]+$"));
    const bool firstNumeric = digits.match(first).hasMatch();
    const bool secondNumeric = digits.match(second).hasMatch();
    if (firstNumeric != secondNumeric)
        return firstNumeric ? -1 : 1;
    if (!firstNumeric)
        return QString::compare(first, second);
    const auto significant = [](const QString &value) {
        qsizetype firstDigit = 0;
        while (firstDigit + 1 < value.size() && value.at(firstDigit) == u'0')
            ++firstDigit;
        return QStringView(value).sliced(firstDigit);
    };
    const auto a = significant(first);
    const auto b = significant(second);
    return a.size() == b.size() ? a.compare(b) : a.size() < b.size() ? -1 : 1;
}

UpdateRelease parseRelease(const QJsonObject &object)
{
    static const QRegularExpression namePattern(QStringLiteral(
        R"(^SekaiSoundbar(?:-[0-9]+(?:\.[0-9]+){1,2})?-Windows11-x64(?:-Preview)?-Setup\.exe$)"));
    static const QRegularExpression digestPattern(QStringLiteral("^sha256:([0-9a-fA-F]{64})$"));
    UpdateRelease release;
    release.tag = object.value(QStringLiteral("tag_name")).toString();
    release.page = QUrl(repository + QStringLiteral("/releases/tag/") + release.tag);
    const auto assets = object.value(QStringLiteral("assets")).toArray();
    for (const auto &value : assets) {
        const auto asset = value.toObject();
        const auto name = asset.value(QStringLiteral("name")).toString();
        const auto digest = digestPattern.match(asset.value(QStringLiteral("digest")).toString());
        const auto size = asset.value(QStringLiteral("size")).toInteger(-1);
        if (!namePattern.match(name).hasMatch() || !digest.hasMatch() || size <= 0 || size > maxInstallerBytes
                || asset.value(QStringLiteral("state")).toString() != QStringLiteral("uploaded"))
            continue;
        release.installer = QUrl(repository + QStringLiteral("/releases/download/") + release.tag + u'/' + name);
        release.sha256 = QByteArray::fromHex(digest.captured(1).toLatin1());
        release.size = size;
        break;
    }
    return release;
}

} // namespace

int UpdateRelease::compareVersions(const QString &first, const QString &second)
{
    const auto a = parseVersion(first);
    const auto b = parseVersion(second);
    const int number = QVersionNumber::compare(a.number, b.number);
    if (number)
        return number;
    if (a.suffix.isEmpty() != b.suffix.isEmpty())
        return a.suffix.isEmpty() ? 1 : -1;
    const auto count = qMin(a.suffix.size(), b.suffix.size());
    for (qsizetype i = 0; i != count; ++i) {
        const auto identifier = compareIdentifiers(a.suffix.at(i), b.suffix.at(i));
        if (identifier)
            return identifier;
    }
    return a.suffix.size() < b.suffix.size() ? -1 : a.suffix.size() > b.suffix.size() ? 1 : 0;
}

std::optional<UpdateRelease> UpdateRelease::newest(const QJsonArray &releases, bool prerelease)
{
    std::optional<UpdateRelease> newest;
    for (const auto &value : releases) {
        const auto release = value.toObject();
        const auto tag = release.value(QStringLiteral("tag_name")).toString();
        const auto version = parseVersion(tag);
        if (release.value(QStringLiteral("draft")).toBool()
                || release.value(QStringLiteral("prerelease")).toBool() != prerelease
                || release.value(QStringLiteral("published_at")).toString().isEmpty()
                || !tag.startsWith(u'v') || version.number.isNull()
                || version.suffix.isEmpty() == prerelease)
            continue;
        if (!newest || compareVersions(tag, newest->tag) > 0)
            newest = parseRelease(release);
    }
    return newest;
}
