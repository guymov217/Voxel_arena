"""Contract tests for the trailer's failure gates and event-based edit/audio clocks.

Run: python -m unittest discover -s tools -p 'test_trailer*.py'
"""
import unittest
from types import SimpleNamespace
from unittest.mock import patch

import numpy as np
import make_trailer75 as film


class TrailerContracts(unittest.TestCase):
    def source(self, duration=12, name="shot"):
        return SimpleNamespace(fps=120.0, dur=duration, path=name + ".avi")

    def meta(self, seconds=12):
        return {"rec0": 0, "end": int(seconds * 120), "seconds": seconds,
                "key": 2.0, "marks": {}, "hits": [], "take": 11}

    def test_exact_timeline_and_frame_grid(self):
        for fps in (30, 60):
            with patch.object(film, "FPS", fps):
                film.validate_plan()
                self.assertEqual(sum(round((s[2] - s[1]) * fps) for s in film.SHOTS), 75 * fps)

    def test_missing_footage_stops_export(self):
        with self.assertRaisesRegex(ValueError, "missing recording"):
            film.cut({}, {})

    def test_missing_event_stops_export(self):
        with self.assertRaisesRegex(ValueError, "no MARK"):
            film.piece(self.source(), self.meta(), ("mark", "free", 0.3), 2)

    def test_short_tail_never_freezes(self):
        with self.assertRaisesRegex(ValueError, "freeze frames are forbidden"):
            film.piece(self.source(3), self.meta(3), ("t", 2.5), 2)

    def test_short_lead_never_shows_setup(self):
        meta = self.meta()
        meta["rec0"] = 240
        meta["key"] = 0.1
        with self.assertRaisesRegex(ValueError, "scene setup"):
            film.piece(self.source(), meta, ("key", 1.0), 2)

    def test_event_must_be_inside_used_footage(self):
        meta = self.meta()
        meta["marks"] = {"lodged": 1.0, "free": 8.0}
        seg = film.piece(self.source(), meta, ("t", 0.5), 4)
        with self.assertRaisesRegex(ValueError, "free is outside"):
            film.require_visible(13, seg, meta)

    def test_mixed_camera_seeds_and_drift_rejected(self):
        a, b = self.meta(), self.meta()
        b["take"] = 12
        with self.assertRaisesRegex(ValueError, "mixed takes"):
            film.check_continuity(["1", "3"], {"1": a, "3": b})
        b["take"] = 11
        b["key"] += 0.1
        with self.assertRaisesRegex(ValueError, "continuity drift"):
            film.check_continuity(["1", "3"], {"1": a, "3": b})

    def test_speed_ramp_contact_matches_picture(self):
        meta = self.meta()
        meta["hits"] = [{"t": 2.0, "J": 80}]
        seg = film.piece(self.source(name="hit"), meta, ("key", 0.7), 2,
                         [(-0.05, 0.35), (0.2, 0.35), (0.4, 1.0)])
        cues = film.contact_accents([seg], {"hit": meta})
        self.assertEqual(len(cues), 1)
        self.assertAlmostEqual(cues[0], 0.7, delta=1.0 / film.FPS)

    def test_music_yields_for_comedy_then_recovers(self):
        g = film.music_envelope(int(film.LENGTH * film.ed.AR))
        self.assertLess(g[int(30 * film.ed.AR)], 0.1)
        self.assertLess(g[int(68 * film.ed.AR)], 0.1)
        self.assertAlmostEqual(g[int(34 * film.ed.AR)], 1.0)
        self.assertEqual(g[-1], 0.0)
        self.assertTrue(np.isfinite(g).all())

    def test_parser_handles_spaces_and_scene_duration(self):
        meta = film.tags_of(["REC_START 240", "KEY 100 0.833", "MARK 110 0.917 combo return",
                            "SCENE_END 6.000", "REC_END 720"])
        self.assertEqual(meta["rec0"], 240)
        self.assertEqual(meta["marks"]["combo return"], 0.917)
        self.assertEqual(meta["seconds"], 6.0)


if __name__ == "__main__":
    unittest.main()
