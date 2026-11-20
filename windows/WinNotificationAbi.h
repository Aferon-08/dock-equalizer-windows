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
    virtual HRESULT STDMETHODCALLTYPE get_Bindings(VectorView<NotificationBinding *> **) = 0;
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

struct XmlDocumentIO : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE LoadXml(HSTRING) = 0;
};

struct ToastNotificationFactory : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE CreateToastNotification(IInspectable *, IInspectable **) = 0;
};

struct ToastNotificationOptions : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE put_Tag(HSTRING) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Tag(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_Group(HSTRING) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Group(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE put_SuppressPopup(boolean) = 0;
};

struct ToastNotifier : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE Show(IInspectable *) = 0;
    virtual HRESULT STDMETHODCALLTYPE Hide(IInspectable *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Setting(INT32 *) = 0;
};

struct ToastManagerStatics : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE CreateToastNotifier(ToastNotifier **) = 0;
};

inline constexpr GUID listenerStaticsId{0xff6123cf, 0x4386, 0x4aa3,
    {0xb7, 0x3d, 0xb8, 0x04, 0xe5, 0xb6, 0x3b, 0x23}};
inline constexpr GUID xmlDocumentIOId{0x6cd0e74e, 0xee65, 0x4489,
    {0x9e, 0xbf, 0xca, 0x43, 0xe8, 0x7b, 0xa6, 0x37}};
inline constexpr GUID xmlDocumentId{0xf7f3a506, 0x1e87, 0x42d6,
    {0xbc, 0xfb, 0xb8, 0xc8, 0x09, 0xfa, 0x54, 0x94}};
inline constexpr GUID toastFactoryId{0x04124b20, 0x82c6, 0x4229,
    {0xb1, 0x09, 0xfd, 0x9e, 0xd4, 0x66, 0x2b, 0x53}};
inline constexpr GUID toastOptionsId{0x9dfb9fd1, 0x143a, 0x490e,
    {0x90, 0xbf, 0xb9, 0xfb, 0xa7, 0x13, 0x2d, 0xe7}};
inline constexpr GUID toastManagerId{0x50ac103f, 0xd235, 0x4598,
    {0xbb, 0xef, 0x98, 0xfe, 0x4d, 0x1a, 0x3a, 0xd4}};

} // namespace winnotification
