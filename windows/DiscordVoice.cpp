#include "DiscordVoice.h"

#include <QSettings>
#include <algorithm>
#include <utility>

using namespace Qt::StringLiterals;

namespace {

const auto linkedKey = u"discord/linked"_s;
const auto readyStatus = u"Discord подключён. Войдите в голосовой канал."_s;
const auto inCallStatus = u"Discord подключён. Голосовая сессия отображается в доке."_s;
const auto clientRequired = u"Запустите настольный Discord. Док подключится автоматически."_s;
const auto channelEvents = {u"VOICE_STATE_CREATE"_s, u"VOICE_STATE_UPDATE"_s, u"VOICE_STATE_DELETE"_s,
    u"SPEAKING_START"_s, u"SPEAKING_STOP"_s};

bool validId(const QString &id)
{
    return id.size() >= 16 && id.size() <= 20
        && std::all_of(id.cbegin(), id.cend(), [](QChar digit) { return digit >= u'0' && digit <= u'9'; });
}

QString memberId(const QJsonObject &member)
{
    return member.value(u"user"_s).toObject().value(u"id"_s).toString();
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
    for (const auto key : {u"nick"_s, u"mute"_s}) {
        if (update.contains(key))
            current.insert(key, update.value(key));
    }
    return current;
}

}

DiscordVoice::DiscordVoice(QSettings &settings, bool available, QString applicationId, QStringList endpoints,
                           QObject *parent)
    : QObject(parent), m_settings(settings), m_available(available && validId(applicationId)),
      m_clientId(std::move(applicationId)), m_rpc(std::move(endpoints)), m_oauth(settings)
{
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
            const auto userId = data.value(u"user"_s).toObject().value(u"id"_s).toString();
            if (error || data.value(u"application"_s).toObject().value(u"id"_s).toString() != m_clientId
                || userId.isEmpty() || !scopes.contains(u"rpc"_s) || !scopes.contains(u"rpc.voice.read"_s)) {
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
            m_authorized = true;
            m_writable = scopes.contains(u"rpc.voice.write"_s);
            const auto ignore = [](const QJsonValue &, int) {};
            m_rpc.request(u"SUBSCRIBE"_s, {}, ignore, u"VOICE_CHANNEL_SELECT"_s);
            m_rpc.request(u"SUBSCRIBE"_s, {}, ignore, u"VOICE_SETTINGS_UPDATE"_s);
            m_poll.start();
            setStatus(readyStatus);
            refreshVoice();
            refreshSettings();
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

    m_switching = false;
    m_channelId = id;
    if (oldChannel != id)
        subscribeChannel(oldChannel);
    if (id.isEmpty()) {
        m_lastChannel.clear();
        m_clock.stop();
        m_speaking.clear();
        // The last display values remain available while the dock closes.
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
    const auto states = channel.value(u"voice_states"_s).toArray();
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
            applyChannel(QJsonValue(QJsonValue::Null));
        } else if (channel.isString() && channel.toString() != m_channelId) {
            ++m_voiceRevision;
            m_switching = true;
            emit changed();
            refreshVoice();
        }
        return;
    }
    if (event == u"VOICE_SETTINGS_UPDATE"_s) {
        voiceSettings(data);
        return;
    }
    if (!connected() || m_switching || !m_subscribed.contains(event))
        return;

    const auto channelId = data.value(u"channel_id"_s);
    if (channelId.isString() && channelId.toString() != m_channelId)
        return;

    if (event == u"SPEAKING_START"_s || event == u"SPEAKING_STOP"_s) {
        const auto id = data.value(u"user_id"_s).toString();
        if (id.isEmpty())
            return;
        if (event == u"SPEAKING_START"_s)
            m_speaking.insert(id);
        else
            m_speaking.remove(id);
    } else {
        auto id = memberId(data);
        if (id.isEmpty())
            id = data.value(u"user_id"_s).toString();
        if (id.isEmpty())
            return;
        qsizetype index = 0;
        while (index < m_members.size() && memberId(m_members.at(index).toObject()) != id)
            ++index;
        if (event == u"VOICE_STATE_DELETE"_s) {
            if (index < m_members.size())
                m_members.removeAt(index);
            m_speaking.remove(id);
        } else if (index == m_members.size()) {
            if (!memberId(data).isEmpty())
                m_members.append(updatedMember({}, data));
        } else {
            m_members.replace(index, updatedMember(m_members.at(index).toObject(), data));
        }
    }
    publishParticipants();
    emit changed();
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
    for (const auto &entry : m_members) {
        const auto member = entry.toObject();
        const auto id = memberId(member);
        if (id.isEmpty())
            continue;
        const auto name = memberName(member);
        const bool self = id == m_selfId;
        if (!self && firstPeer.isEmpty())
            firstPeer = name;
        const auto state = member.value(u"voice_state"_s).toObject();
        const bool deaf = state.value(u"deaf"_s).toBool() || state.value(u"self_deaf"_s).toBool()
            || (self && m_deafened);
        const bool mute = state.value(u"mute"_s).toBool() || state.value(u"self_mute"_s).toBool()
            || member.value(u"mute"_s).toBool() || (self && m_muted);
        const bool speaking = !deaf && !mute && m_speaking.contains(id);
        const auto status = deaf ? u"Без звука"_s : mute ? u"Микрофон выкл."_s
            : speaking ? u"Говорит"_s : u"В канале"_s;
        const QVariantMap row{{u"name"_s, self ? u"Ты"_s : name}, {u"status"_s, status}, {u"speaking"_s, speaking}};
        if (self)
            participants.prepend(row);
        else
            participants.append(row);
    }
    if (m_room.isEmpty())
        m_room = m_channelType == 1 && !firstPeer.isEmpty() ? firstPeer
            : m_channelType == 1 ? u"Личный звонок"_s
            : m_channelType == 3 ? u"Групповой звонок"_s : u"Голосовой канал"_s;
    m_participants = std::move(participants);
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
    m_subscribed.clear();
    m_poll.stop();
    m_clock.stop();
    m_authorized = false;
    m_authenticating = false;
    m_writable = false;
    m_settingsKnown = false;
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
