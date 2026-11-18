#!/usr/bin/env python3
"""Route the verified system output monitor into CAVA without writing PCM to disk."""

import argparse
from array import array
import json
import math
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import threading
import time

from pulse_monitor import FRAME_BYTES, SAMPLE_RATE, MonitorError, PulseMonitor


class OutputCapture:
    def __init__(self, config):
        self.config = config
        self.cava = None
        self.last_status = None

    def report(self, state, output, reason=""):
        status = {
            "type": "output", "state": state, "reason": reason,
            "sink": output.sink.decode(errors="replace") if output else "",
            "label": output.label.decode(errors="replace") if output else "",
            "monitor": output.monitor.decode(errors="replace") if output else "",
            "monitorIndex": output.monitor_index if output else None,
            "pid": self.cava.pid if self.cava else None,
        }
        if status != self.last_status:
            print(json.dumps(status, ensure_ascii=False), flush=True)
            self.last_status = status

    def start_cava(self, stdout=None):
        self.cava = subprocess.Popen(
            ["setpriv", "--pdeathsig", "KILL", "cava", "-p", str(self.config)],
            stdin=subprocess.PIPE, stdout=stdout, bufsize=0,
        )
        os.set_blocking(self.cava.stdin.fileno(), False)

    def stop_cava(self):
        if self.cava:
            self.cava.kill()
            self.cava.wait()
            self.cava.stdin.close()
            if self.cava.stdout:
                self.cava.stdout.close()
            self.cava = None

    def feed(self, data):
        # The kernel pipe bounds latency. Never block PulseAudio behind the FFT
        # and never split a stereo sample when dropping a delayed fragment.
        pipe = self.cava.stdin.fileno()
        chunk_size = select.PIPE_BUF - select.PIPE_BUF % FRAME_BYTES
        for offset in range(0, len(data), chunk_size):
            try:
                os.write(pipe, data[offset:offset + chunk_size])
            except BlockingIOError:
                break

    def run(self, pulse, stop):
        output = None
        retry_at = next_scan = 0.0
        retry_delay = 0.25
        while not stop.is_set():
            # In the no-output state, the loop wakes for device events or an
            # occasional recheck. There is no recorder or CAVA in that state.
            pulse.pump(20000 if self.cava else 100000)
            if not pulse.connected():
                raise pulse.error("Соединение с сервером звука потеряно")
            now = time.monotonic()
            if now >= next_scan and (pulse.changed or not output or not pulse.subscribed):
                candidate = pulse.find_output()
                next_scan = now + (0.25 if candidate else 1.0)
                if candidate != output:
                    pulse.stop_stream()
                    self.stop_cava()
                    output = candidate
                    retry_at, retry_delay = now, 0.25
                if not output:
                    self.report("waiting-output", None, "У выхода по умолчанию нет доступного монитора.")
            if not output:
                continue
            if not self.cava and now >= retry_at:
                self.report("binding", output)
                try:
                    pulse.start_stream(output)
                except MonitorError as error:
                    pulse.stop_stream()
                    self.report("waiting-output", output, str(error))
                    retry_at = now + retry_delay
                    retry_delay = min(4, retry_delay * 2)
                    continue
                self.start_cava()
                self.report("capturing", output)
            if not self.cava:
                continue
            if self.cava.poll() is not None:
                raise RuntimeError(f"CAVA завершилась (код {self.cava.returncode}).")
            try:
                for chunk in pulse.fragments():
                    self.feed(chunk)
                    retry_delay = 0.25
            except MonitorError as error:
                pulse.stop_stream()
                self.stop_cava()
                self.report("waiting-output", output, str(error))
                pulse.changed = True
                retry_at = now + retry_delay
                retry_delay = min(4, retry_delay * 2)


def verify_spectrum(capture, stop):
    """Drive one FFT with a private tone over the same PCM pipe as playback."""
    # Ten complete cycles in each 20 ms fragment, with no gaps in phase.
    tone = array("h")
    for index in range(SAMPLE_RATE // 50):
        sample = round(4600 * math.sin(math.tau * 500 * index / SAMPLE_RATE))
        tone.extend((sample, sample))
    if sys.byteorder != "little":
        tone.byteswap()
    pcm = tone.tobytes()
    capture.start_cava(stdout=subprocess.PIPE)
    stdout = capture.cava.stdout.fileno()
    os.set_blocking(stdout, False)
    pending = bytearray()
    deadline = time.monotonic() + 2.5
    while not stop.is_set() and time.monotonic() < deadline:
        if capture.cava.poll() is not None:
            raise RuntimeError(f"CAVA завершилась (код {capture.cava.returncode}).")
        capture.feed(pcm)
        try:
            pending.extend(os.read(stdout, 8192))
        except BlockingIOError:
            pass
        if len(pending) > 16384:
            break
        while b"\n" in pending:
            line, _, pending = pending.partition(b"\n")
            try:
                bands = [int(raw) for raw in line.strip().rstrip(b";").split(b";")]
            except ValueError:
                continue
            if len(bands) == 64 and max(bands) > 20:
                return len(bands)
        stop.wait(.02)
    raise RuntimeError("CAVA не вернула спектр тестового сигнала.")


def self_test(capture, stop):
    output = None
    try:
        with PulseMonitor(stop.is_set) as pulse:
            output = pulse.find_output()
            if not output:
                raise MonitorError("У выхода по умолчанию нет доступного монитора.")
            # Validate the server's routing without reading or playing sound.
            pulse.start_stream(output, corked=True)
        result = {"ok": True, "bands": verify_spectrum(capture, stop)}
    except (MonitorError, RuntimeError, OSError) as error:
        result = {"ok": False, "reason": str(error)}
    if output:
        result["label"] = output.label.decode(errors="replace")
        result["monitor"] = output.monitor.decode(errors="replace")
    print(json.dumps(result, ensure_ascii=False), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    capture = OutputCapture(args.config)
    try:
        if args.self_test:
            self_test(capture, stop)
        else:
            with PulseMonitor(stop.is_set) as pulse:
                capture.run(pulse, stop)
    except InterruptedError:
        pass
    except (MonitorError, RuntimeError, OSError) as error:
        print(str(error), file=sys.stderr, flush=True)
        return 1
    finally:
        capture.stop_cava()
    return 0


if __name__ == "__main__":
    sys.exit(main())
