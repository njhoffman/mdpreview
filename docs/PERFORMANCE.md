# Performance

Where a render's time goes, measured with `mdpreview --timings` (see the README) on 2026-10-31, NVIM
v0.13.0-dev, 8 CPUs at a 1-minute load of about 2. Each figure is a median of three runs; expect +-20% from
the load on this desktop. Regenerate the per-filetype table with `benchmarks/filetypes`; the Markdown samples
are tracked by `benchmarks/run` in [SYNTAX.md](../SYNTAX.md#markdown-rendering-benchmarks).

## Phases

| Document | Mode | Total | Python imports | Startup | Open | Frames | of which render / redraw | RPC (Python) | ANSI | Neovim RSS |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| tmux fixture, 4 lines | `--all` | 88 | 36 | 23 | 19 | 2 | 0 / 2 | 7 | 0 | 18 MiB |
| benchmarks/medium.md, 353 lines | `--all` | 1031 | 41 | 33 | 55 | 861 | 329 / 479 | 33 | 21 | 59 MiB |
| benchmarks/large.md, 888 lines | `--all` | 2043 | 45 | 65 | 53 | 1815 | 422 / 1241 | 79 | 49 | 67 MiB |
| benchmarks/large.md | `--lines 40` | 487 | 39 | 23 | 46 | 371 | 230 / 129 | 7 | 2 | 43 MiB |

Milliseconds. Python's interpreter start (about 17 ms, `python3 -c pass`) comes before the first import and is
not in the totals.

Findings, in order of what they cost:

1. **Frames dominate Markdown.** Everything up to a ready Neovim (imports, startup, open) is about 130 ms for
   any document; the rest is render-markdown's render and Neovim's redraw, which grow with the grid. Redraw is
   the larger part on tall grids: 1.2 s of large.md's 2 s.
2. **Each Markdown frame redraws three times.** render-markdown calls `on.render` three times per frame
   (which events trigger each is not yet traced), and `notify_ready` schedules a full `redraw` for each; all three finish before mdpreview's `info()` request is answered. Non-Markdown filetypes redraw
   once. `ready_callbacks` in `--timings` shows the count. Notifying once per token, after the explicit
   update, is the most promising optimization (TODO.md), but it changes the ready protocol and needs the
   tail/viewport tests to hold.
3. **Query compilation dominates cuda.** `vim.treesitter.start` takes about 390 ms for cuda (its highlights
   query inherits cpp's and c's), against 1-10 ms for most languages; `--syntax regex` renders the same file
   in about 130 ms. nu, fennel and cue pay 30-40 ms the same way.
4. **Injected languages load during parsing.** astro's 5-line fixture spends about 140 ms in `parse` loading
   and compiling the TypeScript and CSS parsers and queries it injects; `parser load` covers only the root
   language. pug, sxhkdrc, just and hyprlang show the same pattern at a smaller scale.
5. **Startup is a fixed ~75 ms, half of it Python.** Python imports take about 40 ms (argparse and tomllib are
   the largest, 8-9 ms each under `-X importtime`), Neovim before the profile 8 ms, setup 15 ms (theme 4,
   render-markdown 5, icons 2-3, runtimepath 3). For the small files fzf previews mostly show, startup is
   about 60% of the time, which is the case for a persistent worker (TODO.md).
6. **Python's share is small.** Decoding redraw events and maintaining the grid is 7-80 ms, ANSI encoding up
   to 50 ms on 900 rows: under 10% of a complete render.
7. **Dispatch overhead is below the noise.** `mdpreview-dispatch` minus `mdpreview --all` ranges from -41 to
   +71 ms with no pattern; the detection itself is a bash `case`.
8. **Memory is modest.** Neovim peaks at 18-28 MiB for small files and about 60-70 MiB for 350-900-line
   Markdown, Python at 18-33 MiB.

## Render time per filetype

<!-- filetypes:start -->

Recorded 2026-10-31T22:07Z, version 0.6.0 (2728662-dirty), load 1.91, NVIM v0.13.0-dev-1915+gc5641b2bfb, 5 runs per command. 80 columns, medians from hyperfine; regenerate with `benchmarks/filetypes`. Fixture: the file in `tests/fixtures/<filetype>`; large: that file repeated. Overhead is dispatch minus complete on the fixture. Query is `vim.treesitter.start` (query compilation), parse is the synchronous parse or the regex syntax load, frames is render and redraw, all from one `--timings-json` run of the large file.

| Filetype | Engine | Fixture (ms) | Large lines | Large (ms) | Large regex (ms) | Large viewport (ms) | bat large (ms) | Dispatch overhead (ms) | Startup (ms) | Query (ms) | Parse (ms) | Frames (ms) |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| markdown | render-markdown | 243 | 504 | 523 | 476 | 292 | 53 | -2 | 82 | 0 | 0 | 336 |
| helm | treesitter | 175 | 504 | 251 | 189 | 171 | 32 | 71 | 98 | 5 | 31 | 76 |
| htmldjango | treesitter | 147 | 500 | 259 | 247 | 170 | 17 | 37 | 81 | 2 | 9 | 62 |
| tmux | syntax | 137 | 500 | 229 | - | 150 | 14 | -3 | 77 | 0 | 8 | 27 |
| kitty | treesitter | 135 | 500 | 296 | 192 | 220 | 14 | 2 | 73 | 5 | 55 | 76 |
| hyprlang | treesitter | 204 | 504 | 344 | 204 | 282 | 13 | 3 | 74 | 2 | 44 | 143 |
| i3config | syntax | 126 | 500 | 164 | - | 122 | 13 | -2 | 74 | 0 | 3 | 14 |
| sxhkdrc | treesitter | 239 | 500 | 411 | 155 | 224 | 12 | -11 | 76 | 1 | 45 | 224 |
| zathurarc | syntax | 114 | 500 | 162 | - | 118 | 12 | 9 | 76 | 0 | 2 | 9 |
| neomuttrc | syntax | 141 | 500 | 206 | - | 145 | 12 | -7 | 77 | 0 | 11 | 32 |
| muttrc | syntax | 131 | 500 | 188 | - | 138 | 13 | -4 | 71 | 0 | 6 | 33 |
| rasi | treesitter | 116 | 500 | 184 | 178 | 129 | 13 | 8 | 77 | 2 | 2 | 14 |
| readline | treesitter | 128 | 504 | 218 | 157 | 143 | 14 | -11 | 76 | 1 | 6 | 71 |
| udevrules | treesitter | 128 | 500 | 344 | 159 | 137 | 12 | -12 | 84 | 2 | 18 | 189 |
| xdefaults | syntax | 128 | 500 | 156 | - | 125 | 13 | -13 | 77 | 0 | 2 | 8 |
| xcompose | treesitter | 147 | 501 | 305 | 170 | 126 | 12 | -32 | 81 | 1 | 8 | 123 |
| systemd | syntax | 117 | 504 | 161 | - | 117 | 14 | 4 | 74 | 0 | 2 | 6 |
| just | treesitter | 216 | 504 | 359 | 187 | 221 | 13 | -5 | 78 | 3 | 45 | 164 |
| kdl | treesitter | 124 | 504 | 230 | 159 | 130 | 12 | -1 | 71 | 4 | 8 | 63 |
| json5 | treesitter | 127 | 504 | 263 | 168 | 123 | 12 | 17 | 89 | 1 | 5 | 67 |
| hjson | treesitter | 124 | 504 | 213 | 171 | 129 | 12 | 0 | 79 | 1 | 4 | 40 |
| gotmpl | treesitter | 129 | 500 | 357 | 228 | 229 | 19 | 11 | 74 | 3 | 11 | 188 |
| prisma | treesitter | 122 | 500 | 233 | 175 | 150 | 15 | -2 | 74 | 1 | 5 | 69 |
| astro | treesitter | 456 | 500 | 657 | 558 | 477 | 12 | 38 | 73 | 3 | 138 | 226 |
| mermaid | treesitter | 119 | 500 | 253 | 164 | 140 | 13 | 13 | 91 | 3 | 14 | 93 |
| meson | treesitter | 124 | 501 | 283 | 188 | 136 | 11 | -7 | 79 | 3 | 11 | 131 |
| nu | treesitter | 154 | 500 | 297 | 229 | 190 | 12 | -5 | 70 | 29 | 18 | 77 |
| gleam | treesitter | 122 | 504 | 234 | 162 | 145 | 13 | 4 | 74 | 9 | 6 | 60 |
| fennel | treesitter | 161 | 500 | 374 | 158 | 184 | 12 | 17 | 71 | 42 | 10 | 154 |
| cuda | treesitter | 531 | 500 | 694 | 196 | 536 | 14 | 23 | 73 | 389 | 15 | 96 |
| po | treesitter | 119 | 504 | 201 | 163 | 142 | 15 | 12 | 71 | 1 | 4 | 44 |
| pug | treesitter | 231 | 504 | 464 | 172 | 251 | 12 | 31 | 78 | 6 | 67 | 229 |
| ledger | treesitter | 186 | 500 | 328 | 155 | 127 | 12 | -41 | 89 | 2 | 13 | 101 |
| beancount | treesitter | 115 | 500 | 242 | 182 | 159 | 13 | 0 | 71 | 2 | 6 | 62 |
| dts | treesitter | 125 | 504 | 222 | 156 | 133 | 12 | 9 | 80 | 4 | 7 | 73 |
| ebnf | treesitter | 116 | 500 | 296 | 154 | 128 | 12 | 18 | 78 | 2 | 7 | 116 |
| cue | treesitter | 146 | 504 | 257 | 168 | 152 | 12 | 12 | 81 | 35 | 7 | 79 |
| dhall | treesitter | 119 | 501 | 218 | 169 | 143 | 12 | 5 | 75 | 4 | 25 | 29 |
| handlebars | treesitter | 144 | 504 | 273 | 357 | 170 | 14 | 2 | 81 | 2 | 10 | 93 |
| conf | syntax | 115 | 501 | 173 | - | 116 | 11 | 8 | 75 | 0 | 2 | 6 |

<!-- filetypes:end -->
