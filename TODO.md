# Next Steps

The working prototype renders the reference Markdown documents with the user's Neovim appearance.
Preserve that behavior while improving portability and preview latency.

## Portability and repeatable validation

- [ ] Replace hardcoded editor, theme, plugin, and parser paths with explicit configuration and sensible defaults.
- [ ] Provide a sample appearance profile so another user can run the tool without this personal Neovim setup.
- [ ] Declare runtime and development dependencies; provide a reproducible installation method.
- [ ] Turn the historical harnesses into tests that resolve paths from the checkout and use temporary output directories.
- [ ] Add self-contained fixtures for Markdown structures, all supported code languages, aliases, Unicode, and long lines.
- [ ] Retain checks for complete-document tails, stdin, unusual filenames, modelines, cancellation, and source immutability.
- [ ] Exercise parser/query mismatches and missing dependencies with actionable errors.
- [ ] Test released Neovim versions and declare the supported minimum.
- [ ] Document the Linux/Landlock requirement and remove experiment-only helper entrypoints.

## CLI and fzf integration

- [ ] Add `--version` and keep its output consistent with the release tag.
- [ ] Provide a checked-in mixed-file fzf integration example with bat fallback and resize refresh.
- [ ] Verify Markdown aliases, uppercase extensions, symlinks, empty files, and renderer failures.
- [ ] Review selection parsing for filenames containing literal pipes or display separators.
- [ ] Clarify full-document versus viewport behavior and how scrolling interacts with each mode.
- [ ] Define readable fallbacks for input, row, and timeout limits.

## Performance

- [ ] Measure startup, first usable fzf content, total render time, and peak memory on representative documents.
- [ ] Separate warm-process results from fresh-process measurements and rendered-output cache hits.
- [ ] Profile before optimizing; identify theme loading, parser loading, rendering, and RPC costs separately.
- [ ] Trial an optional persistent Neovim worker if startup dominates, with cancellation and cleanup tests.
- [ ] Add caching only if measurements justify it; include viewport, file content, theme, configuration, and parser versions.

## Rendering fidelity and larger documents

- [ ] Compare all reference features at multiple widths, including footnotes, wiki links, HTML comments, and code labels.
- [ ] Qualify transparent backgrounds, combining characters, emoji, and wide glyphs in more terminal/font combinations.
- [ ] Preserve additional underline attributes and assess terminal hyperlink support.
- [ ] Investigate complete-document export beyond one enlarged grid without duplicating or skipping virtual rows.
- [ ] Define memory and parsing limits before claiming streaming or large-file support.

## Releases

- [ ] Follow the SemVer and annotated-tag process in [docs/RELEASING.md](docs/RELEASING.md).
- [ ] Record user-visible changes and known limitations in [CHANGELOG.md](CHANGELOG.md).
- [ ] Run the portable integration suite before each release once it is available.

## Optional support for other filetypes

- [ ] Evaluate whether Neovim-specific source rendering adds value beyond the current bat integration.
- [ ] If needed, add filetype detection or `--filetype`, on-demand parsers, and a general render-ready signal.
- [ ] Compare startup, parsing time, and memory against the Markdown-only profile before enabling broader support.
