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
	cmd = {
		"Shepherd",
		"ShepherdAdd",
		"ShepherdList",
		"ShepherdCapture",
		"ShepherdStats",
		"ShepherdBoards",
		"ShepherdBoardsArchived",
	},
	keys = {
		{ "<leader>T", "<cmd>Shepherd<cr>", desc = "shepherd board" },
		{ "<leader>tg", "<cmd>Shepherd!<cr>", desc = "shepherd global view (all boards)" },
		{ "<leader>ta", "<cmd>ShepherdAdd<cr>", desc = "shepherd quick-add" },
		{ "<leader>tl", "<cmd>ShepherdList<cr>", desc = "shepherd list / pick" },
		{ "<leader>tc", "<cmd>ShepherdCapture<cr>", desc = "shepherd capture line" },
		{ "<leader>tc", ":ShepherdCapture<cr>", mode = "x", desc = "shepherd capture selection" },
		{ "<leader>ts", "<cmd>ShepherdStats<cr>", desc = "shepherd stats" },
		{ "<leader>tp", "<cmd>ShepherdBoards<cr>", desc = "shepherd boards" },
	},
	opts = {
		-- per-repo board (own file under ~/.config/shepherd/boards/)
		board = function()
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
- `:Shepherd!` — open the read-only global view across all boards
  (`shepherd --all`).
- `:ShepherdAdd` — prompt for a todo, then `shepherd add` it. An open board
  reloads and shows it within ~2s.
- `:ShepherdAdd deploy api @work !h due:tomorrow` — add directly, with the same
  quick-add tokens the board accepts.
- `:ShepherdList` — pick an item (`vim.ui.select`), then act on it: toggle
  done/undone, **edit** (a pre-filled quick-add line — text, `@category`,
  `!priority`, `due:`, `defer:`, `link:`, `note:`), set a **status**, add a
  **subtask**, **rm**, or **open link** when it has one. Subtasks show indented
  under their parent and take the same actions. Uses whatever `vim.ui.select` UI
  you have (dressing, snacks, telescope-ui-select), or the built-in menu.
- `:ShepherdList work` — pick within a filtered view. `:ShepherdList!` picks
  across all boards (read-only — items show their `[board]`; only open-link is
  offered).
- `:ShepherdStats` — open shepherd's stats charts in the floating terminal.
- `:ShepherdBoards` — pick a board (shows `open/total`, `*` marks current),
  then **switch** the session to it, **rename**, **archive**, or **delete** it
  (delete shows a dry-run preview and asks to confirm first). Switching overrides
  the configured `board` until you switch again or restart.
- `:ShepherdBoardsArchived` — pick an archived board to unarchive.
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

The count covers the configured board (all todos on it, independent
of `config.filter`); with no `board` set, the default board. A refresh
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
	board = nil,             -- string | fun():string | nil — passed as --board
	float = { width = 0.8, height = 0.8, border = "rounded" },
	status = { icon = "" },  -- prefix for status(); e.g. a nerd-font glyph
})
```

- `filter` — a string, or a function returning one (evaluated on each open, so
  it can track the current project). `nil`/empty means no filter.
- `board` — a shepherd board name (string or function, e.g. derive it
  from the cwd). Scopes everything — board, add, list/pick, statusline counts —
  to `~/.config/shepherd/boards/<name>.md`. `nil`/empty uses the default
  board. `:Shepherd!` ignores it and shows all boards. `:ShepherdBoards` →
  *switch* overrides it for the session.
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
`flatten`, `edit_seed`, `clean`, `build_cmd`/filter resolution) via the
`_internal` table.
