#include "LyricsAlignment.h"
#include "LyricsImport.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QLockFile>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStringDecoder>
#include <QTemporaryDir>
#include <QUuid>

#include <cmath>
#include <utility>

#ifdef Q_OS_WIN
#include <QtCore/qt_windows.h>
#endif

namespace {

constexpr int protocol = 1;
constexpr qsizetype maxEventBytes = 8192;
constexpr qsizetype maxTextBytes = 128 * 1024;
constexpr qint64 maxResultBytes = 4 * 1024 * 1024;
constexpr qint64 maxAudioBytes = 2 * 1024 * 1024 * 1024LL;

QString phaseText(const QString &phase)
{
    if (phase == QStringLiteral("model")) return QStringLiteral("Скачивание модели Whisper…");
    if (phase == QStringLiteral("dependencies")) return QStringLiteral("Установка обработчика и FFmpeg…");
    if (phase == QStringLiteral("checking")) return QStringLiteral("Проверка обработчика…");
    if (phase == QStringLiteral("decoding")) return QStringLiteral("Чтение аудиофайла…");
    if (phase == QStringLiteral("loading")) return QStringLiteral("Загрузка модели…");
    if (phase == QStringLiteral("aligning")) return QStringLiteral("Выравнивание слов…");
    if (phase == QStringLiteral("saving")) return QStringLiteral("Проверка таймингов…");
    return {};
}

} // namespace

LyricsAlignment::LyricsAlignment(QObject *parent)
    : LyricsAlignment(QCoreApplication::applicationDirPath() + QStringLiteral("/alignment"),
        QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) + QStringLiteral("/alignment"),
        parent)
{
}

LyricsAlignment::LyricsAlignment(QString bundle, QString dataDirectory, QObject *parent)
    : QObject(parent), m_bundle(std::move(bundle)), m_data(std::move(dataDirectory))
{
#ifdef Q_OS_WIN
    m_process.setCreateProcessArgumentsModifier([](QProcess::CreateProcessArguments *args) {
        args->flags |= CREATE_NO_WINDOW;
    });
#endif
    m_deadline.setSingleShot(true);
    connect(&m_deadline, &QTimer::timeout, this, [this] {
        stop(QStringLiteral("Задание заняло больше 40 минут."));
    });
    connect(&m_process, &QProcess::started, this, &LyricsAlignment::sendRequest);
    connect(&m_process, &QProcess::readyReadStandardOutput, this, &LyricsAlignment::readEvents);
    connect(&m_process, &QProcess::readyReadStandardError, this, [this] {
        m_process.readAllStandardError();
    });
    connect(&m_process, &QProcess::finished, this, [this](int code, QProcess::ExitStatus exit) {
        finish(code == 0 && exit == QProcess::NormalExit);
    });
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart) {
            m_stopMessage = QStringLiteral("Не удалось запустить обработчик.");
            finish(false);
        }
    });
}

LyricsAlignment::~LyricsAlignment()
{
    disconnect(&m_process, nullptr, this, nullptr);
    closeJob();
    if (m_process.state() != QProcess::NotRunning) {
        m_process.kill();
        m_process.waitForFinished(3000);
    }
}

bool LyricsAlignment::ready() const
{
    const QDir runtime(m_data + QStringLiteral("/cpu-v1"));
    return runtime.exists(QStringLiteral("ready.json"))
        && runtime.exists(QStringLiteral("models/base.pt"))
        && runtime.exists(QStringLiteral("packages/stable_whisper/__init__.py"));
}

void LyricsAlignment::prepare()
{
    if (busy() || ready())
        return;
    m_preparing = true;
    launch({{QStringLiteral("action"), QStringLiteral("prepare")}});
}

void LyricsAlignment::align(const QUrl &audio, const QString &text, const QString &trackKey, double trackDuration)
{
    if (busy())
        return;
    if (!ready()) {
        setStatus(QStringLiteral("Сначала подготовьте модуль выравнивания."));
        return;
    }
    const QFileInfo file(audio.toLocalFile());
    if (!audio.isLocalFile() || !audio.host().isEmpty() || !file.isFile()
            || file.size() <= 0 || file.size() > maxAudioBytes) {
        setStatus(QStringLiteral("Выберите локальный аудиофайл размером до 2 ГБ."));
        return;
    }
    const QString lyrics = text.trimmed();
    if (lyrics.isEmpty() || lyrics.toUtf8().size() > maxTextBytes) {
        setStatus(QStringLiteral("Добавьте готовый текст песни размером до 128 КБ."));
        return;
    }
    m_preparing = false;
    m_trackKey = trackKey;
    m_duration = std::isfinite(trackDuration) && trackDuration > 0 ? trackDuration : 0;
    launch({{QStringLiteral("action"), QStringLiteral("align")},
        {QStringLiteral("audio"), file.absoluteFilePath()}, {QStringLiteral("lyrics"), lyrics},
        {QStringLiteral("trackDuration"), m_duration}});
}

void LyricsAlignment::launch(QJsonObject request)
{
    const QDir bundle(m_bundle);
    const QString python = bundle.filePath(QStringLiteral("python/python.exe"));
    const QString worker = bundle.filePath(QStringLiteral("worker.py"));
    if (!QFileInfo(python).isFile() || !QFileInfo(worker).isFile()) {
        setStatus(QStringLiteral("Файлы модуля отсутствуют. Распакуйте полный ZIP целиком."));
        return;
    }
    if (!QDir().mkpath(m_data)) {
        setStatus(QStringLiteral("Не удалось создать папку обработчика."));
        return;
    }
    auto lock = std::make_unique<QLockFile>(m_data + QStringLiteral("/job.lock"));
    lock->setStaleLockTime(0);
    if (!lock->tryLock()) {
        setStatus(QStringLiteral("Другое окно уже выполняет задание выравнивания."));
        return;
    }
    auto work = std::make_unique<QTemporaryDir>(m_data + QStringLiteral("/job-XXXXXX"));
    if (!work->isValid()) {
        setStatus(QStringLiteral("Не удалось создать рабочую папку задания."));
        return;
    }
#ifdef Q_OS_WIN
    m_job = CreateJobObjectW(nullptr, nullptr);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!m_job || !SetInformationJobObject(m_job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) {
        closeJob();
        setStatus(QStringLiteral("Не удалось создать группу процессов обработчика."));
        return;
    }
#endif
    m_jobId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    request.insert(QStringLiteral("version"), protocol);
    request.insert(QStringLiteral("id"), m_jobId);
    request.insert(QStringLiteral("data"), m_data);
    request.insert(QStringLiteral("work"), work->path());
    m_request = QJsonDocument(request).toJson(QJsonDocument::Compact) + '\n';
    m_lock = std::move(lock);
    m_work = std::move(work);
    m_result = {};
    m_stdout.clear();
    m_stopMessage.clear();
    m_progress = 0;
    setStatus(QStringLiteral("Запуск обработчика…"));
    m_deadline.start(40 * 60 * 1000);
    m_process.start(python, {QStringLiteral("-I"), QStringLiteral("-X"), QStringLiteral("utf8"),
        QStringLiteral("-u"), worker});
}

void LyricsAlignment::sendRequest()
{
#ifdef Q_OS_WIN
    const HANDLE worker = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, FALSE, DWORD(m_process.processId()));
    const bool assigned = worker && m_job && AssignProcessToJobObject(m_job, worker);
    if (worker)
        CloseHandle(worker);
    if (!assigned) {
        stop(QStringLiteral("Не удалось запустить обработчик в отдельной группе процессов."));
        return;
    }
#endif
    // The worker waits for input before it can start any subprocess.
    m_process.write(m_request);
    m_request.clear();
    m_process.closeWriteChannel();
}

void LyricsAlignment::readEvents()
{
    const auto bytes = m_process.readAllStandardOutput();
    if (!busy() || !m_stopMessage.isEmpty())
        return;
    m_stdout += bytes;
    qsizetype lineEnd;
    while ((lineEnd = m_stdout.indexOf('\n')) >= 0) {
        if (lineEnd > maxEventBytes)
            break;
        const auto event = QJsonDocument::fromJson(m_stdout.left(lineEnd)).object();
        m_stdout.remove(0, lineEnd + 1);
        if (event.value(QStringLiteral("version")).toInt() != protocol || event.value(QStringLiteral("id")).toString() != m_jobId) {
            stop(QStringLiteral("Обработчик прислал неверный ответ."));
            return;
        }
        if (event.value(QStringLiteral("type")) == QStringLiteral("result")) {
            m_result = event;
        } else if (event.value(QStringLiteral("type")) == QStringLiteral("progress")) {
            m_progress = qBound(0.0, event.value(QStringLiteral("fraction")).toDouble(), 1.0);
            const auto status = phaseText(event.value(QStringLiteral("phase")).toString());
            if (!status.isEmpty())
                setStatus(status);
        }
    }
    if (m_stdout.size() > maxEventBytes)
        stop(QStringLiteral("Обработчик прислал слишком большой ответ."));
}

void LyricsAlignment::cancel()
{
    if (busy())
        stop(QStringLiteral("Задание отменено."));
}

void LyricsAlignment::stop(const QString &message)
{
    m_stopMessage = message;
    closeJob();
    if (m_process.state() != QProcess::NotRunning)
        m_process.kill();
}

void LyricsAlignment::closeJob()
{
#ifdef Q_OS_WIN
    if (m_job) {
        CloseHandle(m_job);
        m_job = nullptr;
    }
#endif
}

void LyricsAlignment::finish(bool cleanExit)
{
    if (!busy())
        return;
    m_deadline.stop();
    readEvents();
    closeJob();
    QString status = m_stopMessage;
    QVariantMap document;
    if (status.isEmpty()) {
        if (!cleanExit || !m_result.value(QStringLiteral("ok")).toBool()) {
            status = m_result.value(QStringLiteral("message")).toString().left(400);
            if (status.isEmpty())
                status = QStringLiteral("Обработчик прервал задание.");
        } else if (m_preparing) {
            status = ready() ? QStringLiteral("Модуль готов.") : QStringLiteral("Подготовка модуля не завершилась.");
        } else {
            QFile output(m_work->filePath(QStringLiteral("result.json")));
            status = QStringLiteral("Не удалось прочитать результат выравнивания.");
            if (output.open(QIODevice::ReadOnly) && output.size() <= maxResultBytes) {
                const auto bytes = output.read(maxResultBytes + 1);
                QStringDecoder decoder(QStringDecoder::Utf8, QStringDecoder::Flag::Stateless);
                const QString text = decoder(bytes);
                if (output.error() == QFileDevice::NoError && bytes.size() <= maxResultBytes && !decoder.hasError()) {
                    document = LyricsImport::parseWordtime(text, m_duration);
                    if (document.value(QStringLiteral("ok")).toBool()) {
                        m_export = bytes;
                        status = QStringLiteral("Разметка готова. Её можно сохранить в JSON.");
                    } else {
                        status = document.value(QStringLiteral("message")).toString();
                        document.clear();
                    }
                }
            }
        }
    }
    m_request.clear();
    m_work.reset();
    m_lock.reset();
    const QString trackKey = m_trackKey;
    setStatus(status);
    if (!document.isEmpty())
        emit aligned(trackKey, document);
}

QString LyricsAlignment::save(const QUrl &target) const
{
    if (!hasResult() || !target.isLocalFile() || !target.host().isEmpty()
            || QFileInfo(target.toLocalFile()).suffix().compare(QStringLiteral("json"), Qt::CaseInsensitive) != 0)
        return QStringLiteral("Выберите локальный файл с расширением .json.");
    QSaveFile file(target.toLocalFile());
    if (!file.open(QIODevice::WriteOnly) || file.write(m_export) != m_export.size() || !file.commit())
        return QStringLiteral("Не удалось сохранить тайминги.");
    return {};
}

void LyricsAlignment::setStatus(const QString &message)
{
    m_status = message;
    emit changed();
}
