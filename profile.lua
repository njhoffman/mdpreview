local M = { token = 0 }
_G.mdpreview = M

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
  vim.schedule(function()
    if token ~= M.token then
      return
    end
    vim.cmd("redraw")
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

-- paths: settings from config.py runtime_paths(); every key except render_markdown may be nil.
-- channel: the RPC channel for the screen grab, or nil for the pager.
function M.setup(channel, paths)
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
  vim.cmd("highlight clear")
  if paths.theme then
    dofile(paths.theme).apply()
  elseif paths.colorscheme then
    vim.cmd.colorscheme(paths.colorscheme)
  end

  local config = markdown_options(paths.markdown_options)
  -- render-markdown's debounce is a throttle: an update within `debounce` ms of the previous one is
  -- dropped, so the forced update after an --all resize could vanish and the render never signalled.
  config.debounce = 0
  config.log_level = "error"
  config.log_runtime = false
  config.completions = { lsp = { enabled = false } }
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
  if paths.icons then
    require("mini.icons").setup()
  end
  require("render-markdown").setup(config)
  dofile(paths.render_markdown .. "/plugin/render-markdown.lua")
  M.tune_markdown_queries()
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
local function highlight(filetype, lang)
  vim.bo.filetype = filetype
  if has_highlights(lang) then
    vim.treesitter.start(0, lang)
    -- Parse synchronously, injections included, so the captured screen is fully highlighted.
    vim.treesitter.get_parser(0, lang):parse(true)
    M.engine = "treesitter"
  else
    vim.cmd("syntax enable")
    vim.bo.syntax = filetype
    M.engine = "syntax"
  end
end

-- Edit path and highlight it. spec: {filetype, lang} from mdpreview, or nil to use Neovim's detection with a
-- Markdown fallback.
local function load(path, spec)
  vim.api.nvim_cmd({ cmd = "edit", args = { path }, magic = { file = false, bar = false }, mods = { silent = true } }, {})
  if spec == nil or spec == vim.NIL then
    local detected = vim.filetype.match({ buf = 0, filename = path })
    spec = { filetype = detected or "markdown", lang = vim.treesitter.language.get_lang(detected or "markdown") }
  end
  M.filetype = spec.filetype
  if M.filetype == "markdown" then
    vim.bo.filetype = "markdown"
    vim.treesitter.start(0, "markdown")
    M.engine = "render-markdown"
  else
    highlight(M.filetype, spec.lang or M.filetype)
  end
end

function M.open(path, line, token, spec)
  M.token = token
  vim.v.errmsg = ""
  load(path, spec)
  local last = vim.api.nvim_buf_line_count(0)
  assert(line <= last, "Requested line exceeds document length (" .. last .. ")")
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.fn.winrestview({ topline = line, leftcol = 0, skipcol = 0 })
  M.update("Preview")
  return vim.api.nvim_get_current_buf()
end

function M.update(event)
  if M.filetype == "markdown" then
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
  }
end

-- Built-in pager: the document in this Neovim, attached to the user's terminal. session: {paths, path,
-- filetype} from mdpreview's page_nvim(). Keys follow less where Neovim's own would edit the buffer.
function M.pager(session)
  vim.o.shortmess = vim.o.shortmess .. "IF"
  M.setup(nil, session.paths)
  load(session.path, session.filetype)
  if M.filetype == "markdown" then
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
