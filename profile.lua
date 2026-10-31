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

function M.setup(channel, paths)
  M.channel = channel
  for _, path in ipairs(paths.runtime) do
    vim.opt.runtimepath:append(path)
  end
  -- Use the editor's installed parser/query pairs ahead of stale copies in plugin checkouts.
  vim.opt.runtimepath:prepend(paths.editor_site)
  vim.treesitter.language.register("cpp", { "cxx", "cc" })
  vim.treesitter.language.register("bash", { "sh", "shell" })
  vim.treesitter.language.register("javascript", "js")
  vim.treesitter.language.register("python", "py")
  package.path = paths.editor_lua .. "/?.lua;" .. paths.editor_lua .. "/?/init.lua;" .. package.path
  vim.cmd("highlight clear")
  dofile(paths.theme).apply()

  -- Read the existing Markdown options without starting the editor's plugin manager.
  local config
  package.loaded["render-markdown"] = { setup = function(value) config = value end }
  dofile(paths.markdown_config)
  package.loaded["render-markdown"] = nil
  assert(config, "Markdown configuration did not call setup")
  -- render-markdown's debounce is a throttle: an update within `debounce` ms of the previous one is
  -- dropped, so the forced update after an --all resize could vanish and the render never signalled.
  config.debounce = 0
  config.log_level = "error"
  config.log_runtime = false
  config.completions = { lsp = { enabled = false } }
  config.on = {
    render = function(context)
      if context.buf == vim.api.nvim_get_current_buf() then
        notify_ready(context.win)
      end
    end,
  }
  require("mini.icons").setup()
  require("render-markdown").setup(config)
  dofile(paths.markdown_plugin .. "/plugin/render-markdown.lua")
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

-- spec: {filetype, lang} from mdpreview, or nil to use Neovim's detection with a Markdown fallback.
function M.open(path, line, token, spec)
  M.token = token
  vim.v.errmsg = ""
  vim.api.nvim_cmd({ cmd = "edit", args = { path }, magic = { file = false, bar = false }, mods = { silent = true } }, {})
  if spec == nil or spec == vim.NIL then
    local detected = vim.filetype.match({ buf = 0, filename = path })
    spec = { filetype = detected or "markdown", lang = vim.treesitter.language.get_lang(detected or "markdown") }
  end
  M.filetype = spec.filetype
  local last = vim.api.nvim_buf_line_count(0)
  assert(line <= last, "Requested line exceeds document length (" .. last .. ")")
  if M.filetype == "markdown" then
    vim.bo.filetype = "markdown"
    vim.treesitter.start(0, "markdown")
    M.engine = "render-markdown"
  else
    highlight(M.filetype, spec.lang or M.filetype)
  end
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
