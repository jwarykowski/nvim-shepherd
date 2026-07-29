# contributing

A Neovim plugin with no dependencies, three files under `lua/shepherd/`:

| File | What |
|------|------|
| `init.lua` | commands, the picker, quick-add/capture, statusline counts |
| `board.lua` | the board switcher and board CRUD, over `boards --json` |
| `health.lua` | `:checkhealth shepherd` — finds the binary |

Every read and write goes through the installed `shepherd` binary. The plugin
never parses or writes a board file itself — the binary owns that format, so
keep new features behind a CLI verb rather than touching markdown here.

```sh
make fmt     # stylua
make lint    # stylua --check + luacheck
make test    # busted
make check   # lint + test
```

Test deps: [busted](https://lunarmodules.github.io/busted/) and `nlua` (the specs
run under Neovim) — `luarocks install busted nlua`. Formatting and linting need
[stylua](https://github.com/JohnnyMorganz/StyLua) and
[luacheck](https://github.com/lunarmodules/luacheck).

## tests

`tests/shepherd_spec.lua` drives the pure helpers — `tally`, `format_status`,
`label`, `flatten`, `edit_seed`, `clean`, and `build_cmd`/filter resolution —
exposed on the `_internal` table. Keep new logic in a pure helper where you can:
anything that only reshapes data is testable without a running UI, and the
command wiring around it stays thin.

CI (`.github/workflows/pull-request.yml`) runs the lint job plus the suite on
Neovim stable and nightly. Both must be green.

## conventions

- stylua: tabs, 120 columns (`.stylua.toml`). Run `make fmt` before committing.
- luacheck: `vim` is the only permitted global (`.luacheckrc`).
- [Conventional Commits](https://www.conventionalcommits.org) — `feat:`, `fix:`,
  `docs:`, `chore:`.
- Branch for the change; don't commit to `master`.
- The plugin targets the Neovim version in [requirements](README.md#requirements)
  — no compatibility shims for older releases.

## demo gifs

The README's `assets/demo.gif` (the commands) and `assets/stats.gif`
(`:ShepherdStats`) are scripted with
[vhs](https://github.com/charmbracelet/vhs), not screen-captured — regenerate
them after any change to the commands, the picker, or the statusline:

```sh
brew install vhs     # pulls in ttyd + ffmpeg
vhs assets/demo.tape
vhs assets/stats.tape
```

Both tapes run nvim with `assets/demo-init.lua` — this checkout and nothing else,
so the recording never shows another plugin's UI — against a board seeded by
`assets/demo-seed.sh` under `mktemp -d`, with `$SHEPHERD_TODO_FILE` and
`$SHEPHERD_CONFIG` pointed at it. A real board or config is never touched.

Two things worth knowing when you edit a tape:

- The seed writes its dates relative to today, so due dates and the aging numbers
  stay meaningful whenever a gif is re-recorded.
- The window has to clear the tallest screen it shows. `shepherd stats` is 56
  rows and the float only gets 85% of the window, which is why `stats.tape`
  records at a smaller font in a taller window than `demo.tape`.

Named boards live under `$XDG_CONFIG_HOME/shepherd/boards/`, *not* wherever
`$SHEPHERD_TODO_FILE` points — that variable only overrides the default board's
file. Set `XDG_CONFIG_HOME` as well when you want a scratch tree for board
commands (`:ShepherdBoards` and friends), or they will read and write your real
boards.
