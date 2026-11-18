#pragma once

#include <QtCore/qt_windows.h>
#include <inspectable.h>

// WinRT ABI subset from the Windows SDK Windows.Media.Control metadata.
// This keeps the same interfaces usable with MSVC and MinGW, whose headers do
// not yet include Windows.Media.Control. Declaration order is ABI significant.
namespace winmedia {

template<class T> struct AsyncOperation : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE put_Completed(IUnknown *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Completed(IUnknown **) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetResults(T *) = 0;
};

template<class T> struct VectorView : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE GetAt(UINT32, T *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Size(UINT32 *) = 0;
};

struct BoxedDouble : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_Value(double *) = 0;
};

struct StreamReference : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE OpenReadAsync(AsyncOperation<IInspectable *> **) = 0;
};

struct Properties : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_Title(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Subtitle(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_AlbumArtist(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Artist(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_AlbumTitle(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_TrackNumber(INT32 *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Genres(VectorView<HSTRING> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_AlbumTrackCount(INT32 *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_PlaybackType(IInspectable **) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Thumbnail(StreamReference **) = 0;
};

struct PlaybackControls : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_IsPlayEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsPauseEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsStopEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsRecordEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsFastForwardEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsRewindEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsNextEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsPreviousEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsChannelUpEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsChannelDownEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsPlayPauseToggleEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsShuffleEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsRepeatEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsPlaybackRateEnabled(boolean *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_IsPlaybackPositionEnabled(boolean *) = 0;
};

enum class PlaybackStatus : INT32 { Closed, Opened, Changing, Stopped, Playing, Paused };

struct PlaybackInfo : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_Controls(PlaybackControls **) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_PlaybackStatus(PlaybackStatus *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_PlaybackType(IInspectable **) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_AutoRepeatMode(IInspectable **) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_PlaybackRate(BoxedDouble **) = 0;
};

struct WinTime { INT64 ticks; };

struct Timeline : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_StartTime(WinTime *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_EndTime(WinTime *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_MinSeekTime(WinTime *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_MaxSeekTime(WinTime *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_Position(WinTime *) = 0;
    virtual HRESULT STDMETHODCALLTYPE get_LastUpdatedTime(WinTime *) = 0;
};

struct EventToken { INT64 value; };
struct Session;

struct PropertiesChangedHandler : IUnknown
{
    virtual HRESULT STDMETHODCALLTYPE Invoke(Session *, IInspectable *) = 0;
};

inline constexpr GUID propertiesChangedHandlerId{0x0f2ce2b7, 0xafa7, 0x5ed0,
    {0x8c, 0xb6, 0x8c, 0x40, 0xcf, 0x9b, 0x3a, 0x5f}};

struct Session : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE get_SourceAppUserModelId(HSTRING *) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryGetMediaPropertiesAsync(AsyncOperation<Properties *> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetTimelineProperties(Timeline **) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetPlaybackInfo(PlaybackInfo **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryPlayAsync(AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryPauseAsync(AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryStopAsync(AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryRecordAsync(AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryFastForwardAsync(AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryRewindAsync(AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TrySkipNextAsync(AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TrySkipPreviousAsync(AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryChangeChannelUpAsync(AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryChangeChannelDownAsync(AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryTogglePlayPauseAsync(AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryChangeAutoRepeatModeAsync(INT32, AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryChangePlaybackRateAsync(double, AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryChangeShuffleActiveAsync(boolean, AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE TryChangePlaybackPositionAsync(INT64, AsyncOperation<boolean> **) = 0;
    virtual HRESULT STDMETHODCALLTYPE add_TimelinePropertiesChanged(IUnknown *, EventToken *) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_TimelinePropertiesChanged(EventToken) = 0;
    virtual HRESULT STDMETHODCALLTYPE add_PlaybackInfoChanged(IUnknown *, EventToken *) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_PlaybackInfoChanged(EventToken) = 0;
    virtual HRESULT STDMETHODCALLTYPE add_MediaPropertiesChanged(PropertiesChangedHandler *, EventToken *) = 0;
    virtual HRESULT STDMETHODCALLTYPE remove_MediaPropertiesChanged(EventToken) = 0;
};

struct SessionManager : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE GetCurrentSession(Session **) = 0;
    virtual HRESULT STDMETHODCALLTYPE GetSessions(VectorView<Session *> **) = 0;
};

struct SessionManagerFactory : IInspectable
{
    virtual HRESULT STDMETHODCALLTYPE RequestAsync(AsyncOperation<SessionManager *> **) = 0;
};

inline constexpr GUID sessionManagerFactoryId{0x2050c4ee, 0x11a0, 0x57de,
    {0xae, 0xd7, 0xc9, 0x7c, 0x70, 0x33, 0x82, 0x45}};
inline constexpr wchar_t sessionManagerClass[] =
    L"Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager";

} // namespace winmedia
