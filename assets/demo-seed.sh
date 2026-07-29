#!/bin/sh
# Seeds a throwaway board plus its archive for the vhs recording
# (assets/demo.tape). $SHEPHERD_TODO_FILE must already point at a scratch
# todo.md — the tape sets it under `mktemp -d`.
#
# Dates are written relative to today, so the board and `shepherd stats` still
# look lived-in whenever the gif gets re-recorded.
set -e

board=$SHEPHERD_TODO_FILE
archive=$(dirname "$board")/archive.md

ago() { date -v-"$1"d +%d-%m-%Y 2>/dev/null || date -d "$1 days ago" +%d-%m-%Y; }
in_days() { date -v+"$1"d +%Y-%m-%d 2>/dev/null || date -d "$1 days" +%Y-%m-%d; }

cat >"$board" <<EOF
- [ ] (H) float the picker over the buffer
  created: $(ago 2) 09:14
  due: $(in_days 1)
  category: plugin
  - [ ] map the actions
    created: $(ago 2) 09:15
- [ ] wire the statusline count
  created: $(ago 3) 16:02
  category: plugin
  status: in-progress
- [ ] document the capture command
  created: $(ago 6) 11:30
  due: $(in_days 7)
  category: docs
- [ ] (L) tidy the health check
  created: $(ago 11) 14:47
  category: docs
- [ ] (H) fix the flaky spec on nightly
  created: $(ago 38) 08:21
  category: ci
EOF

cat >"$archive" <<EOF
- [x] (H) open the board in a float
  created: $(ago 26) 09:00
  completed: $(ago 24) 17:40
  category: plugin
- [x] quick-add without leaving the buffer
  created: $(ago 25) 10:15
  completed: $(ago 22) 11:05
  category: plugin
- [x] (H) board-scoped commands
  created: $(ago 22) 09:30
  completed: $(ago 21) 15:20
  category: plugin
- [x] pick an item with vim.ui.select
  created: $(ago 20) 13:00
  completed: $(ago 18) 09:45
  category: plugin
- [x] (L) checkhealth for the binary
  created: $(ago 19) 08:10
  completed: $(ago 18) 08:55
  category: docs
- [x] run the specs on nightly
  created: $(ago 17) 14:20
  completed: $(ago 12) 16:30
  category: ci
- [x] (H) archive an item from the picker
  created: $(ago 15) 09:05
  completed: $(ago 9) 18:10
  category: plugin
- [x] board working directories
  created: $(ago 12) 11:40
  completed: $(ago 7) 10:25
  category: plugin
- [x] aggregate stats across boards
  created: $(ago 9) 15:15
  completed: $(ago 4) 12:00
  category: plugin
- [x] (M) capture the visual selection
  created: $(ago 5) 09:50
  completed: $(ago 2) 14:35
  category: plugin
EOF
