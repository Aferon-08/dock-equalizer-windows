#include "VoicePreview.h"

#include <QQuickWindow>
#include <QSGNode>

#ifdef Q_OS_WIN
#include "BackdropTextureNode.h"
#include "WinCaptureInterop.h"

#include <QElapsedTimer>
#include <QImage>
#include <QPointer>
#include <QThread>

#include <asyncinfo.h>
#include <shobjidl.h>

#include <atomic>
#include <iterator>
#include <utility>

namespace {

using namespace wincapture;

constexpr int bufferCount = 3;
constexpr int frameInterval = 33;
constexpr int readbackInterval = 66;
constexpr int idleInterval = 100;
constexpr int firstFrameTimeout = 4000;

QPointer<VoicePreview> previewOwner;

class SourceClosed final : public ItemClosedHandler
{
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID id, void **result) override
    {
        if (!result)
            return E_POINTER;
        *result = nullptr;
        if (IsEqualIID(id, __uuidof(IUnknown)) || IsEqualIID(id, __uuidof(IAgileObject))
                || IsEqualIID(id, itemClosedHandlerId)) {
            *result = static_cast<ItemClosedHandler *>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }

    ULONG STDMETHODCALLTYPE AddRef() override { return ++m_refs; }

    ULONG STDMETHODCALLTYPE Release() override
    {
        const auto refs = --m_refs;
        if (!refs)
            delete this;
        return refs;
    }

    HRESULT STDMETHODCALLTYPE Invoke(Item *, IInspectable *) override
    {
        m_closed = true;
        return S_OK;
    }

    bool closed() const { return m_closed.load(); }

private:
    std::atomic<ULONG> m_refs{1};
    std::atomic<bool> m_closed{false};
};

struct PreviewFrame
{
    QSize size;
    // Keep the pool frame checked out while the render thread copies its surface.
    ComPtr<Frame> lease;
    ComPtr<ID3D11Texture2D> texture;
    QImage image;
};

enum class SampleState { Waiting, Ready, Resized, Failed };

struct Sample
{
    SampleState state = SampleState::Waiting;
    std::shared_ptr<PreviewFrame> frame;
};

class PreviewWorker : public QObject
{
public:
    ~PreviewWorker() override
    {
        stop();
        if (m_initialized)
            RoUninitialize();
    }

    void stop()
    {
        releaseCapture(m_session);
        releaseCapture(m_pool);
        m_pendingReadback = false;
        m_staging.Reset();
        m_context.Reset();
        m_graphicsDevice.Reset();
        m_device.Reset();
        m_resize = {};
    }

    Sample sample(Item *source, ID3D11Device *renderDevice)
    {
        if (!m_pool && !start(source, renderDevice))
            return failed();
        if (m_resize.isValid()) {
            const Size size{m_resize.width(), m_resize.height()};
            if (FAILED(m_pool->Recreate(m_graphicsDevice.Get(), BackdropTextureNode::format, bufferCount, size)))
                return failed();
            m_size = std::exchange(m_resize, {});
            m_pendingReadback = false;
            m_staging.Reset();
        }

        ComPtr<Frame> newest;
        for (int i = 0; i < bufferCount; ++i) {
            ComPtr<Frame> next;
            if (FAILED(m_pool->TryGetNextFrame(next.GetAddressOf())))
                return failed();
            if (!next)
                break;
            newest = std::move(next);
        }
        if (!newest)
            return m_context ? readback(nullptr) : Sample{};

        Size size{};
        if (FAILED(newest->get_ContentSize(&size)))
            return failed();
        const QSize contentSize(size.width, size.height);
        if (contentSize.isEmpty())
            return {};
        if (contentSize != m_size) {
            // The next poll recreates the pool after the GUI releases its old frame.
            m_resize = contentSize;
            return {SampleState::Resized, {}};
        }
        ComPtr<ID3D11Texture2D> texture;
        if (!frameTexture(newest.Get(), texture))
            return failed();
        if (m_context)
            return readback(texture.Get());

        return {SampleState::Ready, std::make_shared<PreviewFrame>(
            PreviewFrame{contentSize, std::move(newest), std::move(texture), {}})};
    }

private:
    bool start(Item *source, ID3D11Device *renderDevice)
    {
        if (!m_initialized) {
            m_initialized = SUCCEEDED(RoInitialize(RO_INIT_MULTITHREADED));
            if (!m_initialized)
                return false;
        }
        if (renderDevice) {
            m_device = renderDevice;
            if (open(source))
                return true;
            stop();
        }

        return SUCCEEDED(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
                   D3D11_CREATE_DEVICE_BGRA_SUPPORT, nullptr, 0, D3D11_SDK_VERSION,
                   m_device.GetAddressOf(), nullptr, m_context.GetAddressOf())) && open(source);
    }

    bool open(Item *source)
    {
        Size size{};
        ComPtr<FramePoolFactory> factory;
        if (FAILED(source->get_Size(&size)) || size.width <= 0 || size.height <= 0
                || !wrapCaptureDevice(m_device.Get(), m_graphicsDevice)
                || FAILED(activationFactory(L"Windows.Graphics.Capture.Direct3D11CaptureFramePool", framePoolFactoryId, factory))
                || FAILED(factory->CreateFreeThreaded(m_graphicsDevice.Get(), BackdropTextureNode::format,
                              bufferCount, size, m_pool.GetAddressOf()))
                || FAILED(m_pool->CreateCaptureSession(source, m_session.GetAddressOf()))
                || FAILED(m_session->StartCapture())) {
            return false;
        }
        m_size = QSize(size.width, size.height);
        return true;
    }

    Sample failed()
    {
        stop();
        return {SampleState::Failed, {}};
    }

    Sample readback(ID3D11Texture2D *texture)
    {
        QImage image;
        if (m_pendingReadback) {
            D3D11_MAPPED_SUBRESOURCE mapped{};
            const HRESULT hr = m_context->Map(m_staging.Get(), 0, D3D11_MAP_READ, D3D11_MAP_FLAG_DO_NOT_WAIT, &mapped);
            if (hr == DXGI_ERROR_WAS_STILL_DRAWING)
                return {};
            if (FAILED(hr))
                return failed();

            const QImage pixels(static_cast<const uchar *>(mapped.pData), m_size.width(), m_size.height(),
                                mapped.RowPitch, QImage::Format_RGB32);
            const QSize previewSize = m_size.scaled(QSize(960, 960), Qt::KeepAspectRatio)
                .expandedTo(QSize(1, 1)).boundedTo(m_size);
            image = previewSize == m_size ? pixels.copy()
                : pixels.scaled(previewSize, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
            m_context->Unmap(m_staging.Get(), 0);
            m_pendingReadback = false;
            for (int y = 0; y < image.height(); ++y) {
                auto *row = reinterpret_cast<QRgb *>(image.scanLine(y));
                for (int x = 0; x < image.width(); ++x)
                    row[x] |= 0xff000000;
            }
        }

        if (texture) {
            if (!m_staging) {
                D3D11_TEXTURE2D_DESC desc{};
                desc.Width = UINT(m_size.width());
                desc.Height = UINT(m_size.height());
                desc.MipLevels = desc.ArraySize = desc.SampleDesc.Count = 1;
                desc.Format = BackdropTextureNode::format;
                desc.Usage = D3D11_USAGE_STAGING;
                desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
                if (FAILED(m_device->CreateTexture2D(&desc, nullptr, m_staging.GetAddressOf())))
                    return failed();
            }
            const D3D11_BOX box{0, 0, 0, UINT(m_size.width()), UINT(m_size.height()), 1};
            m_context->CopySubresourceRegion(m_staging.Get(), 0, 0, 0, 0, texture, 0, &box);
            m_context->Flush();
            m_pendingReadback = true;
        }
        if (image.isNull())
            return {};

        return {SampleState::Ready, std::make_shared<PreviewFrame>(PreviewFrame{m_size, {}, {}, std::move(image)})};
    }

    bool m_initialized = false;
    bool m_pendingReadback = false;
    QSize m_size;
    QSize m_resize;
    ComPtr<ID3D11Device> m_device;
    ComPtr<ID3D11DeviceContext> m_context;
    ComPtr<IInspectable> m_graphicsDevice;
    ComPtr<FramePool> m_pool;
    ComPtr<Session> m_session;
    ComPtr<ID3D11Texture2D> m_staging;
};

} // namespace

struct VoicePreview::Capture
{
    struct Apartment
    {
        const HRESULT result = RoInitialize(RO_INIT_SINGLETHREADED);

        ~Apartment()
        {
            if (SUCCEEDED(result))
                RoUninitialize();
        }
    } apartment;

    // Destroy any queued frame leases before uninitializing WinRT on this thread.
    QObject replies;

    ~Capture()
    {
        cancelPicker();
        releaseSource();
        frame.reset();
        thread.quit();
        thread.wait();
    }

    bool pick(HWND owner)
    {
        if (FAILED(apartment.result) && apartment.result != RPC_E_CHANGED_MODE)
            return false;

        ComPtr<SessionStatics> statics;
        boolean supported = false;
        if (FAILED(activationFactory(L"Windows.Graphics.Capture.GraphicsCaptureSession", sessionStaticsId, statics))
                || FAILED(statics->IsSupported(&supported)) || !supported) {
            return false;
        }

        constexpr wchar_t name[] = L"Windows.Graphics.Capture.GraphicsCapturePicker";
        HSTRING_HEADER header{};
        HSTRING value = nullptr;
        ComPtr<IInspectable> instance;
        ComPtr<IInitializeWithWindow> initialize;
        return SUCCEEDED(WindowsCreateStringReference(name, std::size(name) - 1, &header, &value))
            && SUCCEEDED(RoActivateInstance(value, instance.GetAddressOf()))
            && SUCCEEDED(instance.As(&initialize))
            && SUCCEEDED(initialize->Initialize(owner))
            && SUCCEEDED(query(instance.Get(), pickerId, picker))
            && SUCCEEDED(picker->PickSingleItemAsync(operation.GetAddressOf())) && operation
            && SUCCEEDED(operation.As(&async));
    }

    void cancelPicker()
    {
        if (async)
            async->Cancel();
        finishPicker();
    }

    void finishPicker()
    {
        async.Reset();
        operation.Reset();
        picker.Reset();
    }

    bool selectSource(ComPtr<Item> item)
    {
        ComPtr<SourceClosed> handler;
        handler.Attach(new SourceClosed);
        if (FAILED(item->add_Closed(handler.Get(), &closedToken)))
            return false;
        source = std::move(item);
        sourceClosed = std::move(handler);
        return true;
    }

    void releaseSource()
    {
        if (source)
            source->remove_Closed(closedToken);
        sourceClosed.Reset();
        source.Reset();
    }

    void startWorker()
    {
        if (worker)
            return;
        worker = new PreviewWorker;
        worker->moveToThread(&thread);
        QObject::connect(&thread, &QThread::finished, worker, &QObject::deleteLater);
        thread.start();
    }

    ComPtr<Picker> picker;
    ComPtr<PickerOperation> operation;
    ComPtr<IAsyncInfo> async;
    ComPtr<Item> source;
    ComPtr<SourceClosed> sourceClosed;
    EventRegistrationToken closedToken{};
    QThread thread;
    PreviewWorker *worker = nullptr;
    ComPtr<ID3D11Device> renderDevice;
    std::shared_ptr<PreviewFrame> frame;
    QElapsedTimer waiting;
    quint64 generation = 0;
    quint64 sequence = 0;
    bool running = false;
    bool busy = false;
    bool forceReadback = false;
};
#endif

VoicePreview::VoicePreview(QQuickItem *parent)
    : QQuickItem(parent)
{
    setFlag(ItemHasContents);
#ifdef Q_OS_WIN
    m_poll.setInterval(idleInterval);
    connect(&m_poll, &QTimer::timeout, this, &VoicePreview::poll);
#endif
}

VoicePreview::~VoicePreview()
{
#ifdef Q_OS_WIN
    m_poll.stop();
    if (previewOwner == this)
        previewOwner.clear();
    m_capture.reset();
#endif
}

bool VoicePreview::available() const
{
#ifdef Q_OS_WIN
    return true;
#else
    return false;
#endif
}

bool VoicePreview::hasFrame() const
{
#ifdef Q_OS_WIN
    return m_capture && m_capture->frame;
#else
    return false;
#endif
}

bool VoicePreview::selecting() const
{
#ifdef Q_OS_WIN
    return m_capture && m_capture->async;
#else
    return false;
#endif
}

void VoicePreview::setActive(bool active)
{
    if (m_active == active)
        return;
    m_active = active;
#ifdef Q_OS_WIN
    if (!active)
        suspend();
#endif
    emit activeChanged();
}

void VoicePreview::chooseSource()
{
#ifdef Q_OS_WIN
    auto *view = window();
    if (!m_active || selecting() || !view || !view->isExposed())
        return;

    if (previewOwner && previewOwner != this)
        previewOwner->closePreview();
    previewOwner = this;
    if (!m_capture)
        m_capture = std::make_unique<Capture>();
    suspend();
    m_capture->releaseSource();

    if (!std::exchange(m_opened, true))
        emit openedChanged();
    if (!m_capture->pick(reinterpret_cast<HWND>(view->winId()))) {
        m_capture->cancelPicker();
        failSource(tr("Выбор источника Windows недоступен."));
        return;
    }
    setStatus(tr("Выберите окно или экран в Windows…"));
    emit selectingChanged();
    m_poll.start(idleInterval);
#endif
}

void VoicePreview::closePreview()
{
#ifdef Q_OS_WIN
    if (!m_opened)
        return;
    if (previewOwner == this)
        previewOwner.clear();
    m_poll.stop();
    if (selecting()) {
        m_capture->cancelPicker();
        emit selectingChanged();
    }
    suspend();
    m_capture->releaseSource();
    m_capture->renderDevice.Reset();
    m_capture->forceReadback = false;
    m_opened = false;
    setStatus({});
    emit openedChanged();
#endif
}

#ifdef Q_OS_WIN
void VoicePreview::itemChange(ItemChange change, const ItemChangeData &value)
{
    if (change == ItemSceneChange)
        closePreview();
    else if (change == ItemVisibleHasChanged && !value.boolValue)
        suspend();
    QQuickItem::itemChange(change, value);
}

void VoicePreview::setStatus(const QString &status, bool retryable)
{
    if (m_status == status && m_retryable == retryable)
        return;
    m_status = status;
    m_retryable = retryable;
    emit statusChanged();
}

void VoicePreview::clearFrame()
{
    if (!hasFrame())
        return;
    m_capture->frame.reset();
    emit hasFrameChanged();
    update();
}

void VoicePreview::suspend()
{
    if (!m_capture || !m_capture->running)
        return;
    auto &capture = *m_capture;
    capture.running = false;
    ++capture.generation;
    clearFrame();
    QMetaObject::invokeMethod(capture.worker, [worker = capture.worker] { worker->stop(); }, Qt::QueuedConnection);
}

void VoicePreview::failSource(const QString &status)
{
    m_poll.stop();
    suspend();
    m_capture->releaseSource();
    setStatus(status, true);
}

void VoicePreview::poll()
{
    auto &capture = *m_capture;
    if (selecting()) {
        AsyncStatus state = AsyncStatus::Error;
        if (SUCCEEDED(capture.async->get_Status(&state)) && state == AsyncStatus::Started)
            return;

        ComPtr<Item> source;
        const auto result = state == AsyncStatus::Completed ? capture.operation->GetResults(source.GetAddressOf()) : E_FAIL;
        capture.finishPicker();
        emit selectingChanged();
        if (state == AsyncStatus::Canceled || (SUCCEEDED(result) && !source)) {
            failSource(tr("Источник не выбран."));
            return;
        }
        if (FAILED(result) || !capture.selectSource(std::move(source))) {
            failSource(tr("Источник недоступен."));
            return;
        }
    }

    if (!capture.source)
        return;
    if (capture.sourceClosed->closed()) {
        failSource(tr("Источник закрыт."));
        return;
    }

    auto *view = window();
    if (!m_active || !isVisible() || !view || !view->isExposed() || boundingRect().isEmpty()) {
        suspend();
        setStatus(tr("Превью приостановлено."));
        if (m_poll.interval() != idleInterval)
            m_poll.setInterval(idleInterval);
        return;
    }

    const bool nativeRenderer = view->rendererInterface()->graphicsApi() == QSGRendererInterface::Direct3D11;
    if (nativeRenderer && !capture.renderDevice) {
        setStatus(tr("Получаем изображение…"));
        update();
        return;
    }
    if (capture.busy)
        return;
    if (!capture.running) {
        capture.startWorker();
        capture.running = true;
        capture.waiting.start();
        setStatus(tr("Получаем изображение…"));
    } else if (!hasFrame() && capture.waiting.hasExpired(firstFrameTimeout)) {
        failSource(tr("Источник недоступен."));
        return;
    }

    const bool useNative = nativeRenderer && !capture.forceReadback;
    const int interval = useNative ? frameInterval : readbackInterval;
    if (m_poll.interval() != interval)
        m_poll.setInterval(interval);
    capture.busy = true;
    QMetaObject::invokeMethod(capture.worker, [this, worker = capture.worker, source = capture.source,
                              replies = &capture.replies,
                              device = useNative ? capture.renderDevice : ComPtr<ID3D11Device>{},
                              generation = capture.generation] {
        auto sample = worker->sample(source.Get(), device.Get());
        QMetaObject::invokeMethod(replies, [this, generation, sample = std::move(sample)]() mutable {
            auto &capture = *m_capture;
            capture.busy = false;
            if (capture.generation != generation)
                return;
            switch (sample.state) {
            case SampleState::Failed:
                failSource(capture.sourceClosed->closed() ? tr("Источник закрыт.") : tr("Источник недоступен."));
                break;
            case SampleState::Resized:
                clearFrame();
                capture.waiting.restart();
                setStatus(tr("Получаем изображение…"));
                break;
            case SampleState::Ready: {
                const bool hadFrame = hasFrame();
                capture.frame = std::move(sample.frame);
                ++capture.sequence;
                if (!hadFrame) {
                    setStatus({});
                    emit hasFrameChanged();
                }
                update();
                break;
            }
            case SampleState::Waiting:
                break;
            }
        }, Qt::QueuedConnection);
    }, Qt::QueuedConnection);
}
#endif

void VoicePreview::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    if (newGeometry.size() != oldGeometry.size())
        update();
}

QSGNode *VoicePreview::updatePaintNode(QSGNode *oldNode, UpdatePaintNodeData *)
{
#ifdef Q_OS_WIN
    auto *view = window();
    if (m_active && m_capture && m_capture->source && view) {
        auto *renderer = view->rendererInterface();
        ID3D11Device *device = nullptr;
        if (renderer->graphicsApi() == QSGRendererInterface::Direct3D11)
            device = static_cast<ID3D11Device *>(renderer->getResource(view, QSGRendererInterface::DeviceResource));

        if (m_capture->renderDevice.Get() != device) {
            QMetaObject::invokeMethod(&m_capture->replies, [this, device = ComPtr<ID3D11Device>(device)] {
                if (!m_capture->source || m_capture->renderDevice.Get() == device.Get())
                    return;
                suspend();
                m_capture->renderDevice = device;
                m_capture->forceReadback = false;
            }, Qt::QueuedConnection);
        } else if (hasFrame()) {
            const auto &frame = *m_capture->frame;
            const auto sequence = m_capture->sequence;
            const QRect crop(QPoint(0, 0), frame.size);
            auto *node = oldNode ? static_cast<BackdropTextureNode *>(oldNode) : new BackdropTextureNode;
            auto *context = device ? static_cast<ID3D11DeviceContext *>(renderer->getResource(
                view, QSGRendererInterface::DeviceContextResource)) : nullptr;
            const bool copied = frame.image.isNull()
                ? context && node->copyFrame(view, device, context, frame.texture.Get(), crop, sequence)
                : node->showImage(view, frame.image, sequence);
            if (copied) {
                const QSizeF bounds = boundingRect().size();
                const QSizeF size = QSizeF(frame.size).scaled(bounds, Qt::KeepAspectRatio);
                node->setRect(QRectF((bounds.width() - size.width()) / 2.0,
                    (bounds.height() - size.height()) / 2.0, size.width(), size.height()));
                return node;
            }
            QMetaObject::invokeMethod(&m_capture->replies, [this, sequence] {
                if (!hasFrame() || m_capture->sequence != sequence)
                    return;
                if (m_capture->frame->image.isNull()) {
                    m_capture->forceReadback = true;
                    suspend();
                } else {
                    failSource(tr("Превью недоступно."));
                }
            }, Qt::QueuedConnection);
            delete node;
            return nullptr;
        }
    }
#endif
    delete oldNode;
    return nullptr;
}
