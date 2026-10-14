---
name: herdr-tidy
description: Generic herdr-tidy workflow.
---

Use one workspace per project and one tab per task.
Run `herdr-tidy` to preview. Show the proposed moves to the user, then run
`herdr-tidy --apply`. Add `--close-empty` only when the user agrees to close empty shells.
Never close a pane with a live or idle agent unless the user requests it.
Run the preview again and report the final layout.
