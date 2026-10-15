# Re-record from the repo root: vhs docs/demo/uninstall.tape
# Runs in a throwaway HOME so it never touches your real setup.
Output docs/demo/uninstall.gif
Set Shell bash
Set FontSize 18
Set Width 1100
Set Height 560
Set Padding 24
Set Theme "Rose Pine"
Set TypingSpeed 35ms

Hide
Type "export HOME=$(mktemp -d) && export PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin PS1='$ ' && clear"
Enter
Type "bin/agent-kit install --yes >/dev/null && clear"
Enter
Sleep 1.5s
Show

Type "bin/agent-kit uninstall"
Sleep 400ms
Enter
Sleep 1.5s
Type "bin/agent-kit list"
Sleep 400ms
Enter
Sleep 2s
Type "ls ~/.local/state/agent-kit/backups"
Sleep 400ms
Enter
Sleep 4s
