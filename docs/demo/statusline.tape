# Recorded by tests/e2e/run.sh --record statusline, in a throwaway HOME.
Output docs/demo/statusline.gif
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
Type "bin/agent-kit install --modules usage --yes >/dev/null"
Enter
Type `printf '%s' '{"model":{"display_name":"Opus 5.5"},"rate_limits":{"five_hour":{"used_percentage":23},"seven_day":{"used_percentage":41}}}' > ~/sample-status.json && clear`
Enter
Sleep 3s
Show
Type "# What Claude Code sends the status line (sample numbers)"
Enter
Type "jq -c . ~/sample-status.json"
Sleep 300ms
Enter
Sleep 2s
Type "claude-statusline < ~/sample-status.json"
Sleep 300ms
Enter
Sleep 2.5s
Type "# The note added to each prompt you send"
Enter
Type "prompt-clock </dev/null | jq -r .hookSpecificOutput.additionalContext"
Sleep 300ms
Enter
Sleep 3.5s
