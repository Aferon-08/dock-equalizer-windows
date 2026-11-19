#pragma once

#include <QtCore/qt_windows.h>
#include <QQuickWindow>
#include <QSGSimpleTextureNode>
#include <rhi/qrhi.h>

#include <d3d11.h>
#include <wrl/client.h>

#include <memory>
#include <utility>

// Keep the cropped texture and its Qt wrapper alive together on the render
// thread. The GPU copy and the Qt draw use the same immediate context.
class BackdropTextureNode final : public QSGSimpleTextureNode
{
public:
    static constexpr auto format = DXGI_FORMAT_B8G8R8A8_UNORM;

    bool copyFrame(QQuickWindow *window, ID3D11Device *device, ID3D11DeviceContext *context,
                   ID3D11Texture2D *source, const QRect &crop, quint64 sequence)
    {
        if (m_sourceSequence == sequence)
            return true;

        if (!m_target || m_texture->textureSize() != crop.size()) {
            D3D11_TEXTURE2D_DESC description{};
            description.Width = UINT(crop.width());
            description.Height = UINT(crop.height());
            description.MipLevels = description.ArraySize = description.SampleDesc.Count = 1;
            description.Format = format;
            description.BindFlags = D3D11_BIND_SHADER_RESOURCE;
            Microsoft::WRL::ComPtr<ID3D11Texture2D> target;
            if (FAILED(device->CreateTexture2D(&description, nullptr, target.GetAddressOf())))
                return false;
            // Use the capture's native BGRA format when importing the texture.
            std::unique_ptr<QRhiTexture> resource(window->rhi()->newTexture(QRhiTexture::BGRA8, crop.size()));
            if (!resource->createFrom({quint64(target.Get()), 0}))
                return false;
            std::unique_ptr<QSGTexture> texture(window->createTextureFromRhiTexture(resource.get()));
            if (!texture)
                return false;
            resource.release(); // The window texture owns the QRhi wrapper.
            setTexture(texture.get());
            setFiltering(QSGTexture::Linear);
            m_texture = std::move(texture);
            m_target = std::move(target);
        }

        const D3D11_BOX box{UINT(crop.left()), UINT(crop.top()), 0,
                           UINT(crop.right() + 1), UINT(crop.bottom() + 1), 1};
        context->CopySubresourceRegion(m_target.Get(), 0, 0, 0, 0, source, 0, &box);
        m_sourceSequence = sequence;
        // ShaderEffectSource must refresh even when the texture object and
        // its geometry stay the same.
        markDirty(QSGNode::DirtyMaterial);
        return true;
    }

    bool showImage(QQuickWindow *window, const QImage &image, quint64 sequence)
    {
        if (m_sourceSequence == sequence)
            return true;
        std::unique_ptr<QSGTexture> texture(window->createTextureFromImage(image, QQuickWindow::TextureIsOpaque));
        if (!texture)
            return false;
        setTexture(texture.get());
        setFiltering(QSGTexture::Linear);
        m_texture = std::move(texture);
        m_target.Reset();
        m_sourceSequence = sequence;
        return true;
    }

private:
    Microsoft::WRL::ComPtr<ID3D11Texture2D> m_target;
    std::unique_ptr<QSGTexture> m_texture;
    quint64 m_sourceSequence = 0;
};
