#include "WindowsNotificationBanners.h"

#include <QList>
#include <QSettings>
#include <QtCore/qt_windows.h>

#include <limits>
#include <memory>
#include <optional>
#include <type_traits>
#include <utility>

namespace {

using RegistryKey = std::unique_ptr<std::remove_pointer_t<HKEY>, decltype(&RegCloseKey)>;
constexpr wchar_t bannerValue[] = L"ShowBanner";
constexpr qint64 absentValue = -1;
const auto backupKey = QStringLiteral("notifications/bannerBackup");

bool missing(LSTATUS status)
{
    return status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND;
}

bool managesSender(QStringView sender)
{
    return !sender.isEmpty() && sender.size() <= 255 && !sender.contains(u'\\')
        && !sender.contains(u'/') && !sender.contains(QChar::Null)
        && !sender.startsWith(QLatin1StringView("windows.systemtoast."))
        && !sender.startsWith(QLatin1StringView("microsoft.windowsalarms_"));
}

LSTATUS openKey(HKEY parent, const QString &name, REGSAM access, RegistryKey &key)
{
    HKEY handle = nullptr;
    const LSTATUS result = RegOpenKeyExW(parent, name.toStdWString().c_str(), 0, access, &handle);
    if (result == ERROR_SUCCESS)
        key.reset(handle);
    return result;
}

LSTATUS readBanner(HKEY key, std::optional<DWORD> &value)
{
    DWORD number = 0;
    DWORD type = 0;
    DWORD size = sizeof(number);
    const LSTATUS result = RegQueryValueExW(key, bannerValue, nullptr, &type,
        reinterpret_cast<BYTE *>(&number), &size);
    if (missing(result)) {
        value.reset();
        return ERROR_SUCCESS;
    }
    if (result == ERROR_MORE_DATA && type != REG_DWORD)
        return ERROR_INVALID_DATA;
    if (result != ERROR_SUCCESS)
        return result;
    if (type != REG_DWORD || size != sizeof(number))
        return ERROR_INVALID_DATA;
    value = number;
    return ERROR_SUCCESS;
}

LSTATUS setBanner(HKEY key, DWORD value)
{
    return RegSetValueExW(key, bannerValue, 0, REG_DWORD,
        reinterpret_cast<const BYTE *>(&value), sizeof(value));
}

QSet<QString> registeredSenders(HKEY parent, bool &complete)
{
    QSet<QString> senders;
    for (DWORD index = 0; ; ++index) {
        wchar_t name[256];
        DWORD length = ARRAYSIZE(name);
        const LSTATUS result = RegEnumKeyExW(parent, index, name, &length, nullptr, nullptr, nullptr, nullptr);
        if (result == ERROR_NO_MORE_ITEMS)
            break;
        if (result != ERROR_SUCCESS) {
            complete = false;
            break;
        }
        senders.insert(QString::fromWCharArray(name, length).toCaseFolded());
    }
    return senders;
}

} // namespace

WindowsNotificationBanners::WindowsNotificationBanners(QSettings &settings, QString registryPath)
    : m_settings(settings), m_registryPath(std::move(registryPath)),
      m_previous(m_settings.value(backupKey).toMap())
{
}

bool WindowsNotificationBanners::available() const
{
    RegistryKey root(nullptr, RegCloseKey);
    return openKey(HKEY_CURRENT_USER, m_registryPath, KEY_ENUMERATE_SUB_KEYS | KEY_CREATE_SUB_KEY, root)
        == ERROR_SUCCESS;
}

bool WindowsNotificationBanners::save(const QVariantMap &previous)
{
    if (previous == m_previous)
        return true;
    if (previous.isEmpty())
        m_settings.remove(backupKey);
    else
        m_settings.setValue(backupKey, previous);
    m_settings.sync();
    if (m_settings.status() != QSettings::NoError)
        return false;
    m_previous = previous;
    return true;
}

WindowsNotificationBanners::Result WindowsNotificationBanners::suppress(const QSet<QString> &knownSenders)
{
    RegistryKey root(nullptr, RegCloseKey);
    if (openKey(HKEY_CURRENT_USER, m_registryPath, KEY_ENUMERATE_SUB_KEYS | KEY_CREATE_SUB_KEY, root)
            != ERROR_SUCCESS) {
        return {0, false};
    }

    Result result;
    auto senders = registeredSenders(root.get(), result.complete);
    for (const auto &sender : knownSenders)
        senders.insert(sender.toCaseFolded());

    struct Change {
        QString sender;
        std::optional<DWORD> previous;
    };
    QList<Change> changes;
    auto backup = m_previous;
    for (const auto &sender : std::as_const(senders)) {
        if (!managesSender(sender))
            continue;
        RegistryKey key(nullptr, RegCloseKey);
        const LSTATUS opened = openKey(root.get(), sender, KEY_QUERY_VALUE, key);
        std::optional<DWORD> value;
        if ((!missing(opened) && opened != ERROR_SUCCESS)
                || (key && readBanner(key.get(), value) != ERROR_SUCCESS)) {
            result.complete = false;
            continue;
        }
        if (value == 0) {
            ++result.hidden;
            continue;
        }
        if (m_changed.contains(sender))
            continue;
        const qint64 previous = value ? qint64(*value) : absentValue;
        if (backup.contains(sender) && backup.value(sender).toLongLong() != previous)
            continue;
        backup.insert(sender, previous);
        changes.append({sender, value});
    }

    // Record every original value before the first Windows settings write.
    if (!save(backup))
        return {result.hidden, false};
    for (const auto &change : std::as_const(changes)) {
        HKEY handle = nullptr;
        const LSTATUS opened = RegCreateKeyExW(root.get(), change.sender.toStdWString().c_str(), 0, nullptr,
            REG_OPTION_NON_VOLATILE, KEY_QUERY_VALUE | KEY_SET_VALUE, nullptr, &handle, nullptr);
        RegistryKey key(handle, RegCloseKey);
        std::optional<DWORD> current;
        if (opened != ERROR_SUCCESS || readBanner(key.get(), current) != ERROR_SUCCESS) {
            result.complete = false;
            continue;
        }
        if (current != change.previous) {
            if (current == 0)
                ++result.hidden;
            m_changed.insert(change.sender);
            continue;
        }
        if (setBanner(key.get(), 0) != ERROR_SUCCESS) {
            result.complete = false;
            continue;
        }
        m_changed.insert(change.sender);
        ++result.hidden;
    }
    return result;
}

bool WindowsNotificationBanners::restore()
{
    m_changed.clear();
    if (m_previous.isEmpty())
        return true;

    RegistryKey root(nullptr, RegCloseKey);
    const LSTATUS opened = openKey(HKEY_CURRENT_USER, m_registryPath, KEY_ENUMERATE_SUB_KEYS, root);
    if (missing(opened))
        return save({});
    if (opened != ERROR_SUCCESS)
        return false;

    auto pending = m_previous;
    for (auto it = m_previous.cbegin(); it != m_previous.cend(); ++it) {
        if (!managesSender(it.key()))
            continue;
        bool valid = false;
        const qint64 previous = it.value().toLongLong(&valid);
        if (!valid || previous < absentValue || previous > std::numeric_limits<DWORD>::max())
            continue;
        RegistryKey key(nullptr, RegCloseKey);
        const LSTATUS found = openKey(root.get(), it.key(), KEY_QUERY_VALUE | KEY_SET_VALUE, key);
        if (missing(found)) {
            pending.remove(it.key());
            continue;
        }
        if (found != ERROR_SUCCESS)
            continue;
        std::optional<DWORD> current;
        const LSTATUS read = readBanner(key.get(), current);
        if (read == ERROR_INVALID_DATA || (read == ERROR_SUCCESS && current != 0)) {
            pending.remove(it.key());
            continue;
        }
        if (read != ERROR_SUCCESS)
            continue;
        const LSTATUS restored = previous == absentValue
            ? RegDeleteValueW(key.get(), bannerValue) : setBanner(key.get(), DWORD(previous));
        if (restored == ERROR_SUCCESS || (previous == absentValue && missing(restored)))
            pending.remove(it.key());
    }
    return save(pending) && pending.isEmpty();
}
