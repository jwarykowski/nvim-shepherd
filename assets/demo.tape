# Regenerate assets/demo.gif:
#
#   brew install vhs     # pulls in ttyd + ffmpeg
#   vhs assets/demo.tape
#
# Runs nvim with assets/demo-init.lua (this checkout, no other plugins) against a
# throwaway board seeded by assets/demo-seed.sh, so recording never touches a
# real board or config.

Require nvim
Require shepherd

Output assets/demo.gif

Set Shell zsh
Set FontSize 15
Set Width 1320
Set Height 800
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
Sleep 3s

# the statusline carries the open count for the board
Sleep 1.5s

# capture the TODO comment on line 3 as a todo
Type "3G"
Sleep 1s
Type ":ShepherdCapture"
Enter
Sleep 1.5s
Type " @plugin !h"
Sleep 800ms
Enter
Sleep 2.5s

# pick an item, then edit it with a pre-filled quick-add line
Type ":ShepherdList"
Enter
Sleep 2.5s
Type "4"
Enter
Sleep 2s
Type "2"
Enter
Sleep 2s
Type " due:tomorrow"
Sleep 800ms
Enter
Sleep 2.5s

# pick again, this time tick it off
Type ":ShepherdList"
Enter
Sleep 2s
Type "4"
Enter
Sleep 1.5s
Type "1"
Enter
Sleep 2.5s

# the whole board, in a floating terminal
Type ":Shepherd"
Enter
Sleep 3s
Down@450ms 2
Sleep 1s
Space
Sleep 1.5s
Type "v"
Sleep 2s
Type "q"
Sleep 2s

Type ":q!"
Enter
Sleep 1.5s
