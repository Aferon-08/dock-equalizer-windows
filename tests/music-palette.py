import sys
from pathlib import Path
import unittest
from concurrent.futures import Future
import importlib.util
spec = importlib.util.spec_from_file_location("music_palette", Path(__file__).resolve().parents[1] / "music-palette.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
Session, cover_colors = module.Session, module.cover_colors
from PIL import Image
import tempfile

class SessionTests(unittest.TestCase):
    def setUp(self):
        self.calls, self.jobs = [], []
        def submit(fn, url):
            f = Future()
            f.set_running_or_notify_cancel()
            self.jobs.append((url, f))
            return f
        self.s = Session(lambda *a: self.calls.append(a), submit)

    def start(self, url='a', color='red', now=0):
        self.s.tick(True, url, now)
        self.jobs[-1][1].set_result(color)
        self.s.tick(True, url, now + .1)

    def test_switch_preserves_session_and_original(self):
        self.start()
        owner = self.s.owner
        self.s.tick(False, '', 1)
        self.s.tick(True, 'b', 1.3)  # gap shorter than stopDelay
        self.jobs[-1][1].set_result('blue')
        self.s.tick(True, 'b', 1.4)
        self.assertEqual(self.s.owner, owner)
        self.assertFalse(any(c[0] == 'musicClear' for c in self.calls))
        self.assertEqual(self.calls[-1][2], 'blue')
        self.s.tick(False, '', 2)
        self.s.tick(False, '', 2.7)
        self.assertEqual(self.calls[-1], ('musicClear', owner))

    def test_paused_fetch_cannot_reapply(self):
        self.s.tick(True, 'a', 0)
        self.jobs[-1][1].set_result('red')
        self.s.tick(False, '', 1)
        self.s.tick(False, '', 2)
        self.assertEqual(self.calls, [])

    def test_old_cover_cannot_replace_new(self):
        self.s.tick(True, 'a', 0)
        self.s.tick(True, 'b', .1)
        self.jobs[0][1].set_result('red')
        self.s.tick(True, 'b', .2)
        self.assertEqual(self.calls, [])
        self.jobs[-1][1].set_result('blue')
        self.s.tick(True, 'b', .3)
        self.assertEqual(self.calls[-1][2], 'blue')

    def test_missing_cover_keeps_session_but_disable_restores(self):
        self.start()
        self.s.tick(True, '', 1)
        self.assertTrue(self.s.active)
        self.assertFalse(any(c[0] == 'musicClear' for c in self.calls))
        self.start('b', 'blue', 2)
        self.s.clear()
        self.assertFalse(self.s.active)

    def test_single_color_cover(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'cover.png'
            Image.new('RGB', (20, 20), '#ff0000').save(p)
            self.assertEqual(cover_colors(p.as_uri()).split(','), ['#ff0000'] * 5)

    def test_failure_keeps_palette_and_retries_without_track_change(self):
        self.start()
        self.s.tick(True, 'b', 1)
        self.jobs[-1][1].set_exception(ValueError('bad art'))
        self.s.tick(True, 'b', 1.2)
        self.assertTrue(self.s.active)
        self.assertFalse(any(c[0] == 'musicClear' for c in self.calls))
        count = len(self.jobs)
        self.s.tick(True, 'b', 1.8)
        self.assertEqual(len(self.jobs), count)
        self.s.tick(True, 'b', 2.3)
        self.assertEqual(len(self.jobs), count + 1)
        self.jobs[-1][1].set_result('blue')
        self.s.tick(True, 'b', 2.4)
        self.assertEqual(self.calls[-1][2], 'blue')


    def test_same_colors_after_failed_fetch_clear_diagnostic(self):
        self.start()
        self.s.tick(True, 'b', 1)
        self.jobs[-1][1].set_exception(ValueError('broken cover'))
        self.s.tick(True, 'b', 1.1)
        self.assertIn('broken cover', self.s.error)
        self.s.tick(True, 'b', 2.2)
        self.jobs[-1][1].set_result('red')
        self.s.tick(True, 'b', 2.3)
        self.assertEqual(self.s.palette, 'red')
        self.assertEqual(self.s.error, '')

    def test_rapid_skips_apply_final_cover_without_another_skip(self):
        self.start()
        self.s.tick(True, 'slow-a', .2)
        self.s.tick(True, 'slow-b', .3)
        for i in range(50):
            self.s.tick(True, 'skip-' + str(i), .4 + i * .03)
            self.s.tick(True, '', .41 + i * .03)
        self.assertEqual(len(self.s.jobs), 2)
        self.s.tick(True, 'final', 2)
        self.jobs[1][1].set_result('obsolete-a')
        self.s.tick(True, 'final', 2.1)
        self.assertEqual(self.jobs[-1][0], 'final')
        self.jobs[-1][1].set_result('final-blue')
        self.s.tick(True, 'final', 2.2)
        self.assertEqual(self.calls[-1][2], 'final-blue')
        self.jobs[2][1].set_result('obsolete-b')
        self.s.tick(True, 'final', 2.3)
        self.assertEqual(self.s.palette, 'final-blue')
        self.assertFalse(any(c[0] == 'musicClear' for c in self.calls))
        self.s.tick(False, '', 3)
        self.s.tick(False, '', 3.7)
        self.assertEqual(self.calls[-1][0], 'musicClear')

    def test_empty_art_keeps_lease_alive(self):
        self.start()
        for i in range(1, 20):
            self.s.tick(True, '', i)
            self.assertTrue(self.s.active)
            self.assertEqual(self.calls[-1][0], 'musicSet')
        self.assertFalse(any(c[0] == 'musicClear' for c in self.calls))

    def test_cached_cover_reapplied_after_real_pause(self):
        self.start()
        self.s.tick(False, '', 1)
        self.s.tick(False, '', 2)
        self.assertFalse(self.s.active)
        self.s.tick(True, 'a', 3)
        self.assertTrue(self.s.active)
        self.assertEqual(self.calls[-1][2], 'red')

class ContextInputTests(unittest.TestCase):
    def test_partial_batch_bad_message_and_eof(self):
        import os
        read, write = os.pipe()
        with os.fdopen(read) as stream:
            source = module.ContextInput(stream)
            try:
                os.write(write,b'{"playing":tr')
                self.assertEqual(source.read(),(False,''))
                os.write(write,b'ue,"artUrl":"a"}\n{"playing":false}\n')
                self.assertEqual(source.read(),(False,''))
                os.write(write,b'{"playing":true,"artUrl":"b"}\n')
                self.assertEqual(source.read(),(True,'b'))
                os.write(write,b'not JSON\n')
                self.assertEqual(source.read(),(False,''))
            finally:
                os.close(write)
            source.read()
            self.assertTrue(source.closed)

if __name__ == '__main__':
    unittest.main()
