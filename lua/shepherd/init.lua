local M = {}

local defaults = {
	cmd = "shepherd",
	filter = nil, -- string | fun():string | nil
	project = nil, -- string | fun():string | nil
	float = { width = 0.8, height = 0.8, border = "rounded" },
	status = { icon = "" }, -- prefix for M.status(), e.g. a nerd-font glyph
}

local config = vim.tbl_deep_extend("force", {}, defaults)

-- binary returns the configured shepherd command (used by the health check).
function M.binary()
	return config.cmd
end

-- with_project appends "--project <name>" to cmd when one is configured
-- (string or function). Shepherd wants flags after the verb.
local function with_project(cmd)
	local p = config.project
	p = type(p) == "function" and p() or p
	if p and p ~= "" then
		cmd[#cmd + 1] = "--project"
		cmd[#cmd + 1] = p
	end
	return cmd
end

-- run invokes the shepherd CLI async; notifies on failure, and on success only
-- when ok_msg is given. Project-scoped so mutations land on the same board
-- list()/pick() read.
local function run(args, ok_msg)
	local cmd = { config.cmd }
	for _, a in ipairs(args) do
		cmd[#cmd + 1] = a
	end
	with_project(cmd)
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
		with_project(parts)
	end
	local f = resolve_filter(filter_override)
	if f and f ~= "" then
		parts[#parts + 1] = "--filter"
		parts[#parts + 1] = f
	end
	return parts
end

function M.open(filter, all)
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
	vim.fn.jobstart(build_cmd(filter, all), {
		term = true,
		on_exit = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
			M.refresh() -- board edits change counts
		end,
	})
	vim.cmd("startinsert")
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

-- list fetches items via `list --json` (scoped to the configured project) and
-- passes the decoded array to cb.
local function list(cb)
	vim.system(with_project({ config.cmd, "list", "--json" }), { text = true }, function(r)
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

local function label(it)
	local mark = it.done and "[x]" or "[ ]"
	local cat = (it.category and it.category ~= "") and (" @" .. it.category) or ""
	local pr = (it.priority and it.priority ~= "") and (" !" .. it.priority:lower()) or ""
	return string.format("%s %s%s%s", mark, it.text, cat, pr)
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
-- project's whole board (not scoped to `config.filter`).
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

-- pick shows all items, then a done/undone/rm action on the chosen one.
function M.pick()
	list(function(items)
		if #items == 0 then
			vim.notify("shepherd: no items")
			return
		end
		vim.ui.select(items, { prompt = "shepherd", format_item = label }, function(choice)
			if not choice then
				return
			end
			local toggle = choice.done and "undone" or "done"
			vim.ui.select({ toggle, "rm" }, { prompt = choice.text }, function(act)
				if act then
					run({ act, tostring(choice.index) }, act .. " " .. choice.index)
				end
			end)
		end)
	end)
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

	vim.api.nvim_create_user_command("ShepherdList", function()
		M.pick()
	end, { desc = "pick a todo and act on it" })

	vim.api.nvim_create_user_command("ShepherdCapture", function(a)
		M.capture({ range = a.range, line1 = a.line1, line2 = a.line2 })
	end, { nargs = 0, range = true, desc = "capture current line / selection as a todo" })

	-- keep statusline counts fresh across external edits / other tabs
	vim.api.nvim_create_autocmd("FocusGained", {
		group = vim.api.nvim_create_augroup("shepherd", { clear = true }),
		callback = function()
			M.refresh()
		end,
	})
end

-- _internal exposes pure helpers for the test suite; not part of the public API.
M._internal = {
	tally = tally,
	format_status = format_status,
	label = label,
	clean = clean,
	build_cmd = build_cmd,
	resolve_filter = resolve_filter,
	with_project = with_project,
	set_config = function(c)
		config = vim.tbl_deep_extend("force", {}, defaults, c or {})
	end,
}

return M
