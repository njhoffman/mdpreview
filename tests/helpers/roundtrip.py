#!/usr/bin/python3
"""Render FILE, feed the ANSI output through Neovim's own terminal emulator, and compare the text.

Usage: roundtrip.py FILE END_MARKER. Exits 1 with a diff-like message when the lines differ.
"""

from pathlib import Path
import re
import shutil
import sys
import tempfile

from common import load_mdpreview

SGR = re.compile(rb"\x1b\[[0-9;:]*m")
module = load_mdpreview()
path, end_marker = str(Path(sys.argv[1]).resolve()), sys.argv[2]
with tempfile.TemporaryDirectory(prefix="mdpreview-roundtrip-") as work:
  renderer = module.Renderer(shutil.which("nvim"), module.find_paths(), work, 80, 24, 8)
  try:
    output, _ = renderer.render(path, 80, 24, all_rows=True)
    expected = [line.rstrip() for line in SGR.sub(b"", output).decode().splitlines()]
    renderer.request("nvim_exec_lua", """local output = ...
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_win_set_buf(0, buf)
      vim.api.nvim_chan_send(vim.api.nvim_open_term(buf, {}), output)
      _G.roundtrip_buffer = buf""", [output.decode()])
    actual = renderer.request("nvim_exec_lua", """local marker = ...
      vim.wait(2000, function()
        return table.concat(vim.api.nvim_buf_get_lines(_G.roundtrip_buffer, 0, -1, false), "\\n"):find(marker, 1, true)
      end, 10)
      return vim.api.nvim_buf_get_lines(_G.roundtrip_buffer, 0, -1, false)""", [end_marker])
  finally:
    renderer.close()
actual = [line.rstrip() for line in actual[:len(expected)]]
if actual != expected:
  for number, (want, got) in enumerate(zip(expected, actual + [""] * len(expected)), 1):
    if want != got:
      print(f"line {number}: expected {want!r}, terminal shows {got!r}")
      break
  sys.exit(1)
print(f"ok {len(expected)} lines")
