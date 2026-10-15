# Re-record from the repo root: vhs docs/demo/modules.tape
# Runs in a throwaway HOME so it never touches your real setup.
Output docs/demo/modules.gif
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
Type "bin/agent-kit install --modules base --yes >/dev/null && clear"
Enter
Sleep 1s
Show

Type "agent-kit list"
Sleep 400ms
Enter
Sleep 2.5s
Type "agent-kit install --modules usage,look --dry-run"
Sleep 400ms
Enter
Sleep 2s
Type "agent-kit install --modules crew --dry-run"
Sleep 400ms
Enter
Sleep 4s
