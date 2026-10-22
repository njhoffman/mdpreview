# Development and Integration

## Runtime files

| File | Responsibility |
| --- | --- |
| `mdpreview` | CLI options, dependency paths, MessagePack RPC, screen decoding, ANSI output, process cleanup |
| `profile.lua` | Isolated Neovim options, theme and Markdown setup, render-ready signaling |
| `readonly.py` | Linux Landlock write restriction |
| `queries/markdown/injections.scm` | C++ fence-label injection |

The renderer starts Neovim with its own init file and reads selected appearance modules from the editor config.
Do not replace that profile with the full interactive editor startup: it would load unrelated plugins and state.
The older nvimpager configuration remains a separate working setup.

## Parser and query compatibility

Use the matching installed parser and query files under `~/.local/share/nvim/site`. The first prototype found
old parser binaries in a plugin checkout while omitting the highlight queries. Combining old SQL binaries with
newer SQL queries also produced invalid-node errors. The installed editor data directory supplies coherent pairs.
Normal aliases use Neovim's language registration; the extra query handles `c++`, whose punctuation prevents
normal injection-name lookup.

## Local checks

```sh
python3 - <<'PY'
import ast
from pathlib import Path
for name in ("mdpreview", "readonly.py"):
    ast.parse(Path(name).read_text(), filename=name)
PY
luac -p profile.lua
./mdpreview --columns 80 README.md > /tmp/mdpreview-readme.ansi
./mdpreview --columns 120 --lines 40 README.md > /tmp/mdpreview-viewport.ansi
```

The initial experiments checked all three reference Markdown documents at 80x24 and 120x40, complete-document
tails, Unicode through Neovim's terminal emulator, finite stdin, literal filenames, modelines, errors, limits,
and SIGTERM/SIGKILL cleanup. Language checks verify distinct code-token foregrounds, rather than accepting a
colored header as evidence of code highlighting.

The moved directory also contains historical experiment scripts and generated captures. They are excluded from
the initial source commit: those scripts still reference temporary paths and the nvimpager research checkout.
Preserve local data as needed; do not present the old harnesses as portable tests.

## Mixed-file fzf routing

In an existing preview script, retain binary, audio, and directory handlers. Route text extensions
`.md`, `.markdown`, `.mdown`, `.mkd`, `.mkdn`, and `.mdwn` to `mdpreview --all` with case-insensitive
matching. Keep bat's selected theme for other text. Falling back to bat if Markdown rendering is unavailable
or exceeds the prototype limits keeps the preview useful.

`MDPREVIEW_BIN` can select the Markdown executable. The local integration in `~/.fzf/core/preview.sh` searches PATH, then
`$HOME/git/mdpreview/mdpreview`. Configure fzf's `resize:refresh-preview` binding to rerender at a new width;
the file-routing script cannot configure the parent fzf process.

## Other filetypes

The screen decoder and ANSI exporter can be reused for other syntaxes. The current Lua profile forces Markdown
and waits for render-markdown.nvim's render callback. Supporting standalone source files would require filetype
detection, the matching parser, and a readiness signal independent of the Markdown plugin.

Load parsers on demand so unused language support does not add parsing work to each invocation. Markdown code
fences can already load several language parsers in one document. Measure startup, parsing, and memory separately
before attributing latency to the number of supported languages. Bat remains the selected backend for other text.

## Follow-up work

- Make theme, plugin, and parser paths configurable.
- Create a portable integration suite from the existing experiments.
- Validate a released Neovim version and additional parser configurations.
- Measure a persistent worker before introducing a background service.
- Define larger-document and streaming behavior beyond the current row/input limits.
- Retain the current input immutability, cancellation, and ANSI-output checks for any optimization.
