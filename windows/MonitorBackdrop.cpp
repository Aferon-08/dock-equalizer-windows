#include "MonitorBackdrop.h"
#include "BackdropGeometry.h"

#include <QQuickWindow>
#include <QSGSimpleTextureNode>

#ifdef Q_OS_WIN
#include "WinCaptureAbi.h"

#include <QElapsedTimer>
#include <QThread>

#include <d3d11_4.h>
#include <roapi.h>
#include <winstring.h>
#include <wrl/client.h>

#include <cstring>
#include <utility>

extern "C" HRESULT WINAPI CreateDirect3D11DeviceFromDXGIDevice(IDXGIDevice *, IInspectable **);

namespace {

using Microsoft::WRL::ComPtr;
using namespace wincapture;

constexpr int bufferCount = 2;
constexpr int retryDelay = 2000;
constexpr auto pixelFormat = DXGI_FORMAT_B8G8R8A8_UNORM;

enum class CaptureStatus { Starting, Ready, Unavailable };

struct CapturedFrame
{
    CaptureStatus status;
    QImage image;
};

template<class Interface>
HRESULT query(IUnknown *object, REFIID id, ComPtr<Interface> &result)
{
    return object->QueryInterface(id, reinterpret_cast<void **>(result.ReleaseAndGetAddressOf()));
}

template<class Interface, size_t N>
HRESULT activationFactory(const wchar_t (&name)[N], REFIID id, ComPtr<Interface> &result)
{
    HSTRING_HEADER header{};
    HSTRING value = nullptr;
    const HRESULT hr = WindowsCreateStringReference(name, N - 1, &header, &value);
    return FAILED(hr) ? hr
        : RoGetActivationFactory(value, id, reinterpret_cast<void **>(result.GetAddressOf()));
}

template<class Interface>
void releaseCapture(ComPtr<Interface> &object)
{
    ComPtr<Closable> closable;
    if (object && SUCCEEDED(query(object.Get(), closableId, closable)))
        closable->Close();
    object.Reset();
}

// Owned by the worker thread. It reads only the region the lens can sample.
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
    }

    CapturedFrame sample(HMONITOR monitor, const QRect &bounds, const QRect &crop, bool needsImage)
    {
        if (m_monitor != monitor || m_bounds != bounds) {
            stop();
            m_monitor = monitor;
            m_bounds = bounds;
        }
        if (!m_pool) {
            if (!open())
                return failed();
            m_started.start();
        }

        // Retain one checked-out frame so we can recrop a static desktop when
        // the dock changes shape. The other pool buffer can still receive frames.
        bool updated = false;
        for (int i = 0; i < bufferCount; ++i) {
            ComPtr<Frame> next;
            if (FAILED(m_pool->TryGetNextFrame(next.GetAddressOf())))
                return failed();
            if (!next)
                break;
            releaseCapture(m_frame);
            m_frame = std::move(next);
            updated = true;
        }
        if (!m_frame) {
            if (m_started.elapsed() > retryDelay)
                return failed();
            return {CaptureStatus::Starting, {}};
        }
        if (!updated && crop == m_lastCrop && !needsImage)
            return {CaptureStatus::Ready, {}};

        QImage image = copyRegion(crop);
        if (image.isNull())
            return failed();
        m_lastCrop = crop;
        return {CaptureStatus::Ready, std::move(image)};
    }

private:
    bool open()
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

        if (FAILED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
                D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
                m_device.GetAddressOf(), nullptr, m_context.GetAddressOf())))
            return false;
        ComPtr<ID3D11Multithread> guard;
        if (FAILED(m_context.As(&guard)))
            return false;
        guard->SetMultithreadProtected(TRUE);

        ComPtr<IDXGIDevice> dxgi;
        ComPtr<IInspectable> wrapper;
        ComPtr<IInspectable> graphicsDevice;
        if (FAILED(m_device.As(&dxgi))
                || FAILED(CreateDirect3D11DeviceFromDXGIDevice(dxgi.Get(), wrapper.GetAddressOf()))
                || FAILED(query(wrapper.Get(), direct3dDeviceId, graphicsDevice)))
            return false;

        ComPtr<FramePoolFactory> factory;
        ComPtr<SessionCursor> cursor;
        return SUCCEEDED(activationFactory(L"Windows.Graphics.Capture.Direct3D11CaptureFramePool",
                        framePoolFactoryId, factory))
            && SUCCEEDED(factory->CreateFreeThreaded(graphicsDevice.Get(), pixelFormat,
                         bufferCount, size, m_pool.GetAddressOf()))
            && SUCCEEDED(m_pool->CreateCaptureSession(item.Get(), m_session.GetAddressOf()))
            && SUCCEEDED(query(m_session.Get(), sessionCursorId, cursor))
            && SUCCEEDED(cursor->put_IsCursorCaptureEnabled(false)) && SUCCEEDED(m_session->StartCapture());
    }

    QImage copyRegion(const QRect &crop)
    {
        Size size{};
        ComPtr<IInspectable> surface;
        ComPtr<SurfaceAccess> access;
        ComPtr<ID3D11Texture2D> source;
        if (FAILED(m_frame->get_ContentSize(&size)) || QSize(size.width, size.height) != m_bounds.size()
                || FAILED(m_frame->get_Surface(surface.GetAddressOf()))
                || FAILED(query(surface.Get(), surfaceAccessId, access))
                || FAILED(access->GetInterface(__uuidof(ID3D11Texture2D),
                          reinterpret_cast<void **>(source.GetAddressOf()))))
            return {};

        if (m_readSize != crop.size()) {
            D3D11_TEXTURE2D_DESC description{};
            description.Width = UINT(crop.width());
            description.Height = UINT(crop.height());
            description.MipLevels = description.ArraySize = description.SampleDesc.Count = 1;
            description.Format = pixelFormat;
            description.Usage = D3D11_USAGE_STAGING;
            description.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
            if (FAILED(m_device->CreateTexture2D(&description, nullptr, m_readback.ReleaseAndGetAddressOf())))
                return {};
            m_readSize = crop.size();
        }

        const D3D11_BOX box{UINT(crop.left()), UINT(crop.top()), 0,
                           UINT(crop.right() + 1), UINT(crop.bottom() + 1), 1};
        m_context->CopySubresourceRegion(m_readback.Get(), 0, 0, 0, 0, source.Get(), 0, &box);
        QImage image(crop.size(), QImage::Format_RGB32);
        D3D11_MAPPED_SUBRESOURCE mapped{};
        if (image.isNull() || FAILED(m_context->Map(m_readback.Get(), 0, D3D11_MAP_READ, 0, &mapped)))
            return {};
        const auto *pixels = static_cast<const uchar *>(mapped.pData);
        for (int y = 0; y < image.height(); ++y) {
            auto *row = reinterpret_cast<QRgb *>(image.scanLine(y));
            std::memcpy(row, pixels + size_t(y) * mapped.RowPitch, size_t(image.width()) * sizeof(QRgb));
            for (int x = 0; x < image.width(); ++x)
                row[x] |= 0xff000000;
        }
        m_context->Unmap(m_readback.Get(), 0);
        return image;
    }

    CapturedFrame failed()
    {
        close();
        return {CaptureStatus::Unavailable, {}};
    }

    void close()
    {
        releaseCapture(m_session);
        releaseCapture(m_frame);
        releaseCapture(m_pool);
        m_readback.Reset();
        m_context.Reset();
        m_device.Reset();
        m_readSize = {};
        m_lastCrop = {};
    }

    bool m_initialized = false;
    HMONITOR m_monitor = nullptr;
    QRect m_bounds;
    QRect m_lastCrop;
    QSize m_readSize;
    QElapsedTimer m_started;
    ComPtr<ID3D11Device> m_device;
    ComPtr<ID3D11DeviceContext> m_context;
    ComPtr<FramePool> m_pool;
    ComPtr<Session> m_session;
    ComPtr<Frame> m_frame;
    ComPtr<ID3D11Texture2D> m_readback;
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
    HWND excluded = nullptr;
    DWORD affinity = WDA_NONE;
    QRect monitorBounds;
    HMONITOR monitor = nullptr;
    QPoint origin;
    qreal scale = 0;
    QElapsedTimer retry;
    quint64 generation = 0;
    bool busy = false;
    bool closing = false;
};
#endif

MonitorBackdrop::MonitorBackdrop(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents);
    setClip(true);
    m_poll.setInterval(67);
    connect(&m_poll, &QTimer::timeout, this, &MonitorBackdrop::poll);
}

MonitorBackdrop::~MonitorBackdrop()
{
    m_poll.stop();
#ifdef Q_OS_WIN
    // Join before QObject teardown. A worker reply may still be queued here.
    m_capture.reset();
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
    if (!m_frame.isNull()) {
        m_frame = {};
        emit hasFrameChanged();
        update();
    }
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
                                      generation = capture.generation, needsImage = m_frame.isNull()] {
        auto frame = worker->sample(monitor, bounds, crop, needsImage);
        QMetaObject::invokeMethod(this, [this, generation, position, frame = std::move(frame)]() mutable {
            m_capture->busy = false;
            if (generation != m_capture->generation)
                return;
            if (frame.status == CaptureStatus::Unavailable) {
                m_capture->restoreAffinity();
                m_capture->retry.start();
                clearFrame();
                setStatus(unavailable);
            } else if (frame.status == CaptureStatus::Starting) {
                setStatus(QStringLiteral("Получаем изображение рабочего стола…"));
            } else {
                const bool hadFrame = hasFrame();
                if (!frame.image.isNull())
                    m_frame = std::move(frame.image);
                m_frameSceneRect = position;
                if (!hadFrame && hasFrame())
                    emit hasFrameChanged();
                setStatus(QStringLiteral("Фон рабочего стола используется для преломления."));
                update();
            }
        }, Qt::QueuedConnection);
    }, Qt::QueuedConnection);
#else
    setStatus(unavailable);
#endif
}

QSGNode *MonitorBackdrop::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
    class FrameNode : public QSGSimpleTextureNode
    {
    public:
        qint64 imageKey = 0;
    };

    auto *node = static_cast<FrameNode *>(oldNode);
    if (m_frame.isNull()) {
        delete node;
        return nullptr;
    }
    if (!node)
        node = new FrameNode;
    if (node->imageKey != m_frame.cacheKey()) {
        auto *texture = window()->createTextureFromImage(m_frame, QQuickWindow::TextureIsOpaque);
        if (!texture) {
            delete node;
            return nullptr;
        }
        node->setOwnsTexture(true);
        node->setTexture(texture);
        node->setFiltering(QSGTexture::Linear);
        node->imageKey = m_frame.cacheKey();
    }
    node->setRect(mapRectFromScene(m_frameSceneRect));
    return node;
}
