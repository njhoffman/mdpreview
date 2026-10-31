#!/usr/bin/env bats
# The built-in Neovim pager (--pager nvim, the default): keys, resize, signals, stdin, the auto-mode probe,
# and selecting it or an external pager through --pager, MDPREVIEW_PAGER, and the config file.

bats_require_minimum_version 1.5.0

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  MDPREVIEW=$ROOT/mdpreview
  HELPERS=$BATS_TEST_DIRNAME/helpers
  FIXTURES=$BATS_TEST_DIRNAME/fixtures
  unset NVIM FZF_PREVIEW_COLUMNS FZF_PREVIEW_LINES MDPREVIEW_PAGER
  export MDPREVIEW_CONFIG=$BATS_TEST_TMPDIR/config.toml
  DOCUMENT=$BATS_TEST_TMPDIR/pager.md
  { echo '# PAGER_TOP'; echo
    for i in $(seq 1 30); do echo "- item $i"; done
    echo; echo 'PAGER_MIDDLE'; echo
    for i in $(seq 31 60); do echo "- item $i"; done
    echo; echo 'PAGER_BOTTOM'; } > "$DOCUMENT"
}

session() {
  run timeout 60 python3 "$HELPERS/pager_session.py" "$@"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$output" = ok ]
}

@test "renders without raw Markdown; G, gg, search, space and q work" {
  session keys "$DOCUMENT"
}

@test "--syntax regex reaches the pager: raw Markdown with Vim's syntax" {
  session regex "$DOCUMENT" --syntax regex
}

@test "a terminal resize redraws" {
  session resize "$DOCUMENT"
}

@test "SIGTERM while paging exits 130 and leaves no Neovim behind" {
  session term "$DOCUMENT"
}

@test "SIGHUP while paging leaves no Neovim behind" {
  session hup "$DOCUMENT"
}

@test "a document on stdin is paged with keys from the terminal" {
  STDIN_FILE=$DOCUMENT session keys -
}

@test "auto prints a document that fits the terminal instead of opening the pager" {
  run timeout 30 script -qec "stty rows 20 cols 80; '$MDPREVIEW' '$FIXTURES/markdown/sample.md'; echo rc=\$?" /dev/null < /dev/null
  [[ $output == *Title* ]]
  [[ $output == *rc=0* ]]
  [[ $output != *$'\e[?1049h'* ]]  # Neovim's TUI switches to the alternate screen; printing does not.
}

@test "always opens the pager even for a short non-Markdown file, and q quits" {
  run timeout 30 bash -c "{ sleep 2; printf q; } | script -qec \"stty rows 20 cols 80; '$MDPREVIEW' --paging=always '$FIXTURES/kdl/config.kdl'; echo rc=\\\$?\" /dev/null"
  [[ $output == *$'\e[?1049h'* ]]
  [[ $output == *package* ]]
  [[ $output == *rc=0* ]]
}

@test "always without a terminal prints the complete document" {
  run --separate-stderr "$MDPREVIEW" --columns 80 --paging=always "$DOCUMENT"
  [ "$status" -eq 0 ]
  [[ $output == *PAGER_BOTTOM* ]]
}

@test "the pager never modifies the source file" {
  before=$(stat -c '%Y %s' "$DOCUMENT"; sha256sum < "$DOCUMENT")
  session keys "$DOCUMENT"
  after=$(stat -c '%Y %s' "$DOCUMENT"; sha256sum < "$DOCUMENT")
  [ "$before" = "$after" ]
}

pager_command() {
  # An external pager that records that it ran.
  echo "sh -c 'cat > \"\$1\"' pager $BATS_TEST_TMPDIR/paged"
}

@test "--pager with a command line uses that external pager" {
  "$MDPREVIEW" --columns 80 --paging=always --pager "$(pager_command)" "$DOCUMENT"
  grep -q PAGER_BOTTOM "$BATS_TEST_TMPDIR/paged"
}

@test "MDPREVIEW_PAGER selects an external pager" {
  MDPREVIEW_PAGER=$(pager_command) "$MDPREVIEW" --columns 80 --paging=always "$DOCUMENT"
  grep -q PAGER_BOTTOM "$BATS_TEST_TMPDIR/paged"
}

@test "the config file's pager key selects an external pager" {
  printf "pager = \"%s\"\n" "$(pager_command | sed 's/"/\\"/g')" > "$MDPREVIEW_CONFIG"
  "$MDPREVIEW" --columns 80 --paging=always "$DOCUMENT"
  grep -q PAGER_BOTTOM "$BATS_TEST_TMPDIR/paged"
}

@test "--pager nvim overrides an external MDPREVIEW_PAGER" {
  MDPREVIEW_PAGER=$(pager_command) session keys "$DOCUMENT"
  [ ! -e "$BATS_TEST_TMPDIR/paged" ]
}

@test "--pager less runs less -R" {
  mkdir "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "$@" > %s/less-args\ncat > %s/paged\n' "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR" \
    > "$BATS_TEST_TMPDIR/bin/less"
  chmod +x "$BATS_TEST_TMPDIR/bin/less"
  PATH=$BATS_TEST_TMPDIR/bin:$PATH "$MDPREVIEW" --columns 80 --paging=always --pager less "$DOCUMENT"
  [ "$(cat "$BATS_TEST_TMPDIR/less-args")" = -R ]
  grep -q PAGER_BOTTOM "$BATS_TEST_TMPDIR/paged"
}

@test "--check reports the pager and its source" {
  run "$MDPREVIEW" --check
  [[ $output == *'pager            nvim  [default]'* ]]
  MDPREVIEW_PAGER=less run "$MDPREVIEW" --check
  [[ $output == *'pager            less  [MDPREVIEW_PAGER]'* ]]
}
