#!/usr/bin/env bats
# Ported from the historical fzf-check.py: mdpreview as the previewer of a real fzf in a pseudo-terminal.

@test "fzf: scrolling, file changes, resize re-render, rapid selection, cleanup" {
  command -v fzf >/dev/null || skip "fzf not installed"
  reference=$BATS_TEST_DIRNAME/fixtures/reference
  MARKERS='REFERENCE_TABLES_TOP,REFERENCE_TABLES_BOTTOM;REFERENCE_SYNTAX_TOP,REFERENCE_SYNTAX_BOTTOM;REFERENCE_EXTENDED_TOP,REFERENCE_EXTENDED_BOTTOM' \
    run timeout 120 python3 "$BATS_TEST_DIRNAME/helpers/fzf_session.py" \
    "$reference/tables.md" "$reference/syntax.md" "$reference/extended.md"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ "$(grep -c '^ok ' <<<"$output")" -eq 8 ]
}
