#include "WifiStatus.h"

#include <QScopeGuard>
#include <QStringDecoder>
#include <QUuid>

#include <algorithm>
#include <cmath>
#include <utility>

#ifdef Q_OS_WIN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <QtCore/qt_windows.h>
#include <iphlpapi.h>
#include <netlistmgr.h>
#include <wlanapi.h>
#include <wrl/client.h>

namespace {

using Microsoft::WRL::ComPtr;

int internetAccess(const GUID &adapter)
{
    if (FAILED(CoInitializeEx(nullptr, COINIT_MULTITHREADED)))
        return -1;
    const auto apartment = qScopeGuard([] { CoUninitialize(); });
    ComPtr<INetworkListManager> manager;
    ComPtr<IEnumNetworkConnections> connections;
    if (FAILED(CoCreateInstance(__uuidof(NetworkListManager), nullptr, CLSCTX_INPROC_SERVER,
            __uuidof(INetworkListManager), reinterpret_cast<void **>(manager.GetAddressOf())))
        || FAILED(manager->GetNetworkConnections(connections.GetAddressOf())))
        return -1;

    ComPtr<INetworkConnection> connection;
    while (connections->Next(1, connection.ReleaseAndGetAddressOf(), nullptr) == S_OK) {
        GUID id{};
        NLM_CONNECTIVITY connectivity{};
        if (SUCCEEDED(connection->GetAdapterId(&id)) && IsEqualGUID(id, adapter)
            && SUCCEEDED(connection->GetConnectivity(&connectivity))) {
            return (connectivity & (NLM_CONNECTIVITY_IPV4_INTERNET | NLM_CONNECTIVITY_IPV6_INTERNET)) ? 1 : 0;
        }
    }
    return -1;
}

QString networkName(const DOT11_SSID &ssid)
{
    const QByteArrayView bytes(reinterpret_cast<const char *>(ssid.ucSSID),
        std::min<ULONG>(ssid.uSSIDLength, sizeof ssid.ucSSID));
    QStringDecoder utf8(QStringDecoder::Utf8);
    const QString decoded = utf8(bytes);
    return (utf8.hasError() ? QString::fromLocal8Bit(bytes.data(), bytes.size()) : decoded).trimmed();
}

} // namespace
#endif

WifiStatus::WifiStatus(bool preview)
    : m_preview(preview)
{
    m_timer.setInterval(1000);
    connect(&m_timer, &QTimer::timeout, this, &WifiStatus::sample);
    m_worker.setMaxThreadCount(1);
}

WifiStatus::~WifiStatus()
{
    m_worker.waitForDone();
}

void WifiStatus::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    ++m_generation;
    emit activeChanged();
    if (!active) {
        m_timer.stop();
        return;
    }
    m_previous = {};
    m_samples.clear();
    m_snapshot = {{QStringLiteral("state"), QStringLiteral("loading")}};
    emit snapshotChanged();
    m_clock.start();
    sample();
    m_timer.start();
}

WifiStatus::Reading WifiStatus::readConnection()
{
    Reading result;
#ifdef Q_OS_WIN
    result.details.insert(QStringLiteral("state"), QStringLiteral("unavailable"));
    HANDLE client = nullptr;
    DWORD version = 0;
    const auto opened = WlanOpenHandle(2, nullptr, &version, &client);
    if (opened != ERROR_SUCCESS) {
        if (opened == ERROR_SERVICE_NOT_ACTIVE)
            result.details[QStringLiteral("state")] = QStringLiteral("disconnected");
        return result;
    }
    const auto closeClient = qScopeGuard([&] { WlanCloseHandle(client, nullptr); });
    PWLAN_INTERFACE_INFO_LIST interfaces = nullptr;
    if (WlanEnumInterfaces(client, nullptr, &interfaces) != ERROR_SUCCESS || !interfaces)
        return result;
    const auto freeInterfaces = qScopeGuard([&] { WlanFreeMemory(interfaces); });
    result.details[QStringLiteral("state")] = QStringLiteral("disconnected");

    for (DWORD index = 0; index < interfaces->dwNumberOfItems; ++index) {
        const auto &adapter = interfaces->InterfaceInfo[index];
        if (adapter.isState != wlan_interface_state_connected)
            continue;

        QString ssid;
        DWORD bytes = 0;
        void *buffer = nullptr;
        const auto status = WlanQueryInterface(client, &adapter.InterfaceGuid,
            wlan_intf_opcode_current_connection, nullptr, &bytes, &buffer, nullptr);
        const auto freeConnection = qScopeGuard([&] { if (buffer) WlanFreeMemory(buffer); });
        if (status == ERROR_INVALID_STATE)
            continue;
        result.details[QStringLiteral("state")] = status == ERROR_ACCESS_DENIED
            ? QStringLiteral("restricted") : QStringLiteral("connected");
        if (status == ERROR_SUCCESS && buffer && bytes >= sizeof(WLAN_CONNECTION_ATTRIBUTES)) {
            const auto &connection = *static_cast<const WLAN_CONNECTION_ATTRIBUTES *>(buffer);
            if (connection.isState != wlan_interface_state_connected)
                continue;
            const auto &link = connection.wlanAssociationAttributes;
            ssid = networkName(link.dot11Ssid);
            if (ssid.isEmpty())
                ssid = QString::fromWCharArray(connection.strProfileName);
            result.details.insert(QStringLiteral("ssid"), ssid);
            result.details.insert(QStringLiteral("signal"), int(std::min<ULONG>(100, link.wlanSignalQuality)));
            if (link.ulRxRate > 0)
                result.details.insert(QStringLiteral("linkMbps"), link.ulRxRate / 1000.0);
        }
        result.details.insert(QStringLiteral("internet"), internetAccess(adapter.InterfaceGuid));
        result.networkId = QUuid(adapter.InterfaceGuid).toString(QUuid::WithoutBraces) + u':' + ssid;
        MIB_IF_ROW2 row{};
        if (ConvertInterfaceGuidToLuid(&adapter.InterfaceGuid, &row.InterfaceLuid) == NO_ERROR
            && GetIfEntry2(&row) == NO_ERROR) {
            result.received = row.InOctets;
            result.sent = row.OutOctets;
            result.hasCounters = true;
        }
        return result;
    }
#else
    result.details.insert(QStringLiteral("state"), QStringLiteral("unavailable"));
#endif
    return result;
}

WifiStatus::Reading WifiStatus::previewReading(qint64 milliseconds)
{
    const double seconds = (milliseconds + 12000) / 1000.0;
    return {{{QStringLiteral("state"), QStringLiteral("connected")},
             {QStringLiteral("ssid"), QStringLiteral("Sekai Studio")},
             {QStringLiteral("signal"), 82}, {QStringLiteral("linkMbps"), 866.7},
             {QStringLiteral("internet"), 1}, {QStringLiteral("preview"), true}},
        QStringLiteral("preview"), milliseconds,
        quint64(2600000 * seconds + 2700000 * std::sin(seconds * 0.7)),
        quint64(420000 * seconds + 420000 * std::sin(seconds * 0.8)), true};
}

void WifiStatus::sample()
{
    const auto milliseconds = m_clock.elapsed();
    if (m_preview) {
        if (m_previous.networkId.isEmpty()) {
            for (int offset = -9; offset < 0; ++offset)
                accept(previewReading(milliseconds + offset * 1000));
        }
        accept(previewReading(milliseconds));
        return;
    }
    if (m_pending)
        return;
    m_pending = true;
    const auto generation = m_generation;
    m_worker.start([this, generation, milliseconds] {
        auto reading = readConnection();
        reading.milliseconds = milliseconds;
        QMetaObject::invokeMethod(this, [this, generation, reading = std::move(reading)]() mutable {
            m_pending = false;
            if (m_active && generation == m_generation)
                accept(std::move(reading));
        }, Qt::QueuedConnection);
    });
}

void WifiStatus::accept(Reading reading)
{
    const auto elapsed = reading.milliseconds - m_previous.milliseconds;
    if (reading.hasCounters && m_previous.hasCounters && reading.networkId == m_previous.networkId
        && elapsed > 0 && elapsed <= 5000 && reading.received >= m_previous.received
        && reading.sent >= m_previous.sent) {
        const double toMbps = 0.008 / double(elapsed);
        const double down = double(reading.received - m_previous.received) * toMbps;
        const double up = double(reading.sent - m_previous.sent) * toMbps;
        m_samples.append(QVariantMap{{QStringLiteral("down"), down}, {QStringLiteral("up"), up}});
        if (m_samples.size() > 20)
            m_samples.removeFirst();
    } else {
        m_samples.clear();
    }
    m_previous = reading;
    m_snapshot = std::move(reading.details);
    m_snapshot.insert(QStringLiteral("hasCounters"), reading.hasCounters);
    m_snapshot.insert(QStringLiteral("samples"), m_samples);
    emit snapshotChanged();
}
