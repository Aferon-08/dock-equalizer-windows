#!/usr/bin/env python3
"""Verify real CAVA, libpulse, and QML hotplug in a private audio graph."""

import argparse
from array import array
from contextlib import ExitStack
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import wave

ROOT = Path(__file__).resolve().parents[1]


def write_tone(path, hz):
    rate = 44100
    sample = array("h")
    for i in range(rate):
        value = round(4300 * math.sin(2 * math.pi * hz * i / rate))
        sample.extend((value, value))
    if sys.byteorder != "little":
        sample.byteswap()
    with wave.open(str(path), "wb") as stream:
        stream.setparams((2, 2, rate, 0, "NONE", ""))
        stream.writeframes(sample.tobytes() * 44)


def run(stage, backend):
    run_dir = stage / "run"
    run_dir.mkdir(mode=0o700)
    config = stage / "config"
    config.mkdir()
    graph = stage / "graph"
    graph.mkdir()
    env = dict(os.environ, XDG_RUNTIME_DIR=str(run_dir), PIPEWIRE_RUNTIME_DIR=str(graph),
               XDG_CONFIG_HOME=str(config), XDG_STATE_HOME=str(stage / "state"),
               XDG_CACHE_HOME=str(stage / "cache"), XDG_DATA_HOME=str(stage / "data"),
               PULSE_RUNTIME_PATH=str(graph / "pulse"), PIPEWIRE_REMOTE="pipewire-0",
               PULSE_SERVER="unix:" + str(graph / "pulse/native"),
               QT_QPA_PLATFORM="offscreen", TEST_PLUGIN_DIR=str(ROOT))
    env.pop("WAYLAND_DISPLAY", None)

    def command(*args, **options):
        return subprocess.run(args, env=env, text=True, capture_output=True, timeout=3, **options)

    def pactl(*args):
        return command("pactl", *args, check=True).stdout.strip()

    def destroy(proc):
        if proc.poll() is not None:
            return
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)

    with ExitStack() as resources:
        def start(name, *args):
            log = resources.enter_context((stage / (name + ".log")).open("w"))
            process = subprocess.Popen(args, env=env, stdout=log, stderr=subprocess.STDOUT)
            resources.callback(destroy, process)
            return process

        if backend == "pipewire":
            # Policy-only WirePlumber discovers the fixture's virtual nodes.
            # It never runs ALSA or Bluetooth monitors against the host devices.
            drop_in = config / "pipewire/pipewire-pulse.conf.d"
            drop_in.mkdir(parents=True)
            (drop_in / "fixture.conf").write_text("pulse.properties = { pulse.cmd.always-sink = false }")
            start("core", "pipewire")
            start("server", "pipewire-pulse")
            start("policy", "wireplumber", "--profile=policy")
        else:
            socket = graph / "pulse/native"
            socket.parent.mkdir(mode=0o700)
            modules = os.environ.get("TEST_PULSE_MODULES")
            extra = ["--dl-search-path=" + modules] if modules else []
            server = os.environ.get("TEST_PULSE_BINARY", "pulseaudio")
            start("server", server, "-n", "--daemonize=no", "--exit-idle-time=-1",
                  "--use-pid-file=no", "--disable-shm=yes", *extra,
                  "-L", f"module-native-protocol-unix socket={socket} auth-anonymous=yes")

        def wait(predicate, description, timeout=7):
            deadline = time.monotonic() + timeout
            seen = None
            while time.monotonic() < deadline:
                seen = predicate()
                if seen:
                    return seen
                time.sleep(0.08)
            raise AssertionError(description + " timed out")

        wait(lambda: command("pactl", "info").returncode == 0, "private Pulse server")
        assert str(graph) in pactl("info"), "Refusing to change a non-fixture audio graph"

        if backend == "pipewire":
            command("pw-cli", "create-node", "adapter",
                    "{ factory.name=support.null-audio-sink node.name=fixture_input "
                    "media.class=Audio/Source/Virtual audio.position=[ FL FR ] object.linger=true }",
                    check=True)
        else:
            pactl("load-module", "module-pipe-source", "source_name=fixture_input",
                  f"file={graph / 'mic.pcm'}")

        wait(lambda: "fixture_input" in pactl("list", "short", "sources"), "virtual input")
        pactl("set-default-source", "fixture_input")

        def load(name):
            return pactl("load-module", "module-null-sink", "sink_name=" + name, "rate=44100", "channels=2")

        usb, effects = load("fixture_usb"), load("easyeffects_sink")
        pactl("set-default-sink", "fixture_usb")
        low = stage / "low.wav"
        high = stage / "high.wav"
        write_tone(low, 330)
        write_tone(high, 2400)
        low_player = start("low", "paplay", "--device=fixture_usb", str(low))
        high_player = start("high", "paplay", "--device=easyeffects_sink", str(high))
        shutil.copy2(ROOT / "tests/audio-output.qml", stage / "shell.qml")
        for component in ("SpectrumCapture.qml", "AudioSelfTest.qml"):
            shutil.copy2(ROOT / component, stage)
        shell = start("shell", "qs", "-p", str(stage), "-n")

        def ipc(method):
            return command("qs", "-p", str(stage), "ipc", "call", "audio-output-test", method)

        def status():
            result = ipc("status")
            if result.returncode:
                return {}
            data = json.loads(result.stdout)
            assert not data["error"], data
            return data

        def sources():
            records = json.loads(pactl("-f", "json", "list", "sources"))
            return {s["index"]: s["name"] for s in records}

        def assert_output_only():
            names = sources()
            captures = json.loads(pactl("-f", "json", "list", "source-outputs"))
            for capture in captures:
                # Allow a just-removed source to vanish between two snapshots.
                name = names.get(capture["source"])
                assert name != "fixture_input", "A recording stream reached the microphone"
            return captures

        def signal_on(sink, test_bin, old=None):
            matches = 0
            def predicate():
                nonlocal matches
                current = status()
                assert_output_only()
                route = current.get("output") or {}
                if (route.get("sink") == sink and current.get("state") == "running"
                        and current["peak"] > 45 and test_bin(current["bin"])):
                    matches += 1
                    if matches < 4:
                        return None
                    if old is not None:
                        assert current["clears"] > old["clears"], current
                    assert {s["source"] for s in assert_output_only()} == {route["monitorIndex"]}, current
                    return current
                matches = 0
                return None
            try:
                return wait(predicate, f"real spectrum on {sink}")
            except AssertionError as error:
                diag = {key: pactl("list", "short", key)
                        for key in ("sinks", "sources", "sink-inputs", "source-outputs")}
                raise AssertionError(f"{error}; default {pactl('get-default-sink')}; last QML state {status()}; graph {diag}") from error

        first = signal_on("fixture_usb", lambda index: index >= 0)
        assert first["testResult"] is None, first
        assert 0 <= (time.time() * 1000 - first["lastPacketAt"]) < 1000, first
        print(f"PASS {backend}: USB monitor carries the low test tone (bin {first['bin']})", flush=True)
        attached = assert_output_only()[0]
        # Even an explicit server move request must not redirect the capture to the default input.
        command("pactl", "move-source-output", str(attached["index"]), "fixture_input")
        signal_on("fixture_usb", lambda index: abs(index - first["bin"]) <= 2)
        # An explicitly targeted playback stream can follow the old default
        # per WirePlumber policy. Separate the fixture tones unambiguously.
        destroy(low_player)
        pactl("set-default-sink", "easyeffects_sink")
        second = signal_on("easyeffects_sink", lambda index: abs(index - first["bin"]) >= 6, first)
        assert second["pid"] == first["pid"], "Output change restarted the supervisor"
        assert second["output"]["pid"] != first["output"]["pid"]
        assert not Path(f"/proc/{first['output']['pid']}").exists()
        print(f"PASS {backend}: default switch picks up EasyEffects tone (bin {second['bin']})", flush=True)

        low_player = start("low-return", "paplay", "--device=fixture_usb", str(low))
        pactl("unload-module", effects)
        destroy(high_player)
        returned = signal_on("fixture_usb", lambda index: abs(index - first["bin"]) <= 2, second)
        assert returned["pid"] == first["pid"]
        pactl("unload-module", usb)
        destroy(low_player)

        def no_output():
            current = status()
            assert not assert_output_only(), "Capture remained active without an output"
            return current if current.get("state") == "waiting-output" else None

        wait(lambda: status().get("state") == "waiting-output", "missing default output")
        empty = no_output()
        assert empty["peak"] == 0 and empty["pid"] == first["pid"] and empty["lastPacketAt"] == 0
        ipc("checkAudio").check_returncode()
        no_monitor = wait(lambda: status().get("testResult"), "silent self-test without output")
        assert no_monitor["ok"] is False and no_monitor["reason"], no_monitor
        # Remain empty longer than the startup watchdog before reappearing.
        until = time.monotonic() + 6.2
        while time.monotonic() < until:
            state = no_output()
            assert state and state["frames"] == empty["frames"], state
            time.sleep(.15)
        print(f"PASS {backend}: no output, no FFT or input stream, no restart loop", flush=True)

        load("fixture_hdmi")
        wait(lambda: "fixture_hdmi.monitor" in pactl("list", "short", "sources"), "HDMI monitor registration")
        pactl("set-default-sink", "fixture_hdmi")
        wait(lambda: pactl("get-default-sink") == "fixture_hdmi", "new default sink")
        start("hdmi", "paplay", "--device=fixture_hdmi", str(high))
        final = signal_on("fixture_hdmi", lambda index: abs(index - second["bin"]) <= 2, returned)
        assert final["pid"] == first["pid"], "New monitor required a new playback session"
        ipc("pause").check_returncode()
        wait(lambda: not assert_output_only() and status().get("pid") is None, "pause cleanup")
        assert not Path(f"/proc/{final['output']['pid']}").exists()
        assert status()["state"] == "idle" and status()["lastPacketAt"] == 0, status()
        print(f"PASS {backend}: HDMI reappears, audio resumes, pause reaps recorder and CAVA", flush=True)

        playback = pactl("list", "short", "sink-inputs")
        ipc("checkAudio").check_returncode()
        verified = wait(lambda: status().get("testResult"), "silent HDMI self-test")
        assert verified["ok"] and verified["bands"] == 64 and verified["monitor"] == "fixture_hdmi.monitor", verified
        assert not assert_output_only() and pactl("list", "short", "sink-inputs") == playback
        assert status()["state"] == "idle", status()
        print(f"PASS {backend}: manual self-test diagnoses a missing output and checks 64 bands silently", flush=True)

        ipc("quit")
        shell.wait(timeout=3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", choices=("pipewire", "pulse"), default="pipewire")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="dock-output-") as folder:
        stage = Path(folder)
        try:
            run(stage, args.backend)
        except BaseException:
            for name in ("core", "server", "policy", "shell"):
                log = stage / (name + ".log")
                if log.exists():
                    print(f"{name}:\n{log.read_text()[-2200:]}", file=sys.stderr)
            raise


if __name__ == "__main__":
    main()
