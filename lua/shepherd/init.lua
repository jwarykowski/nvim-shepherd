local M = {}

local config = {
	cmd = "shepherd",
	filter = nil, -- string | fun():string | nil
	float = { width = 0.8, height = 0.8, border = "rounded" },
}

local function build_cmd()
	local parts = { config.cmd }
	local f = type(config.filter) == "function" and config.filter() or config.filter
	if f and f ~= "" then
		parts[#parts + 1] = "--filter"
		parts[#parts + 1] = f
	end
	return parts
end

function M.open()
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
	vim.fn.jobstart(build_cmd(), {
		term = true,
		on_exit = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end,
	})
	vim.cmd("startinsert")
end

function M.add(text)
	if not text or text == "" then
		return
	end
	vim.system({ config.cmd, "add", text }, {}, function(r)
		vim.schedule(function()
			if r.code == 0 then
				vim.notify("shepherd: added")
			else
				vim.notify("shepherd: " .. ((r.stderr or ""):gsub("%s+$", "")), vim.log.levels.ERROR)
			end
		end)
	end)
end

function M.quick_add()
	vim.ui.input({ prompt = "todo: " }, function(text)
		M.add(text)
	end)
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
	vim.api.nvim_create_user_command("Shepherd", function()
		M.open()
	end, {})
	vim.api.nvim_create_user_command("ShepherdAdd", function(a)
		if a.args ~= "" then
			M.add(a.args)
		else
			M.quick_add()
		end
	end, { nargs = "*" })
end

return M
