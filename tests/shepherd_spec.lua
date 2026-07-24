local sh = require("shepherd")
local internal = sh._internal

describe("tally", function()
	it("counts open items and overdue relative to today", function()
		local items = {
			{ done = false, due = "2026-06-01" }, -- overdue
			{ done = false, due = "2027-01-01" }, -- future
			{ done = false }, -- no due
			{ done = true, due = "2026-06-01" }, -- done, ignored
		}
		local open, overdue = internal.tally(items, "2026-07-11")
		assert.equals(3, open)
		assert.equals(1, overdue)
	end)

	it("treats empty due as not overdue", function()
		local open, overdue = internal.tally({ { done = false, due = "" } }, "2026-07-11")
		assert.equals(1, open)
		assert.equals(0, overdue)
	end)

	it("handles an empty list", function()
		local open, overdue = internal.tally({}, "2026-07-11")
		assert.equals(0, open)
		assert.equals(0, overdue)
	end)
end)

describe("format_status", function()
	it("is empty when nothing is open", function()
		assert.equals("", internal.format_status(0, 0, ""))
		assert.equals("", internal.format_status(0, 5, "T"))
	end)

	it("renders plain count without an icon", function()
		assert.equals("3 todo", internal.format_status(3, 0, ""))
	end)

	it("renders icon-prefixed count", function()
		assert.equals("T 3", internal.format_status(3, 0, "T"))
	end)

	it("appends an overdue suffix", function()
		assert.equals("3 todo (1 overdue)", internal.format_status(3, 1, ""))
		assert.equals("T 3 (2 overdue)", internal.format_status(3, 2, "T"))
	end)
end)

describe("clean", function()
	it("strips comment markers and TODO/FIXME tags", function()
		assert.equals("wire the thing", internal.clean("  -- TODO: wire the thing"))
		assert.equals("fix this", internal.clean("// FIXME fix this"))
		assert.equals("a note", internal.clean("# a note"))
		assert.equals("star", internal.clean(" * star"))
	end)

	it("leaves plain text untouched", function()
		assert.equals("no marker here", internal.clean("no marker here"))
	end)
end)

describe("label", function()
	it("formats an open item with category and priority", function()
		assert.equals(
			"[ ] buy milk @home !h",
			internal.label({ done = false, text = "buy milk", category = "home", priority = "H" })
		)
	end)

	it("marks done items and omits empty fields", function()
		assert.equals("[x] done thing", internal.label({ done = true, text = "done thing" }))
		assert.equals("[ ] bare", internal.label({ done = false, text = "bare", category = "", priority = "" }))
	end)

	it("shows status, due and defer", function()
		assert.equals(
			"[ ] ship it <blocked> due:2026-07-20 defer:2026-07-18",
			internal.label({
				done = false,
				text = "ship it",
				status = "blocked",
				due = "2026-07-20",
				defer = "2026-07-18",
			})
		)
	end)

	it("hides status on done items", function()
		assert.equals("[x] shipped", internal.label({ done = true, text = "shipped", status = "blocked" }))
	end)

	it("shows the board tag in the aggregate view", function()
		assert.equals("[ ] task [web]", internal.label({ done = false, text = "task", board = "web" }))
	end)

	it("indents subtask rows", function()
		assert.equals("  [ ] a sub", internal.label({ done = false, text = "a sub", _sub = true }))
	end)
end)

describe("flatten", function()
	it("orders each parent before its subtasks with n / n.m refs", function()
		local rows = internal.flatten({
			{ index = 1, text = "parent", subtasks = { { index = 1, text = "kid" } } },
			{ index = 2, text = "solo" },
		})
		assert.equals(3, #rows)
		assert.equals("1", rows[1]._ref)
		assert.equals("1.1", rows[2]._ref)
		assert.is_true(rows[2]._sub)
		assert.equals("2", rows[3]._ref)
		assert.is_nil(rows[3]._sub)
	end)
end)

describe("edit_seed", function()
	it("reconstructs a quick-add line with note last", function()
		assert.equals(
			"buy milk @home !h due:2026-07-20 defer:2026-07-18 link:http://x note:from the shop",
			internal.edit_seed({
				text = "buy milk",
				category = "home",
				priority = "H",
				due = "2026-07-20",
				defer = "2026-07-18",
				link = "http://x",
				note = "from the shop",
			})
		)
	end)

	it("omits empty fields", function()
		assert.equals("bare", internal.edit_seed({ text = "bare", category = "", priority = "" }))
	end)
end)

describe("build_cmd / resolve_filter", function()
	after_each(function()
		internal.set_config({})
	end)

	it("omits --filter when no filter is set", function()
		internal.set_config({ cmd = "shepherd" })
		assert.same({ "shepherd" }, internal.build_cmd())
	end)

	it("passes a string filter", function()
		internal.set_config({ filter = "work" })
		assert.same({ "shepherd", "--filter", "work" }, internal.build_cmd())
	end)

	it("evaluates a function filter", function()
		internal.set_config({
			filter = function()
				return "proj"
			end,
		})
		assert.same({ "shepherd", "--filter", "proj" }, internal.build_cmd())
	end)

	it("lets an explicit override win over config", function()
		internal.set_config({ filter = "work" })
		assert.same({ "shepherd", "--filter", "other" }, internal.build_cmd("other"))
	end)

	it("passes a string board", function()
		internal.set_config({ board = "web" })
		assert.same({ "shepherd", "--board", "web" }, internal.build_cmd())
	end)

	it("evaluates a function board", function()
		internal.set_config({
			board = function()
				return "web"
			end,
		})
		assert.same({ "shepherd", "--board", "web" }, internal.build_cmd())
	end)

	it("combines board and filter", function()
		internal.set_config({ board = "web", filter = "work" })
		assert.same({ "shepherd", "--board", "web", "--filter", "work" }, internal.build_cmd())
	end)

	it("emits --all for the global view, dropping the board", function()
		internal.set_config({ board = "web" })
		assert.same({ "shepherd", "--all" }, internal.build_cmd(nil, true))
	end)

	it("keeps the filter in the global view", function()
		internal.set_config({ board = "web", filter = "work" })
		assert.same({ "shepherd", "--all", "--filter", "work" }, internal.build_cmd(nil, true))
	end)
end)

describe("with_board", function()
	after_each(function()
		internal.set_config({})
	end)

	it("appends --board after the verb args", function()
		internal.set_config({ board = "web" })
		assert.same({ "shepherd", "add", "x", "--board", "web" }, internal.with_board({ "shepherd", "add", "x" }))
	end)

	it("is a no-op without a board", function()
		internal.set_config({})
		assert.same({ "shepherd", "list", "--json" }, internal.with_board({ "shepherd", "list", "--json" }))
	end)
end)
