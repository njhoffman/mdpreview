#!/usr/bin/env bats
# --paging: less for the complete document, auto-detected from the terminal. Uses script(1) for a pty.

bats_require_minimum_version 1.5.0

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  MDPREVIEW=$ROOT/mdpreview
  FIXTURES=$BATS_TEST_DIRNAME/fixtures
  unset NVIM FZF_PREVIEW_COLUMNS FZF_PREVIEW_LINES
  PAGED=$BATS_TEST_TMPDIR/paged
  LONG=$BATS_TEST_TMPDIR/long.md
  for i in $(seq 1 60); do echo "- line $i"; done > "$LONG"
  export MDPREVIEW_PAGER="sh -c 'cat > \"\$1\"' pager $PAGED"
}

# Run a command in a 10x80 pseudo-terminal.
in_pty() {
  run script -qec "stty rows 10 cols 80; $*" /dev/null
}

@test "auto pages a long document on a terminal" {
  in_pty "'$MDPREVIEW' '$LONG'"
  [ "$status" -eq 0 ]
  [ -f "$PAGED" ]
  [ "$(grep -c 'line' "$PAGED")" -eq 60 ]
}

@test "auto prints a document that fits the terminal" {
  in_pty "'$MDPREVIEW' '$FIXTURES/markdown/sample.md'"
  [ "$status" -eq 0 ]
  [ ! -e "$PAGED" ]
  [[ $output == *Title* ]]
}

@test "auto prints when stdout is not a terminal" {
  run "$MDPREVIEW" --columns 80 "$LONG"
  [ "$status" -eq 0 ]
  [ ! -e "$PAGED" ]
  [ "${#lines[@]}" -eq 60 ]
}

@test "auto prints inside fzf previews" {
  in_pty "FZF_PREVIEW_COLUMNS=80 '$MDPREVIEW' --all '$LONG'"
  [ ! -e "$PAGED" ]
}

@test "auto prints inside Neovim terminals (Telescope)" {
  in_pty "NVIM=/tmp/nvim.sock '$MDPREVIEW' '$LONG'"
  [ ! -e "$PAGED" ]
}

@test "auto prints a viewport instead of paging it" {
  in_pty "'$MDPREVIEW' --lines 5 '$LONG'"
  [ ! -e "$PAGED" ]
}

@test "never prints on a terminal" {
  in_pty "'$MDPREVIEW' --paging=never '$LONG'"
  [ ! -e "$PAGED" ]
  [[ $output == *'line 60'* ]]
}

@test "always pages the same bytes that never prints" {
  "$MDPREVIEW" --columns 80 --paging=always "$LONG"
  "$MDPREVIEW" --columns 80 --paging=never "$LONG" > "$BATS_TEST_TMPDIR/printed"
  cmp "$PAGED" "$BATS_TEST_TMPDIR/printed"
}

@test "always pages short documents and non-Markdown files" {
  "$MDPREVIEW" --columns 80 --paging=always "$FIXTURES/kdl/config.kdl"
  [ "$(grep -c 'package' "$PAGED")" -eq 1 ]
}

@test "always rejects viewport options" {
  run "$MDPREVIEW" --paging=always --lines 5 "$LONG"
  [ "$status" -eq 1 ]
  [[ $output == *'--paging=always'* ]]
  run "$MDPREVIEW" --paging=always --start-line 3 "$LONG"
  [ "$status" -eq 1 ]
}

@test "the pager gets LESSHISTFILE=- because Landlock blocks writes outside /tmp" {
  MDPREVIEW_PAGER="sh -c 'printf %s \"\$LESSHISTFILE\" > \"\$1\"; cat > /dev/null' pager $PAGED" \
    "$MDPREVIEW" --columns 80 --paging=always "$LONG"
  [ "$(cat "$PAGED")" = - ]
}

@test "a pager that quits early is not an error" {
  MDPREVIEW_PAGER=true run --separate-stderr "$MDPREVIEW" --columns 80 --paging=always "$LONG"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "the pager's exit status is returned" {
  MDPREVIEW_PAGER="sh -c 'cat > /dev/null; exit 3'" run "$MDPREVIEW" --columns 80 --paging=always "$LONG"
  [ "$status" -eq 3 ]
}

@test "a missing pager is reported" {
  MDPREVIEW_PAGER=/nonexistent/pager run "$MDPREVIEW" --columns 80 --paging=always "$LONG"
  [ "$status" -eq 1 ]
  [[ $output == *'/nonexistent/pager'* ]]
}

@test "less is the default pager and quits on q" {
  unset MDPREVIEW_PAGER
  run bash -c "printf q | LESS=-R script -qec \"stty rows 10 cols 80; '$MDPREVIEW' '$LONG'; echo rc=\\\$?\" /dev/null"
  [[ $output == *'line 1'* ]]
  [[ $output == *'rc=0'* ]]
}
