#!/usr/bin/env python3
"""MPRIS -> expiring, in-memory SekaiPop palette. No theme files are written."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import io
import json
import os
import re
import signal
import subprocess
import sys
import time
from urllib.parse import unquote, urlparse
from urllib.request import Request, urlopen
import uuid

from PIL import Image, ImageOps


def cover_colors(url):
    parsed = urlparse(url)
    if parsed.scheme == 'file':
        if parsed.netloc not in ('', 'localhost'):
            raise ValueError('Nonlocal file URL')
        with open(unquote(parsed.path), 'rb') as cover:
            data = cover.read(12 * 1024 * 1024 + 1)
    elif parsed.scheme in ('https', 'http'):
        request = Request(url, headers={'User-Agent': 'SekaiPop-MusicPalette/1.0'})
        with urlopen(request, timeout=5) as response:
            data = response.read(12 * 1024 * 1024 + 1)
    else:
        raise ValueError('Unsupported cover URL')
    if len(data) > 12 * 1024 * 1024:
        raise ValueError('Cover exceeds 12 MiB')
    with Image.open(io.BytesIO(data)) as source:
        image = ImageOps.exif_transpose(source).convert('RGBA')
        image.thumbnail((128, 128))
        background = Image.new('RGBA', image.size, '#202020')
        background.alpha_composite(image)
        quantized = background.convert('RGB').quantize(colors=5)
        palette = quantized.getpalette()
        entries = sorted(quantized.getcolors(), reverse=True)
        colors = ['#%02x%02x%02x' % tuple(palette[i*3:i*3+3]) for _, i in entries]
    return ','.join((colors * 5)[:5])


class Session:
    """Track changes never end a music session; only playback stopping does."""
    def __init__(self, ipc, submit, delay=.6):
        self.ipc, self.submit, self.delay = ipc, submit, delay
        self.owner = str(uuid.uuid4())
        self.url = ''
        self.jobs = {}
        self.cache = {}
        self.palette = None
        self.active = False
        self.stop_at = None
        self.refresh_at = 0
        self.retry_at = 0

    def clear(self):
        if self.active:
            self.ipc('musicClear', self.owner)
        self.palette = None
        self.active = False
        self.refresh_at = 0

    def renew(self, now):
        if self.active and now >= self.refresh_at:
            self.ipc('musicSet', self.owner, self.palette)
            self.refresh_at = now + 1

    def tick(self, playing, url, now):
        if not playing:
            if self.stop_at is None:
                self.stop_at = now + self.delay
            if now >= self.stop_at:
                self.clear()
            else:
                self.renew(now)
            # Never apply a completed fetch while paused.
            self.url = ''
            return
        self.stop_at = None
        if url != self.url:
            self.url = url
            self.retry_at = 0
        # MPRIS may briefly publish empty artwork while switching tracks.
        # Neither missing artwork nor an HTTP failure means playback stopped.
        self.renew(now)
        for job_url, future in list(self.jobs.items()):
            if not future.done():
                continue
            del self.jobs[job_url]
            try:
                self.cache[job_url] = future.result()
                if len(self.cache) > 32:
                    self.cache.pop(next(iter(self.cache)))
            except Exception as error:
                print('Обложка: ' + str(error), file=sys.stderr, flush=True)
                if job_url == url:
                    self.retry_at = now + 1
        if not url:
            return
        desired = self.cache.get(url)
        if desired is not None:
            if desired != self.palette or not self.active:
                self.ipc('musicSet', self.owner, desired)
                self.active, self.palette = True, desired
                self.refresh_at = now + 1
            return
        # Cancel obsolete queued work. At most two downloads run concurrently;
        # there is no queue of tracks that have already been skipped.
        for job_url, future in list(self.jobs.items()):
            if job_url != url and future.cancel():
                del self.jobs[job_url]
        if url not in self.jobs and len(self.jobs) < 2 and now >= self.retry_at:
            self.jobs[url] = self.submit(cover_colors, url)


class Mpris:
    def __init__(self):
        import gi
        from gi.repository import Gio, GLib
        self.Gio, self.GLib = Gio, GLib
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.selected = ''

    def call(self, name, path, interface, method, args=None):
        return self.bus.call_sync(name, path, interface, method, args, None,
                                  self.Gio.DBusCallFlags.NONE, 500, None).unpack()

    def read(self):
        names = self.call('org.freedesktop.DBus', '/org/freedesktop/DBus',
                          'org.freedesktop.DBus', 'ListNames')[0]
        playing = []
        for name in names:
            if not name.startswith('org.mpris.MediaPlayer2.'):
                continue
            try:
                properties = self.call(name, '/org/mpris/MediaPlayer2',
                    'org.freedesktop.DBus.Properties', 'GetAll',
                    self.GLib.Variant('(s)', ('org.mpris.MediaPlayer2.Player',)))[0]
                if properties.get('PlaybackStatus') == 'Playing':
                    playing.append((name, properties.get('Metadata', {})))
            except Exception:
                continue  # Player disappeared during the query.
        if not playing:
            return False, ''
        name, metadata = next((p for p in playing if p[0] == self.selected), playing[0])
        self.selected = name
        art = metadata.get('mpris:artUrl', '')
        if not art:
            match = re.search(r'(?:[?&]v=|youtu\.be/|/shorts/)([A-Za-z0-9_-]{11})', metadata.get('xesam:url', ''))
            if match:
                art = 'https://i.ytimg.com/vi/' + match[1] + '/mqdefault.jpg'
        return True, art


def main():
    args = argparse.ArgumentParser()
    args.add_argument('--stop-delay', type=int, default=600)
    options = args.parse_args()
    stopped = False
    parent = os.getppid()
    def stop(*_):
        nonlocal stopped
        stopped = True
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    def ipc(method, *values):
        result = subprocess.run(['qs', '-c', 'sekaipop', 'ipc', 'call', 'theme', method, *values],
                                capture_output=True, text=True, timeout=2)
        if result.returncode or result.stdout.strip() != 'ok':
            raise RuntimeError('Theme bridge unavailable: ' + result.stderr.strip() + result.stdout.strip())
    mpris = Mpris()
    pool = ThreadPoolExecutor(max_workers=2)
    session = Session(ipc, pool.submit, max(0, min(options.stop_delay, 2000)) / 1000)
    last_status = ''
    last_error = ''
    try:
        while not stopped and os.getppid() == parent:
            try:
                playing, url = mpris.read()
                session.tick(playing, url, time.monotonic())
                status = ('Цвета обложки активны' if session.active else 'Загрузка обложки…') if playing and url else ('У трека нет обложки' if playing else 'Ожидание музыки — исходная палитра')
                if status != last_status or last_error:
                    print(json.dumps({"active": session.active, "playing": playing, "message": status}, ensure_ascii=False), flush=True)
                    last_status = status
                last_error = ''
            except Exception as error:
                if str(error) != last_error:
                    print(str(error), file=sys.stderr, flush=True)
                    last_error = str(error)
                # A transient D-Bus/IPC error must not replace the user's
                # colours. The next poll reconciles the current track again.
                # If communication stays broken, the shell lease still expires.
            time.sleep(.2)
    finally:
        try:
            session.clear()
        finally:
            pool.shutdown(wait=False, cancel_futures=True)

if __name__ == '__main__':
    main()
