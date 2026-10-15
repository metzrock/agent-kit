# Recorded by tests/e2e/run.sh --record install, in a throwaway HOME.
Output docs/demo/install.gif
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
Sleep 3s
Show
Type "bin/agent-kit install --dry-run"
Sleep 300ms
Enter
Sleep 1.5s
Type "bin/agent-kit install --yes"
Sleep 300ms
Enter
Sleep 2.5s
Type "agent-kit doctor"
Sleep 300ms
Enter
Sleep 4s
