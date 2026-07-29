-- Minimal init for the vhs recording (assets/demo.tape): loads this checkout,
-- nothing else. No plugin manager, no colourscheme, no other plugins, so what
-- the gif shows is only ever nvim-shepherd.
--
--   nvim -u assets/demo-init.lua
--
-- The board comes from $SHEPHERD_TODO_FILE (the tape points it at a scratch
-- file), so `board` stays nil here.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)

vim.o.swapfile = false
vim.o.shadafile = "NONE"
vim.o.termguicolors = true
vim.o.number = true
vim.o.showmode = false
vim.o.laststatus = 3
vim.o.statusline = "  %t%=%{v:lua.require'shepherd'.status()}  "

require("shepherd").setup({
	status = { icon = "todo" },
	float = { width = 0.85, height = 0.85, border = "rounded" },
})

-- The counts land asynchronously, so redraw when they do — same hook the README
-- suggests for a statusline that doesn't refresh itself.
vim.api.nvim_create_autocmd("User", {
	pattern = "ShepherdStatusUpdate",
	callback = function()
		vim.cmd.redrawstatus()
	end,
})
