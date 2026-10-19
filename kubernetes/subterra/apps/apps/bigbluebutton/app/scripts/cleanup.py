"""Purge BBB recordings deleted and inactive for the retention period.

Dry-run by default. BBB rewrites metadata.xml on deletion; folder timestamps
can still be the original recording date. No external packages are required.
"""
import argparse
import contextlib
import fcntl
import os
from pathlib import Path
import re
import shutil
import time
import xml.etree.ElementTree as ET

ID = re.compile(r"[0-9a-f]{40}-\d+")
FORMAT = re.compile(r"[a-zA-Z0-9_-]+")


class Cleanup:
    def __init__(self, root, days=1, apply=False, now=None):
        self.root = Path(os.path.abspath(root))
        if days < 1:
            raise ValueError("Retention must be at least one day")
        if not self.root.is_dir() or self.root.resolve() != self.root or self.root == Path("/"):
            raise ValueError("Root must be a real directory")
        self.cutoff = (time.time() if now is None else now) - days * 86400
        self.apply = apply

    def formats(self, section):
        base = self.root / section
        if base.is_symlink():
            raise ValueError(f"Unsafe storage path: {section}")
        return [p for p in base.iterdir() if FORMAT.fullmatch(p.name) and p.is_dir() and not p.is_symlink()] if base.is_dir() else []

    def paths(self, section, recording_id):
        return [p / recording_id for p in self.formats(section) if os.path.lexists(p / recording_id)]

    def available(self, recording_id):
        return self.paths("published", recording_id) + self.paths("unpublished", recording_id)

    def old_safe_tree(self, path):
        if not os.path.lexists(path):
            return True
        for parent in (path, *path.parents):
            if parent == self.root:
                break
            if parent.is_symlink():
                return False
        entries = [path]
        if path.is_dir():
            for parent, dirs, files in os.walk(path, followlinks=False):
                entries.extend(Path(parent) / name for name in dirs + files)
        return all(not p.is_symlink() and p.stat().st_mtime <= self.cutoff for p in entries)

    @staticmethod
    def remove(path):
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink(missing_ok=True)

    def run(self):
        for section in ("deleted", "published", "unpublished", "recording", "recording/raw", "recording/process", "recording/publish", "recording/status", "recording/summary", "captions"):
            if (self.root / section).is_symlink():
                raise ValueError(f"Unsafe storage path: {section}")
        ids = sorted({p.name for folder in self.formats("deleted") for p in folder.iterdir() if ID.fullmatch(p.name)})
        print(f"Scan {len(ids)} deleted recordings ({'apply' if self.apply else 'dry-run'})", flush=True)
        for recording_id in ids:
            self.clean(recording_id)

    def clean(self, recording_id):
        deleted = self.paths("deleted", recording_id)
        if not deleted or self.available(recording_id):
            return
        for path in deleted:
            metadata = path / "metadata.xml"
            if not metadata.is_file() or metadata.is_symlink() or metadata.stat().st_mtime > self.cutoff:
                return
            xml = ET.parse(metadata).getroot()
            if xml.tag != "recording" or xml.findtext("id") != recording_id or xml.findtext("state") != "deleted":
                return
        cache = self.root / "recording/summary" / recording_id
        paths = [self.root / "recording/raw" / recording_id, cache, self.root / "captions" / recording_id, self.root / recording_id]
        for section in ("recording/process", "recording/publish"):
            paths.extend(self.paths(section, recording_id))
        status_name = re.compile(re.escape(recording_id) + r"(?:-[a-zA-Z0-9_-]+)?\.(?:done|fail|norecord)")
        for stage in self.formats("recording/status"):
            paths.extend(p for p in stage.iterdir() if status_name.fullmatch(p.name))
        if not all(self.old_safe_tree(p) for p in paths + deleted):
            print(f"Skip {recording_id}: recent activity or unsafe path", flush=True)
            return
        with contextlib.ExitStack() as stack:
            lock_path = cache / "lock"
            lock = stack.enter_context(lock_path.open("r+")) if lock_path.is_file() else None
            if lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    print(f"Skip {recording_id}: summary worker is active", flush=True)
                    return
            if self.available(recording_id):
                return
            print(f"{'Purge' if self.apply else 'Would purge'} {recording_id} ({len(deleted)} deleted formats plus processing cache)", flush=True)
            if not self.apply:
                return
            # Tombstones remain until the other files are removed, allowing retry.
            for path in dict.fromkeys(paths):
                if path != cache:
                    self.remove(path)
            # Close the NFS lock before removing its directory. Raw inputs are
            # already gone, so a new summary attempt cannot proceed.
            if lock:
                lock.close()
            self.remove(cache)
            for path in deleted:
                self.remove(path)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default="/var/bigbluebutton")
    parser.add_argument("--days", type=int, default=int(os.environ.get("BBB_DELETED_RETENTION_DAYS", "1")))
    parser.add_argument("--apply", action="store_true")
    Cleanup(**vars(parser.parse_args())).run()
