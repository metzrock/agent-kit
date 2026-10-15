# Recorded by tests/e2e/run.sh --record uninstall, in a throwaway HOME.
Output docs/demo/uninstall.gif
Set Shell bash
Set FontSize 20
Set Width 1280
Set Height 640
Set Padding 24
Set Theme "Rose Pine"
Set TypingSpeed 35ms
Set Framerate 15

Hide
Type "export HOME=$DEMO_HOME PATH=$DEMO_PATH KIT=$DEMO_KIT PS1='$ ' && cd $KIT && clear"
Enter
Type "bin/agent-kit install --yes >/dev/null && clear"
Enter
Sleep 3s
Show
Type "bin/agent-kit uninstall"
Sleep 300ms
Enter
Sleep 1.5s
Type "bin/agent-kit list"
Sleep 300ms
Enter
Sleep 2.5s
Type "ls ~/.local/state/agent-kit/backups | head -3"
Sleep 300ms
Enter
Sleep 3.5s
