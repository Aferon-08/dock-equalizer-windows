#include "WindowsNotifications.h"

#include <QDateTime>
#include <QSet>
#include <QStringList>

#include <algorithm>
#include <utility>

#ifdef Q_OS_WIN
#include "WinNotificationAbi.h"

#include <appmodel.h>
#include <asyncinfo.h>
#include <roapi.h>
#include <winstring.h>
#include <wrl/client.h>

namespace {

using Microsoft::WRL::ComPtr;
using namespace winnotification;

template<class Interface, class Getter>
QString readString(Interface *object, Getter getter)
{
    HSTRING value = nullptr;
    QString text;
    if (SUCCEEDED((object->*getter)(&value)) && value) {
        UINT32 length = 0;
        const auto *buffer = WindowsGetStringRawBuffer(value, &length);
        text = QString::fromWCharArray(buffer, std::min(length, UINT32(1024))).trimmed();
    }
    WindowsDeleteString(value);
    return text;
}

AsyncStatus operationStatus(IInspectable *operation)
{
    ComPtr<IAsyncInfo> info;
    AsyncStatus status = AsyncStatus::Error;
    if (SUCCEEDED(operation->QueryInterface(__uuidof(IAsyncInfo),
            reinterpret_cast<void **>(info.GetAddressOf())))) {
        info->get_Status(&status);
    }
    return status;
}

QVariantMap toCard(UserNotification *entry, qint64 timestamp)
{
    ComPtr<Notification> notification;
    ComPtr<NotificationVisual> visual;
    ComPtr<NotificationBinding> binding;
    ComPtr<VectorView<AdaptiveText *>> texts;
    constexpr wchar_t toastBinding[] = L"ToastGeneric";
    HSTRING_HEADER header{};
    HSTRING bindingName = nullptr;
    WindowsCreateStringReference(toastBinding, ARRAYSIZE(toastBinding) - 1, &header, &bindingName);
    if (FAILED(entry->get_Notification(notification.GetAddressOf())) || !notification
        || FAILED(notification->get_Visual(visual.GetAddressOf())) || !visual
        || FAILED(visual->GetBinding(bindingName, binding.GetAddressOf())) || !binding
        || FAILED(binding->GetTextElements(texts.GetAddressOf())) || !texts)
        return {};

    QStringList lines;
    UINT32 count = 0;
    texts->get_Size(&count);
    for (UINT32 index = 0; index < std::min(count, UINT32(8)); ++index) {
        ComPtr<AdaptiveText> text;
        if (SUCCEEDED(texts->GetAt(index, text.GetAddressOf())) && text) {
            const auto line = readString(text.Get(), &AdaptiveText::get_Text);
            if (!line.isEmpty())
                lines.append(line);
        }
    }
    if (lines.isEmpty())
        return {};

    QString source = WindowsNotifications::tr("Приложение Windows");
    QString appId;
    ComPtr<AppInfo> appInfo;
    if (SUCCEEDED(entry->get_AppInfo(appInfo.GetAddressOf())) && appInfo) {
        appId = readString(appInfo.Get(), &AppInfo::get_AppUserModelId);
        ComPtr<AppDisplayInfo> display;
        if (SUCCEEDED(appInfo->get_DisplayInfo(display.GetAddressOf())) && display) {
            const auto displayName = readString(display.Get(), &AppDisplayInfo::get_DisplayName);
            if (!displayName.isEmpty())
                source = displayName;
        }
    }
    const bool system = appId.startsWith(QLatin1StringView("Windows.SystemToast."), Qt::CaseInsensitive);
    const auto title = lines.takeFirst();
    const auto detail = lines.join(u'\n');
    QVariantMap event{{QStringLiteral("kind"), system ? QStringLiteral("system") : QStringLiteral("app")},
        {QStringLiteral("accent"), system ? QStringLiteral("#ffdb91") : QStringLiteral("#c3b5ff")},
        {QStringLiteral("title"), title}, {QStringLiteral("summary"), detail.isEmpty() ? source : lines.first()},
        {QStringLiteral("source"), source}, {QStringLiteral("detail"), detail.isEmpty() ? title : detail}};
    constexpr qint64 windowsEpochMs = 11644473600000LL;
    if (timestamp / 10000 > windowsEpochMs)
        event.insert(QStringLiteral("sentAt"), QDateTime::fromMSecsSinceEpoch(timestamp / 10000 - windowsEpochMs));
    return event;
}

} // namespace
#endif

struct WindowsNotifications::Private
{
#ifdef Q_OS_WIN
    bool apartment = false;
    ComPtr<Listener> listener;
    ComPtr<AsyncOperation<Access>> permission;
    ComPtr<AsyncOperation<NotificationList *>> read;
    bool seeded = false;
    QSet<QPair<UINT32, qint64>> seen;
#endif
};

WindowsNotifications::WindowsNotifications(bool enabled)
    : m_data(std::make_unique<Private>())
{
#ifdef Q_OS_WIN
    if (!enabled)
        return;
    UINT32 length = 0;
    if (GetCurrentPackageFullName(&length, nullptr) != ERROR_INSUFFICIENT_BUFFER) {
        setStatus(QStringLiteral("packageRequired"));
        return;
    }
    m_data->apartment = SUCCEEDED(RoInitialize(RO_INIT_SINGLETHREADED));
    if (!m_data->apartment)
        return;
    constexpr wchar_t listenerClass[] = L"Windows.UI.Notifications.Management.UserNotificationListener";
    HSTRING_HEADER header{};
    HSTRING name = nullptr;
    ComPtr<ListenerStatics> factory;
    if (FAILED(WindowsCreateStringReference(listenerClass, ARRAYSIZE(listenerClass) - 1, &header, &name))
        || FAILED(RoGetActivationFactory(name, listenerStaticsId, reinterpret_cast<void **>(factory.GetAddressOf())))
        || !factory || FAILED(factory->get_Current(m_data->listener.GetAddressOf())) || !m_data->listener)
        return;

    connect(&m_timer, &QTimer::timeout, this, &WindowsNotifications::refresh);
    QTimer::singleShot(0, this, &WindowsNotifications::refresh);
    m_timer.start(1500);
#else
    Q_UNUSED(enabled);
#endif
}

WindowsNotifications::~WindowsNotifications()
{
#ifdef Q_OS_WIN
    const bool uninitialize = m_data->apartment;
    m_data.reset();
    if (uninitialize)
        RoUninitialize();
#endif
}

void WindowsNotifications::setStatus(const QString &status)
{
    if (status == m_status)
        return;
    m_status = status;
    emit statusChanged();
}

void WindowsNotifications::requestAccess()
{
#ifdef Q_OS_WIN
    if (!m_data->listener || m_data->permission)
        return;
    if (SUCCEEDED(m_data->listener->RequestAccessAsync(m_data->permission.GetAddressOf())) && m_data->permission)
        setStatus(QStringLiteral("requesting"));
    else
        setStatus(QStringLiteral("unavailable"));
#endif
}

void WindowsNotifications::refresh()
{
#ifdef Q_OS_WIN
    if (m_data->permission) {
        const auto state = operationStatus(m_data->permission.Get());
        if (state == AsyncStatus::Started)
            return;
        m_data->permission.Reset();
    }

    Access access = Access::Unspecified;
    const auto accessResult = m_data->listener->GetAccessStatus(&access);
    if (FAILED(accessResult) || access != Access::Allowed) {
        m_data->read.Reset();
        m_data->seen.clear();
        m_data->seeded = false;
        setStatus(FAILED(accessResult) ? QStringLiteral("unavailable")
            : access == Access::Denied ? QStringLiteral("denied") : QStringLiteral("permissionRequired"));
        return;
    }

    if (!m_data->read) {
        constexpr UINT32 toast = 1;
        if (FAILED(m_data->listener->GetNotificationsAsync(toast, m_data->read.GetAddressOf())) || !m_data->read)
            setStatus(QStringLiteral("unavailable"));
        return;
    }
    const auto state = operationStatus(m_data->read.Get());
    if (state == AsyncStatus::Started)
        return;

    auto read = std::exchange(m_data->read, {});
    ComPtr<NotificationList> list;
    UINT32 count = 0;
    if (state != AsyncStatus::Completed || FAILED(read->GetResults(list.GetAddressOf())) || !list
        || FAILED(list->get_Size(&count))) {
        setStatus(QStringLiteral("unavailable"));
        return;
    }
    setStatus(QStringLiteral("active"));
    QSet<QPair<UINT32, qint64>> seen;
    QList<QPair<qint64, QVariantMap>> arrivals;
    for (UINT32 index = 0; index < count; ++index) {
        ComPtr<UserNotification> entry;
        UINT32 id = 0;
        WinTime timestamp{};
        if (FAILED(list->GetAt(index, entry.GetAddressOf())) || !entry || FAILED(entry->get_Id(&id)))
            continue;
        entry->get_CreationTime(&timestamp);
        const auto key = qMakePair(id, qint64(timestamp.ticks));
        seen.insert(key);
        if (!m_data->seeded || m_data->seen.contains(key))
            continue;
        auto card = toCard(entry.Get(), timestamp.ticks);
        if (!card.isEmpty())
            arrivals.append(qMakePair(qint64(timestamp.ticks), std::move(card)));
    }
    m_data->seen = std::move(seen);
    m_data->seeded = true;
    std::stable_sort(arrivals.begin(), arrivals.end(), [](const auto &first, const auto &second) {
        return first.first < second.first;
    });
    for (const auto &arrival : std::as_const(arrivals))
        emit notification(arrival.second);
#endif
}
