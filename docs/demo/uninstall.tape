# Rendered by docs/demo/render.py, which records this tape and then zooms it.
# Runs in a throwaway HOME so it never touches your real setup.
Output docs/demo/build/uninstall.mp4
Set Shell bash
Set FontSize 22
Set Width 1280
Set Height 720
Set Padding 28
Set Theme "Rose Pine"
Set TypingSpeed 35ms
Set Framerate 30

Hide
Type "export KIT=$PWD CLAUDE_DIR=$(dirname $(command -v claude 2>/dev/null || echo /usr/bin/x)) GUM_DIR=$(dirname $(command -v gum 2>/dev/null || echo /usr/bin/x))"
Enter
Type "export HOME=$(mktemp -d) && export PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$GUM_DIR PS1='$ ' && clear"
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
