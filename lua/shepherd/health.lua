local M = {}

function M.check()
	local health = vim.health
	health.start("shepherd")

	local cmd = require("shepherd").binary()
	if vim.fn.executable(cmd) == 0 then
		health.error("`" .. cmd .. "` not found on $PATH", {
			"brew install jwarykowski/tap/shepherd",
			"or set `cmd` in setup() to the binary path",
		})
		return
	end

	local r = vim.system({ cmd, "--help" }, { text = true }):wait()
	if r.code == 0 then
		health.ok("`" .. cmd .. "` found: " .. vim.fn.exepath(cmd))
	else
		health.warn("`" .. cmd .. "` found but `--help` exited " .. r.code)
	end
end

return M
