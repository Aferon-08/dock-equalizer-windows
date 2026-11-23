#include "DiscordVoice.h"

#include <QBuffer>
#include <QImage>
#include <QImageReader>
#include <QNetworkProxy>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QSettings>
#include <algorithm>
#include <utility>

using namespace Qt::StringLiterals;

namespace {

const auto linkedKey = u"discord/linked"_s;
const auto proxyModeKey = u"discord/proxyMode"_s;
const auto systemProxy = u"system"_s;
const auto incySocks5 = u"incy-socks5"_s;
const auto incyHttp = u"incy-http"_s;
const auto readyStatus = u"Discord подключён. Войдите в голосовой канал."_s;
const auto inCallStatus = u"Discord подключён. Голосовая сессия отображается в доке."_s;
const auto clientRequired = u"Запустите настольный Discord. Док подключится автоматически."_s;
const auto voiceConnectionEvent = u"VOICE_CONNECTION_STATUS"_s;
const auto unknownVoiceStatus = u"unknown"_s;
const auto channelEvents = {u"VOICE_STATE_CREATE"_s, u"VOICE_STATE_UPDATE"_s, u"VOICE_STATE_DELETE"_s,
    u"SPEAKING_START"_s, u"SPEAKING_STOP"_s};
const QHash<int, QByteArray> participantRoles{{Qt::UserRole, "participantId"}, {Qt::UserRole + 1, "name"},
    {Qt::UserRole + 2, "avatar"}, {Qt::UserRole + 3, "avatarUrl"}, {Qt::UserRole + 4, "localUser"},
    {Qt::UserRole + 5, "speaking"}, {Qt::UserRole + 6, "micOff"}, {Qt::UserRole + 7, "status"}};
constexpr qint64 maxAvatarBytes = 256 * 1024;

bool validId(const QString &id)
{
    return id.size() >= 16 && id.size() <= 20 && !id.startsWith(u'0') && id.toULongLong()
        && std::all_of(id.cbegin(), id.cend(), [](QChar digit) { return digit >= u'0' && digit <= u'9'; });
}

bool validProxyMode(const QString &mode)
{
    return mode == systemProxy || mode == incySocks5 || mode == incyHttp;
}

QNetworkProxy discordProxy(const QString &mode)
{
    if (mode == incySocks5)
        return QNetworkProxy(QNetworkProxy::Socks5Proxy, u"127.0.0.1"_s, 10808);
    if (mode == incyHttp)
        return QNetworkProxy(QNetworkProxy::HttpProxy, u"127.0.0.1"_s, 10809);
    return QNetworkProxy(QNetworkProxy::DefaultProxy);
}

QString memberId(const QJsonObject &member)
{
    const auto id = member.value(u"user"_s).toObject().value(u"id"_s).toString();
    return id.isEmpty() ? member.value(u"user_id"_s).toString() : id;
}

QString memberName(const QJsonObject &member)
{
    const auto user = member.value(u"user"_s).toObject();
    for (const auto &name : {member.value(u"nick"_s), user.value(u"global_name"_s), user.value(u"username"_s)}) {
        if (!name.toString().trimmed().isEmpty())
            return name.toString().simplified().left(128);
    }
    return u"Участник Discord"_s;
}

QUrl avatarUrl(const QString &id, const QJsonObject &user)
{
    static const QRegularExpression hashPattern(u"\\A(?:a_)?[0-9a-f]{32}\\z"_s);
    const auto hash = user.value(u"avatar"_s).toString();
    if (!validId(id) || !hashPattern.match(hash).hasMatch())
        return {};
    return QUrl(u"https://cdn.discordapp.com/avatars/%1/%2.png?size=128"_s.arg(id, hash));
}

QJsonObject updatedMember(QJsonObject current, const QJsonObject &update)
{
    for (const auto key : {u"user"_s, u"voice_state"_s}) {
        if (!update.value(key).isObject())
            continue;
        auto fields = current.value(key).toObject();
        const auto changes = update.value(key).toObject();
        for (auto it = changes.constBegin(); it != changes.constEnd(); ++it)
            fields.insert(it.key(), it.value());
        current.insert(key, fields);
    }
    for (const auto key : {u"user_id"_s, u"nick"_s}) {
        if (update.contains(key))
            current.insert(key, update.value(key));
    }
    return current;
}

}

DiscordParticipants::DiscordParticipants(QObject *parent) : QAbstractListModel(parent)
{
}

int DiscordParticipants::rowCount(const QModelIndex &parent) const
{
    return parent.isValid() ? 0 : int(m_rows.size());
}

QVariant DiscordParticipants::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= rowCount())
        return {};
    return m_rows.at(index.row()).toMap().value(QString::fromLatin1(participantRoles.value(role)));
}

QHash<int, QByteArray> DiscordParticipants::roleNames() const
{
    return participantRoles;
}

bool DiscordParticipants::setRows(QVariantList rows)
{
    if (m_rows == rows)
        return false;

    const auto idOf = [](const QVariant &value) { return value.toMap().value(u"participantId"_s).toString(); };
    QSet<QString> ids;
    for (const auto &row : std::as_const(rows))
        ids.insert(idOf(row));
    for (int row = rowCount() - 1; row >= 0; --row) {
        if (ids.contains(idOf(m_rows.at(row))))
            continue;
        beginRemoveRows({}, row, row);
        m_rows.removeAt(row);
        endRemoveRows();
    }

    for (int row = 0; row < rows.size(); ++row) {
        const auto &next = rows.at(row);
        const auto id = idOf(next);
        int current = row;
        while (current < rowCount() && idOf(m_rows.at(current)) != id)
            ++current;
        if (current == rowCount()) {
            beginInsertRows({}, row, row);
            m_rows.insert(row, next);
            endInsertRows();
            continue;
        }
        if (current != row) {
            beginMoveRows({}, current, current, {}, row);
            m_rows.move(current, row);
            endMoveRows();
        }
        if (m_rows.at(row) == next)
            continue;
        const auto oldData = m_rows.at(row).toMap();
        const auto newData = next.toMap();
        QList<int> roles;
        for (auto it = participantRoles.constBegin(); it != participantRoles.constEnd(); ++it) {
            const auto key = QString::fromLatin1(it.value());
            if (oldData.value(key) != newData.value(key))
                roles.append(it.key());
        }
        m_rows[row] = next;
        emit dataChanged(index(row, 0), index(row, 0), roles);
    }
    return true;
}

DiscordVoice::DiscordVoice(QSettings &settings, bool available, QString applicationId, QStringList endpoints,
                           QObject *parent)
    : QObject(parent), m_settings(settings), m_available(available && validId(applicationId)),
      m_clientId(std::move(applicationId)), m_proxyMode(settings.value(proxyModeKey, systemProxy).toString()),
      m_rpc(std::move(endpoints)), m_oauth(settings), m_participants(this)
{
    if (!validProxyMode(m_proxyMode))
        m_proxyMode = systemProxy;
    m_oauth.setProxy(discordProxy(m_proxyMode));
    m_avatarNetwork.setProxy(discordProxy(m_proxyMode));
    m_status = u"Discord отключён."_s;
    m_poll.setInterval(5000);
    m_clock.setInterval(1000);

    connect(&m_rpc, &DiscordRpc::handshakeReady, this, &DiscordVoice::openClient);
    connect(&m_rpc, &DiscordRpc::waitingForClient, this, &DiscordVoice::clientLost);
    connect(&m_rpc, &DiscordRpc::eventReceived, this, &DiscordVoice::dispatch);
    connect(&m_oauth, &DiscordOAuth::authorizing, this, [this] {
        setStatus(u"Подтвердите доступ в браузере."_s);
    });
    connect(&m_oauth, &DiscordOAuth::exchanging, this, [this] {
        if (!m_authorized)
            setStatus(u"Получаем разрешение Discord…"_s);
    });
    connect(&m_oauth, &DiscordOAuth::granted, this, [this] {
        if (m_rpc.ready())
            authenticate();
        else
            setStatus(clientRequired);
    });
    connect(&m_oauth, &DiscordOAuth::failed, this, [this](const QString &message) {
        m_consentRequested = false;
        // If a refresh fails, reconnecting or choosing Connect can try again.
        // Keep reading the IPC session while Discord still accepts it.
        setStatus(message);
    });
    connect(&m_poll, &QTimer::timeout, this, [this] {
        refreshVoice();
        refreshSettings();
    });
    connect(&m_clock, &QTimer::timeout, this, [this] {
        const int seconds = int(m_callStarted.elapsed() / 1000);
        if (m_seconds != seconds) {
            m_seconds = seconds;
            emit durationChanged();
        }
    });

    if (m_available && m_settings.value(linkedKey).toBool()) {
        m_linked = true;
        m_oauth.setClientId(m_clientId);
        m_rpc.start(m_clientId);
        m_status = u"Ищем настольный Discord…"_s;
    }
}

DiscordVoice::~DiscordVoice()
{
    syncAvatars({});
}

void DiscordVoice::setProxyMode(const QString &mode)
{
    if (signingIn() || !validProxyMode(mode))
        return;
    m_settings.setValue(proxyModeKey, mode);
    if (m_proxyMode == mode)
        return;
    m_proxyMode = mode;
    m_oauth.setProxy(discordProxy(mode));
    m_avatarNetwork.setProxy(discordProxy(mode));
    syncAvatars({});
    publishParticipants();
    emit proxyModeChanged();
}

void DiscordVoice::connectDiscord()
{
    if (!m_available || signingIn() || authorized())
        return;

    m_rpc.stop();
    m_oauth.cancel();
    m_oauth.setClientId(m_clientId);
    clearSession();
    m_linked = true;
    m_settings.setValue(linkedKey, true);
    m_consentRequested = true;
    m_rpc.start(m_clientId);
    setStatus(u"Ищем настольный Discord…"_s);
}

void DiscordVoice::disconnectDiscord()
{
    m_linked = false;
    m_consentRequested = false;
    m_rpc.stop();
    m_oauth.cancel();
    m_oauth.forget();
    clearSession();
    m_lastChannel.clear();
    m_settings.remove(linkedKey);
    setStatus(u"Discord отключён."_s);
}

bool DiscordVoice::canHangUp() const
{
    return m_authorized && m_writable && connected() && !m_switching && !m_mutating;
}

QString DiscordVoice::durationText() const
{
    const int hours = m_seconds / 3600;
    const int minutes = m_seconds / 60 % 60;
    return (hours ? QString::number(hours) + u':' : QString())
        + u"%1:%2"_s.arg(minutes, 2, 10, QChar(u'0')).arg(m_seconds % 60, 2, 10, QChar(u'0'));
}

void DiscordVoice::openClient()
{
    if (m_oauth.busy())
        return;
    if (m_oauth.usable()) {
        authenticate();
    } else if (m_oauth.renewable()) {
        m_oauth.refresh();
    } else if (std::exchange(m_consentRequested, false)) {
        m_oauth.authorize();
    } else {
        setStatus(u"Подключите Discord, чтобы подтвердить доступ."_s);
    }
}

void DiscordVoice::clientLost()
{
    if (connected())
        m_ipcLostAt.start();
    clearSession();
    if (!m_oauth.busy())
        setStatus(clientRequired);
    else
        emit changed();
}

void DiscordVoice::authenticate()
{
    if (m_authenticating)
        return;
    m_authenticating = true;
    setStatus(u"Подключаем голосовой RPC…"_s);
    m_rpc.request(u"AUTHENTICATE"_s, {{u"access_token"_s, m_oauth.accessToken()}},
        [this](const QJsonValue &value, int error) {
            m_authenticating = false;
            const auto data = value.toObject();
            const auto scopes = data.value(u"scopes"_s).toArray();
            const auto user = data.value(u"user"_s).toObject();
            const auto userId = user.value(u"id"_s).toString();
            if (error || data.value(u"application"_s).toObject().value(u"id"_s).toString() != m_clientId
                || !validId(userId) || !scopes.contains(u"rpc"_s) || !scopes.contains(u"rpc.voice.read"_s)) {
                if (error >= 0)
                    m_oauth.forget();
                setStatus(u"Discord не подтвердил доступ к голосовым каналам. Попробуйте подключиться снова."_s);
                return;
            }
            if (!m_rpc.userId().isEmpty() && m_rpc.userId() != userId) {
                m_oauth.forget();
                setStatus(u"Войдите в один и тот же аккаунт в браузере и настольном Discord."_s);
                return;
            }
            m_consentRequested = false;
            m_selfId = userId;
            m_selfUser = user;
            m_authorized = true;
            m_writable = scopes.contains(u"rpc.voice.write"_s);
            const auto ignore = [](const QJsonValue &, int) {};
            m_rpc.request(u"SUBSCRIBE"_s, {}, ignore, u"VOICE_CHANNEL_SELECT"_s);
            m_rpc.request(u"SUBSCRIBE"_s, {}, ignore, u"VOICE_SETTINGS_UPDATE"_s);
            m_poll.start();
            setStatus(readyStatus);
            refreshVoice();
            refreshSettings();
            m_rpc.request(u"SUBSCRIBE"_s, {}, [this](const QJsonValue &reply, int error) {
                m_voiceStatusSubscribed = !error && reply.toObject().value(u"evt"_s) == voiceConnectionEvent;
            }, voiceConnectionEvent);
        });
}

void DiscordVoice::refreshVoice()
{
    if (!m_authorized || m_queryingVoice || m_mutating)
        return;
    m_queryingVoice = true;
    const auto revision = m_voiceRevision;
    m_rpc.request(u"GET_SELECTED_VOICE_CHANNEL"_s, {}, [this, revision](const QJsonValue &data, int error) {
        m_queryingVoice = false;
        if (revision != m_voiceRevision) {
            refreshVoice();
            return;
        }
        if (error == 4006) {
            const bool canRenew = m_oauth.renewable() && !m_oauth.usable();
            if (connected())
                m_ipcLostAt.start();
            clearSession();
            if (canRenew) {
                m_rpc.start(m_clientId);
                setStatus(u"Восстанавливаем доступ к Discord…"_s);
            } else {
                m_rpc.stop();
                m_oauth.forget();
                setStatus(u"Discord завершил сеанс голосового RPC. Подключите Discord снова."_s);
            }
            return;
        }
        if (!error && (data.isNull() || data.isObject()))
            applyChannel(data);
    });
}

void DiscordVoice::refreshSettings()
{
    if (!m_authorized || m_queryingSettings || m_mutating)
        return;
    m_queryingSettings = true;
    const auto revision = m_settingsRevision;
    m_rpc.request(u"GET_VOICE_SETTINGS"_s, {}, [this, revision](const QJsonValue &data, int error) {
        m_queryingSettings = false;
        if (!error && revision == m_settingsRevision)
            voiceSettings(data.toObject());
    });
}

void DiscordVoice::voiceSettings(const QJsonObject &settings)
{
    const auto mute = settings.value(u"mute"_s);
    const auto deaf = settings.value(u"deaf"_s);
    if (mute.isBool() && deaf.isBool()) {
        const bool changed = !m_settingsKnown || m_muted != mute.toBool() || m_deafened != deaf.toBool();
        m_settingsKnown = true;
        m_muted = mute.toBool();
        m_deafened = deaf.toBool();
        ++m_settingsRevision;
        if (changed) {
            publishParticipants();
            emit this->changed();
        }
    }
}

void DiscordVoice::applyChannel(const QJsonValue &data)
{
    const auto channel = data.toObject();
    const auto id = channel.value(u"id"_s).toString();
    const auto oldChannel = m_channelId;
    if (id.isEmpty() && !data.isNull())
        return;

    if (oldChannel != id || m_switching) {
        setVoiceStatus(m_pendingChannel == id && !m_pendingVoiceStatus.isEmpty()
            ? m_pendingVoiceStatus : unknownVoiceStatus);
    }
    m_switching = false;
    m_channelId = id;
    if (oldChannel != id)
        subscribeChannel(oldChannel);
    m_pendingChannel.clear();
    m_pendingVoiceStatus.clear();
    if (id.isEmpty()) {
        m_lastChannel.clear();
        m_clock.stop();
        m_speaking.clear();
        m_members = QJsonArray{};
        syncAvatars({});
        setParticipantRows({});
        if (m_status != readyStatus || !oldChannel.isEmpty())
            setStatus(readyStatus);
        return;
    }

    if (oldChannel != id) {
        if (id != m_lastChannel || !m_ipcLostAt.isValid() || m_ipcLostAt.elapsed() > 30000) {
            m_callStarted.start();
            m_seconds = 0;
            emit durationChanged();
        }
        m_ipcLostAt.invalidate();
        m_lastChannel = id;
        m_speaking.clear();
        m_clock.start();
    }
    const auto newName = channel.value(u"name"_s).toString().simplified().left(128);
    const int newType = channel.value(u"type"_s).toInt();
    const auto voiceStates = channel.value(u"voice_states"_s);
    QJsonArray states;
    if (voiceStates.isArray()) {
        QHash<QString, qsizetype> indices;
        const auto snapshot = voiceStates.toArray();
        for (const auto &entry : snapshot) {
            const auto member = entry.toObject();
            const auto memberUserId = memberId(member);
            if (!validId(memberUserId))
                continue;
            const auto existing = indices.constFind(memberUserId);
            if (existing == indices.constEnd()) {
                indices.insert(memberUserId, states.size());
                states.append(member);
            } else {
                states.replace(*existing, updatedMember(states.at(*existing).toObject(), member));
            }
        }
        m_speaking.removeIf([&](const QString &memberUserId) {
            return memberUserId != m_selfId && !indices.contains(memberUserId);
        });
    } else if (oldChannel == id) {
        states = m_members;
    }
    const bool rosterChanged = m_members != states || m_channelType != newType || m_channelName != newName;
    m_members = states;
    m_channelType = newType;
    m_channelName = newName;
    if (rosterChanged || oldChannel != id)
        publishParticipants();
    const auto status = m_writable ? inCallStatus : u"Голосовая сессия подключена. Discord разрешил только просмотр."_s;
    if (rosterChanged || oldChannel != id || m_status == readyStatus)
        setStatus(status);
}

void DiscordVoice::subscribeChannel(const QString &oldChannel)
{
    m_subscribed.clear();
    for (const auto &event : channelEvents) {
        if (!oldChannel.isEmpty())
            m_rpc.request(u"UNSUBSCRIBE"_s, {{u"channel_id"_s, oldChannel}}, [](const QJsonValue &, int) {}, event);
        if (!m_channelId.isEmpty()) {
            m_rpc.request(u"SUBSCRIBE"_s, {{u"channel_id"_s, m_channelId}},
                [this, event, channel = m_channelId](const QJsonValue &, int error) {
                    if (!error && m_channelId == channel)
                        m_subscribed.insert(event);
                }, event);
        }
    }
}

void DiscordVoice::dispatch(const QString &event, const QJsonObject &data)
{
    if (!m_authorized)
        return;

    if (event == u"VOICE_CHANNEL_SELECT"_s) {
        const auto channel = data.value(u"channel_id"_s);
        if (channel.isNull()) {
            ++m_voiceRevision;
            m_pendingChannel.clear();
            m_pendingVoiceStatus.clear();
            applyChannel(QJsonValue(QJsonValue::Null));
        } else if (channel.isString() && validId(channel.toString())
            && channel.toString() != (m_switching ? m_pendingChannel : m_channelId)) {
            ++m_voiceRevision;
            m_pendingChannel = channel.toString();
            m_pendingVoiceStatus.clear();
            m_switching = true;
            setVoiceStatus(unknownVoiceStatus);
            emit changed();
            refreshVoice();
        }
        return;
    }
    if (event == u"VOICE_SETTINGS_UPDATE"_s) {
        voiceSettings(data);
        return;
    }
    if (event == voiceConnectionEvent) {
        connectionStatus(data);
        return;
    }
    if (!connected() || m_switching || !m_subscribed.contains(event))
        return;

    const auto channelId = data.value(u"channel_id"_s);
    if (channelId.isString() && channelId.toString() != m_channelId)
        return;

    if (event == u"SPEAKING_START"_s || event == u"SPEAKING_STOP"_s) {
        const auto id = data.value(u"user_id"_s).toString();
        const bool speaking = event == u"SPEAKING_START"_s;
        if (!validId(id) || m_speaking.contains(id) == speaking)
            return;
        if (speaking)
            m_speaking.insert(id);
        else
            m_speaking.remove(id);
    } else {
        const auto id = memberId(data);
        if (!validId(id))
            return;
        ++m_voiceRevision;
        qsizetype index = 0;
        while (index < m_members.size() && memberId(m_members.at(index).toObject()) != id)
            ++index;
        if (event == u"VOICE_STATE_DELETE"_s) {
            if (index < m_members.size())
                m_members.removeAt(index);
            m_speaking.remove(id);
        } else if (index == m_members.size()) {
            m_members.append(updatedMember({}, data));
        } else {
            m_members.replace(index, updatedMember(m_members.at(index).toObject(), data));
        }
    }
    publishParticipants();
    emit changed();
}

void DiscordVoice::connectionStatus(const QJsonObject &data)
{
    const auto &selected = m_switching ? m_pendingChannel : m_channelId;
    const auto channel = data.value(u"channel_id"_s);
    if (!m_voiceStatusSubscribed || selected.isEmpty() || (channel.isString() && channel.toString() != selected))
        return;

    const auto state = data.value(u"state"_s).toString();
    auto status = unknownVoiceStatus;
    if (state == u"VOICE_CONNECTED"_s) {
        status = u"connected"_s;
    } else if (state == u"DISCONNECTED"_s || state == u"VOICE_DISCONNECTED"_s || state == u"NO_ROUTE"_s) {
        status = u"disconnected"_s;
    } else if (state == u"AWAITING_ENDPOINT"_s || state == u"AUTHENTICATING"_s || state == u"CONNECTING"_s
        || state == u"CONNECTED"_s || state == u"VOICE_CONNECTING"_s || state == u"ICE_CHECKING"_s) {
        status = u"connecting"_s;
    }
    // An event can precede the snapshot when Discord has just selected a channel.
    if (m_switching)
        m_pendingVoiceStatus = status;
    else
        setVoiceStatus(status);
}

void DiscordVoice::setVoiceStatus(const QString &status)
{
    if (m_voiceStatus == status)
        return;
    m_voiceStatus = status;
    emit voiceStatusChanged();
}

void DiscordVoice::publishParticipants()
{
    if (!connected())
        return;

    m_context = m_channelType == 1 ? u"Discord · Личный звонок"_s
        : m_channelType == 3 ? u"Discord · Групповой звонок"_s : u"Discord · Голосовой канал"_s;
    m_room = m_channelName;
    QString firstPeer;
    QVariantList participants;
    QSet<QUrl> avatars;
    const auto appendParticipant = [&](QJsonObject member, const QString &id) {
        const bool self = id == m_selfId;
        auto user = member.value(u"user"_s).toObject();
        if (self) {
            for (auto it = m_selfUser.constBegin(); it != m_selfUser.constEnd(); ++it) {
                if (!user.contains(it.key()))
                    user.insert(it.key(), it.value());
            }
            member.insert(u"user"_s, user);
        }
        const auto name = memberName(member);
        if (!self && firstPeer.isEmpty())
            firstPeer = name;
        const auto state = member.value(u"voice_state"_s).toObject();
        const bool deaf = state.value(u"deaf"_s).toBool()
            || (self && m_settingsKnown ? m_deafened : state.value(u"self_deaf"_s).toBool());
        const bool mute = state.value(u"mute"_s).toBool()
            || (self && m_settingsKnown ? m_muted : state.value(u"self_mute"_s).toBool());
        const bool micOff = mute || deaf || state.value(u"suppress"_s).toBool();
        const bool speaking = !micOff && m_speaking.contains(id);
        const auto status = deaf ? u"Без звука"_s : micOff ? u"Микрофон выкл."_s
            : speaking ? u"Говорит"_s : u"В канале"_s;
        const auto url = avatarUrl(id, user);
        if (!url.isEmpty())
            avatars.insert(url);
        const QVariantMap row{{u"participantId"_s, id}, {u"name"_s, name}, {u"localUser"_s, self},
            {u"avatar"_s, m_avatars.value(url)}, {u"avatarUrl"_s, url}, {u"status"_s, status},
            {u"speaking"_s, speaking}, {u"micOff"_s, micOff}};
        if (self)
            participants.prepend(row);
        else
            participants.append(row);
    };
    bool ownRow = false;
    for (const auto &entry : std::as_const(m_members)) {
        const auto member = entry.toObject();
        const auto id = memberId(member);
        ownRow |= id == m_selfId;
        appendParticipant(member, id);
    }
    if (!ownRow)
        appendParticipant({}, m_selfId);
    if (m_room.isEmpty())
        m_room = m_channelType == 1 && !firstPeer.isEmpty() ? firstPeer
            : m_channelType == 1 ? u"Личный звонок"_s
            : m_channelType == 3 ? u"Групповой звонок"_s : u"Голосовой канал"_s;
    setParticipantRows(std::move(participants));
    syncAvatars(avatars);
}

void DiscordVoice::setParticipantRows(QVariantList rows)
{
    const bool countChanged = participantCount() != rows.size();
    if (!m_participants.setRows(std::move(rows)))
        return;
    if (countChanged)
        emit participantCountChanged();
    emit participantsChanged();
}

void DiscordVoice::syncAvatars(const QSet<QUrl> &urls)
{
    m_avatars.removeIf([&](QHash<QUrl, QUrl>::iterator entry) { return !urls.contains(entry.key()); });
    for (const auto &url : m_avatarRequests.keys()) {
        if (urls.contains(url))
            continue;
        auto *reply = m_avatarRequests.take(url);
        reply->disconnect(this);
        reply->abort();
        reply->deleteLater();
    }
    for (const auto &url : urls) {
        if (!m_avatars.contains(url) && !m_avatarRequests.contains(url))
            fetchAvatar(url);
    }
}

void DiscordVoice::fetchAvatar(const QUrl &url)
{
    QNetworkRequest request(url);
    request.setTransferTimeout(5000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    request.setAttribute(QNetworkRequest::CookieLoadControlAttribute, QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::CookieSaveControlAttribute, QNetworkRequest::Manual);
    request.setAttribute(QNetworkRequest::AuthenticationReuseAttribute, QNetworkRequest::Manual);
    auto *reply = m_avatarNetwork.get(request);
    m_avatarRequests.insert(url, reply);
    reply->setReadBufferSize(maxAvatarBytes + 1);
    connect(reply, &QNetworkReply::readyRead, this, [reply] {
        if (reply->bytesAvailable() > maxAvatarBytes)
            reply->abort();
    });
    connect(reply, &QNetworkReply::finished, this, [this, reply, url] {
        m_avatarRequests.remove(url);
        reply->deleteLater();
        m_avatars.insert(url, {});
        if (reply->error() != QNetworkReply::NoError || reply->bytesAvailable() > maxAvatarBytes
            || reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt() != 200)
            return;

        QBuffer image;
        image.setData(reply->readAll());
        image.open(QIODevice::ReadOnly);
        QImageReader reader(&image, "png");
        const auto size = reader.size();
        if (!size.isValid() || size.width() > 256 || size.height() > 256 || reader.read().isNull())
            return;

        m_avatars[url] = QUrl::fromEncoded("data:image/png;base64," + image.data().toBase64());
        publishParticipants();
    });
}

void DiscordVoice::toggleMute()
{
    if (canChangeVoice() && !m_deafened)
        mutate(u"SET_VOICE_SETTINGS"_s, {{u"mute"_s, !m_muted}});
}

void DiscordVoice::toggleDeafen()
{
    if (canChangeVoice())
        mutate(u"SET_VOICE_SETTINGS"_s, {{u"deaf"_s, !m_deafened}});
}

void DiscordVoice::hangUp()
{
    if (canHangUp())
        mutate(u"SELECT_VOICE_CHANNEL"_s, {{u"channel_id"_s, QJsonValue(QJsonValue::Null)}});
}

void DiscordVoice::mutate(const QString &command, const QJsonObject &args)
{
    const bool leaving = command == u"SELECT_VOICE_CHANNEL"_s;
    const auto revision = ++m_voiceRevision;
    const auto settingsRevision = ++m_settingsRevision;
    m_mutating = true;
    emit changed();
    m_rpc.request(command, args, [this, leaving, revision, settingsRevision](const QJsonValue &data, int error) {
        m_mutating = false;
        if (error) {
            setStatus(u"Discord не выполнил действие. Проверьте разрешения и настройки голоса в Discord."_s);
        } else {
            if (leaving && m_voiceRevision == revision && data.isNull())
                applyChannel(data);
            else if (!leaving && m_settingsRevision == settingsRevision)
                voiceSettings(data.toObject());
            setStatus(connected() ? inCallStatus : readyStatus);
        }
        refreshVoice();
        refreshSettings();
    });
}

void DiscordVoice::clearSession()
{
    ++m_voiceRevision;
    ++m_settingsRevision;
    m_channelId.clear();
    m_pendingChannel.clear();
    m_pendingVoiceStatus.clear();
    setVoiceStatus(unknownVoiceStatus);
    m_subscribed.clear();
    m_members = QJsonArray{};
    m_speaking.clear();
    m_selfId.clear();
    m_selfUser = {};
    syncAvatars({});
    setParticipantRows({});
    m_poll.stop();
    m_clock.stop();
    m_authorized = false;
    m_voiceStatusSubscribed = false;
    m_authenticating = false;
    m_writable = false;
    m_settingsKnown = false;
    m_muted = false;
    m_deafened = false;
    m_mutating = false;
    m_switching = false;
    m_queryingVoice = false;
    m_queryingSettings = false;
}

void DiscordVoice::setStatus(const QString &status)
{
    m_status = status;
    emit changed();
}
