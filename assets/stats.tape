# Regenerate assets/stats.gif:
#
#   brew install vhs     # pulls in ttyd + ffmpeg
#   vhs assets/stats.tape
#
# Same throwaway board as demo.tape (assets/demo-seed.sh), whose archive carries
# a few weeks of completed work so the sparkline and backlog trend are populated.
# Smaller font and a taller window than the board recording: `shepherd stats` is
# 56 rows, and the float only gets 85% of them.

Require nvim
Require shepherd

Output assets/stats.gif

Set Shell zsh
Set FontSize 12
Set Width 1500
Set Height 1160
Set Padding 20
Set Theme "Catppuccin Mocha"
Set Framerate 24
Set TypingSpeed 55ms

Hide
Type 'd=$(mktemp -d) && export SHEPHERD_TODO_FILE=$d/todo.md SHEPHERD_CONFIG=$d/config.toml'
Enter
Type 'sh assets/demo-seed.sh'
Enter
Type 'printf "%s\n" "local M = {}" "" "-- TODO: retry the board fetch on a transient failure" "function M.fetch() end" "" "return M" > $d/board.lua'
Enter
Type 'clear'
Enter
Show

Type "nvim -u assets/demo-init.lua $d/board.lua"
Enter
Sleep 2.5s

Type ":ShepherdStats"
Enter
Sleep 6s

# the charts hold until dismissed
Type "q"
Sleep 1.5s
Type ":q!"
Enter
Sleep 1s
