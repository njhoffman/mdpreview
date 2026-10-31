#!/usr/bin/env bats
# --version agrees with VERSION, and a tagged checkout agrees with its tag.

bats_require_minimum_version 1.5.0

setup() {
  ROOT=$(cd "$BATS_TEST_DIRNAME/.." && pwd)
  MDPREVIEW=$ROOT/mdpreview
  VERSION=$(<"$ROOT/VERSION")
}

@test "VERSION holds one semantic version" {
  [[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "--version prints the VERSION file without needing a file argument" {
  run --separate-stderr "$MDPREVIEW" --version
  [ "$status" -eq 0 ]
  [ "$output" = "mdpreview $VERSION" ]
}

@test "-v is --version" {
  run --separate-stderr "$MDPREVIEW" -v
  [ "$status" -eq 0 ]
  [ "$output" = "mdpreview $VERSION" ]
}

@test "--check reports the same version" {
  run "$MDPREVIEW" --check
  [[ $output == *"mdpreview        $VERSION"* ]]
}

@test "a tagged HEAD carries the tag of VERSION" {
  tags=$(git -C "$ROOT" tag --points-at HEAD 'v*' 2>/dev/null) || skip "not a git checkout"
  [ -n "$tags" ] || skip "HEAD is not tagged"
  # Uncommitted changes may be the next release in progress; the tag check applies to the tagged state.
  git -C "$ROOT" diff --quiet HEAD -- VERSION || skip "VERSION changed since the tag"
  grep -qx "v$VERSION" <<<"$tags"
}

@test "the newest CHANGELOG release is VERSION" {
  newest=$(grep -m1 -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$ROOT/CHANGELOG.md" | tr -d '#[] ')
  [ "$newest" = "$VERSION" ]
}
