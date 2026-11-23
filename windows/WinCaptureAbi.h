#pragma once

#include <QtCore/qt_windows.h>
#include <eventtoken.h>
#include <inspectable.h>

// Windows.Graphics.Capture ABI, from the Windows SDK metadata. MinGW's SDK
// does not declare the frame pool interfaces. Keep the method order and types.
namespace wincapture {

struct Size { INT32 width, height; };

struct Closable : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE Close() = 0;
};
inline constexpr IID closableId{0x30d5a829, 0x7fa4, 0x4026, {0x83, 0xbb, 0xd5, 0xb0, 0xae, 0x4f, 0xea, 0x9e}};

struct SurfaceAccess : IUnknown
{
    virtual HRESULT STDMETHODCALLTYPE GetInterface(REFIID, void **) = 0;
};
inline constexpr IID surfaceAccessId{0xa9b3d012, 0x3df2, 0x4ee3, {0xb8, 0xd1, 0x86, 0x95, 0xf4, 0x57, 0xd3, 0xc1}};
inline constexpr IID direct3dDeviceId{0xa37624ab, 0x8d5f, 0x4650, {0x9d, 0x3e, 0x9e, 0xae, 0x3d, 0x9b, 0xc6, 0x70}};

struct Item : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_DisplayName(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Size(Size *) = 0;
    virtual HRESULT STDMETHODCALLTYPE add_Closed(IUnknown *, EventRegistrationToken *) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_Closed(EventRegistrationToken) = 0;
};
inline constexpr IID itemId{0x79c3f95b, 0x31f7, 0x4ec2, {0xa4, 0x64, 0x63, 0x2e, 0xf5, 0xd3, 0x07, 0x60}};

struct ItemClosedHandler : IUnknown
{
    virtual HRESULT STDMETHODCALLTYPE Invoke(Item *, IInspectable *) = 0;
};
// TypedEventHandler<GraphicsCaptureItem, IInspectable>.
inline constexpr IID itemClosedHandlerId{0xe9c610c0, 0xa68c, 0x5bd9, {0x80, 0x21, 0x85, 0x89, 0x34, 0x6e, 0xee, 0xe2}};

struct ItemInterop : IUnknown
{
    virtual HRESULT STDMETHODCALLTYPE CreateForWindow(HWND, REFIID, void **) = 0;
    virtual HRESULT STDMETHODCALLTYPE CreateForMonitor(HMONITOR, REFIID, void **) = 0;
};
inline constexpr IID itemInteropId{0x3628e81b, 0x3cac, 0x4c60, {0xb7, 0xf4, 0x23, 0xce, 0x0e, 0x0c, 0x33, 0x56}};

struct PickerOperation : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE put_Completed(IUnknown *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Completed(IUnknown **) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetResults(Item **) = 0;
};

struct Picker : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE PickSingleItemAsync(PickerOperation **) = 0;
};
inline constexpr IID pickerId{0x5a1711b3, 0xad79, 0x4b4a, {0x93, 0x36, 0x13, 0x18, 0xfd, 0xde, 0x35, 0x39}};

struct SessionStatics : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE IsSupported(boolean *) = 0;
};
inline constexpr IID sessionStaticsId{0x2224a540, 0x5974, 0x49aa, {0xb2, 0x32, 0x08, 0x82, 0x53, 0x6f, 0x4c, 0xb5}};

struct Frame : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_Surface(IInspectable **) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_SystemRelativeTime(INT64 *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_ContentSize(Size *) = 0;
};

struct Session : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE StartCapture() = 0;
};

struct SessionCursor : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_IsCursorCaptureEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsCursorCaptureEnabled(boolean) = 0;
};
inline constexpr IID sessionCursorId{0x2c39ae40, 0x7d2e, 0x5044, {0x80, 0x4e, 0x8b, 0x67, 0x99, 0xd4, 0xcf, 0x9e}};

struct SessionBorder : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_IsBorderRequired(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_IsBorderRequired(boolean) = 0;
};
inline constexpr IID sessionBorderId{0xf2cdd966, 0x22ae, 0x5ea1, {0x95, 0x96, 0x3a, 0x28, 0x93, 0x44, 0xc3, 0xbe}};

enum class AccessKind : INT32 { Borderless = 0 };
enum class AccessStatus : INT32 { Allowed = 4 };

struct AccessOperation : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE put_Completed(IUnknown *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Completed(IUnknown **) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetResults(AccessStatus *) = 0;
};

struct AccessFactory : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE RequestAccessAsync(AccessKind, AccessOperation **) = 0;
};
inline constexpr IID accessFactoryId{0x743ed370, 0x06ec, 0x5040, {0xa5, 0x8a, 0x90, 0x1f, 0x0f, 0x75, 0x70, 0x95}};

struct FramePool : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE Recreate(IInspectable *, INT32 format, INT32 buffers, Size) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryGetNextFrame(Frame **) = 0;
    virtual HRESULT STDMETHODCALLTYPE add_FrameArrived(IUnknown *, EventRegistrationToken *) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_FrameArrived(EventRegistrationToken) = 0;
    virtual HRESULT STDMETHODCALLTYPE CreateCaptureSession(Item *, Session **) = 0;
};

struct FramePoolFactory : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE CreateFreeThreaded(IInspectable *, INT32 format, INT32 buffers, Size, FramePool **) = 0;
};
inline constexpr IID framePoolFactoryId{0x589b103f, 0x6bbc, 0x5df5, {0xa9, 0x91, 0x02, 0xe2, 0x8b, 0x3b, 0x66, 0xd5}};

} // namespace wincapture
