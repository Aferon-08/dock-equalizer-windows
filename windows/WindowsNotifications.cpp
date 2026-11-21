#include "WindowsNotifications.h"

#include <QDateTime>
#include <QElapsedTimer>
#include <QStringList>

#include <algorithm>
#include <utility>

#ifdef Q_OS_WIN
#include "NotificationFeed.h"
#include "WinNotificationAbi.h"

#include <appmodel.h>
#include <asyncinfo.h>
#include <roapi.h>
#include <shobjidl.h>
#include <winstring.h>
#include <wrl/client.h>

namespace {

using Microsoft::WRL::ComPtr;
using namespace winnotification;
constexpr qint64 windowsEpochMs = 11644473600000LL;
const QString probeTitle = QStringLiteral("Проверка Sekai Soundbar");

qint64 windowsTime()
{
    return (QDateTime::currentMSecsSinceEpoch() + windowsEpochMs) * 10000;
}

QString errorText(const char *step, HRESULT result)
{
    return QStringLiteral("%1 (0x%2)").arg(QString::fromLatin1(step))
        .arg(quint32(result), 8, 16, QLatin1Char('0'));
}

template<class Interface, size_t length>
HRESULT getFactory(const wchar_t (&className)[length], REFIID iid, ComPtr<Interface> &factory)
{
    HSTRING_HEADER header{};
    HSTRING name = nullptr;
    const HRESULT result = WindowsCreateStringReference(className, UINT32(length - 1), &header, &name);
    return FAILED(result) ? result : RoGetActivationFactory(name, iid,
        reinterpret_cast<void **>(factory.GetAddressOf()));
}

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

ComPtr<IAsyncInfo> asyncInfo(IInspectable *operation)
{
    ComPtr<IAsyncInfo> info;
    if (operation)
        operation->QueryInterface(__uuidof(IAsyncInfo), reinterpret_cast<void **>(info.GetAddressOf()));
    return info;
}

AsyncStatus operationStatus(IAsyncInfo *info)
{
    AsyncStatus status = AsyncStatus::Error;
    if (info)
        info->get_Status(&status);
    return status;
}

HRESULT operationError(IAsyncInfo *info)
{
    HRESULT error = E_FAIL;
    if (info)
        info->get_ErrorCode(&error);
    return FAILED(error) ? error : E_FAIL;
}

QStringList bindingText(NotificationBinding *binding)
{
    ComPtr<VectorView<AdaptiveText *>> texts;
    UINT32 count = 0;
    if (FAILED(binding->GetTextElements(texts.GetAddressOf())) || !texts || FAILED(texts->get_Size(&count)))
        return {};
    QStringList lines;
    for (UINT32 index = 0; index < std::min(count, UINT32(8)); ++index) {
        ComPtr<AdaptiveText> text;
        if (SUCCEEDED(texts->GetAt(index, text.GetAddressOf())) && text) {
            const auto line = readString(text.Get(), &AdaptiveText::get_Text);
            if (!line.isEmpty())
                lines.append(line);
        }
    }
    return lines;
}

QStringList notificationText(winnotification::UserNotification *entry)
{
    ComPtr<Notification> notification;
    ComPtr<NotificationVisual> visual;
    ComPtr<NotificationBinding> binding;
    constexpr wchar_t toastBinding[] = L"ToastGeneric";
    HSTRING_HEADER header{};
    HSTRING bindingName = nullptr;
    WindowsCreateStringReference(toastBinding, ARRAYSIZE(toastBinding) - 1, &header, &bindingName);
    if (FAILED(entry->get_Notification(notification.GetAddressOf())) || !notification
        || FAILED(notification->get_Visual(visual.GetAddressOf())) || !visual)
        return {};

    if (SUCCEEDED(visual->GetBinding(bindingName, binding.GetAddressOf())) && binding) {
        const auto lines = bindingText(binding.Get());
        if (!lines.isEmpty())
            return lines;
    }
    ComPtr<VectorView<NotificationBinding *>> bindings;
    UINT32 count = 0;
    if (FAILED(visual->get_Bindings(bindings.GetAddressOf())) || !bindings || FAILED(bindings->get_Size(&count)))
        return {};
    for (UINT32 index = 0; index < std::min(count, UINT32(8)); ++index) {
        if (SUCCEEDED(bindings->GetAt(index, binding.ReleaseAndGetAddressOf())) && binding) {
            const auto lines = bindingText(binding.Get());
            if (!lines.isEmpty())
                return lines;
        }
    }
    return {};
}

QVariantMap toCard(winnotification::UserNotification *entry, qint64 timestamp)
{
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
    auto lines = notificationText(entry);
    const auto title = lines.isEmpty() ? source : lines.takeFirst();
    const auto summary = lines.isEmpty() ? source : lines.first();
    const auto detail = lines.isEmpty() ? WindowsNotifications::tr("Уведомление получено из Центра уведомлений.")
        : lines.join(u'\n');
    QVariantMap event{{QStringLiteral("kind"), system ? QStringLiteral("system") : QStringLiteral("app")},
        {QStringLiteral("accent"), system ? QStringLiteral("#ffdb91") : QStringLiteral("#c3b5ff")},
        {QStringLiteral("title"), title}, {QStringLiteral("summary"), summary},
        {QStringLiteral("source"), source}, {QStringLiteral("detail"), detail}};
    if (timestamp / 10000 > windowsEpochMs)
        event.insert(QStringLiteral("sentAt"), QDateTime::fromMSecsSinceEpoch(timestamp / 10000 - windowsEpochMs));
    return event;
}

HRESULT showTestToast(const QString &message)
{
    constexpr wchar_t className[] = L"Windows.Data.Xml.Dom.XmlDocument";
    HSTRING_HEADER classHeader{};
    HSTRING xmlClass = nullptr;
    WindowsCreateStringReference(className, ARRAYSIZE(className) - 1, &classHeader, &xmlClass);
    ComPtr<IInspectable> document;
    HRESULT result = RoActivateInstance(xmlClass, document.GetAddressOf());
    if (FAILED(result))
        return result;
    ComPtr<IInspectable> xmlDocument;
    result = document->QueryInterface(xmlDocumentId, reinterpret_cast<void **>(xmlDocument.GetAddressOf()));
    if (FAILED(result))
        return result;
    ComPtr<XmlDocumentIO> loader;
    result = document->QueryInterface(xmlDocumentIOId, reinterpret_cast<void **>(loader.GetAddressOf()));
    if (FAILED(result))
        return result;
    const auto xml = QStringLiteral("<toast><visual><binding template='ToastGeneric'>"
        "<text>%1</text><text>%2</text></binding></visual></toast>")
        .arg(probeTitle.toHtmlEscaped(), message.toHtmlEscaped()).toStdWString();
    HSTRING_HEADER xmlHeader{};
    HSTRING content = nullptr;
    result = WindowsCreateStringReference(xml.c_str(), UINT32(xml.size()), &xmlHeader, &content);
    if (FAILED(result) || FAILED(result = loader->LoadXml(content)))
        return result;

    ComPtr<ToastNotificationFactory> factory;
    ComPtr<IInspectable> toast;
    result = getFactory(L"Windows.UI.Notifications.ToastNotification", toastFactoryId, factory);
    if (FAILED(result) || FAILED(result = factory->CreateToastNotification(xmlDocument.Get(), toast.GetAddressOf())))
        return result;
    ComPtr<ToastNotificationOptions> options;
    if (SUCCEEDED(toast->QueryInterface(toastOptionsId, reinterpret_cast<void **>(options.GetAddressOf()))))
        options->put_SuppressPopup(true);

    ComPtr<ToastManagerStatics> manager;
    ComPtr<ToastNotifier> notifier;
    result = getFactory(L"Windows.UI.Notifications.ToastNotificationManager", toastManagerId, manager);
    if (FAILED(result) || FAILED(result = manager->CreateToastNotifier(notifier.GetAddressOf())))
        return result;
    INT32 setting = 0;
    result = notifier->get_Setting(&setting);
    if (FAILED(result))
        return result;
    return setting == 0 ? notifier->Show(toast.Get()) : HRESULT_FROM_WIN32(ERROR_ACCESS_DISABLED_BY_POLICY);
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
    NotificationFeed feed;
    QElapsedTimer clock;
    qint64 nextRead = 0;
    qint64 readDeadline = 0;
    int delivered = 0;
    QString permissionDiagnostic;
    QString testMessage;
    qint64 testDeadline = 0;
#endif
};

WindowsNotifications::WindowsNotifications(bool enabled)
    : m_data(std::make_unique<Private>())
{
#ifdef Q_OS_WIN
    if (!enabled)
        return;
    if (!hasPackageIdentity()) {
        setStatus(QStringLiteral("packageRequired"));
        return;
    }
    const HRESULT apartment = RoInitialize(RO_INIT_SINGLETHREADED);
    m_data->apartment = SUCCEEDED(apartment);
    if (!m_data->apartment) {
        setStatus(QStringLiteral("unavailable"), errorText("RoInitialize", apartment));
        return;
    }
    ComPtr<ListenerStatics> factory;
    HRESULT result = getFactory(L"Windows.UI.Notifications.Management.UserNotificationListener", listenerStaticsId, factory);
    if (SUCCEEDED(result))
        result = factory->get_Current(m_data->listener.GetAddressOf());
    if (FAILED(result) || !m_data->listener) {
        setStatus(QStringLiteral("unavailable"), errorText("UserNotificationListener.Current", FAILED(result) ? result : E_UNEXPECTED));
        return;
    }

    m_data->clock.start();
    m_data->feed.reset(windowsTime());
    connect(&m_timer, &QTimer::timeout, this, &WindowsNotifications::refresh);
    refresh();
    m_timer.start(400);
#else
    Q_UNUSED(enabled);
#endif
}

WindowsNotifications::~WindowsNotifications()
{
#ifdef Q_OS_WIN
    m_timer.stop();
    if (const auto permission = asyncInfo(m_data->permission.Get()))
        permission->Cancel();
    if (const auto read = asyncInfo(m_data->read.Get()))
        read->Cancel();
    const bool uninitialize = m_data->apartment;
    m_data.reset();
    if (uninitialize)
        RoUninitialize();
#endif
}

bool WindowsNotifications::hasPackageIdentity()
{
#ifdef Q_OS_WIN
    UINT32 length = 0;
    return GetCurrentPackageFullName(&length, nullptr) == ERROR_INSUFFICIENT_BUFFER;
#else
    return false;
#endif
}

void WindowsNotifications::setStatus(const QString &status, const QString &diagnostic)
{
    if (status == m_status && diagnostic == m_diagnostic)
        return;
    m_status = status;
    m_diagnostic = diagnostic;
    emit statusChanged();
}

void WindowsNotifications::setTestResult(const QString &result, bool testing)
{
    m_testResult = result;
    m_testing = testing;
    emit testChanged();
}

void WindowsNotifications::requestAccess(QWindow *owner)
{
#ifdef Q_OS_WIN
    if (!m_data->listener || m_data->permission || m_status != QStringLiteral("permissionRequired"))
        return;
    if (owner) {
        ComPtr<IInitializeWithWindow> windowInitializer;
        if (SUCCEEDED(m_data->listener->QueryInterface(__uuidof(IInitializeWithWindow),
                reinterpret_cast<void **>(windowInitializer.GetAddressOf())))) {
            windowInitializer->Initialize(reinterpret_cast<HWND>(owner->winId()));
        }
    }
    m_data->feed.reset(windowsTime());
    m_data->permissionDiagnostic.clear();
    const HRESULT result = m_data->listener->RequestAccessAsync(m_data->permission.GetAddressOf());
    if (SUCCEEDED(result) && m_data->permission) {
        setStatus(QStringLiteral("requesting"));
    } else {
        m_data->permissionDiagnostic = errorText("RequestAccessAsync", FAILED(result) ? result : E_UNEXPECTED);
        setStatus(QStringLiteral("permissionRequired"), m_data->permissionDiagnostic);
    }
#else
    Q_UNUSED(owner);
#endif
}

void WindowsNotifications::sendTestNotification()
{
#ifdef Q_OS_WIN
    if (m_status != QStringLiteral("active") || m_testing)
        return;
    m_data->testMessage = tr("Проверка чтения из Центра уведомлений в %1.")
        .arg(QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss.zzz")));
    const HRESULT result = showTestToast(m_data->testMessage);
    if (FAILED(result)) {
        setTestResult(tr("Windows отклонила проверочное уведомление. %1").arg(errorText("ToastNotifier", result)));
        return;
    }
    m_data->testDeadline = m_data->clock.elapsed() + 10000;
    setTestResult(tr("Уведомление отправлено в Windows. Ожидаем его в Центре уведомлений."), true);
#endif
}

void WindowsNotifications::refresh()
{
#ifdef Q_OS_WIN
    const qint64 elapsed = m_data->clock.elapsed();
    if (m_testing && elapsed >= m_data->testDeadline) {
        setTestResult(tr("Проверочное уведомление не вернулось из Центра уведомлений. "
            "Проверьте его наличие в Центре уведомлений Windows."));
    }
    if (m_data->permission) {
        const auto info = asyncInfo(m_data->permission.Get());
        const auto state = operationStatus(info.Get());
        if (state == AsyncStatus::Started)
            return;
        Access requested = Access::Unspecified;
        const HRESULT result = state == AsyncStatus::Completed ? m_data->permission->GetResults(&requested)
            : operationError(info.Get());
        if (FAILED(result) && state != AsyncStatus::Canceled)
            m_data->permissionDiagnostic = errorText("RequestAccessAsync", result);
        m_data->permission.Reset();
    }

    Access access = Access::Unspecified;
    const auto accessResult = m_data->listener->GetAccessStatus(&access);
    if (FAILED(accessResult) || access != Access::Allowed) {
        m_data->read.Reset();
        m_data->nextRead = elapsed;
        m_data->feed.reset(windowsTime());
        if (FAILED(accessResult)) {
            setStatus(QStringLiteral("unavailable"), errorText("GetAccessStatus", accessResult));
        } else {
            setStatus(access == Access::Denied ? QStringLiteral("denied") : QStringLiteral("permissionRequired"),
                m_data->permissionDiagnostic);
        }
        return;
    }

    if (!m_data->read) {
        if (elapsed < m_data->nextRead)
            return;
        constexpr UINT32 toast = 1;
        const HRESULT result = m_data->listener->GetNotificationsAsync(toast, m_data->read.GetAddressOf());
        if (FAILED(result) || !m_data->read) {
            m_data->nextRead = elapsed + 1200;
            setStatus(QStringLiteral("unavailable"), errorText("GetNotificationsAsync", FAILED(result) ? result : E_UNEXPECTED));
        } else {
            m_data->readDeadline = elapsed + 7000;
            if (m_status != QStringLiteral("active"))
                setStatus(QStringLiteral("connecting"));
        }
        return;
    }
    const auto info = asyncInfo(m_data->read.Get());
    const auto state = operationStatus(info.Get());
    if (state == AsyncStatus::Started && elapsed < m_data->readDeadline)
        return;

    auto read = std::exchange(m_data->read, {});
    m_data->nextRead = elapsed + 800;
    if (state == AsyncStatus::Started) {
        info->Cancel();
        setStatus(QStringLiteral("unavailable"), errorText("GetNotificationsAsync", HRESULT_FROM_WIN32(ERROR_TIMEOUT)));
        return;
    }
    ComPtr<NotificationList> list;
    UINT32 count = 0;
    HRESULT result = state == AsyncStatus::Completed ? read->GetResults(list.GetAddressOf()) : operationError(info.Get());
    if (SUCCEEDED(result) && list)
        result = list->get_Size(&count);
    if (FAILED(result) || !list) {
        setStatus(QStringLiteral("unavailable"), errorText("GetNotificationsAsync", FAILED(result) ? result : E_UNEXPECTED));
        return;
    }

    QList<QPair<qint64, QVariantMap>> arrivals;
    for (UINT32 index = 0; index < count; ++index) {
        ComPtr<winnotification::UserNotification> entry;
        UINT32 id = 0;
        WinTime timestamp{};
        if (FAILED(list->GetAt(index, entry.GetAddressOf())) || !entry || FAILED(entry->get_Id(&id)))
            continue;
        entry->get_CreationTime(&timestamp);
        if (!m_data->feed.observe(id, timestamp.ticks))
            continue;
        auto card = toCard(entry.Get(), timestamp.ticks);
        if (m_testing && card.value(QStringLiteral("title")).toString() == probeTitle
                && card.value(QStringLiteral("detail")).toString() == m_data->testMessage) {
            setTestResult(tr("Проверочное уведомление получено из Windows и передано доку."));
        }
        arrivals.append(qMakePair(qint64(timestamp.ticks), std::move(card)));
    }
    m_data->feed.finish();
    m_data->delivered += int(arrivals.size());
    setStatus(QStringLiteral("active"), tr("В Центре уведомлений %1 · передано доку %2").arg(count).arg(m_data->delivered));
    std::stable_sort(arrivals.begin(), arrivals.end(), [](const auto &first, const auto &second) {
        return first.first < second.first;
    });
    for (const auto &arrival : std::as_const(arrivals))
        emit notification(arrival.second);
#endif
}
