# Recorded by tests/e2e/run.sh --record modules, in a throwaway HOME.
Output docs/demo/modules.gif
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
Type "bin/agent-kit install --modules base --yes >/dev/null && clear"
Enter
Sleep 3s
Show
Type "agent-kit list"
Sleep 300ms
Enter
Sleep 3s
Type "agent-kit install --modules crew --dry-run"
Sleep 300ms
Enter
Sleep 3.5s
