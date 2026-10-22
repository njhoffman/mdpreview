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

function M.setup(channel, paths)
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
  config.log_level = "error"
  config.log_runtime = false
  config.completions = { lsp = { enabled = false } }
  config.on = {
    render = function(context)
      local token = M.token
      vim.schedule(function()
        if token ~= M.token or context.buf ~= vim.api.nvim_get_current_buf() then
          return
        end
        vim.cmd("redraw!")
        vim.rpcnotify(channel, "mdpreview_ready", {
          token = token,
          buffer = context.buf,
          topline = vim.fn.winsaveview().topline,
          width = vim.api.nvim_win_get_width(context.win),
          height = vim.api.nvim_win_get_height(context.win),
        })
      end)
    end,
  }
  require("mini.icons").setup()
  require("render-markdown").setup(config)
  dofile(paths.markdown_plugin .. "/plugin/render-markdown.lua")
end

function M.open(path, line, token)
  M.token = token
  vim.v.errmsg = ""
  vim.api.nvim_cmd({ cmd = "edit", args = { path }, magic = { file = false, bar = false }, mods = { silent = true } }, {})
  vim.bo.filetype = "markdown"
  vim.treesitter.start(0, "markdown")
  local last = vim.api.nvim_buf_line_count(0)
  assert(line <= last, "Requested line exceeds document length (" .. last .. ")")
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.fn.winrestview({ topline = line, leftcol = 0, skipcol = 0 })
  require("render-markdown.core.ui").update(
    vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win(), "Preview", true
  )
  return vim.api.nvim_get_current_buf()
end

function M.resized(token)
  M.token = token
  vim.fn.winrestview({ topline = 1, leftcol = 0, skipcol = 0 })
  require("render-markdown.core.ui").update(
    vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win(), "PreviewResize", true
  )
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
    extmarks = #vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, {}),
    normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false }),
  }
end
