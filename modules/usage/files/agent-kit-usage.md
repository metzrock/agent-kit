# Usage awareness
Each prompt carries the local time and, when known, Claude and Codex usage for the 5-hour
and weekly windows with their reset times. A `Usage note:` line below it means a threshold
was crossed (low, near a reset, ahead of weekly pace, one pool much emptier, prompt cache
expired): do what it says. A `Usage update:` line after a tool call means usage just passed
50, 80 or 95%. Mention either to the user only when it changes what you're doing, in one line.
Near a usage limit, keep the task focused, prefer medium effort and small delegated jobs, and
ask before expanding scope. Use /clear after finished work and /compact when keeping the
current task's context. Codex usage appears only when local Codex session logs exist.
