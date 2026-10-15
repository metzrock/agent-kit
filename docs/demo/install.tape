# Re-record from the repo root: vhs docs/demo/install.tape
# Runs in a throwaway HOME so it never touches your real setup.
Output docs/demo/install.gif
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
Show

Type "bin/agent-kit install --dry-run"
Sleep 400ms
Enter
Sleep 1.5s
Type "bin/agent-kit install --yes"
Sleep 400ms
Enter
Sleep 2.5s
Type "agent-kit doctor"
Sleep 400ms
Enter
Sleep 4s
