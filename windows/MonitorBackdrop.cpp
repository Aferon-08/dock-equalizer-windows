#include "MonitorBackdrop.h"
#include "BackdropGeometry.h"

#include <QImage>
#include <QQuickWindow>
#include <QSGSimpleTextureNode>

#ifdef Q_OS_WIN
#include "BackdropTextureNode.h"
#include "WinCaptureInterop.h"

#include <QElapsedTimer>
#include <QThread>

#include <asyncinfo.h>
#include <cstring>
#include <utility>

namespace {

using namespace wincapture;

constexpr int bufferCount = 3;
constexpr int retryDelay = 2000;

enum class CaptureStatus { Starting, Ready, Unavailable };

struct CaptureLease
{
    // The WinRT frame is agile. Keeping it checked out protects its texture
    // until the render thread schedules the copy.
    ComPtr<Frame> frame;
    ComPtr<ID3D11Texture2D> texture;
    QImage image;
};

struct CapturedFrame
{
    CaptureStatus status;
    std::shared_ptr<CaptureLease> lease;
    bool borderError = false;
};

// The worker hands off a checked-out frame instead of reading back pixels.
class CaptureWorker : public QObject
{
public:
    ~CaptureWorker() override
    {
        stop();
        if (m_initialized)
            RoUninitialize();
    }

    void stop()
    {
        close();
        m_monitor = nullptr;
        m_renderDevice.Reset();
    }

    CapturedFrame sample(ID3D11Device *device, HMONITOR monitor, const QRect &bounds,
                        const QRect &crop, bool needsFrame, bool borderless)
    {
        if (m_renderDevice.Get() != device || m_monitor != monitor || m_bounds != bounds) {
            stop();
            m_renderDevice = device;
            m_monitor = monitor;
            m_bounds = bounds;
        }
        if (!m_pool) {
            if (!start(borderless))
                return failed();
            m_started.start();
        } else {
            applyBorder(borderless);
        }

        // Drain the tiny queue. Keep the newest frame for recropping a static
        // desktop while the dock changes shape.
        ComPtr<Frame> newest;
        for (int i = 0; i < bufferCount; ++i) {
            ComPtr<Frame> next;
            if (FAILED(m_pool->TryGetNextFrame(next.GetAddressOf())))
                return failed();
            if (!next)
                break;
            newest = std::move(next);
        }
        const bool updated = bool(newest);
        if (updated) {
            auto lease = mapFrame(std::move(newest));
            if (!lease)
                return failed();
            m_frame = std::move(lease);
        }
        if (!m_frame) {
            if (m_started.elapsed() > retryDelay)
                return failed();
            return {CaptureStatus::Starting, {}};
        }
        if (m_readContext)
            return sampleReadback(crop, updated, needsFrame);
        if (!updated && crop == m_lastCrop && !needsFrame)
            return {CaptureStatus::Ready, {}, m_borderError};
        m_lastCrop = crop;
        return {CaptureStatus::Ready, m_frame, m_borderError};
    }

private:
    bool start(bool borderless)
    {
        m_device = m_renderDevice;
        if (open(borderless))
            return true;
        close();

        // Compatibility path for a Qt device that Windows Capture cannot wrap.
        return SUCCEEDED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
                              D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
                              m_device.GetAddressOf(), nullptr, m_readContext.GetAddressOf()))
            && open(borderless);
    }

    bool open(bool borderless)
    {
        if (!m_initialized) {
            m_initialized = SUCCEEDED(RoInitialize(RO_INIT_MULTITHREADED));
            if (!m_initialized)
                return false;
        }

        ComPtr<ItemInterop> interop;
        ComPtr<Item> item;
        Size size{};
        if (FAILED(activationFactory(L"Windows.Graphics.Capture.GraphicsCaptureItem", itemInteropId, interop))
                || FAILED(interop->CreateForMonitor(m_monitor, itemId, reinterpret_cast<void **>(item.GetAddressOf())))
                || FAILED(item->get_Size(&size)) || QSize(size.width, size.height) != m_bounds.size())
            return false;

        ComPtr<IInspectable> graphicsDevice;
        if (!wrapCaptureDevice(m_device.Get(), graphicsDevice))
            return false;

        ComPtr<FramePoolFactory> factory;
        ComPtr<SessionCursor> cursor;
        if (FAILED(activationFactory(L"Windows.Graphics.Capture.Direct3D11CaptureFramePool", framePoolFactoryId, factory))
                || FAILED(factory->CreateFreeThreaded(graphicsDevice.Get(), BackdropTextureNode::format,
                          bufferCount, size, m_pool.GetAddressOf()))
                || FAILED(m_pool->CreateCaptureSession(item.Get(), m_session.GetAddressOf())))
            return false;
        if (SUCCEEDED(query(m_session.Get(), sessionCursorId, cursor)))
            cursor->put_IsCursorCaptureEnabled(false);
        applyBorder(borderless);
        return SUCCEEDED(m_session->StartCapture());
    }

    void applyBorder(bool borderless)
    {
        if (m_borderless == borderless)
            return;
        m_borderless = borderless;
        ComPtr<SessionBorder> border;
        m_borderError = FAILED(query(m_session.Get(), sessionBorderId, border))
            || FAILED(border->put_IsBorderRequired(!borderless));
    }

    std::shared_ptr<CaptureLease> mapFrame(ComPtr<Frame> frame)
    {
        Size size{};
        ComPtr<ID3D11Texture2D> source;
        if (FAILED(frame->get_ContentSize(&size)) || QSize(size.width, size.height) != m_bounds.size()
                || !frameTexture(frame.Get(), source))
            return {};

        return std::make_shared<CaptureLease>(CaptureLease{std::move(frame), std::move(source), {}});
    }

    CapturedFrame sampleReadback(const QRect &crop, bool updated, bool needsFrame)
    {
        m_readDirty |= updated;
        QImage image;
        if (m_readPending) {
            D3D11_MAPPED_SUBRESOURCE mapped{};
            const HRESULT hr = m_readContext->Map(m_staging.Get(), 0, D3D11_MAP_READ, D3D11_MAP_FLAG_DO_NOT_WAIT, &mapped);
            if (hr == DXGI_ERROR_WAS_STILL_DRAWING)
                return {needsFrame ? CaptureStatus::Starting : CaptureStatus::Ready, {}, m_borderError};
            if (FAILED(hr))
                return failed();

            if (m_readCrop == crop) {
                image = QImage(crop.size(), QImage::Format_RGB32);
                if (!image.isNull()) {
                    const auto *pixels = static_cast<const uchar *>(mapped.pData);
                    for (int y = 0; y < image.height(); ++y) {
                        auto *row = reinterpret_cast<QRgb *>(image.scanLine(y));
                        std::memcpy(row, pixels + size_t(y) * mapped.RowPitch, size_t(image.width()) * sizeof(QRgb));
                        for (int x = 0; x < image.width(); ++x)
                            row[x] |= 0xff000000;
                    }
                }
            }
            m_readContext->Unmap(m_staging.Get(), 0);
            m_readPending = false;
        }

        if (m_readDirty || m_readCrop != crop || (needsFrame && image.isNull())) {
            if (!m_staging || m_readCrop.size() != crop.size()) {
                D3D11_TEXTURE2D_DESC desc{};
                desc.Width = UINT(crop.width());
                desc.Height = UINT(crop.height());
                desc.MipLevels = desc.ArraySize = desc.SampleDesc.Count = 1;
                desc.Format = BackdropTextureNode::format;
                desc.Usage = D3D11_USAGE_STAGING;
                desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
                if (FAILED(m_device->CreateTexture2D(&desc, nullptr, m_staging.ReleaseAndGetAddressOf())))
                    return failed();
            }
            const D3D11_BOX box{UINT(crop.left()), UINT(crop.top()), 0,
                               UINT(crop.right() + 1), UINT(crop.bottom() + 1), 1};
            m_readContext->CopySubresourceRegion(m_staging.Get(), 0, 0, 0, 0, m_frame->texture.Get(), 0, &box);
            m_readContext->Flush();
            m_readCrop = crop;
            m_readPending = true;
            m_readDirty = false;
        }
        if (image.isNull())
            return {needsFrame ? CaptureStatus::Starting : CaptureStatus::Ready, {}, m_borderError};
        auto frame = std::make_shared<CaptureLease>();
        frame->image = std::move(image);
        return {CaptureStatus::Ready, std::move(frame), m_borderError};
    }

    CapturedFrame failed()
    {
        close();
        return {CaptureStatus::Unavailable, {}};
    }

    void close()
    {
        m_frame.reset();
        releaseCapture(m_session);
        releaseCapture(m_pool);
        m_staging.Reset();
        m_readContext.Reset();
        m_device.Reset();
        m_lastCrop = {};
        m_readCrop = {};
        m_readPending = false;
        m_readDirty = false;
        m_borderless = false;
        m_borderError = false;
    }

    bool m_initialized = false;
    HMONITOR m_monitor = nullptr;
    QRect m_bounds;
    QRect m_lastCrop;
    QRect m_readCrop;
    bool m_readPending = false;
    bool m_readDirty = false;
    bool m_borderless = false;
    bool m_borderError = false;
    QElapsedTimer m_started;
    ComPtr<ID3D11Device> m_renderDevice;
    ComPtr<ID3D11Device> m_device;
    ComPtr<ID3D11DeviceContext> m_readContext;
    ComPtr<ID3D11Texture2D> m_staging;
    ComPtr<FramePool> m_pool;
    ComPtr<Session> m_session;
    std::shared_ptr<CaptureLease> m_frame;
};

} // namespace

struct MonitorBackdrop::Capture
{
    Capture()
    {
        worker->moveToThread(&thread);
        QObject::connect(&thread, &QThread::finished, worker, &QObject::deleteLater);
        thread.start();
    }

    ~Capture()
    {
        frame.reset();
        thread.quit();
        thread.wait();
        restoreAffinity();
    }

    bool exclude(HWND window)
    {
        if (excluded == window)
            return true;
        DWORD previous = WDA_NONE;
        GetWindowDisplayAffinity(window, &previous);
        if (!SetWindowDisplayAffinity(window, WDA_EXCLUDEFROMCAPTURE))
            return false;
        excluded = window;
        affinity = previous;
        return true;
    }

    void restoreAffinity()
    {
        if (excluded && IsWindow(excluded))
            SetWindowDisplayAffinity(excluded, affinity);
        excluded = nullptr;
    }

    QThread thread;
    CaptureWorker *const worker = new CaptureWorker;
    ComPtr<ID3D11Device> device;
    std::shared_ptr<CaptureLease> frame;
    QRect crop;
    QRectF frameSceneRect;
    quint64 sequence = 0;
    HWND excluded = nullptr;
    DWORD affinity = WDA_NONE;
    QRect monitorBounds;
    HMONITOR monitor = nullptr;
    QPoint origin;
    qreal scale = 0;
    QElapsedTimer retry;
    QElapsedTimer rateInterval;
    int frames = 0;
    quint64 generation = 0;
    bool busy = false;
    bool closing = false;
};

struct MonitorBackdrop::BorderRequest
{
    const HRESULT apartment = RoInitialize(RO_INIT_SINGLETHREADED);
    ComPtr<AccessOperation> operation;
    ComPtr<IAsyncInfo> info;

    ~BorderRequest()
    {
        if (info)
            info->Cancel();
        info.Reset();
        operation.Reset();
        if (SUCCEEDED(apartment))
            RoUninitialize();
    }
};
#endif

MonitorBackdrop::MonitorBackdrop(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents);
    setClip(true);
    m_poll.setTimerType(Qt::PreciseTimer);
    m_poll.setInterval(16);
    connect(&m_poll, &QTimer::timeout, this, &MonitorBackdrop::poll);
    m_borderPoll.setInterval(100);
    connect(&m_borderPoll, &QTimer::timeout, this, &MonitorBackdrop::pollBorderRequest);
}

MonitorBackdrop::~MonitorBackdrop()
{
    m_poll.stop();
    m_borderPoll.stop();
#ifdef Q_OS_WIN
    // Join before QObject teardown. A worker reply may still be queued here.
    m_capture.reset();
#endif
}

bool MonitorBackdrop::hasFrame() const
{
#ifdef Q_OS_WIN
    return m_capture && m_capture->frame;
#else
    return false;
#endif
}

void MonitorBackdrop::setBorderless(bool borderless)
{
    if (m_borderless == borderless)
        return;
    m_borderless = borderless;
    m_borderStatus.clear();
    emit borderStatusChanged();
}

bool MonitorBackdrop::requestingBorderless() const
{
#ifdef Q_OS_WIN
    return bool(m_borderRequest);
#else
    return false;
#endif
}

void MonitorBackdrop::requestBorderless()
{
#ifdef Q_OS_WIN
    if (m_borderRequest)
        return;
    auto request = std::make_unique<BorderRequest>();
    ComPtr<AccessFactory> factory;
    if ((SUCCEEDED(request->apartment) || request->apartment == RPC_E_CHANGED_MODE)
            && SUCCEEDED(activationFactory(L"Windows.Graphics.Capture.GraphicsCaptureAccess", accessFactoryId, factory))
            && SUCCEEDED(factory->RequestAccessAsync(AccessKind::Borderless, request->operation.GetAddressOf()))
            && SUCCEEDED(request->operation.As(&request->info))) {
        m_borderRequest = std::move(request);
        m_borderStatus = QStringLiteral("Ожидаем разрешение Windows…");
        m_borderPoll.start();
        pollBorderRequest();
    } else {
        m_borderStatus = QStringLiteral("Windows оставила рамку захвата. Запрос разрешения недоступен.");
    }
    emit borderStatusChanged();
#endif
}

void MonitorBackdrop::pollBorderRequest()
{
#ifdef Q_OS_WIN
    AsyncStatus state = AsyncStatus::Error;
    if (SUCCEEDED(m_borderRequest->info->get_Status(&state)) && state == AsyncStatus::Started)
        return;
    AccessStatus access{};
    const bool allowed = state == AsyncStatus::Completed
        && SUCCEEDED(m_borderRequest->operation->GetResults(&access)) && access == AccessStatus::Allowed;
    m_borderPoll.stop();
    m_borderRequest.reset();
    if (allowed)
        emit borderlessGranted();
    m_borderStatus = allowed ? QString{}
        : QStringLiteral("Рамка остаётся. Windows не разрешила захват без границы.");
    emit borderStatusChanged();
#endif
}

void MonitorBackdrop::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
    if (active) {
        setStatus(QStringLiteral("Подключаемся к захвату рабочего стола…"));
        m_poll.start();
        poll();
    } else {
        m_poll.stop();
        suspend();
#ifdef Q_OS_WIN
        if (m_capture)
            m_capture->retry.invalidate();
#endif
        setStatus({});
    }
    emit activeChanged();
}

void MonitorBackdrop::setStatus(const QString &status)
{
    if (m_status != status) {
        m_status = status;
        emit statusChanged();
    }
}

void MonitorBackdrop::clearFrame()
{
#ifdef Q_OS_WIN
    if (hasFrame()) {
        m_capture->frame.reset();
        m_capture->rateInterval.invalidate();
        m_capture->frames = 0;
        emit hasFrameChanged();
        update();
    }
#endif
}

void MonitorBackdrop::suspend()
{
    clearFrame();
#ifdef Q_OS_WIN
    if (!m_capture || !m_capture->excluded || m_capture->closing)
        return;
    ++m_capture->generation;
    m_capture->closing = true;
    auto *worker = m_capture->worker;
    QMetaObject::invokeMethod(worker, [this, worker] {
        worker->stop();
        QMetaObject::invokeMethod(this, [this] {
            m_capture->restoreAffinity();
            m_capture->closing = false;
        }, Qt::QueuedConnection);
    }, Qt::QueuedConnection);
#endif
}

void MonitorBackdrop::poll()
{
    static const QString unavailable = QStringLiteral("Захват рабочего стола недоступен. Используется обычное стекло.");
#ifdef Q_OS_WIN
    auto *view = window();
    if (!view || !view->isExposed() || !view->handle() || boundingRect().isEmpty()) {
        suspend();
        return;
    }
    const auto hwnd = reinterpret_cast<HWND>(view->winId());
    const HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONULL);
    MONITORINFO info{};
    info.cbSize = sizeof(info);
    POINT nativeOrigin{};
    if (!monitor || !GetMonitorInfoW(monitor, &info) || !ClientToScreen(hwnd, &nativeOrigin)) {
        suspend();
        setStatus(unavailable);
        return;
    }
    const auto &rect = info.rcMonitor;
    const QRect bounds(rect.left, rect.top, rect.right - rect.left, rect.bottom - rect.top);
    const QPoint origin(nativeOrigin.x, nativeOrigin.y);
    const qreal scale = view->devicePixelRatio();
    const QRect area = BackdropGeometry::captureRect(mapRectToScene(boundingRect()), origin, scale, bounds);
    if (area.isEmpty()) {
        suspend();
        return;
    }

    if (!m_capture)
        m_capture = std::make_unique<Capture>();
    auto &capture = *m_capture;
    if (!capture.device) {
        update();
        return;
    }
    if (capture.excluded && capture.excluded != hwnd)
        suspend();
    if (capture.monitor != monitor || capture.monitorBounds != bounds || capture.origin != origin || capture.scale != scale) {
        capture.monitor = monitor;
        capture.monitorBounds = bounds;
        capture.origin = origin;
        capture.scale = scale;
        capture.retry.invalidate();
        ++capture.generation;
        clearFrame();
    }
    if (capture.closing || capture.busy || (capture.retry.isValid() && capture.retry.elapsed() < retryDelay))
        return;
    if (!capture.exclude(hwnd)) {
        capture.retry.start();
        setStatus(unavailable);
        return;
    }

    capture.busy = true;
    const auto position = BackdropGeometry::sceneRect(area, origin, scale);
    const auto crop = area.translated(-bounds.topLeft());
    auto *worker = capture.worker;
    QMetaObject::invokeMethod(worker, [this, worker, monitor, bounds, crop, position,
                                      generation = capture.generation, needsFrame = !hasFrame(),
                                      device = capture.device, borderless = m_borderless] {
        auto frame = worker->sample(device.Get(), monitor, bounds, crop, needsFrame, borderless);
        QMetaObject::invokeMethod(this, [this, generation, crop, position, frame = std::move(frame)]() mutable {
            auto &capture = *m_capture;
            capture.busy = false;
            if (generation != capture.generation)
                return;
            if (frame.status == CaptureStatus::Unavailable) {
                capture.restoreAffinity();
                capture.retry.start();
                clearFrame();
                setStatus(unavailable);
            } else if (frame.status == CaptureStatus::Starting) {
                setStatus(QStringLiteral("Получаем изображение рабочего стола…"));
            } else {
                if (frame.lease) {
                    const bool hadFrame = hasFrame();
                    capture.frame = std::move(frame.lease);
                    capture.crop = crop;
                    capture.frameSceneRect = position;
                    ++capture.sequence;
                    ++capture.frames;
                    if (!hadFrame) {
                        capture.rateInterval.start();
                        setStatus(QStringLiteral("Захват фона активен."));
                        emit hasFrameChanged();
                    }
                    update();
                }
                const auto elapsed = capture.rateInterval.isValid() ? capture.rateInterval.elapsed() : 0;
                if (elapsed >= 1000) {
                    const int fps = qRound(capture.frames * 1000.0 / elapsed);
                    capture.rateInterval.restart();
                    capture.frames = 0;
                    QString status = QStringLiteral("Захват фона · %1 кадр/с.").arg(fps);
                    if (frame.borderError && m_borderless)
                        status += QStringLiteral(" Windows оставила рамку захвата.");
                    setStatus(status);
                }
            }
        }, Qt::QueuedConnection);
    }, Qt::QueuedConnection);
#else
    setStatus(unavailable);
#endif
}

QSGNode *MonitorBackdrop::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
#ifdef Q_OS_WIN
    auto *view = window();
    if (m_active && m_capture && view && view->rendererInterface()->graphicsApi() == QSGRendererInterface::Direct3D11) {
        auto *renderer = view->rendererInterface();
        auto *device = static_cast<ID3D11Device *>(renderer->getResource(view, QSGRendererInterface::DeviceResource));
        if (device != m_capture->device.Get()) {
            QMetaObject::invokeMethod(this, [this, device = ComPtr<ID3D11Device>(device)] {
                m_capture->device = device;
                ++m_capture->generation;
                m_capture->retry.invalidate();
                clearFrame();
            }, Qt::QueuedConnection);
        } else if (device && hasFrame()) {
            auto *context = static_cast<ID3D11DeviceContext *>(renderer->getResource(
                view, QSGRendererInterface::DeviceContextResource));
            auto *node = oldNode ? static_cast<BackdropTextureNode *>(oldNode) : new BackdropTextureNode;
            const auto &frame = *m_capture->frame;
            const bool copied = frame.image.isNull()
                ? context && node->copyFrame(view, device, context, frame.texture.Get(), m_capture->crop, m_capture->sequence)
                : node->showImage(view, frame.image, m_capture->sequence);
            if (copied) {
                node->setRect(mapRectFromScene(m_capture->frameSceneRect));
                return node;
            }
            delete node;
            return nullptr;
        }
    }
#endif
    delete oldNode;
    return nullptr;
}
