# Rendered by docs/demo/render.py, which records this tape and then zooms it.
# Runs in a throwaway HOME so it never touches your real setup.
Output docs/demo/build/addons.mp4
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
Type "export PATH=$PATH:$CLAUDE_DIR && bin/agent-kit install --modules base --yes >/dev/null && clear"
Enter
Sleep 3s
Show
Type "agent-kit install --modules writing"
Sleep 300ms
Enter
Sleep 4s
Enter
Sleep 2.5s
Hide
Sleep 45s
Show
Sleep 3.5s
Ctrl+C
Sleep 1.5s
