#!/usr/bin/env bats
# --budget and --fallback: complete output that takes too long goes to bat instead of failing.

bats_require_minimum_version 1.5.0

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  MDPREVIEW=$ROOT/mdpreview
  FIXTURES=$BATS_TEST_DIRNAME/fixtures
}

@test "over budget, Markdown falls back to bat with a notice" {
  run --separate-stderr "$MDPREVIEW" --paging=never --columns 80 --budget 0.01 "$FIXTURES/markdown/sample.md"
  [ "$status" -eq 0 ]
  [[ $stderr == *'showing bat output instead'* ]]
  [[ $output == *'Title'* ]]
  [[ $output == *$'\e['* ]]
}

@test "the fallback output matches bat's Markdown rendering" {
  run --separate-stderr "$MDPREVIEW" --paging=never --columns 80 --budget 0.01 "$FIXTURES/markdown/sample.md"
  expected=$(bat --color=always --paging=never --style=plain --terminal-width=80 --language=markdown -- \
    "$FIXTURES/markdown/sample.md")
  [ "$output" = "$expected" ]
}

@test "non-Markdown filetypes fall back to bat without forcing Markdown" {
  run --separate-stderr "$MDPREVIEW" --paging=never --columns 80 --budget 0.01 --filetype kdl -- \
    "$FIXTURES/kdl/config.kdl"
  [ "$status" -eq 0 ]
  expected=$(bat --color=always --paging=never --style=plain --terminal-width=80 -- "$FIXTURES/kdl/config.kdl")
  [ "$output" = "$expected" ]
}

@test "--fallback=none reports the budget error" {
  run "$MDPREVIEW" --paging=never --columns 80 --budget 0.01 --fallback=none "$FIXTURES/markdown/sample.md"
  [ "$status" -eq 1 ]
  [[ $output == *'longer than the budget'* ]]
}

@test "the budget does not apply to viewports" {
  run --separate-stderr "$MDPREVIEW" --paging=never --columns 80 --lines 5 --budget 0.01 \
    "$FIXTURES/markdown/sample.md"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "--budget 0 disables the budget" {
  run --separate-stderr "$MDPREVIEW" --paging=never --columns 80 --budget 0 "$FIXTURES/markdown/sample.md"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "stdin falls back too" {
  run --separate-stderr bash -c "'$MDPREVIEW' --paging=never --columns 80 --budget 0.01 - < '$FIXTURES/markdown/sample.md'"
  [ "$status" -eq 0 ]
  [[ $output == *'Title'* ]]
}

@test "fallback output is paged like a normal render" {
  paged=$BATS_TEST_TMPDIR/paged
  MDPREVIEW_PAGER="sh -c 'cat > \"\$1\"' pager $paged" \
    "$MDPREVIEW" --paging=always --columns 80 --budget 0.01 "$FIXTURES/markdown/sample.md" 2>/dev/null
  grep -q 'Title' "$paged"
}

@test "a large table renders in full within the default budget or falls back, never errors" {
  table=$BATS_TEST_TMPDIR/table.md
  { echo '| a | b | c | d |'; echo '|---|---|---|---|'
    for i in $(seq 1 1500); do echo "| \`f$i\` | \`.e$i\`, 1 pattern | \`p\` |  |"; done; } > "$table"
  run --separate-stderr "$MDPREVIEW" --paging=never --columns 120 "$table"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -ge 1500 ]
}
