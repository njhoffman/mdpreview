-- Usage: nvim --clean -S redraw.lua FILE  (in a terminal with many rows); writes timing to $OUT
vim.treesitter.start(0, "markdown")
vim.wo.conceallevel = 2
vim.treesitter.get_parser(0):parse(true)
vim.cmd("redraw")
local t0 = vim.uv.hrtime()
for _ = 1, 3 do vim.cmd("redraw!") end
local f = io.open(os.getenv("OUT"), "a")
f:write(string.format("%s rows=%d redraw!=%.0f ms (avg of 3)\n", vim.fn.expand("%"), vim.o.lines, (vim.uv.hrtime() - t0) / 3e6))
f:close()
vim.cmd("qa!")
