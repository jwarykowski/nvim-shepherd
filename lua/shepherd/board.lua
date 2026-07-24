-- Board management: a board switcher and CRUD, driven by the shepherd CLI's
-- `boards --json` reads and `board <sub>` verbs. Board verbs name their
-- target explicitly, so they run with { no_board = true } to bypass scoping.
local sh = require("shepherd")

local M = {}

-- fetch decodes `boards --json [args]` and hands the board array to cb.
local function fetch(args, cb)
	local cmd = { sh.binary(), "boards", "--json" }
	for _, a in ipairs(args or {}) do
		cmd[#cmd + 1] = a
	end
	vim.system(cmd, { text = true }, function(r)
		vim.schedule(function()
			if r.code ~= 0 then
				vim.notify("shepherd: " .. ((r.stderr or ""):gsub("%s+$", "")), vim.log.levels.ERROR)
				return
			end
			local ok, boards = pcall(vim.json.decode, r.stdout)
			if not ok then
				vim.notify("shepherd: could not parse `boards --json`", vim.log.levels.ERROR)
				return
			end
			cb(boards or {})
		end)
	end)
end

local function plabel(b)
	local s = string.format("%s %s (%d/%d)", b.current and "*" or " ", b.name, b.open, b.total)
	if b.dir and b.dir ~= "" then
		s = s .. "  " .. vim.fn.fnamemodify(b.dir, ":~")
	end
	return s
end

-- confirm_delete previews the removal with --dry-run, then requires an explicit
-- "yes" before the destructive --force delete.
local function confirm_delete(name)
	vim.system({ sh.binary(), "board", "delete", name, "--dry-run" }, { text = true }, function(r)
		vim.schedule(function()
			local preview = (r.stdout or ""):gsub("%s+$", "")
			vim.ui.select({ "no", "yes" }, { prompt = "delete '" .. name .. "'? " .. preview }, function(ans)
				if ans == "yes" then
					sh._run({ "board", "delete", name, "--force" }, "deleted " .. name, { no_board = true })
				end
			end)
		end)
	end)
end

-- switch lists boards; selecting one offers switch/rename/archive/delete.
function M.switch()
	fetch({}, function(boards)
		if #boards == 0 then
			vim.notify("shepherd: no boards")
			return
		end
		vim.ui.select(boards, { prompt = "board", format_item = plabel }, function(b)
			if not b then
				return
			end
			vim.ui.select({ "switch", "rename", "dir", "archive", "delete" }, { prompt = b.name }, function(act)
				if act == "switch" then
					sh.set_active_board(b.name)
					if b.dir and b.dir ~= "" then
						vim.cmd.tcd(vim.fn.fnamemodify(b.dir, ":p"))
					end
					sh.refresh()
					vim.notify("shepherd: board " .. b.name)
				elseif act == "dir" then
					-- omit to show is CLI-only; here empty clears, a path sets it
					vim.ui.input({ prompt = "dir: ", default = b.dir or "" }, function(v)
						if v ~= nil then
							sh._run({ "board", "dir", b.name, v }, "dir " .. b.name, { no_board = true })
						end
					end)
				elseif act == "rename" then
					vim.ui.input({ prompt = "rename to: ", default = b.name }, function(v)
						if v and v ~= "" and v ~= b.name then
							sh._run(
								{ "board", "rename", b.name, v },
								"renamed " .. b.name .. " -> " .. v,
								{ no_board = true }
							)
						end
					end)
				elseif act == "archive" then
					sh._run({ "board", "archive", b.name }, "archived " .. b.name, { no_board = true })
				elseif act == "delete" then
					confirm_delete(b.name)
				end
			end)
		end)
	end)
end

-- archived lists archived boards; selecting one unarchives it.
function M.archived()
	fetch({ "--archived" }, function(boards)
		if #boards == 0 then
			vim.notify("shepherd: no archived boards")
			return
		end
		vim.ui.select(boards, { prompt = "unarchive", format_item = plabel }, function(b)
			if b then
				sh._run({ "board", "unarchive", b.name }, "unarchived " .. b.name, { no_board = true })
			end
		end)
	end)
end

return M
