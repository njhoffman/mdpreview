local hrtime = vim.uv.hrtime
-- timings: {name, milliseconds} per phase in first-recorded order, summed over repeats (mdpreview --timings).
-- marks: hrtime (CLOCK_MONOTONIC nanoseconds) when this profile was sourced and when setup began, so mdpreview
-- can split Neovim's startup.
local M = { token = 0, timings = {}, marks = { profile = hrtime() }, warnings = {} }
_G.mdpreview = M

-- Add the time since start (an hrtime) to phase name; returns now, so consecutive phases can chain.
local function lap(name, start)
  local now = hrtime()
  for _, entry in ipairs(M.timings) do
    if entry[1] == name then
      entry[2] = entry[2] + (now - start) / 1e6
      return now
    end
  end
  table.insert(M.timings, { name, (now - start) / 1e6 })
  return now
end

for name, value in pairs({
  shadafile = "NONE", swapfile = false, undofile = false, backup = false,
  writebackup = false, modeline = false, readonly = true, number = false,
  relativenumber = false, signcolumn = "no", foldcolumn = "0", foldenable = false,
  laststatus = 0, showtabline = 0, showmode = false, ruler = false, cmdheight = 0,
  termguicolors = true, wrap = true, linebreak = true, list = false,
  cursorline = false, scrolloff = 0, sidescrolloff = 0, report = 999999,
}) do
  vim.o[name] = value
end
vim.opt.fillchars = { eob = " " }
vim.g.loaded_python3_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0

local function notify_ready(win)
  local token = M.token
  if M.update_started then
    lap("render", M.update_started)
    M.update_started = nil
  end
  local scheduled = hrtime()
  vim.schedule(function()
    if token ~= M.token then
      return
    end
    -- render-markdown calls on.render three times per Markdown frame, and each redraws (see PERFORMANCE.md).
    M.callbacks = (M.callbacks or 0) + 1
    -- Other queued work (render-markdown's own callbacks, Tree-sitter's async parsing) runs before this.
    local start = lap("queued", scheduled)
    vim.cmd("redraw")
    lap("redraw", start)
    vim.rpcnotify(M.channel, "mdpreview_ready", {
      token = token,
      buffer = vim.api.nvim_get_current_buf(),
      topline = vim.fn.winsaveview().topline,
      width = vim.api.nvim_win_get_width(win),
      height = vim.api.nvim_win_get_height(win),
    })
  end)
end

-- Read render-markdown options from a file that either calls require("render-markdown").setup(opts), as an
-- editor config does, or returns the options table. The editor's plugin manager is never started.
local function markdown_options(file)
  if not file then
    return {}
  end
  local captured
  package.loaded["render-markdown"] = { setup = function(value) captured = value end }
  local ok, returned = pcall(dofile, file)
  package.loaded["render-markdown"] = nil
  assert(ok, "markdown_options " .. file .. ": " .. tostring(returned))
  local options = captured or (type(returned) == "table" and returned)
  assert(options, "markdown_options " .. file .. " neither called setup() nor returned a table")
  return options
end

-- "Query error at 1:2. Invalid node type "x"" from an error raised with a Lua location and a source excerpt.
local function first_line(err)
  return (tostring(err):gsub("^.-%.lua:%d+: ", ""):match("^[^\n]*"):gsub(":$", ""))
end

-- The compile error of a query, naming the file that causes it (each of the query's files compiled alone).
local function query_problem(lang, name, err)
  for _, file in ipairs(vim.treesitter.query.get_files(lang, name)) do
    local handle = io.open(file, "r")
    if handle then
      local ok, file_err = pcall(vim.treesitter.query.parse, lang, handle:read("*a"))
      handle:close()
      if not ok then
        return first_line(file_err) .. " in " .. file
      end
    end
  end
  return first_line(err)
end

-- A query written for another version of its parser fails to compile ("Invalid node type"). Neovim's
-- ftplugins, the highlighter and injections all call query.get, so the error would abort the render with a
-- stack trace. Report it once as a warning and treat the query as missing: the language loses Tree-sitter
-- highlighting (highlight() switches it to regex syntax) and the rest of the document still renders.
local get_query = vim.treesitter.query.get
local reported = {}
local function guarded_get(lang, name)
  local ok, result = pcall(get_query, lang, name)
  if ok then
    return result
  end
  local key = lang .. "/" .. name
  if not reported[key] then
    reported[key] = true
    local problem = query_problem(lang, name, result)
    local advice = problem:find("Query error", 1, true)
        and "; update the " .. lang .. " parser and its queries together (see parser_dir in mdpreview --check)"
      or ""
    table.insert(M.warnings, ("%s %s query failed: %s%s"):format(lang, name, problem, advice))
  end
  return nil
end
-- query.get is a memoized callable table on recent Neovim (query.set calls get:clear()), a function before.
if type(get_query) == "table" then
  vim.treesitter.query.get = setmetatable({}, {
    __index = get_query,
    __call = function(_, lang, name) return guarded_get(lang, name) end,
  })
else
  vim.treesitter.query.get = guarded_get
end

-- paths: settings from config.py runtime_paths(); every key except render_markdown may be nil.
-- channel: the RPC channel for the screen grab, or nil for the pager.
function M.setup(channel, paths)
  local start = hrtime()
  M.marks.setup = start
  M.channel = channel
  vim.opt.runtimepath:append(paths.render_markdown)
  if paths.icons then
    vim.opt.runtimepath:append(paths.icons)
  end
  vim.opt.runtimepath:append(paths.root) -- queries/ shipped with mdpreview
  -- Prefer an installed parser/query directory over stale copies in plugin checkouts and the bundled ones.
  if paths.parser_dir then
    vim.opt.runtimepath:prepend(paths.parser_dir)
  end
  vim.treesitter.language.register("cpp", { "cxx", "cc" })
  vim.treesitter.language.register("bash", { "sh", "shell" })
  vim.treesitter.language.register("javascript", "js")
  vim.treesitter.language.register("python", "py")
  if paths.lua_path then
    package.path = paths.lua_path .. "/?.lua;" .. paths.lua_path .. "/?/init.lua;" .. package.path
  end
  start = lap("setup: runtimepath", start)
  vim.cmd("highlight clear")
  if paths.theme then
    dofile(paths.theme).apply()
  elseif paths.colorscheme then
    vim.cmd.colorscheme(paths.colorscheme)
  end
  start = lap("setup: theme", start)

  local config = markdown_options(paths.markdown_options)
  -- render-markdown's debounce is a throttle: an update within `debounce` ms of the previous one is
  -- dropped, so the forced update after an --all resize could vanish and the render never signalled.
  config.debounce = 0
  config.log_level = "error"
  config.log_runtime = false
  config.completions = { lsp = { enabled = false } }
  -- --syntax regex: keep render-markdown off Markdown buffers. The flag is set before :edit, whose filetype
  -- detection already attaches the plugin.
  local ignore = config.ignore
  config.ignore = function(buf)
    return M.syntax == "regex" or (ignore ~= nil and ignore(buf) or false)
  end
  if M.channel then
    config.on = {
      render = function(context)
        if context.buf == vim.api.nvim_get_current_buf() then
          notify_ready(context.win)
        end
      end,
    }
  else
    -- Pager: render in every mode, and never reveal the raw Markdown of the cursor line.
    config.render_modes = true
    config.anti_conceal = { enabled = false }
  end
  start = lap("setup: render-markdown options", start)
  if paths.icons then
    require("mini.icons").setup()
  end
  start = lap("setup: icons", start)
  require("render-markdown").setup(config)
  dofile(paths.render_markdown .. "/plugin/render-markdown.lua")
  start = lap("setup: render-markdown", start)
  M.tune_markdown_queries()
  lap("setup: query tuning", start)
end

-- Neovim's Tree-sitter highlighter does per-line work proportional to the number of injected trees, and
-- Markdown injects one markdown_inline tree per paragraph and per table cell. conceal_lines in the
-- highlights query enables a per-line hook that re-parses and walks every tree, so line-height queries cost
-- rows x trees: a 20-line viewport of a 600-row table never finished. render-markdown draws code fences
-- itself, so drop conceal_lines. (Combining the inline injections was tried and hangs on some documents.)
local function rewrite_query(lang, name, rewrite)
  local sources = {}
  for _, file in ipairs(vim.treesitter.query.get_files(lang, name)) do
    local handle = assert(io.open(file, "r"))
    table.insert(sources, rewrite(handle:read("*a")))
    handle:close()
  end
  if #sources > 0 then
    vim.treesitter.query.set(lang, name, table.concat(sources, "\n"))
  end
end

function M.tune_markdown_queries()
  rewrite_query("markdown", "highlights", function(text)
    return (text:gsub('%(#set! conceal_lines ""%)', ""))
  end)
end

local function has_highlights(lang)
  return pcall(vim.treesitter.language.add, lang) and #vim.treesitter.query.get_files(lang, "highlights") > 0
end

-- Highlight a non-Markdown buffer with Tree-sitter when the language has a highlights query,
-- otherwise with Neovim's regex syntax file for the filetype.
-- syntax: "auto" uses Tree-sitter when lang has a highlights query, "regex" always uses Vim's syntax files.
local function highlight(filetype, lang, syntax)
  local start = hrtime()
  vim.bo.filetype = filetype
  start = lap("open: filetype", start)
  local treesitter = syntax ~= "regex" and has_highlights(lang)
  start = lap("open: parser load", start)
  if treesitter then
    vim.treesitter.start(0, lang)
    start = lap("open: treesitter start", start)
    if vim.treesitter.query.get(lang, "highlights") == nil then -- Did not compile (warned); memoized otherwise.
      vim.treesitter.stop(0)
      treesitter = false
    end
  end
  if treesitter then
    -- Parse synchronously, injections included, so the captured screen is fully highlighted.
    vim.treesitter.get_parser(0, lang):parse(true)
    lap("open: parse", start)
    M.engine = "treesitter"
  else
    if vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()] then
      vim.treesitter.stop(0) -- Started by the filetype's ftplugin, e.g. Neovim's own for Lua.
    end
    vim.cmd("syntax enable")
    vim.bo.syntax = filetype
    lap("open: regex syntax", start)
    M.engine = "syntax"
  end
end

-- Edit path and highlight it. spec: {filetype, lang} from mdpreview, or nil to use Neovim's detection with a
-- Markdown fallback. syntax: "auto" (default) or "regex"; regex Markdown skips render-markdown.
local function load(path, spec, syntax)
  M.syntax = syntax
  local start = hrtime()
  vim.api.nvim_cmd({ cmd = "edit", args = { path }, magic = { file = false, bar = false }, mods = { silent = true } }, {})
  start = lap("open: edit", start)
  if spec == nil or spec == vim.NIL then
    local detected = vim.filetype.match({ buf = 0, filename = path })
    spec = { filetype = detected or "markdown", lang = vim.treesitter.language.get_lang(detected or "markdown") }
    lap("open: filetype detection", start)
  end
  M.filetype = spec.filetype
  M.rendered = M.filetype == "markdown" and syntax ~= "regex"
  if M.rendered then
    start = hrtime()
    vim.bo.filetype = "markdown"
    start = lap("open: filetype", start)
    vim.treesitter.start(0, "markdown")
    lap("open: treesitter start", start)
    M.engine = "render-markdown"
  else
    highlight(M.filetype, spec.lang or M.filetype, syntax)
  end
end

function M.open(path, line, token, spec, syntax)
  M.token = token
  vim.v.errmsg = ""
  load(path, spec, syntax)
  local last = vim.api.nvim_buf_line_count(0)
  assert(line <= last, "Requested line exceeds document length (" .. last .. ")")
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.fn.winrestview({ topline = line, leftcol = 0, skipcol = 0 })
  M.update("Preview")
  return vim.api.nvim_get_current_buf()
end

function M.update(event)
  M.update_started = hrtime()
  if M.rendered then
    require("render-markdown.core.ui").update(
      vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win(), event, true
    )
  else
    notify_ready(vim.api.nvim_get_current_win())
  end
end

function M.resized(token)
  M.token = token
  vim.fn.winrestview({ topline = 1, leftcol = 0, skipcol = 0 })
  M.update("PreviewResize")
end

function M.info()
  local view = vim.fn.winsaveview()
  local namespace = vim.api.nvim_get_namespaces()["render-markdown.nvim"]
  return {
    total_height = vim.api.nvim_win_text_height(0, {}).all,
    remaining_height = vim.api.nvim_win_text_height(0, { start_row = view.topline - 1 }).all,
    bottom_line = vim.fn.line("w$"),
    buffer_lines = vim.api.nvim_buf_line_count(0),
    width = vim.api.nvim_win_get_width(0),
    height = vim.api.nvim_win_get_height(0),
    topline = view.topline,
    error = vim.v.errmsg,
    filetype = M.filetype,
    engine = M.engine,
    extmarks = #vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}),
    normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false }),
    timings = M.timings,
    warnings = M.warnings,
    marks = M.marks,
    callbacks = M.callbacks,
  }
end

-- Built-in pager: the document in this Neovim, attached to the user's terminal. session: {paths, path,
-- filetype} from mdpreview's page_nvim(). Keys follow less where Neovim's own would edit the buffer.
-- mdpreview --check: compile the highlights and injections queries of each language, and write a JSON report
-- to stdout: languages whose queries compile, those without a parser or a highlights query (shown with regex
-- syntax), and the compile failures (M.warnings).
-- installed: also every parser on the runtimepath, since code fences can inject any of them (slow).
function M.check_queries(langs, installed)
  local report = { ok = {}, no_parser = {}, no_highlights = {} }
  local seen = {}
  for _, lang in ipairs(langs) do
    seen[lang] = true
  end
  for _, file in ipairs(installed and vim.api.nvim_get_runtime_file("parser/*.so", true) or {}) do
    local lang = vim.fn.fnamemodify(file, ":t:r")
    if not seen[lang] then
      seen[lang] = true
      table.insert(langs, lang)
    end
  end
  for _, lang in ipairs(langs) do
    if not pcall(vim.treesitter.language.add, lang) then
      table.insert(report.no_parser, lang)
    elseif #vim.treesitter.query.get_files(lang, "highlights") == 0 then
      table.insert(report.no_highlights, lang)
    else
      local before = #M.warnings
      vim.treesitter.query.get(lang, "highlights")
      vim.treesitter.query.get(lang, "injections")
      if #M.warnings == before then
        table.insert(report.ok, lang)
      end
    end
  end
  report.warnings = M.warnings
  io.stdout:write(vim.json.encode(report))
end

function M.pager(session)
  vim.o.shortmess = vim.o.shortmess .. "IF"
  M.setup(nil, session.paths)
  load(session.path, session.filetype, session.syntax)
  if M.rendered then
    -- render-markdown's update() renders from a scheduled callback, after Neovim has drawn the raw text once.
    -- Run its updater directly so the first frame is rendered; fall back to update() if that internal changes.
    local ui = require("render-markdown.core.ui")
    local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
    if not (ui.updater and pcall(function() ui.updater.new(buf, win, true):run() end)) then
      ui.update(buf, win, "Pager", true)
    end
  end
  vim.bo.modifiable = false
  vim.bo.modified = false
  if #M.warnings > 0 then
    vim.notify("mdpreview: " .. table.concat(M.warnings, "\nmdpreview: "), vim.log.levels.WARN)
  end
  local map = function(lhs, rhs)
    vim.keymap.set("n", lhs, rhs, { buffer = true, nowait = true, silent = true })
  end
  map("q", "<Cmd>qa!<CR>")
  map("<Space>", "<C-f>")
  map("f", "<C-f>")
  map("b", "<C-b>")
  map("d", "<C-d>")
  map("u", "<C-u>")
end
