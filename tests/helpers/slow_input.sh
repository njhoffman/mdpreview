# Source from a bats test: slow_input PATH writes about 2 MiB of Markdown prose. A 40-row viewport of it keeps
# Neovim busy for seconds (Tree-sitter parses the whole input) without reaching the row or size limits, so a
# test has time to signal mdpreview or Neovim mid-render.
slow_input() {
  python3 -c '
import sys
paragraph = "Paragraph {} with *emphasis*, `code` and a [link](https://example.com/{}) " + "lorem ipsum dolor " * 4
with open(sys.argv[1], "w") as handle:
    for i in range(14000):
        if i % 20 == 0:
            handle.write(f"## Section {i}\n\n")
        handle.write(paragraph.format(i, i) + "\n\n")
' "$1"
}
