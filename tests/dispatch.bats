#!/usr/bin/env bats
# Routing in the generated mdpreview-dispatch, and its agreement with filetypes.py.

bats_require_minimum_version 1.5.0

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  DISPATCH=$ROOT/mdpreview-dispatch
  FIXTURES=$BATS_TEST_DIRNAME/fixtures
  STUBS=$BATS_TEST_TMPDIR/stubs
  mkdir -p "$STUBS"
  printf '#!/bin/sh\necho "mdpreview $*"\n' > "$STUBS/mdpreview-ok"
  printf '#!/bin/sh\necho partial; echo boom >&2; exit 1\n' > "$STUBS/mdpreview-fail"
  printf '#!/bin/sh\necho "bat $*"\n' > "$STUBS/bat"
  chmod +x "$STUBS"/*
}

route() {
  run "$DISPATCH" --print "$1"
}

@test "generated script is current with filetypes.json and bat" {
  run diff <("$ROOT/gen-dispatch" --output -) "$DISPATCH"
  [ "$status" -eq 0 ]
}

@test "every filetype entry has a fixture that routes to it" {
  missing=$(python3 -c '
import sys; sys.path.insert(0, sys.argv[1]); import filetypes
print(" ".join(e["filetype"] for e in filetypes.load()))' "$ROOT")
  for filetype in $missing; do
    [ -d "$FIXTURES/$filetype" ] || { echo "no fixture directory for $filetype"; return 1; }
  done
}

@test "fixtures route to the filetype named by their directory" {
  while IFS= read -r file; do
    expected=${file#"$FIXTURES"/}
    expected=${expected%%/*}
    case $expected in bat | reference) continue ;; esac  # reference/: Markdown documents, not a filetype
    case $file in */plain.html | */nochart/* | */Chart.yaml) continue ;; esac
    route "$file"
    [ "$status" -eq 0 ] || { echo "$file: not routed"; return 1; }
    [ "$output" = "$expected" ] || { echo "$file: got $output, expected $expected"; return 1; }
  done < <(find "$FIXTURES" -type f | sort)
}

@test "Markdown extensions match case-insensitively" {
  cp "$FIXTURES/markdown/sample.md" "$BATS_TEST_TMPDIR/UPPER.MD"
  route "$BATS_TEST_TMPDIR/UPPER.MD"
  [ "$output" = markdown ]
}

@test "relative paths match path globs" {
  cd "$FIXTURES/kitty"
  route kitty/kitty.conf
  [ "$output" = kitty ]
  cd "$FIXTURES/helm/chart"
  route templates/deployment.yaml
  [ "$output" = helm ]
}

@test "helm needs Chart.yaml above templates/" {
  route "$FIXTURES/helm/nochart/templates/plain.yaml"
  [ "$status" -eq 1 ]
}

@test "html without Django tags goes to bat" {
  route "$FIXTURES/htmldjango/plain.html"
  [ "$status" -eq 1 ]
}

@test "names bat claims go to bat even when a glob matches" {
  route "$FIXTURES/bat/nginx/nginx.conf"
  [ "$status" -eq 1 ]
}

@test "prefer_over_bat entries win over bat's patterns" {
  route "$FIXTURES/systemd/app.service"
  [ "$output" = systemd ]
  route "$FIXTURES/markdown/sample.md"
  [ "$output" = markdown ]
}

@test "languages bat has go to bat" {
  route "$FIXTURES/bat/script.py"
  [ "$status" -eq 1 ]
}

@test "missing files and directories go to bat" {
  route "$BATS_TEST_TMPDIR/missing.md"
  [ "$status" -eq 1 ]
  mkdir "$BATS_TEST_TMPDIR/dir.md"
  route "$BATS_TEST_TMPDIR/dir.md"
  [ "$status" -eq 1 ]
}

@test "filenames with spaces and leading dashes" {
  cp "$FIXTURES/markdown/sample.md" "$BATS_TEST_TMPDIR/-a b.md"
  MDPREVIEW=$STUBS/mdpreview-ok BAT=$STUBS/bat run "$DISPATCH" "$BATS_TEST_TMPDIR/-a b.md"
  [ "$output" = "mdpreview --all --paging=never --budget=2 --filetype markdown -- $BATS_TEST_TMPDIR/-a b.md" ]
}

@test "routed files call mdpreview with the filetype" {
  MDPREVIEW=$STUBS/mdpreview-ok BAT=$STUBS/bat run "$DISPATCH" "$FIXTURES/tmux/.tmux.conf"
  [ "$status" -eq 0 ]
  [ "$output" = "mdpreview --all --paging=never --budget=2 --filetype tmux -- $FIXTURES/tmux/.tmux.conf" ]
}

@test "other files go to bat" {
  MDPREVIEW=$STUBS/mdpreview-ok BAT=$STUBS/bat run "$DISPATCH" "$FIXTURES/bat/script.py"
  [ "$output" = "bat --color=always --paging=never -- $FIXTURES/bat/script.py" ]
}

@test "mdpreview failure falls back to bat and hides mdpreview stderr" {
  MDPREVIEW=$STUBS/mdpreview-fail BAT=$STUBS/bat run --separate-stderr "$DISPATCH" "$FIXTURES/kdl/config.kdl"
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "bat --color=always --paging=never -- $FIXTURES/kdl/config.kdl" ]
  [ -z "$stderr" ]
}

@test "missing mdpreview falls back to bat" {
  MDPREVIEW=$BATS_TEST_TMPDIR/none BAT=$STUBS/bat run "$DISPATCH" "$FIXTURES/kdl/config.kdl"
  [ "$output" = "bat --color=always --paging=never -- $FIXTURES/kdl/config.kdl" ]
}

@test "usage errors" {
  run "$DISPATCH"
  [ "$status" -eq 2 ]
  run "$DISPATCH" a b
  [ "$status" -eq 2 ]
}

@test "filetypes.py agrees with the script on every routed fixture" {
  while IFS= read -r file; do
    route "$file"
    [ "$status" -eq 0 ] || continue
    expected=$output
    actual=$(python3 -c '
import sys; sys.path.insert(0, sys.argv[1]); import filetypes
entry = filetypes.detect(sys.argv[2]); print(entry["filetype"] if entry else "")' "$ROOT" "$file")
    [ "$actual" = "$expected" ] || { echo "$file: python $actual, bash $expected"; return 1; }
  done < <(find "$FIXTURES" -type f | sort)
}

@test "routing is fast" {
  start=$(date +%s%N)
  for _ in 1 2 3 4 5 6 7 8 9 10; do "$DISPATCH" --print "$FIXTURES/conf/app.conf" >/dev/null; done
  elapsed=$(( ($(date +%s%N) - start) / 10000000 ))
  echo "average ${elapsed}ms"
  [ "$elapsed" -lt 20 ]
}
