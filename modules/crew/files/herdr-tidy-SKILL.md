---
name: herdr-tidy
description: "Preview and consolidate Herdr workspaces into one per project while preserving live agents and split panes. Use when asked to tidy or organize Herdr tabs and workspaces."
argument-hint: "[--apply] [--close-empty]"
---

1. Run `herdr-tidy` to preview grouping tabs by repository. Crew workspaces and
   linked worktrees remain separate. Running and idle agents stay together with
   their split panes.
2. Explain the proposed moves. Run `herdr-tidy --apply` when the user has authorized
   tidying; otherwise ask before applying the preview. It restores workspace focus.
3. Add `--close-empty` only when authorized to close empty terminal shells. Never
   close a live or idle agent unless specifically requested.
4. Run the preview again and report the remaining layout or any failed move.
