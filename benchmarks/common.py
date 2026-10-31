"""Helpers shared by the benchmark scripts: the load gate, run metadata, and git."""

import datetime
from pathlib import Path
import subprocess
import sys
import time

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def load1():
  return float(Path("/proc/loadavg").read_text().split()[0])


def wait_for_load(limit, max_wait, interval):
  deadline = time.monotonic() + max_wait
  while (current := load1()) > limit:
    if time.monotonic() >= deadline:
      return False
    print(f"load {current:.2f} > {limit:.2f}; waiting {interval:.0f}s", file=sys.stderr, flush=True)
    time.sleep(interval)
  return True


def git(*arguments):
  return subprocess.run(["git", "-C", str(ROOT), *arguments], capture_output=True, text=True).stdout.strip()


def metadata():
  """Date, version, commit (with -dirty for uncommitted tracked changes), load, and the Neovim version."""
  dirty = "-dirty" if git("status", "--porcelain", "--untracked-files=no") else ""
  return {
    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ"),
    "version": (ROOT / "VERSION").read_text().strip(),
    "commit": git("rev-parse", "--short", "HEAD") + dirty,
    "load1": f"{load1():.2f}",
    "nvim": subprocess.run(["nvim", "--version"], capture_output=True, text=True).stdout.splitlines()[0],
  }
