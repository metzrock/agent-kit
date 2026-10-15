# Rendered by docs/demo/render.py, which records this tape and then zooms it.
# Runs in a throwaway HOME so it never touches your real setup.
Output docs/demo/build/statusline.mp4
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
Type "bin/agent-kit install --modules usage --yes >/dev/null"
Enter
Type `printf '%s' '{"model":{"display_name":"Opus 5.5"},"rate_limits":{"five_hour":{"used_percentage":23},"seven_day":{"used_percentage":41}}}' > /tmp/sample-status.json && clear`
Enter
Sleep 3s
Show
Type "# What Claude Code sends the status line (sample numbers)"
Enter
Type "jq -c . /tmp/sample-status.json"
Sleep 300ms
Enter
Sleep 2s
Type "claude-statusline < /tmp/sample-status.json"
Sleep 300ms
Enter
Sleep 2.5s
Type "# The note added to each prompt you send"
Enter
Type "prompt-clock </dev/null | jq -r .hookSpecificOutput.additionalContext"
Sleep 300ms
Enter
Sleep 3.5s
