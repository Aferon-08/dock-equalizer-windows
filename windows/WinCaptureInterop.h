#pragma once

#include "WinCaptureAbi.h"

#include <d3d11_4.h>
#include <roapi.h>
#include <winstring.h>
#include <wrl/client.h>

extern "C" HRESULT WINAPI CreateDirect3D11DeviceFromDXGIDevice(IDXGIDevice *, IInspectable **);

namespace wincapture {

using Microsoft::WRL::ComPtr;

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
        : RoGetActivationFactory(value, id, reinterpret_cast<void **>(result.ReleaseAndGetAddressOf()));
}

template<class Interface>
void releaseCapture(ComPtr<Interface> &object)
{
    ComPtr<Closable> closable;
    if (object && SUCCEEDED(query(object.Get(), closableId, closable)))
        closable->Close();
    object.Reset();
}

inline bool wrapCaptureDevice(ID3D11Device *device, ComPtr<IInspectable> &graphicsDevice)
{
    ComPtr<ID3D11DeviceContext> context;
    device->GetImmediateContext(context.GetAddressOf());
    ComPtr<ID3D11Multithread> guard;
    if (FAILED(context.As(&guard)))
        return false;
    guard->SetMultithreadProtected(TRUE);

    ComPtr<IDXGIDevice> dxgi;
    ComPtr<IInspectable> wrapper;
    return SUCCEEDED(device->QueryInterface(__uuidof(IDXGIDevice),
                         reinterpret_cast<void **>(dxgi.GetAddressOf())))
        && SUCCEEDED(CreateDirect3D11DeviceFromDXGIDevice(dxgi.Get(), wrapper.GetAddressOf()))
        && SUCCEEDED(query(wrapper.Get(), direct3dDeviceId, graphicsDevice));
}

inline bool frameTexture(Frame *frame, ComPtr<ID3D11Texture2D> &texture)
{
    ComPtr<IInspectable> surface;
    ComPtr<SurfaceAccess> access;
    return SUCCEEDED(frame->get_Surface(surface.GetAddressOf())) && surface
        && SUCCEEDED(query(surface.Get(), surfaceAccessId, access))
        && SUCCEEDED(access->GetInterface(__uuidof(ID3D11Texture2D),
                         reinterpret_cast<void **>(texture.ReleaseAndGetAddressOf())));
}

} // namespace wincapture
