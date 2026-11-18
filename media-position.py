#!/usr/bin/env python3
"""Read the selected MPRIS player's position and explicit seek events."""

import json
import os
import re
import sys

from gi.repository import Gio, GLib


PLAYER = "org.mpris.MediaPlayer2.Player"
PROPERTIES = "org.freedesktop.DBus.Properties"
PATH = "/org/mpris/MediaPlayer2"


def matches(expected, metadata):
    return bool(expected) and all(str(metadata.get(key, "")) == value for key, value in expected.items())


class PositionBridge:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.loop = GLib.MainLoop()
        self.context = {}
        self.pending = b""
        self.subscriptions = []
        self.timer = 0
        self.query = None
        self.refresh = False
        self.seek_event = None
        os.set_blocking(sys.stdin.fileno(), False)
        GLib.io_add_watch(sys.stdin.fileno(), GLib.PRIORITY_DEFAULT,
                         GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, self.read)

    def read(self, fd, condition):
        try:
            data = os.read(fd, 8192) if condition & GLib.IO_IN else b""
        except BlockingIOError:
            return GLib.SOURCE_CONTINUE
        if not data:
            self.loop.quit()
            return GLib.SOURCE_REMOVE
        self.pending += data
        while b"\n" in self.pending:
            line, _, self.pending = self.pending.partition(b"\n")
            try:
                request = json.loads(line)
            except ValueError:
                continue
            if isinstance(request, dict):
                self.configure(request)
        if len(self.pending) > 32768:
            self.pending = b""
        return GLib.SOURCE_CONTINUE

    def configure(self, request):
        name = request.get("player", "")
        if not isinstance(name, str) or not re.fullmatch(r"org\.mpris\.MediaPlayer2\.[A-Za-z0-9_.-]+", name):
            return
        if name != self.context.get("player"):
            for subscription in self.subscriptions:
                self.bus.signal_unsubscribe(subscription)
            self.subscriptions = [
                self.bus.signal_subscribe(name, PLAYER, "Seeked", PATH, None,
                                          Gio.DBusSignalFlags.NONE, self.on_seek),
                self.bus.signal_subscribe(name, PROPERTIES, "PropertiesChanged", PATH, PLAYER,
                                          Gio.DBusSignalFlags.NONE, self.on_properties),
            ]
        if request.get("epoch") != self.context.get("epoch"):
            self.seek_event = None
        self.context = request
        if self.timer and not request.get("playing"):
            GLib.source_remove(self.timer)
            self.timer = 0
        if not self.timer and request.get("playing"):
            self.timer = GLib.timeout_add(720, self.poll)
        self.request_sample()

    def poll(self):
        self.request_sample()
        return GLib.SOURCE_CONTINUE

    def on_seek(self, _connection, sender, _path, _interface, _signal, args):
        self.seek_event = (self.context.get("epoch"), sender, args.unpack()[0] / 1_000_000,
                           GLib.get_monotonic_time())
        self.request_sample()

    def on_properties(self, _connection, _sender, _path, _interface, _signal, args):
        _, changed, invalidated = args.unpack()
        if "Position" in changed or "Position" in invalidated:
            self.request_sample()

    def request_sample(self):
        if self.query:
            self.refresh = True
            return
        self.refresh = False
        context = self.context
        self.query = context
        seek, self.seek_event = self.seek_event, None
        # A Seeked signal has no track id. Query the emitting connection so
        # a restarted player with the same name cannot validate the event.
        name = seek[1] if seek and seek[0] == context.get("epoch") else context["player"]
        self.bus.call(name, PATH, PROPERTIES, "GetAll", GLib.Variant("(s)", (PLAYER,)),
                      GLib.VariantType.new("(a{sv})"), Gio.DBusCallFlags.NO_AUTO_START, 650,
                      None, self.on_sample, (context, seek))

    def on_sample(self, connection, response, query):
        context, seek = query
        self.query = None
        deferred = False
        try:
            properties = connection.call_finish(response).unpack()[0]
            if context["epoch"] != self.context.get("epoch"):
                return
            if not matches(context.get("metadata"), properties.get("Metadata", {})):
                return
            position = properties.get("Position")
            position = position / 1_000_000 if isinstance(position, int) and position >= 0 else None
            event = {"epoch": context["epoch"], "position": position}
            if seek and seek[0] == context["epoch"] and seek[2] >= 0:
                age = (GLib.get_monotonic_time() - seek[3]) / 1_000_000
                drift = age * properties.get("Rate", 1) if properties.get("PlaybackStatus") == "Playing" else 0
                if position is None or abs(position - seek[2] - drift) < .8:
                    event["seek"] = seek[2] + drift
                elif age < 1 and not self.seek_event:
                    # The position may settle just after the signal. A stale
                    # seek from the previous track will never match this track.
                    self.seek_event = seek
                    deferred = True
                    GLib.timeout_add(160, self.retry_seek)
            print(json.dumps(event), flush=True)
        except GLib.Error:
            pass  # The next sample can resolve a delayed or disappearing player.
        finally:
            if self.refresh or (self.seek_event and not deferred):
                self.request_sample()

    def retry_seek(self):
        if self.seek_event:
            self.request_sample()
        return GLib.SOURCE_REMOVE


if __name__ == "__main__":
    PositionBridge().loop.run()
