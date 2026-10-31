#!/usr/bin/env bats
# Parser/query mismatches and missing dependencies give one actionable line, never a stack trace.
# The broken queries are for lua and markdown, whose parsers ship with Neovim.

bats_require_minimum_version 1.5.0

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  MDPREVIEW=$ROOT/mdpreview
  BROKEN=$BATS_TEST_TMPDIR/parsers
  mkdir -p "$BROKEN/parser"
  printf 'local x = 1\n' > "$BATS_TEST_TMPDIR/sample.lua"
  printf '# Heading\n\ntext\n\n```lua\nlocal y = 2\n```\n' > "$BATS_TEST_TMPDIR/sample.md"
}

plain() {
  sed 's/\x1b\[[0-9;]*m//g' <<<"$1"
}

break_query() {  # lang [name]
  mkdir -p "$BROKEN/queries/$1"
  echo '(no_such_node) @keyword' > "$BROKEN/queries/$1/${2:-highlights}.scm"
}

@test "a highlights query that does not match its parser falls back to regex syntax with one warning" {
  break_query lua
  MDPREVIEW_PARSER_DIR=$BROKEN run --separate-stderr "$MDPREVIEW" --paging=never --columns 60 --timings-json \
    "$BATS_TEST_TMPDIR/sample.lua"
  [ "$status" -eq 0 ]
  [[ $output == *'local'*'x'* ]]
  [[ $output == *$'\e[0;38;2;'* ]]
  warning=$(grep '^mdpreview: warning:' <<<"$stderr")
  [ "$(wc -l <<<"$warning")" -eq 1 ]
  [[ $warning == *'lua highlights query failed: Query error at 1:2. Invalid node type "no_such_node" in '"$BROKEN/queries/lua/highlights.scm"* ]]
  [[ $warning == *'update the lua parser and its queries together'* ]]
  [[ $stderr == *'"engine": "syntax"'* ]]
  [[ $stderr != *traceback* ]]
}

@test "a broken Markdown query still renders the document with render-markdown" {
  break_query markdown
  MDPREVIEW_PARSER_DIR=$BROKEN run --separate-stderr "$MDPREVIEW" --paging=never --columns 60 \
    "$BATS_TEST_TMPDIR/sample.md"
  [ "$status" -eq 0 ]
  [[ $stderr == *'markdown highlights query failed'* ]]
  [[ $(plain "$output") == *'Heading'* ]]
  [[ $(plain "$output") == *'local y = 2'* ]]
}

@test "a broken query for a language injected in a code fence warns once and renders the rest" {
  break_query lua
  MDPREVIEW_PARSER_DIR=$BROKEN run --separate-stderr "$MDPREVIEW" --paging=never --columns 60 --all \
    "$BATS_TEST_TMPDIR/sample.md"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'lua highlights query failed' <<<"$stderr")" -eq 1 ]
  [[ $output == *'Heading'* ]]
}

@test "a broken injections query is reported too" {
  break_query markdown injections
  MDPREVIEW_PARSER_DIR=$BROKEN run --separate-stderr "$MDPREVIEW" --paging=never --columns 60 \
    "$BATS_TEST_TMPDIR/sample.md"
  [ "$status" -eq 0 ]
  [[ $stderr == *'markdown injections query failed'* ]]
}

@test "--check compiles the filetype table's queries and reports failures as warnings" {
  run "$MDPREVIEW" --check
  [ "$status" -eq 0 ]
  [[ $output == *'tree-sitter queries:'*'compiled '*' languages'* ]]
  break_query lua
  break_query markdown
  MDPREVIEW_PARSER_DIR=$BROKEN run "$MDPREVIEW" --check
  [ "$status" -eq 0 ]
  [[ $output == *'warning: markdown highlights query failed'* ]]
  [[ $output != *'lua highlights'* ]]
}

@test "--check --all also compiles the queries of parsers outside the table" {
  break_query lua
  MDPREVIEW_PARSER_DIR=$BROKEN run timeout 300 "$MDPREVIEW" --check --all
  [ "$status" -eq 0 ]
  [[ $output == *'checked installed parsers'* ]]
  [[ $output == *'warning: lua highlights query failed'* ]]
}

@test "a missing Neovim executable is named" {
  run "$MDPREVIEW" --nvim "$BATS_TEST_TMPDIR/no-such-nvim" --paging=never --columns 60 "$BATS_TEST_TMPDIR/sample.md"
  [ "$status" -eq 1 ]
  [[ $output == "mdpreview: Neovim executable not found or not executable: $BATS_TEST_TMPDIR/no-such-nvim"* ]]
}

@test "a Neovim that exits at once is reported with its stderr" {
  printf '#!/bin/sh\necho "nvim: broken install" >&2\nexit 2\n' > "$BATS_TEST_TMPDIR/nvim"
  chmod +x "$BATS_TEST_TMPDIR/nvim"
  run "$MDPREVIEW" --nvim "$BATS_TEST_TMPDIR/nvim" --paging=never --columns 60 "$BATS_TEST_TMPDIR/sample.md"
  [ "$status" -eq 1 ]
  [[ $output == *'Neovim exited before completing the preview. nvim: broken install'* ]]
}

@test "a missing msgpack is named with how to install it" {
  mkdir -p "$BATS_TEST_TMPDIR/python/msgpack"
  echo 'raise ImportError("No module named msgpack")' > "$BATS_TEST_TMPDIR/python/msgpack/__init__.py"
  PYTHONPATH=$BATS_TEST_TMPDIR/python run "$MDPREVIEW" --paging=never "$BATS_TEST_TMPDIR/sample.md"
  [ "$status" -eq 1 ]
  [ "$output" = "mdpreview: the Python package msgpack is missing; install python3-msgpack or run 'make deps'" ]
}

@test "Lua errors reach the user without their stack trace or location" {
  run "$MDPREVIEW" --paging=never --columns 60 --lines 3 --start-line 99 "$BATS_TEST_TMPDIR/sample.lua"
  [ "$status" -eq 1 ]
  [ "$output" = 'mdpreview: Requested line exceeds document length (1)' ]
}
