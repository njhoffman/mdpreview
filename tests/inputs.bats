#!/usr/bin/env bats
# Input files: Markdown extension aliases in any case, symbolic links, unreadable inputs, empty inputs, and
# a renderer that dies mid-render.

bats_require_minimum_version 1.5.0

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  MDPREVIEW=$ROOT/mdpreview
  FIXTURES=$BATS_TEST_DIRNAME/fixtures
  HELPERS=$BATS_TEST_DIRNAME/helpers
}

# The filetype and engine mdpreview used for a file, from --timings-json.
detected() {
  "$MDPREVIEW" --paging=never --columns 60 --lines 3 --timings-json "$@" 2>&1 >/dev/null |
    python3 -c 'import json, sys; facts = json.loads(sys.stdin.read().splitlines()[-1]); print(facts["filetype"], facts["engine"])'
}

@test "every Markdown extension renders with render-markdown in lower, upper and mixed case" {
  extensions=$(python3 -c 'import json, sys; print(" ".join(next(e for e in json.load(open(sys.argv[1]))["filetypes"] if e["filetype"] == "markdown")["extensions"]))' "$ROOT/filetypes.json")
  [ -n "$extensions" ]
  for extension in $extensions; do
    upper=$(tr a-z A-Z <<<"$extension")
    mixed=$(tr a-z A-Z <<<"${extension:0:1}")${extension:1}
    for name in "doc.$extension" "DOC.$upper" "Doc.$mixed"; do
      cp "$FIXTURES/markdown/sample.md" "$BATS_TEST_TMPDIR/$name"
      result=$(detected "$BATS_TEST_TMPDIR/$name")
      [ "$result" = "markdown render-markdown" ] || { echo "$name: $result"; return 1; }
    done
  done
}

@test "uppercase extensions of other table filetypes are detected" {
  cp "$FIXTURES/kdl/config.kdl" "$BATS_TEST_TMPDIR/CONFIG.KDL"
  [ "$(detected "$BATS_TEST_TMPDIR/CONFIG.KDL" | cut -d' ' -f1)" = kdl ]
}

@test "a symbolic link is detected by its own name first" {
  ln -s "$FIXTURES/ebnf/grammar.ebnf" "$BATS_TEST_TMPDIR/grammar.md"
  [ "$(detected "$BATS_TEST_TMPDIR/grammar.md")" = "markdown render-markdown" ]
}

@test "a symbolic link without a known name is detected by its target" {
  # Neovim does not detect .ebnf, so only the table, applied to the target, finds it.
  ln -s "$FIXTURES/ebnf/grammar.ebnf" "$BATS_TEST_TMPDIR/grammar"
  [ "$(detected "$BATS_TEST_TMPDIR/grammar" | cut -d' ' -f1)" = ebnf ]
}

@test "a chain of symbolic links renders the final target" {
  ln -s "$FIXTURES/markdown/sample.md" "$BATS_TEST_TMPDIR/one.md"
  ln -s "$BATS_TEST_TMPDIR/one.md" "$BATS_TEST_TMPDIR/two"
  run --separate-stderr "$MDPREVIEW" --paging=never --columns 60 "$BATS_TEST_TMPDIR/two"
  [ "$status" -eq 0 ]
  [[ $output == *'Title'* ]]
}

@test "unreadable inputs are named with the reason" {
  cd "$BATS_TEST_TMPDIR"
  ln -s nowhere.md broken.md
  ln -s loop-b loop-a
  ln -s loop-a loop-b
  mkdir directory.md
  for case in "missing.md:no such file" "broken.md:broken symbolic link to nowhere.md" \
              "loop-a:too many levels of symbolic links" "directory.md:not a regular file"; do
    run "$MDPREVIEW" --paging=never --columns 60 "${case%%:*}"
    [ "$status" -eq 1 ]
    [ "$output" = "mdpreview: ${case%%:*}: ${case#*:}" ] || { echo "$output"; return 1; }
  done
}

@test "a file without read permission is named" {
  [ "$(id -u)" -ne 0 ] || skip "root reads any file"
  printf '# x\n' > "$BATS_TEST_TMPDIR/secret.md"
  chmod 000 "$BATS_TEST_TMPDIR/secret.md"
  run "$MDPREVIEW" --paging=never --columns 60 "$BATS_TEST_TMPDIR/secret.md"
  [ "$status" -eq 1 ]
  [ "$output" = "mdpreview: $BATS_TEST_TMPDIR/secret.md: permission denied" ]
}

@test "empty inputs render as nothing in every mode" {
  : > "$BATS_TEST_TMPDIR/empty.kdl"
  : > "$BATS_TEST_TMPDIR/empty.md"
  for arguments in "$BATS_TEST_TMPDIR/empty.kdl" "--lines 5 $BATS_TEST_TMPDIR/empty.md" \
                   "--all $BATS_TEST_TMPDIR/empty.md"; do
    run --separate-stderr "$MDPREVIEW" --paging=never --columns 60 $arguments
    [ "$status" -eq 0 ] && [ -z "$stderr" ] || { echo "$arguments: $status $stderr"; return 1; }
    [ -z "$(sed 's/\x1b\[[0-9;]*m//g' <<<"$output" | tr -d '[:space:]')" ]
  done
  run --separate-stderr bash -c "'$MDPREVIEW' --paging=never --columns 60 - < /dev/null"
  [ "$status" -eq 0 ]
  [ -z "$(sed 's/\x1b\[[0-9;]*m//g' <<<"$output" | tr -d '[:space:]')" ]
}

@test "a Neovim killed mid-render is reported, not hung on" {
  before=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from common import embedded_nvims; print(" ".join(map(str, sorted(embedded_nvims()))))' "$HELPERS")
  "$MDPREVIEW" --paging=never --columns 100 --all --budget 0 "$ROOT/benchmarks/large.md" \
    > /dev/null 2> "$BATS_TEST_TMPDIR/stderr" &
  pid=$!
  victim=
  for _ in $(seq 1 100); do
    victim=$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from common import embedded_nvims; before = set(map(int, sys.argv[2].split())); print(" ".join(map(str, embedded_nvims() - before)))' "$HELPERS" "$before")
    [ -n "$victim" ] && break
    sleep 0.05
  done
  [ -n "$victim" ]
  kill -9 $victim
  code=0
  wait "$pid" || code=$?
  [ "$code" -eq 1 ]
  grep -q '^mdpreview: Neovim exited before completing the preview' "$BATS_TEST_TMPDIR/stderr"
}

@test "a non-numeric fzf size variable is a usage error naming the variable" {
  for variable in FZF_PREVIEW_COLUMNS FZF_PREVIEW_LINES; do
    for value in abc -3 1.5 '10 x'; do
      run --separate-stderr env "$variable=$value" "$MDPREVIEW" "$FIXTURES/markdown/sample.md"
      [ "$status" -eq 2 ] || { echo "$variable=$value: $status $stderr"; return 1; }
      [[ $stderr == *"$variable must be a whole number, got '$value'"* ]]
      [[ $stderr != *Traceback* ]]
    done
  done
}

@test "empty fzf size variables count as unset" {
  run --separate-stderr env FZF_PREVIEW_COLUMNS= FZF_PREVIEW_LINES= "$MDPREVIEW" --columns 80 --paging=never \
    "$FIXTURES/markdown/sample.md"
  [ "$status" -eq 0 ]
  [[ $output == *Title* ]]
}
