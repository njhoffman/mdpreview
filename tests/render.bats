#!/usr/bin/env bats
# End-to-end rendering through Neovim. Needs the local Neovim, parsers, and theme (see README).

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  MDPREVIEW=$ROOT/mdpreview
  FIXTURES=$BATS_TEST_DIRNAME/fixtures
}

colors() {
  grep -o '38;2;[0-9;]*m' <<<"$1" | sort -u | wc -l
}

render_entry() {
  local filetype=$1 file
  file=$(find "$FIXTURES/$filetype" -type f ! -name Chart.yaml ! -name 'plain.*' | sort | head -1)
  run "$MDPREVIEW" --columns 80 --all --filetype "$filetype" -- "$file"
  [ "$status" -eq 0 ] || { echo "$filetype: $output"; return 1; }
  [ "$(colors "$output")" -ge 3 ] || { echo "$filetype: only $(colors "$output") colors"; return 1; }
}

@test "every filetype entry renders with highlighting" {
  for filetype in $(python3 -c '
import sys; sys.path.insert(0, sys.argv[1]); import filetypes
print(" ".join(e["filetype"] for e in filetypes.load()))' "$ROOT"); do
    render_entry "$filetype"
  done
}

@test "regex-syntax filetypes highlight comments" {
  run "$MDPREVIEW" --columns 80 --all --filetype tmux -- "$FIXTURES/tmux/.tmux.conf"
  [ "$status" -eq 0 ]
  first=$(head -1 <<<"$output")
  [[ $first == *$'\e[0;3;'* ]]  # Comment is italic in the theme
  [[ $first == *'# prefix'* ]]
}

@test "the table detects the filetype when --filetype is omitted" {
  run "$MDPREVIEW" --columns 80 --all -- "$FIXTURES/kdl/config.kdl"
  [ "$status" -eq 0 ]
  [ "$(colors "$output")" -ge 3 ]
}

@test "files outside the table use Neovim detection" {
  run "$MDPREVIEW" --columns 80 --all -- "$FIXTURES/bat/script.py"
  [ "$status" -eq 0 ]
  [ "$(colors "$output")" -ge 3 ]
}

@test "stdin renders as Markdown" {
  run bash -c "'$MDPREVIEW' --columns 40 - < '$FIXTURES/markdown/sample.md'"
  [ "$status" -eq 0 ]
  [[ $output == *'Title'* ]]
  [[ $output == *'item'* ]]
}

@test "Markdown fixture renders headings and code" {
  run "$MDPREVIEW" --columns 60 --all -- "$FIXTURES/markdown/sample.md"
  [ "$status" -eq 0 ]
  [[ $output == *'Title'* ]]
  [[ $output == *'print'* ]]
}

@test "viewport rendering works for non-Markdown files" {
  run "$MDPREVIEW" --columns 60 --lines 2 --filetype just -- "$FIXTURES/just/justfile"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "start line past the end fails cleanly" {
  run "$MDPREVIEW" --columns 60 --lines 5 --start-line 999 --filetype kdl -- "$FIXTURES/kdl/config.kdl"
  [ "$status" -eq 1 ]
  [[ $output == *'exceeds document length'* ]]
}

@test "dispatch renders through the real mdpreview" {
  MDPREVIEW=$ROOT/mdpreview run "$ROOT/mdpreview-dispatch" "$FIXTURES/gleam/app.gleam"
  [ "$status" -eq 0 ]
  [ "$(colors "$output")" -ge 3 ]
}
