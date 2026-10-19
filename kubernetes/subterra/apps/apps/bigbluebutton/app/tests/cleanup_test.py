"""Run with: python3 -B -m unittest discover -s tests -p '*_test.py'."""
import contextlib
import fcntl
import importlib.util
import io
import os
from pathlib import Path
import shutil
import tempfile
import time
import unittest

script = Path(os.environ.get("BBB_CLEANUP_SCRIPT", str(Path(__file__).resolve().parents[1] / "scripts/cleanup.py")))
spec = importlib.util.spec_from_file_location("cleanup", script)
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


class CleanupTest(unittest.TestCase):
    recording_id = "a" * 40 + "-1000"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.now = time.time()
        for section in ("deleted/summary", "deleted/presentation", "recording/raw", "recording/process/summary", "recording/summary"):
            path = self.root / section / self.recording_id
            path.mkdir(parents=True)
            (path / "synthetic.txt").write_text("Synthetic fixture")
            if section.startswith("deleted/"):
                (path / "metadata.xml").write_text(f"<recording><id>{self.recording_id}</id><state>deleted</state></recording>")
        self.lock = self.root / "recording/summary" / self.recording_id / "lock"
        self.lock.touch()
        for path in (self.root, *self.root.rglob("*")):
            os.utime(path, (self.now - 3 * 86400,) * 2)

    def run_cleanup(self, apply=True):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            cleanup.Cleanup(self.root, days=1, apply=apply, now=self.now).run()
        return output.getvalue()

    def remains(self):
        return (self.root / "recording/raw" / self.recording_id).exists()

    def test_dry_run_and_purge_remove_all_matching_artifacts(self):
        self.assertIn("Would purge", self.run_cleanup(apply=False))
        self.assertTrue(self.remains())
        self.run_cleanup()
        self.assertFalse(self.remains())
        self.assertFalse(self.lock.parent.exists())
        self.assertFalse((self.root / "deleted/summary" / self.recording_id).exists())
        self.assertFalse((self.root / "deleted/presentation" / self.recording_id).exists())
        self.assertFalse((self.root / "recording/process/summary" / self.recording_id).exists())
        self.run_cleanup()

    def test_recent_deletion_uses_metadata_time(self):
        os.utime(self.root / "deleted/summary" / self.recording_id / "metadata.xml", (self.now,) * 2)
        self.run_cleanup()
        self.assertTrue(self.remains())

    def test_recent_processing_activity_is_preserved(self):
        os.utime(self.root / "recording/raw" / self.recording_id / "synthetic.txt", (self.now,) * 2)
        self.run_cleanup()
        self.assertTrue(self.remains())

    def test_available_formats_are_preserved(self):
        for section in ("published/video", "unpublished/video"):
            with self.subTest(section=section):
                path = self.root / section / self.recording_id
                path.mkdir(parents=True)
                self.run_cleanup()
                self.assertTrue(self.remains())
                path.rmdir()

    def test_locked_summary_is_preserved(self):
        with self.lock.open("r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            self.assertIn("worker is active", self.run_cleanup())
            self.assertTrue(self.remains())

    def test_symlinks_and_unrelated_recordings_are_preserved(self):
        unrelated = self.root / "recording/raw" / ("b" * 40 + "-1000")
        unrelated.mkdir()
        (self.lock.parent / "link").symlink_to(unrelated, target_is_directory=True)
        self.run_cleanup()
        self.assertTrue(self.remains())
        self.assertTrue(unrelated.exists())

    def test_invalid_identifiers_are_ignored(self):
        invalid = self.root / "deleted/summary/not-a-recording"
        invalid.mkdir()
        self.run_cleanup()
        self.assertTrue(invalid.exists())
        self.assertFalse(self.remains())

    def test_symlinked_storage_and_zero_day_retention_are_rejected(self):
        with self.assertRaises(ValueError):
            cleanup.Cleanup(self.root, days=0)
        shutil.rmtree(self.root / "published", ignore_errors=True)
        (self.root / "published").symlink_to(self.root / "deleted")
        with self.assertRaises(ValueError):
            self.run_cleanup()
        self.assertTrue(self.remains())


if __name__ == "__main__":
    unittest.main()
