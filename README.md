# nvim-shepherd

Neovim wrapper for [shepherd](https://github.com/jwarykowski/shepherd) — opens
the todo board in a floating terminal and adds items without leaving your
buffer. Zero dependencies; drives the installed `shepherd` binary.

- [requirements](#requirements)
- [install](#install)
- [usage](#usage)
- [statusline](#statusline)
- [configuration](#configuration)
- [development](#development)

## requirements

- Neovim ≥ 0.11 (`vim.fn.jobstart({ term = true })`, `vim.system`).
- `shepherd` on `$PATH` — `brew install jwarykowski/tap/shepherd`.

## install

lazy.nvim — add the spec. With a structured config (e.g. LazyVim), drop it in
its own file at `lua/plugins/shepherd.lua`; otherwise add it to your existing
plugin list:

```lua
return {
	"jwarykowski/nvim-shepherd",
	cmd = { "Shepherd", "ShepherdAdd", "ShepherdList", "ShepherdCapture" },
	keys = {
		{ "<leader>T", "<cmd>Shepherd<cr>", desc = "shepherd board" },
		{ "<leader>tg", "<cmd>Shepherd!<cr>", desc = "shepherd global view (all boards)" },
		{ "<leader>ta", "<cmd>ShepherdAdd<cr>", desc = "shepherd quick-add" },
		{ "<leader>tl", "<cmd>ShepherdList<cr>", desc = "shepherd list / pick" },
		{ "<leader>tc", "<cmd>ShepherdCapture<cr>", desc = "shepherd capture line" },
		{ "<leader>tc", ":ShepherdCapture<cr>", mode = "x", desc = "shepherd capture selection" },
	},
	opts = {
		-- per-repo project board (own file under ~/.config/shepherd/projects/)
		project = function()
			return vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
		end,
	},
}
```

`opts` (even `{}`) triggers `setup()`, which registers the commands. `cmd` and
`keys` lazy-load the plugin — it loads on first `:Shepherd`, `<leader>T`, or
`<leader>ta`.

## usage

- `:Shepherd` — open the board in a floating terminal. Closes when shepherd
  exits (`q`).
- `:Shepherd work` — open with an explicit filter, overriding the configured
  one for that view.
- `:Shepherd!` — open the read-only global view across all project boards
  (`shepherd --all`).
- `:ShepherdAdd` — prompt for a todo, then `shepherd add` it. An open board
  reloads and shows it within ~2s.
- `:ShepherdAdd deploy api @work !h due:tomorrow` — add directly, with the same
  quick-add tokens the board accepts.
- `:ShepherdList` — pick an item (`vim.ui.select`), then mark it done/undone or
  remove it. Uses whatever `vim.ui.select` UI you have (dressing, snacks,
  telescope-ui-select), or the built-in menu.
- `:ShepherdCapture` — turn the current line into a todo; in visual mode
  (`:'<,'>ShepherdCapture`) the selection. Strips a leading comment marker and
  `TODO:`/`FIXME:`, then opens the add prompt pre-filled so you can tweak it.

Run `:checkhealth shepherd` to verify the binary is found.

## statusline

`require("shepherd").status()` returns a short string — the open count, plus an
overdue suffix — or `""` when there's nothing open or the count hasn't loaded
yet. Counts refresh after any add/done/rm you make and on `FocusGained`; call
`require("shepherd").refresh()` to force it.

lualine:

```lua
require("lualine").setup({
	sections = {
		lualine_x = { { function() return require("shepherd").status() end } },
	},
})
```

Native statusline:

```lua
vim.o.statusline = "%{v:lua.require'shepherd'.status()}"
```

The count covers the configured project's board (all todos on it, independent
of `config.filter`); with no `project` set, the default board. A refresh
fires the `User ShepherdStatusUpdate` autocmd — hook it if your statusline
needs a manual redraw:

```lua
vim.api.nvim_create_autocmd("User", {
	pattern = "ShepherdStatusUpdate",
	callback = function() vim.cmd.redrawstatus() end,
})
```

## configuration

Defaults:

```lua
require("shepherd").setup({
	cmd = "shepherd",        -- binary name / path
	filter = nil,            -- string | fun():string | nil — passed as --filter
	project = nil,           -- string | fun():string | nil — passed as --project
	float = { width = 0.8, height = 0.8, border = "rounded" },
	status = { icon = "" },  -- prefix for status(); e.g. a nerd-font glyph
})
```

- `filter` — a string, or a function returning one (evaluated on each open, so
  it can track the current project). `nil`/empty means no filter.
- `project` — a shepherd project board name (string or function, e.g. derive it
  from the cwd). Scopes everything — board, add, list/pick, statusline counts —
  to `~/.config/shepherd/projects/<name>.md`. `nil`/empty uses the default
  board. `:Shepherd!` ignores it and shows all boards.
- `float` — fractions of the editor size, and the window border.
- `status.icon` — prefix for `status()`. With an icon it renders `<icon> 3`;
  empty renders `3 todo`.

## development

Tooling: [stylua](https://github.com/JohnnyMorganz/StyLua),
[luacheck](https://github.com/lunarmodules/luacheck), and
[busted](https://lunarmodules.github.io/busted/) + `nlua` (tests run under
Neovim). Install the test deps with `luarocks install busted nlua`.

```sh
make fmt     # format
make lint    # stylua --check + luacheck
make test    # busted
make check   # lint + test
```

CI (`.github/workflows/pull-request.yml`) runs lint plus the suite on Neovim
stable and nightly. Tests cover the pure helpers (`tally`, `format_status`, `label`,
`clean`, `build_cmd`/filter resolution) via the `_internal` table.
