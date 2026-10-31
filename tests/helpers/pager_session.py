#!/usr/bin/python3
"""Drive mdpreview's built-in Neovim pager in a pseudo-terminal.

Usage: pager_session.py SCENARIO FILE [MDPREVIEW-ARGS...]
FILE "-" sends the file named by $STDIN_FILE on mdpreview's stdin. The document must be taller than the 20-row terminal and contain the markers PAGER_TOP (a level-one heading on the
first line), PAGER_MIDDLE, and PAGER_BOTTOM (on the last line). Scenarios:
  keys    first screen shows the rendered heading, not '# PAGER_TOP'; G reaches PAGER_BOTTOM; g g returns to
          the top; /PAGER_MIDDLE finds it; space pages down; q exits 0
  resize  a narrower terminal makes Neovim redraw; q still exits 0
  term    SIGTERM to mdpreview while the pager is open exits 130
  hup     SIGHUP to mdpreview while the pager is open exits non-zero
Every scenario also checks that no Neovim started by this checkout outlives mdpreview.
Prints "ok" on success; otherwise the reason and the tail of the screen output, and exits 1.
"""

import fcntl
import os
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

from common import ROOT, embedded_nvims

ROWS, COLUMNS = 20, 80
scenario, path, *extra = sys.argv[1:]
baseline = embedded_nvims()
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLUMNS, 0, 0))


def session():
  os.setsid()
  fcntl.ioctl(slave, termios.TIOCSCTTY, 0)


environment = dict(os.environ, TERM="xterm-256color", COLORTERM="truecolor")
for name in ["NVIM", "FZF_PREVIEW_COLUMNS", "FZF_PREVIEW_LINES"]:
  environment.pop(name, None)
# FILE "-" reads the document from $STDIN_FILE on a pipe, so keys must come from /dev/tty.
document = open(os.environ["STDIN_FILE"], "rb") if path == "-" else slave
process = subprocess.Popen([str(ROOT / "mdpreview"), "--pager", "nvim", *extra, path], env=environment,
                           stdin=document, stdout=slave, stderr=slave, preexec_fn=session)
os.close(slave)
captured = bytearray()
answered = {}
# Terminal queries Neovim's TUI sends at start-up; answering them avoids its "did not respond" warnings.
ANSWERS = {b"\x1b]11;?": b"\x1b]11;rgb:0000/0000/0000\x1b\\", b"\x1b[c": b"\x1b[?62;22c",
           b"\x1b[5n": b"\x1b[0n", b"\x1b[6n": b"\x1b[1;1R"}


def plain(data):
  text = re.sub(rb"\x1b\][^\x07\x1b]*(\x07|\x1b\\)", b"", bytes(data))
  text = re.sub(rb"\x1b\[[0-9;?<>=! ]*[a-zA-Z@`~]", b" ", text)
  return re.sub(rb"\x1b.", b"", text).decode(errors="replace")


def read(timeout):
  if not select.select([master], [], [], timeout)[0]:
    return True
  try:
    chunk = os.read(master, 65536)
  except OSError:
    return False
  captured.extend(chunk)
  for query, answer in ANSWERS.items():
    # Count in everything read so far: a query can be split across reads.
    if captured.count(query) > answered.get(query, 0):
      answered[query] = captured.count(query)
      os.write(master, answer)
  return bool(chunk)


def fail(reason):
  print(reason)
  print(plain(captured)[-1500:])
  if process.poll() is None:
    process.kill()
  sys.exit(1)


def until(marker, start, what, timeout=15):
  deadline = time.monotonic() + timeout
  while marker not in plain(captured[start:]):
    if time.monotonic() > deadline or not read(0.1):
      fail(f"timed out waiting for {what}")


def quiet(seconds=0.4):
  """Read until the terminal has been idle for the given time."""
  last = time.monotonic()
  while time.monotonic() - last < seconds:
    size = len(captured)
    if not read(0.05):
      return
    if len(captured) != size:
      last = time.monotonic()


def press(keys):
  start = len(captured)
  os.write(master, keys.encode())
  return start


def finish(expected):
  deadline = time.monotonic() + 10
  while process.poll() is None:
    if time.monotonic() > deadline:
      fail("mdpreview did not exit")
    read(0.1)
  if not expected(process.returncode):
    fail(f"unexpected exit status {process.returncode}")
  deadline = time.monotonic() + 5
  while embedded_nvims() - baseline:
    if time.monotonic() > deadline:
      fail(f"Neovim left running: {sorted(embedded_nvims() - baseline)}")
    time.sleep(0.05)


until("PAGER_TOP", 0, "the first screen")
quiet()
first = plain(captured)
if "# PAGER_TOP" in first:
  fail("the cursor line shows raw Markdown (anti_conceal)")
if "PAGER_BOTTOM" in first:
  fail("the bottom marker is on the first screen; the file is too short")

if scenario == "keys":
  until("PAGER_BOTTOM", press("G"), "G to reach the bottom")
  quiet()
  until("PAGER_TOP", press("gg"), "gg to return to the top")
  quiet()
  until("PAGER_MIDDLE", press("/PAGER_MIDDLE\r"), "a search")
  quiet()
  press("gg")
  quiet()
  start = press(" ")
  quiet()
  if "PAGER_TOP" in plain(captured[start:]) or len(captured) == start:
    fail("space did not page down")
  press("q")
  finish(lambda status: status == 0)
elif scenario == "resize":
  start = len(captured)
  fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, 40, 0, 0))
  process.send_signal(signal.SIGWINCH)
  quiet(0.8)
  if len(captured) == start:
    fail("no redraw after the terminal was resized")
  press("q")
  finish(lambda status: status == 0)
elif scenario == "term":
  process.send_signal(signal.SIGTERM)
  finish(lambda status: status == 130)
elif scenario == "hup":
  process.send_signal(signal.SIGHUP)
  finish(lambda status: status != 0)
else:
  fail(f"unknown scenario {scenario}")
print("ok")
