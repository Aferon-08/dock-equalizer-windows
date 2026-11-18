#!/usr/bin/env python3
"""Exercise the real Quickshell timeline on a private MPRIS test player."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
PLAYER = "org.mpris.MediaPlayer2.Player"
PATH = "/org/mpris/MediaPlayer2"
SPEC = """<node>
<interface name="org.mpris.MediaPlayer2">
  <property name="Identity" type="s" access="read"/>
  <property name="DesktopEntry" type="s" access="read"/>
</interface>
<interface name="org.mpris.MediaPlayer2.Player">
  <property name="PlaybackStatus" type="s" access="read"/>
  <property name="Metadata" type="a{sv}" access="read"/>
  <property name="Position" type="x" access="read"/>
  <property name="Rate" type="d" access="readwrite"/>
  <property name="CanSeek" type="b" access="read"/>
  <property name="CanControl" type="b" access="read"/>
  <property name="CanPlay" type="b" access="read"/>
  <property name="CanPause" type="b" access="read"/>
  <property name="CanGoNext" type="b" access="read"/>
  <property name="CanGoPrevious" type="b" access="read"/>
  <method name="SetPosition"><arg type="o" direction="in"/><arg type="x" direction="in"/></method>
  <signal name="Seeked"><arg type="x"/></signal>
</interface>
</node>"""


def player(control):
    from gi.repository import Gio, GLib

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    node = Gio.DBusNodeInfo.new_for_xml(SPEC)
    state = {"serial": 0, "title": "First", "playback": "Playing", "rate": 1.0, "zero": False}
    base, since = 32.0, time.monotonic()
    delayed = None

    def clock():
        elapsed = time.monotonic() - since if state["playback"] == "Playing" else 0
        return base + elapsed * state["rate"]

    def reported_position():
        if state["zero"]:
            return 0
        if delayed and time.monotonic() < delayed[0]:
            return delayed[1]
        return clock()

    def track_id():
        return "/org/example/track/" + state["title"]

    def value(prop):
        if prop == "Metadata":
            return GLib.Variant("a{sv}", {
                "mpris:trackid": GLib.Variant("o", track_id()),
                "mpris:length": GLib.Variant("x", 180_000_000),
                "xesam:title": GLib.Variant("s", state["title"]),
                "xesam:url": GLib.Variant("s", "https://www.youtube.com/watch?v=" + state["title"]),
            })
        return {
            "Identity": GLib.Variant("s", "Clock Browser"),
            "DesktopEntry": GLib.Variant("s", "clock_browser"),
            "PlaybackStatus": GLib.Variant("s", state["playback"]),
            "Position": GLib.Variant("x", round(reported_position() * 1_000_000)),
            "Rate": GLib.Variant("d", state["rate"]),
            "CanSeek": GLib.Variant("b", True),
            "CanControl": GLib.Variant("b", True),
            "CanPlay": GLib.Variant("b", True),
            "CanPause": GLib.Variant("b", True),
            "CanGoNext": GLib.Variant("b", False),
            "CanGoPrevious": GLib.Variant("b", False),
        }[prop]

    def get_property(_connection, _sender, _path, _interface, prop):
        return value(prop)

    def seeked(seconds):
        bus.emit_signal(None, PATH, PLAYER, "Seeked", GLib.Variant("(x)", (round(seconds * 1_000_000),)))

    def method(_connection, _sender, _path, _interface, name, parameters, reply):
        nonlocal base, since
        if name == "SetPosition":
            path, usec = parameters.unpack()
            if path == track_id():
                base, since = usec / 1_000_000, time.monotonic()
                seeked(base)
        reply.return_value(None)

    def apply():
        nonlocal base, since, delayed
        update = json.loads(control.read_text())
        if state["serial"] == update["serial"]:
            return GLib.SOURCE_CONTINUE
        previous_pos = clock()
        base, since = previous_pos, time.monotonic()
        delayed = None
        props = []
        for key, prop in (("title", "Metadata"), ("playback", "PlaybackStatus"), ("rate", "Rate"), ("zero", "Position")):
            if key in update and state[key] != update[key]:
                state[key] = update[key]
                props.append(prop)
        if "position" in update:
            base = update["position"]
        if props:
            bus.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                            GLib.Variant("(sa{sv}as)", (PLAYER, {prop: value(prop) for prop in props}, [])))
        if "seek" in update:
            base = update["seek"]
            if update.get("delay"):
                delayed = (time.monotonic() + update["delay"], previous_pos)
            seeked(base)
        if "staleSeek" in update:
            seeked(update["staleSeek"])
        state["serial"] = update["serial"]
        return GLib.SOURCE_CONTINUE

    for interface in node.interfaces:
        bus.register_object(PATH, interface, method, get_property, None)
    Gio.bus_own_name_on_connection(bus, "org.mpris.MediaPlayer2.clock_browser",
                                  Gio.BusNameOwnerFlags.NONE, None, None)
    GLib.timeout_add(15, apply)
    GLib.MainLoop().run()


def run(stage):
    run_dir = stage / "runtime"
    run_dir.mkdir(mode=0o700)
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=str(run_dir), TEST_PLUGIN_DIR=str(ROOT))
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    for name in ("MediaContext.qml", "MediaTimeline.qml", "PositionClock.js"):
        shutil.copy2(ROOT / name, stage / name)
    shutil.copy2(ROOT / "tests/media-timeline.qml", stage / "shell.qml")

    control = stage / "fixture.json"
    serial = 0
    def change(**kwargs):
        nonlocal serial
        replacement = control.with_suffix(".tmp")
        replacement.write_text(json.dumps(dict(serial=serial, **kwargs)))
        replacement.replace(control)
        serial += 1
    change()

    def ipc(method, *args):
        return subprocess.run(["qs", "-p", str(stage), "ipc", "call", "timeline-test", method, *args],
                              env=env, text=True, capture_output=True, timeout=3)
    def status():
        result = ipc("status")
        return json.loads(result.stdout) if result.returncode == 0 else {}
    def wait(predicate, description, timeout=6):
        deadline = time.monotonic() + timeout
        sample = {}
        while time.monotonic() < deadline:
            sample = status()
            if predicate(sample):
                return sample
            time.sleep(.06)
        raise AssertionError(f"{description}: {sample}")

    with (stage / "shell.log").open("w") as log:
        fixture = subprocess.Popen([sys.executable, __file__, "--player", str(control)], env=env)
        shell = subprocess.Popen(["qs", "-p", str(stage), "-n"], env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            first = wait(lambda s: s.get("source") == "mpris" and s["position"] >= 33, "verified D-Bus anchor")
            change(zero=True)
            during = wait(lambda s: s.get("ignoredZeros", 0) >= 2, "temporary zero samples")
            assert during["position"] > first["position"] + .35 and during["epoch"] == first["epoch"]
            change(zero=False)
            after = wait(lambda s: s.get("position", 0) > during["position"] + .35, "continuous browser progress")
            print("PASS temporary MPRIS zeros preserve the advancing shared position", flush=True)

            change(seek=0, delay=.3)
            sought = wait(lambda s: s.get("seekRevision", 0) > after["seekRevision"] and s["position"] < 1.5,
                          "explicit seek to zero after delayed position")
            assert sought["epoch"] == first["epoch"]
            print("PASS real Seeked returns to zero within the same epoch", flush=True)

            change(title="Second", position=0)
            next_track = wait(lambda s: s.get("title") == "Second" and s.get("source") == "mpris"
                              and s["epoch"] > first["epoch"], "new track epoch")
            change(staleSeek=75)
            time.sleep(1.3)
            after_stale = status()
            assert after_stale["epoch"] == next_track["epoch"] and after_stale["seekRevision"] == 0, after_stale
            assert .9 < after_stale["position"] < 3, after_stale
            change(playback="Paused")
            paused = wait(lambda s: s.get("playback") == "paused", "paused position")
            time.sleep(.25)
            assert abs(status()["position"] - paused["position"]) < .13
            assert ipc("seek", "6").stdout.strip() == "true"
            assert abs(status()["position"] - 6) < .08
            print("PASS new metadata, stale seek rejection, frozen pause and shared dock seek", flush=True)

            change(playback="Playing", rate=1.5)
            resumed = wait(lambda s: s.get("playback") == "playing" and s.get("rate") == 1.5,
                           "resumed at 1.5×")
            start = time.monotonic()
            time.sleep(.45)
            end = status()
            assert abs(end["position"] - resumed["position"] - (time.monotonic() - start) * 1.5) < .18, end
            fixture.terminate()
            fixture.wait(timeout=3)
            wait(lambda s: s.get("playback") == "absent" and not s["bridge"], "closed MPRIS player")
            print("PASS rate change and bridge cleanup after the player exits", flush=True)
        finally:
            ipc("quit")
            for process in (shell, fixture):
                if process.poll() is None:
                    process.terminate()
                    process.wait(timeout=3)


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--player":
        player(Path(sys.argv[2]))
    elif len(sys.argv) == 3 and sys.argv[1] == "--private":
        stage = Path(sys.argv[2])
        try:
            run(stage)
        except Exception:
            log = stage / "shell.log"
            if log.exists():
                print(log.read_text()[-3100:], file=sys.stderr)
            raise
    else:
        with tempfile.TemporaryDirectory(prefix="dock-timeline-") as folder:
            subprocess.run(["dbus-run-session", "--", sys.executable, __file__, "--private", folder], check=True)
