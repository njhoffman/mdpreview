#!/usr/bin/env bats
# Ported from the historical verify.py: document tails, viewports, unusual names, stdin, empty files,
# modelines, errors, terminal round trip, cancellation, source immutability, and the write sandbox.

bats_require_minimum_version 1.5.0

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  MDPREVIEW=$ROOT/mdpreview
  REFERENCE=$BATS_TEST_DIRNAME/fixtures/reference
  HELPERS=$BATS_TEST_DIRNAME/helpers
}

plain() {
  sed 's/\x1b\[[0-9;]*m//g' <<<"$1"
}

@test "complete output includes each reference document's first and last lines" {
  for name in syntax tables extended; do
    upper=$(tr a-z A-Z <<<"$name")
    for width in 80 120; do
      run --separate-stderr "$MDPREVIEW" --paging=never --columns "$width" --all "$REFERENCE/$name.md"
      [ "$status" -eq 0 ] || { echo "$name $width: $stderr"; return 1; }
      text=$(plain "$output")
      [[ $text == *"REFERENCE_${upper}_TOP"* ]] || { echo "$name $width: top missing"; return 1; }
      [[ $text == *"REFERENCE_${upper}_BOTTOM"* ]] || { echo "$name $width: tail missing"; return 1; }
    done
  done
}

@test "viewports never exceed the requested height" {
  for name in syntax tables extended; do
    for size in 80x24 120x40 40x5; do
      run "$MDPREVIEW" --paging=never --columns "${size%x*}" --lines "${size#*x}" "$REFERENCE/$name.md"
      [ "$status" -eq 0 ]
      [ "${#lines[@]}" -le "${size#*x}" ] || { echo "$name $size: ${#lines[@]} lines"; return 1; }
    done
  done
}

@test "literal filenames with spaces, pipes, hashes, percents and brackets, plus Unicode" {
  special="$BATS_TEST_TMPDIR/name with spaces | # % [brackets].md"
  printf '# Unicode preview\n\n日本語 café e\xcc\x81 🙂\n\nEND_UNICODE\n' > "$special"
  run --separate-stderr "$MDPREVIEW" --paging=never --columns 80 "$special"
  [ "$status" -eq 0 ]
  text=$(plain "$output")
  [[ $text == *$'日本語 café e\xcc\x81 🙂'* ]]
  [[ $text == *END_UNICODE* ]]
}

@test "finite stdin with Unicode" {
  run --separate-stderr bash -c "printf '# Stdin\n\n日本語 🙂\n\nEND_STDIN\n' | '$MDPREVIEW' --paging=never --columns 80 -"
  [ "$status" -eq 0 ]
  [[ $(plain "$output") == *'日本語 🙂'*END_STDIN* ]]
}

@test "an empty file renders as nothing" {
  : > "$BATS_TEST_TMPDIR/empty.md"
  run --separate-stderr "$MDPREVIEW" --paging=never --columns 80 "$BATS_TEST_TMPDIR/empty.md"
  [ "$status" -eq 0 ]
  [ -z "$(plain "$output" | tr -d '[:space:]')" ]
}

@test "modelines are not executed" {
  marker=$BATS_TEST_TMPDIR/MODELINE_EXECUTED
  printf 'SAFE\n<!-- vim: set modelineexpr foldmethod=expr foldexpr=system("touch %s"): -->\n' "$marker" \
    > "$BATS_TEST_TMPDIR/modeline.md"
  run "$MDPREVIEW" --paging=never --columns 80 "$BATS_TEST_TMPDIR/modeline.md"
  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
}

@test "errors are reported without a traceback" {
  run "$MDPREVIEW" --paging=never "$BATS_TEST_TMPDIR/missing.md"
  [ "$status" -eq 1 ]
  [[ $output == mdpreview:* ]]
  [[ $output != *Traceback* ]]
  run "$MDPREVIEW" --paging=never --columns 80 --start-line 99999 "$REFERENCE/syntax.md"
  [ "$status" -eq 1 ]
  [[ $output != *Traceback* ]]
  mkdir "$BATS_TEST_TMPDIR/dir.md"
  run "$MDPREVIEW" --paging=never "$BATS_TEST_TMPDIR/dir.md"
  [ "$status" -eq 1 ]
  [[ $output != *Traceback* ]]
}

@test "ANSI output round-trips through Neovim's terminal emulator" {
  special="$BATS_TEST_TMPDIR/unicode.md"
  printf '# Unicode preview\n\n日本語 café e\xcc\x81 🙂\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nEND_UNICODE\n' > "$special"
  run python3 "$HELPERS/roundtrip.py" "$special" END_UNICODE
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run python3 "$HELPERS/roundtrip.py" "$REFERENCE/tables.md" REFERENCE_TABLES_BOTTOM
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
}

nvims() {
  python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from common import embedded_nvims; print(" ".join(map(str, sorted(embedded_nvims()))))' "$HELPERS"
}

cancel_during_render() {
  local signal=$1 before after pid
  before=$(nvims)
  "$MDPREVIEW" --paging=never --columns 100 --all --budget 0 "$ROOT/benchmarks/large.md" >/dev/null 2>&1 &
  pid=$!
  for _ in $(seq 1 100); do
    [ "$(nvims)" != "$before" ] && break
    sleep 0.05
  done
  [ "$(nvims)" != "$before" ] || { echo "no embedded Neovim observed"; return 1; }
  kill -s "$signal" "$pid"
  wait "$pid" 2>/dev/null || true
  for _ in $(seq 1 60); do
    after=$(nvims)
    [ "$after" = "$before" ] && return 0
    sleep 0.05
  done
  echo "embedded Neovim left after SIG$signal: before [$before] after [$after]"
  return 1
}

@test "SIGTERM during a render leaves no Neovim behind" {
  cancel_during_render TERM
}

@test "SIGINT during a render leaves no Neovim behind" {
  cancel_during_render INT
}

@test "SIGKILL during a render leaves no Neovim behind" {
  cancel_during_render KILL
}

@test "rendering never modifies the source file" {
  copy=$BATS_TEST_TMPDIR/source.md
  cp "$REFERENCE/syntax.md" "$copy"
  before=$(stat -c '%Y %s' "$copy"; sha256sum < "$copy")
  "$MDPREVIEW" --paging=never --columns 80 "$copy" >/dev/null
  "$MDPREVIEW" --paging=never --columns 80 --lines 10 "$copy" >/dev/null
  after=$(stat -c '%Y %s' "$copy"; sha256sum < "$copy")
  [ "$before" = "$after" ]
}

@test "the write sandbox blocks writes outside /tmp and allows them inside" {
  run python3 - "$ROOT" "$BATS_TEST_TMPDIR" <<'PY'
import os, sys
sys.path.insert(0, sys.argv[1])
from readonly import restrict_writes
restrict_writes()
try:
    os.open(os.path.join(sys.argv[1], "SANDBOX_ESCAPE"), os.O_WRONLY | os.O_CREAT)
    print("escaped")
except PermissionError:
    print("blocked")
inside = os.path.join(sys.argv[2], "inside")
with open(inside, "w") as handle:
    handle.write("ok")
print("tmp ok" if sys.argv[2].startswith("/tmp/") else "tmp skipped")
PY
  [ "${lines[0]}" = blocked ]
  [ ! -e "$ROOT/SANDBOX_ESCAPE" ]
}
