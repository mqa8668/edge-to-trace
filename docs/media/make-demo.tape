# Terminal capture of the `make demo` narrative. Reproduce: REPLAY_DIR=docs/media/tools vhs docs/media/make-demo.tape (see docs/media/README.md)
Output make-demo.gif
Set Shell "bash"
Set FontSize 17
Set Width 1500
Set Height 900
Set Padding 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms
Set PlaybackSpeed 1

Hide
Type `export PS1='$ ' && cd "$REPLAY_DIR" && clear` Enter
Type "make() { ./replay.sh demo-transcript.txt; }" Enter
Type "clear" Enter
Show

Sleep 700ms
Type "make demo"
Sleep 400ms
Enter
Sleep 22s
