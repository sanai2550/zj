# VHS tape (https://github.com/charmbracelet/vhs) for the README demo.
# Run via demo/make-demo.sh: it builds a fabricated history and throwaway repo
# in /tmp/jev-demo (nothing personal is recorded) and assembles the MP4/GIF from
# the frames with ffmpeg (vhs 0.12.0 fails to render on its own, see vhs#787).

Output demo/frames/

Set Shell zsh
Set FontSize 30
Set Width 1300
Set Height 500
Set Theme "Catppuccin Mocha"
Set TypingSpeed 90ms

Hide
Type "source /tmp/jev-demo/setup.zsh && clear"
Enter
Sleep 1s
Show

Sleep 1s

# 1. prefix mode: history has both "git status" and "git stash list"
Type "git st"
Sleep 2500ms
Right
Sleep 800ms
Enter
Sleep 2s

# 2. fuzzy mode: describe what you want, Jev finds the command
Type "last 5 commits"
Sleep 2500ms
Ctrl+E
Sleep 800ms
Enter
Sleep 2500ms

# 3. nothing in history matches: no suggestion
Type "xyzzy"
Sleep 2500ms
Ctrl+U
Sleep 600ms

# 4. fuzzy mode again
Type "logs"
Sleep 2500ms
Right
Sleep 2500ms
