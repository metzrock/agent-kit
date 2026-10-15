# Re-record from the repo root: vhs docs/demo/statusline.tape
# Runs in a throwaway HOME so it never touches your real setup.
Output docs/demo/statusline.gif
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
Type "bin/agent-kit install --modules usage --yes >/dev/null"
Enter
Type `printf '%s' '{"model":{"display_name":"Opus 5.5"},"rate_limits":{"five_hour":{"used_percentage":23},"seven_day":{"used_percentage":41}}}' > sample-status.json && clear`
Enter
Sleep 1s
Show

Type "# Sample of what Claude Code sends the status line"
Enter
Type "jq . sample-status.json"
Sleep 400ms
Enter
Sleep 2.5s
Type "claude-statusline < sample-status.json"
Sleep 400ms
Enter
Sleep 2.5s
Type "# The note added to each prompt you send"
Enter
Type "prompt-clock </dev/null | jq -r .hookSpecificOutput.additionalContext"
Sleep 400ms
Enter
Sleep 4s
