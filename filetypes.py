"""Filetype table shared by nvcat and gen-dispatch; see filetypes.json."""

from fnmatch import fnmatchcase
import json
import os
from pathlib import Path
import re

TABLE = Path(__file__).resolve().parent / "filetypes.json"
HEAD_LINES = 40


def load(table=TABLE):
  with open(table, encoding="utf-8") as handle:
    return json.load(handle)["filetypes"]


def globs(entry):
  """Bash case patterns for an entry, matched case-insensitively against an absolute path."""
  patterns = [f"*.{extension}" for extension in entry.get("extensions", [])]
  for name in entry.get("names", []):
    patterns += [name, f"*/{name}"]
  patterns += entry.get("paths", [])
  return patterns


def requirement_met(entry, path):
  requires = entry.get("requires", {})
  if "ancestor_file" in requires:
    if "/templates/" not in path:
      return False
    if not os.path.isfile(path.rsplit("/templates/", 1)[0] + "/" + requires["ancestor_file"]):
      return False
  if "head_regex" in requires:
    pattern = re.compile(requires["head_regex"], re.IGNORECASE)
    try:
      with open(path, encoding="utf-8", errors="replace") as handle:
        head = [line for _, line in zip(range(HEAD_LINES), handle)]
    except OSError:
      return False
    if not any(pattern.search(line) for line in head):
      return False
  return True


def absolute(path):
  path = os.fspath(path)
  return path if path.startswith("/") else os.path.join(os.getcwd(), path)


def detect(path, entries=None):
  """Return the first table entry matching path, mirroring the generated nvcat-dispatch."""
  path = absolute(path)
  folded = path.lower()
  for entry in load() if entries is None else entries:
    if any(fnmatchcase(folded, pattern.lower()) for pattern in globs(entry)) and requirement_met(entry, path):
      return entry
  return None


def find(filetype, entries=None):
  for entry in load() if entries is None else entries:
    if entry["filetype"] == filetype:
      return entry
  return None
