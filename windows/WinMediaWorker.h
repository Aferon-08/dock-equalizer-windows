#pragma once

#include "MediaSessions.h"

#include <atomic>
#include <condition_variable>
#include <mutex>
#include <thread>
#include <vector>

class WinMediaWorker
{
public:
    explicit WinMediaWorker(MediaSessions *owner);
    ~WinMediaWorker();
    void select(const QString &id, quint64 revision);
    void enqueue(MediaCommand command);

private:
    void run();
    void publish(MediaUpdate update);

    MediaSessions *m_owner;
    std::atomic_bool m_stopping = false;
    std::mutex m_mutex;
    std::condition_variable m_wake;
    bool m_changed = false;
    QString m_preference;
    quint64 m_revision = 0;
    std::vector<MediaCommand> m_commands;
    std::thread m_thread;
};
