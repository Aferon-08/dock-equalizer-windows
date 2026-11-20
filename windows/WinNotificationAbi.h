#pragma once

#include "WinMediaAbi.h"

// Windows.ApplicationModel and Windows.UI.Notifications WinRT ABI subset.
// Keep the vtable order from the Windows SDK metadata for MSVC and MinGW.
namespace winnotification {

using winmedia::AsyncOperation;
using winmedia::VectorView;
using winmedia::WinTime;

struct AppDisplayInfo : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_DisplayName(HSTRING *) = 0;
};

struct AppInfo : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_Id(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_AppUserModelId(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_DisplayInfo(AppDisplayInfo **) = 0;
};

struct AdaptiveText : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_Text(HSTRING *) = 0;
};

struct NotificationBinding : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_Template(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_Template(HSTRING) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Language(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_Language(HSTRING) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Hints(IInspectable **) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetTextElements(VectorView<AdaptiveText *> **) = 0;
};

struct NotificationVisual : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_Language(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_Language(HSTRING) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Bindings(IInspectable **) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetBinding(HSTRING, NotificationBinding **) = 0;
};

struct Notification : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_ExpirationTime(IInspectable **) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_ExpirationTime(IInspectable *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Visual(NotificationVisual **) = 0;
};

struct UserNotification : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_Notification(Notification **) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_AppInfo(AppInfo **) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Id(UINT32 *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_CreationTime(WinTime *) = 0;
};

enum class Access : INT32 { Unspecified, Allowed, Denied };

using NotificationList = VectorView<UserNotification *>;

struct Listener : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE RequestAccessAsync(AsyncOperation<Access> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetAccessStatus(Access *) = 0;
    virtual HRESULT STDMETHODCALLTYPE add_NotificationChanged(IUnknown *, INT64 *) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_NotificationChanged(INT64) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetNotificationsAsync(UINT32, AsyncOperation<NotificationList *> **) = 0;
};

struct ListenerStatics : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_Current(Listener **) = 0;
};

inline constexpr GUID listenerStaticsId{0xff6123cf, 0x4386, 0x4aa3,
    {0xb7, 0x3d, 0xb8, 0x04, 0xe5, 0xb6, 0x3b, 0x23}};

} // namespace winnotification
