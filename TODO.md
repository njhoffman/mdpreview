# Next Steps

The working prototype renders the reference Markdown documents with the user's Neovim appearance.
Preserve that behavior while improving portability and preview latency.

## Portability and repeatable validation

- [ ] (p1) [refactor] Replace hardcoded editor, theme, plugin, and parser paths with explicit configuration and sensible defaults.
- [ ] (p2) [feature] Provide a sample appearance profile so another user can run the tool without this personal Neovim setup.
- [ ] (p1) [chore] Declare runtime and development dependencies; provide a reproducible installation method.
- [ ] (p1) [test] Turn the historical harnesses into tests that resolve paths from the checkout and use temporary output directories.
- [ ] (p2) [test] Add self-contained fixtures for Markdown structures, all supported code languages, aliases, Unicode, and long lines.
- [ ] (p2) [test] Retain checks for complete-document tails, stdin, unusual filenames, modelines, cancellation, and source immutability.
- [ ] (p2) [test] Exercise parser/query mismatches and missing dependencies with actionable errors.
- [ ] (p2) [test] Test released Neovim versions and declare the supported minimum.
- [ ] (p2) [docs] Document the Linux/Landlock requirement and remove experiment-only helper entrypoints.

## CLI and fzf integration

- [ ] (p2) [feature] Add `--version` and keep its output consistent with the release tag.
- [ ] (p3) [docs] Provide a checked-in mixed-file fzf integration example with bat fallback and resize refresh.
- [ ] (p2) [test] Verify Markdown aliases, uppercase extensions, symlinks, empty files, and renderer failures.
- [ ] (p2) [bug] Review selection parsing for filenames containing literal pipes or display separators.
- [ ] (p2) [docs] Clarify full-document versus viewport behavior and how scrolling interacts with each mode.
- [ ] (p2) [feature] Define readable fallbacks for input, row, and timeout limits.

## Performance

- [ ] (p2) [perf] Measure startup, first usable fzf content, total render time, and peak memory on representative documents.
- [ ] (p3) [perf] Separate warm-process results from fresh-process measurements and rendered-output cache hits.
- [ ] (p2) [perf] Profile before optimizing; identify theme loading, parser loading, rendering, and RPC costs separately.
- [ ] (p3) [perf] Trial an optional persistent Neovim worker if startup dominates, with cancellation and cleanup tests.
- [ ] (p3) [perf] Add caching only if measurements justify it; include viewport, file content, theme, configuration, and parser versions.

## Rendering fidelity and larger documents

- [ ] (p3) [test] Compare all reference features at multiple widths, including footnotes, wiki links, HTML comments, and code labels.
- [ ] (p3) [test] Qualify transparent backgrounds, combining characters, emoji, and wide glyphs in more terminal/font combinations.
- [ ] (p3) [feature] Preserve additional underline attributes and assess terminal hyperlink support.
- [ ] (p3) [feature] Investigate complete-document export beyond one enlarged grid without duplicating or skipping virtual rows.
- [ ] (p2) [docs] Define memory and parsing limits before claiming streaming or large-file support.

## Releases

- [ ] (p2) [chore] Follow the SemVer and annotated-tag process in [docs/RELEASING.md](docs/RELEASING.md).
- [ ] (p2) [docs] Record user-visible changes and known limitations in [CHANGELOG.md](CHANGELOG.md).
- [ ] (p2) [test] Run the portable integration suite before each release once it is available.

## Optional support for other filetypes

- [ ] (p3) [feature] Evaluate whether Neovim-specific source rendering adds value beyond the current bat integration.
- [ ] (p3) [feature] If needed, add filetype detection or `--filetype`, on-demand parsers, and a general render-ready signal.
- [ ] (p3) [perf] Compare startup, parsing time, and memory against the Markdown-only profile before enabling broader support.
