"""A PulseAudio client that reads only the server's default output monitor."""

import ctypes as C
from dataclasses import dataclass, field
import time


# Public libpulse ABI. Read only the prefixes of output/server structures,
# whose trailing fields have grown across PulseAudio releases.
class SampleSpec(C.Structure):
    _fields_ = [("format", C.c_int), ("rate", C.c_uint32), ("channels", C.c_uint8)]


class ChannelMap(C.Structure):
    _fields_ = [("channels", C.c_uint8), ("map", C.c_int * 32)]


class Volume(C.Structure):
    _fields_ = [("channels", C.c_uint8), ("values", C.c_uint32 * 32)]


class SinkInfo(C.Structure):
    _fields_ = [
        ("name", C.c_char_p), ("index", C.c_uint32), ("description", C.c_char_p),
        ("sample_spec", SampleSpec), ("channel_map", ChannelMap),
        ("owner_module", C.c_uint32), ("volume", Volume), ("mute", C.c_int),
        ("monitor_source", C.c_uint32), ("monitor_source_name", C.c_char_p),
    ]


class BufferAttr(C.Structure):
    _fields_ = [(name, C.c_uint32) for name in ("maxlength", "tlength", "prebuf", "minreq", "fragsize")]


Handle = C.c_void_p
SinkCallback = C.CFUNCTYPE(None, Handle, C.POINTER(SinkInfo), C.c_int, Handle)
Subscription = C.CFUNCTYPE(None, Handle, C.c_uint32, C.c_uint32, Handle)
Success = C.CFUNCTYPE(None, Handle, C.c_int, Handle)

INVALID_INDEX = (1 << 32) - 1
CONTEXT_READY = 4
STREAM_READY = 2
CONTEXT_NOAUTOSPAWN = 0x1
START_CORKED = 0x1
DONT_MOVE = 0x200
ADJUST_LATENCY = 0x2000
SAMPLE_RATE = 44100
FRAME_BYTES = 4  # Signed 16-bit little-endian, two channels
FRAGMENT = SAMPLE_RATE * FRAME_BYTES // 50


def load_api():
    pulse = C.CDLL("libpulse.so.0")
    signatures = [
        ("mainloop_new", Handle), ("mainloop_get_api", Handle, Handle),
        ("mainloop_prepare", C.c_int, Handle, C.c_int),
        ("mainloop_poll", C.c_int, Handle), ("mainloop_dispatch", C.c_int, Handle),
        ("mainloop_free", None, Handle),
        ("context_new", Handle, Handle, C.c_char_p),
        ("context_connect", C.c_int, Handle, C.c_char_p, C.c_uint32, Handle),
        ("context_get_state", C.c_int, Handle), ("context_errno", C.c_int, Handle),
        ("context_disconnect", None, Handle), ("context_unref", None, Handle),
        ("context_set_subscribe_callback", None, Handle, Subscription, Handle),
        ("context_subscribe", Handle, Handle, C.c_uint32, Success, Handle),
        ("context_get_sink_info_by_name", Handle, Handle, C.c_char_p, SinkCallback, Handle),
        ("strerror", C.c_char_p, C.c_int),
        ("operation_get_state", C.c_int, Handle),
        ("operation_cancel", None, Handle), ("operation_unref", None, Handle),
        ("proplist_new", Handle), ("proplist_free", None, Handle),
        ("proplist_sets", C.c_int, Handle, C.c_char_p, C.c_char_p),
        ("stream_new_with_proplist", Handle, Handle, C.c_char_p, C.POINTER(SampleSpec), Handle, Handle),
        ("stream_connect_record", C.c_int, Handle, C.c_char_p, C.POINTER(BufferAttr), C.c_uint32),
        ("stream_get_state", C.c_int, Handle), ("stream_get_device_index", C.c_uint32, Handle),
        ("stream_get_device_name", C.c_char_p, Handle),
        ("stream_cork", Handle, Handle, C.c_int, Success, Handle),
        ("stream_readable_size", C.c_size_t, Handle),
        ("stream_peek", C.c_int, Handle, C.POINTER(Handle), C.POINTER(C.c_size_t)),
        ("stream_drop", C.c_int, Handle), ("stream_disconnect", C.c_int, Handle),
        ("stream_unref", None, Handle),
    ]
    for name, result, *args in signatures:
        function = getattr(pulse, "pa_" + name)
        function.argtypes = args
        function.restype = result
    return pulse


@dataclass(frozen=True)
class Output:
    sink: bytes
    sink_index: int
    monitor: bytes
    monitor_index: int
    label: bytes = field(compare=False)


class MonitorError(RuntimeError):
    pass


class PulseMonitor:
    def __init__(self, stopping):
        self.api = load_api()
        self.loop = self.api.pa_mainloop_new()
        self.stopping = stopping
        self.context = self.stream = self.output = None
        self.changed = True
        self.subscribed = False
        self.subscription_callback = Subscription(self._route_event)

    def error(self, message):
        if self.context:
            error = self.api.pa_strerror(self.api.pa_context_errno(self.context)).decode(errors="replace")
            if error != "OK":
                message = f"{message}: {error}"
        return MonitorError(message)

    def __enter__(self):
        if not self.loop:
            raise MonitorError("Не удалось создать цикл PulseAudio.")
        try:
            self.context = self.api.pa_context_new(self.api.pa_mainloop_get_api(self.loop), b"Dock Equalizer")
            if not self.context or self.api.pa_context_connect(self.context, None, CONTEXT_NOAUTOSPAWN, None) < 0:
                raise self.error("Не удалось подключиться к серверу звука")
            state = lambda: self.api.pa_context_get_state(self.context)
            self.wait_until(lambda: state() not in (1, 2, 3), "Сервер звука не ответил")
            if state() != CONTEXT_READY:
                raise self.error("Сервер звука недоступен")
            self.api.pa_context_set_subscribe_callback(self.context, self.subscription_callback, None)
            # Sink/source add/remove and global default changes. Readiness can
            # still be checked occasionally if a server cannot subscribe.
            self.subscribed = self.successful(self.api.pa_context_subscribe, self.context, 0x83)
            return self
        except BaseException:
            self.close()
            raise

    def __exit__(self, *_):
        self.close()

    def close(self):
        self.stop_stream()
        if self.context:
            self.api.pa_context_disconnect(self.context)
            self.api.pa_context_unref(self.context)
            self.context = None
        if self.loop:
            self.api.pa_mainloop_free(self.loop)
            self.loop = None

    def _route_event(self, _context, event, _index, _userdata):
        facility, kind = event & 0x0f, event & 0x30
        # A running monitor reports frequent volume and state changes.
        if facility == 7 or (facility in (0, 1) and kind in (0, 0x20)):
            self.changed = True

    def pump(self, timeout_us=20000):
        if self.stopping():
            raise InterruptedError
        if (self.api.pa_mainloop_prepare(self.loop, timeout_us) < 0
                or self.api.pa_mainloop_poll(self.loop) < 0
                or self.api.pa_mainloop_dispatch(self.loop) < 0):
            if self.stopping():
                raise InterruptedError
            raise self.error("Цикл звукового сервера остановился")

    def connected(self):
        return self.api.pa_context_get_state(self.context) == CONTEXT_READY

    def wait_until(self, predicate, message, seconds=1.5):
        deadline = time.monotonic() + seconds
        while not predicate():
            if time.monotonic() >= deadline:
                raise self.error(message)
            self.pump()

    def finish(self, operation):
        if not operation:
            return False
        try:
            state = lambda: self.api.pa_operation_get_state(operation)
            self.wait_until(lambda: state() != 0 or not self.connected(), "Сервер звука не ответил")
            return state() == 1 and self.connected()
        finally:
            self.api.pa_operation_cancel(operation)
            self.api.pa_operation_unref(operation)

    def successful(self, request, *args):
        result = False

        @Success
        def callback(_owner, success, _userdata):
            nonlocal result
            result = bool(success)

        return self.finish(request(*args, callback, None)) and result

    def find_output(self):
        self.changed = False
        output = None

        @SinkCallback
        def callback(_context, info, end, _userdata):
            nonlocal output
            if info and not end:
                sink = info.contents
                if sink.name and sink.monitor_source_name and sink.monitor_source != INVALID_INDEX:
                    output = Output(sink.name, sink.index, sink.monitor_source_name, sink.monitor_source,
                                    sink.description or sink.name)

        query = self.api.pa_context_get_sink_info_by_name(self.context, b"@DEFAULT_SINK@", callback, None)
        return output if self.finish(query) else None

    def stop_stream(self):
        if self.stream:
            self.api.pa_stream_disconnect(self.stream)
            self.api.pa_stream_unref(self.stream)
            self.stream = None
        self.output = None

    def start_stream(self, output, corked=False):
        self.stop_stream()
        properties = self.api.pa_proplist_new()
        if not properties:
            raise self.error("Не удалось описать поток захвата")
        try:
            # PulseAudio honors DONT_MOVE. PipeWire also consumes these
            # properties through its Pulse protocol compatibility server.
            for key, value in (
                (b"node.dont-move", b"true"), (b"node.dont-fallback", b"true"),
                (b"node.dont-reconnect", b"true"), (b"state.restore-target", b"false"),
                (b"stream.capture.sink", b"true"),
            ):
                if self.api.pa_proplist_sets(properties, key, value) < 0:
                    raise self.error("Не удалось закрепить монитор выхода")
            spec = SampleSpec(3, SAMPLE_RATE, 2)  # PA_SAMPLE_S16LE
            self.stream = self.api.pa_stream_new_with_proplist(
                self.context, b"Dock Equalizer output monitor", C.byref(spec), None, properties
            )
        finally:
            self.api.pa_proplist_free(properties)
        self.output = output
        attr = BufferAttr(INVALID_INDEX, INVALID_INDEX, INVALID_INDEX, INVALID_INDEX, FRAGMENT)
        if not self.stream or self.api.pa_stream_connect_record(
            self.stream, output.monitor, C.byref(attr), START_CORKED | DONT_MOVE | ADJUST_LATENCY
        ) < 0:
            raise self.error("Не удалось подключить монитор выхода")
        self.wait_until(
            lambda: self.api.pa_stream_get_state(self.stream) != 1 or not self.connected(),
            "Монитор выхода не ответил",
        )
        # Confirm the actual source before uncorking, then before reading every
        # fragment. In particular, the default input is never opened.
        if not self.attached() or (not corked and not self.successful(self.api.pa_stream_cork, self.stream, 0)):
            raise self.error("Сервер не подтвердил монитор выхода")

    def attached(self):
        return bool(self.stream and self.api.pa_stream_get_state(self.stream) == STREAM_READY
                    and self.api.pa_stream_get_device_index(self.stream) == self.output.monitor_index
                    and self.api.pa_stream_get_device_name(self.stream) == self.output.monitor)

    def fragments(self):
        for _ in range(8):
            if not self.attached():
                raise self.error("Монитор выхода отключился или был перемещён")
            size = self.api.pa_stream_readable_size(self.stream)
            if size == C.c_size_t(-1).value:
                raise self.error("Звуковой сервер остановил поток")
            if size == 0:
                return
            data, length = Handle(), C.c_size_t()
            if self.api.pa_stream_peek(self.stream, C.byref(data), C.byref(length)) < 0:
                raise self.error("Не удалось получить звук с монитора")
            if not length.value:
                return
            # libpulse represents a hole in the stream with a null buffer.
            count = min(length.value, FRAGMENT * 4)
            count -= count % FRAME_BYTES
            pcm = C.string_at(data, count) if data else bytes(count)
            if self.api.pa_stream_drop(self.stream) < 0:
                raise self.error("Не удалось освободить буфер монитора")
            yield pcm
