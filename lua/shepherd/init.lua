local M = {}

local defaults = {
	cmd = "shepherd",
	filter = nil, -- string | fun():string | nil
	board = nil, -- string | fun():string | nil
	float = { width = 0.8, height = 0.8, border = "rounded" },
	status = { icon = "" }, -- prefix for M.status(), e.g. a nerd-font glyph
}

local config = vim.tbl_deep_extend("force", {}, defaults)

-- active_board is a session override set by the board switcher. When non-nil
-- it wins over config.board; "default" means the unscoped default board.
local active_board = nil

-- binary returns the configured shepherd command (used by the health check).
function M.binary()
	return config.cmd
end

-- set_active_board switches the board the session targets, overriding
-- config.board until changed again.
function M.set_active_board(name)
	active_board = name
end

-- with_board appends "--board <name>" to cmd when one is in effect: the
-- session override if set, else the configured string/function. Shepherd wants
-- flags after the verb.
local function with_board(cmd)
	local p = active_board
	if p == nil then
		p = config.board
		p = type(p) == "function" and p() or p
	end
	if p and p ~= "" and p ~= "default" then
		cmd[#cmd + 1] = "--board"
		cmd[#cmd + 1] = p
	end
	return cmd
end

-- run invokes the shepherd CLI async; notifies on failure, and on success only
-- when ok_msg is given. Board-scoped so mutations land on the same board
-- list()/pick() read, unless opts.no_board is set (board verbs name their
-- target explicitly).
local function run(args, ok_msg, opts)
	local cmd = { config.cmd }
	for _, a in ipairs(args) do
		cmd[#cmd + 1] = a
	end
	if not (opts and opts.no_board) then
		with_board(cmd)
	end
	vim.system(cmd, { text = true }, function(r)
		vim.schedule(function()
			if r.code == 0 then
				if ok_msg then
					vim.notify("shepherd: " .. ok_msg)
				end
				M.refresh() -- counts changed
			else
				vim.notify("shepherd: " .. ((r.stderr or ""):gsub("%s+$", "")), vim.log.levels.ERROR)
			end
		end)
	end)
end

-- resolve_filter returns the effective filter: an explicit override, else the
-- configured string/function, else nil.
local function resolve_filter(override)
	if override ~= nil then
		return override
	end
	local f = config.filter
	return type(f) == "function" and f() or f
end

local function build_cmd(filter_override, all)
	local parts = { config.cmd }
	if all then
		parts[#parts + 1] = "--all"
	else
		with_board(parts)
	end
	local f = resolve_filter(filter_override)
	if f and f ~= "" then
		parts[#parts + 1] = "--filter"
		parts[#parts + 1] = f
	end
	return parts
end

-- float_term runs argv in a terminal inside a centered floating window, then
-- refreshes counts. Shared by open/stats. Interactive commands (the board) quit
-- on `q`, so the window closes when the process exits. One-shot commands (stats)
-- print and exit immediately; pass hold=true to keep the output up until the
-- user dismisses it with q/esc.
local function float_term(argv, hold)
	local cols, rows = vim.o.columns, vim.o.lines
	local w = math.floor(cols * config.float.width)
	local h = math.floor(rows * config.float.height)
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = w,
		height = h,
		row = math.floor((rows - h) / 2),
		col = math.floor((cols - w) / 2),
		style = "minimal",
		border = config.float.border,
	})
	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	vim.fn.jobstart(argv, {
		term = true,
		on_exit = function()
			if hold and vim.api.nvim_win_is_valid(win) then
				vim.cmd("stopinsert")
				for _, k in ipairs({ "q", "<esc>", "<cr>" }) do
					vim.keymap.set("n", k, close, { buffer = buf, nowait = true })
				end
			else
				close()
			end
			M.refresh() -- board edits change counts
		end,
	})
	vim.cmd("startinsert")
end

function M.open(filter, all)
	float_term(build_cmd(filter, all))
end

-- stats opens shepherd's native terminal chart view in the float. With `all`,
-- aggregates every board (shepherd stats --all). stats is one-shot, so the float
-- holds until dismissed.
function M.stats(all)
	local argv = { config.cmd, "stats" }
	if all then
		argv[#argv + 1] = "--all"
	end
	float_term(argv, true)
end

function M.add(text)
	if not text or text == "" then
		return
	end
	run({ "add", text }, "added")
end

function M.quick_add()
	vim.ui.input({ prompt = "todo: " }, function(text)
		M.add(text)
	end)
end

-- list fetches items via `list --json` and passes the decoded array to cb.
-- Scoped to the current board unless `all` (read-only aggregate across every
-- board). An explicit `filter` narrows the result; the configured config.filter
-- is deliberately NOT applied so counts cover the whole board.
local function list(cb, filter, all)
	local cmd = { config.cmd, "list", "--json" }
	if all then
		cmd[#cmd + 1] = "--all"
	else
		with_board(cmd)
	end
	if filter and filter ~= "" then
		cmd[#cmd + 1] = "--filter"
		cmd[#cmd + 1] = filter
	end
	vim.system(cmd, { text = true }, function(r)
		vim.schedule(function()
			if r.code ~= 0 then
				vim.notify("shepherd: " .. ((r.stderr or ""):gsub("%s+$", "")), vim.log.levels.ERROR)
				return
			end
			local ok, items = pcall(vim.json.decode, r.stdout)
			if not ok then
				vim.notify("shepherd: could not parse `list --json`", vim.log.levels.ERROR)
				return
			end
			cb(items or {})
		end)
	end)
end

-- label renders an item for the picker, appending only non-empty fields:
-- subtask indent, [board] (--all view), <status>, @category, !priority, and
-- due/defer dates.
local function label(it)
	local parts = { it._sub and ("  " .. (it.done and "[x]" or "[ ]")) or (it.done and "[x]" or "[ ]"), it.text }
	if it.board and it.board ~= "" then
		parts[#parts + 1] = "[" .. it.board .. "]"
	end
	if it.status and it.status ~= "" and not it.done then
		parts[#parts + 1] = "<" .. it.status .. ">"
	end
	if it.category and it.category ~= "" then
		parts[#parts + 1] = "@" .. it.category
	end
	if it.priority and it.priority ~= "" then
		parts[#parts + 1] = "!" .. it.priority:lower()
	end
	if it.due and it.due ~= "" then
		parts[#parts + 1] = "due:" .. it.due
	end
	if it.defer and it.defer ~= "" then
		parts[#parts + 1] = "defer:" .. it.defer
	end
	return table.concat(parts, " ")
end

-- flatten yields picker rows: each parent followed by its subtasks. _ref is the
-- CLI address ("n" for parents, "n.m" for subtasks); _sub marks subtask rows.
local function flatten(items)
	local rows = {}
	for _, it in ipairs(items) do
		it._ref = tostring(it.index)
		rows[#rows + 1] = it
		for _, sub in ipairs(it.subtasks or {}) do
			sub._ref = it.index .. "." .. sub.index
			sub._sub = true
			rows[#rows + 1] = sub
		end
	end
	return rows
end

-- edit_seed reconstructs a quick-add line from an item so the edit prompt is
-- pre-filled. note: consumes the rest of the line, so it goes last.
local function edit_seed(it)
	local parts = { it.text or "" }
	if it.category and it.category ~= "" then
		parts[#parts + 1] = "@" .. it.category
	end
	if it.priority and it.priority ~= "" then
		parts[#parts + 1] = "!" .. it.priority:lower()
	end
	if it.due and it.due ~= "" then
		parts[#parts + 1] = "due:" .. it.due
	end
	if it.defer and it.defer ~= "" then
		parts[#parts + 1] = "defer:" .. it.defer
	end
	if it.link and it.link ~= "" then
		parts[#parts + 1] = "link:" .. it.link
	end
	if it.note and it.note ~= "" then
		parts[#parts + 1] = "note:" .. it.note
	end
	return table.concat(parts, " ")
end

-- statusline counts, refreshed async. `ready` gates the first render.
local counts = { open = 0, overdue = 0, ready = false }

-- tally counts open items and those overdue relative to today (ISO date).
local function tally(items, today)
	local open, overdue = 0, 0
	for _, it in ipairs(items) do
		if not it.done then
			open = open + 1
			if it.due and it.due ~= "" and it.due < today then
				overdue = overdue + 1
			end
		end
	end
	return open, overdue
end

-- format_status renders the counts: "" when nothing open, else the open count
-- with the configured icon prefix and an overdue suffix.
local function format_status(open, overdue, icon)
	if open == 0 then
		return ""
	end
	local s = (icon ~= "" and (icon .. " ") or "") .. open .. (icon ~= "" and "" or " todo")
	if overdue > 0 then
		s = s .. " (" .. overdue .. " overdue)"
	end
	return s
end

-- refresh recomputes the open/overdue counts and fires User
-- ShepherdStatusUpdate so a statusline can redraw. Counts cover the configured
-- board's whole board (not scoped to `config.filter`).
function M.refresh()
	list(function(items)
		counts.open, counts.overdue = tally(items, os.date("%Y-%m-%d"))
		counts.ready = true
		vim.api.nvim_exec_autocmds("User", { pattern = "ShepherdStatusUpdate" })
	end)
end

-- status returns a statusline string: "" when empty/loading, else the open
-- count with the configured icon and an overdue suffix.
function M.status()
	if not counts.ready then
		M.refresh()
		return ""
	end
	return format_status(counts.open, counts.overdue, config.status.icon)
end

-- pick shows items (with subtasks) then an action menu on the chosen one:
-- toggle done, edit, set status, add a subtask, remove, or open its link.
-- With `all`, the aggregate view is read-only (indexes aren't valid for
-- mutations) so only open-link is offered. An optional `filter` narrows the list.
function M.pick(filter, all)
	list(function(items)
		if #items == 0 then
			vim.notify("shepherd: no items")
			return
		end
		vim.ui.select(flatten(items), { prompt = "shepherd", format_item = label }, function(choice)
			if not choice then
				return
			end
			if all then
				if choice.link and choice.link ~= "" then
					vim.ui.open(choice.link)
				else
					vim.notify("shepherd: --all view is read-only")
				end
				return
			end
			local ref = choice._ref
			local toggle = choice.done and "undone" or "done"
			local actions = { toggle, "edit", "status", "rm" }
			if not choice._sub then
				actions[#actions + 1] = "subtask"
				actions[#actions + 1] = "archive"
			end
			if choice.link and choice.link ~= "" then
				actions[#actions + 1] = "open link"
			end
			vim.ui.select(actions, { prompt = choice.text }, function(act)
				if not act then
					return
				end
				if act == "edit" then
					vim.ui.input({ prompt = "edit: ", default = edit_seed(choice) }, function(v)
						if v and v ~= "" then
							run({ "edit", ref, v }, "edited " .. ref)
						end
					end)
				elseif act == "status" then
					vim.ui.input({ prompt = "status: ", default = choice.status or "" }, function(v)
						if v ~= nil then
							run({ "edit", ref, "status:" .. v }, "status " .. ref)
						end
					end)
				elseif act == "subtask" then
					vim.ui.input({ prompt = "subtask: " }, function(v)
						if v and v ~= "" then
							run({ "sub", tostring(choice.index), v }, "added subtask")
						end
					end)
				elseif act == "open link" then
					vim.ui.open(choice.link)
				else
					run({ act, ref }, act .. " " .. ref)
				end
			end)
		end)
	end, filter, all)
end

-- clean strips a leading comment marker and TODO/FIXME tag so a code comment
-- becomes plain task text.
local function clean(s)
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	s = s:gsub('^[%-/#*;"%%]+%s*', "")
	s = s:gsub("^[Tt][Oo][Dd][Oo]%s*:?%s*", "")
	s = s:gsub("^[Ff][Ii][Xx][Mm][Ee]%s*:?%s*", "")
	return s
end

-- capture seeds the add prompt from the current line, or the selected lines
-- when invoked with a range.
function M.capture(opts)
	opts = opts or {}
	local text
	if opts.range and opts.range > 0 then
		local lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
		text = table.concat(lines, " ")
	else
		text = vim.api.nvim_get_current_line()
	end
	text = clean(text)
	if text == "" then
		return
	end
	vim.ui.input({ prompt = "todo: ", default = text }, function(v)
		M.add(v)
	end)
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", {}, defaults, opts or {})

	vim.api.nvim_create_user_command("Shepherd", function(a)
		M.open(a.args ~= "" and a.args or nil, a.bang)
	end, { nargs = "?", bang = true, desc = "open the shepherd board (! = global view, optional filter)" })

	vim.api.nvim_create_user_command("ShepherdAdd", function(a)
		if a.args ~= "" then
			M.add(a.args)
		else
			M.quick_add()
		end
	end, { nargs = "*", desc = "add a todo (args or prompt)" })

	vim.api.nvim_create_user_command("ShepherdList", function(a)
		M.pick(a.args ~= "" and a.args or nil, a.bang)
	end, { nargs = "?", bang = true, desc = "pick a todo and act on it (! = all boards, optional filter)" })

	vim.api.nvim_create_user_command("ShepherdCapture", function(a)
		M.capture({ range = a.range, line1 = a.line1, line2 = a.line2 })
	end, { nargs = 0, range = true, desc = "capture current line / selection as a todo" })

	vim.api.nvim_create_user_command("ShepherdStats", function(a)
		M.stats(a.bang)
	end, { bang = true, desc = "open the stats dashboard (! = all boards)" })

	vim.api.nvim_create_user_command("ShepherdBoards", function()
		require("shepherd.board").switch()
	end, { desc = "switch board or manage boards (rename/archive/delete)" })

	vim.api.nvim_create_user_command("ShepherdBoardsArchived", function()
		require("shepherd.board").archived()
	end, { desc = "unarchive an archived board" })

	-- keep statusline counts fresh across external edits / other tabs
	vim.api.nvim_create_autocmd("FocusGained", {
		group = vim.api.nvim_create_augroup("shepherd", { clear = true }),
		callback = function()
			M.refresh()
		end,
	})
end

-- _run exposes the CLI runner to the board-management submodule
-- (shepherd.board), which passes { no_board = true } for board verbs.
M._run = run

-- _internal exposes pure helpers for the test suite; not part of the public API.
M._internal = {
	tally = tally,
	format_status = format_status,
	label = label,
	flatten = flatten,
	edit_seed = edit_seed,
	clean = clean,
	build_cmd = build_cmd,
	resolve_filter = resolve_filter,
	with_board = with_board,
	set_config = function(c)
		active_board = nil
		config = vim.tbl_deep_extend("force", {}, defaults, c or {})
	end,
}

return M
