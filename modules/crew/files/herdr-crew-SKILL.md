---
name: herdr-crew
description: Generic herdr-crew workflow.
---

1. Start `herdr-crew task <slug>` from the project in a Herdr pane.
2. Scout the relevant code, then let the lead write a complete spec.
3. Run `herdr-crew implement <spec.md>` and read its report.
4. Review the real diff and run checks. Use `herdr-crew review` for a fresh review.
5. Send findings through `herdr-crew fix <findings.md>` and verify again.
6. Commit and finish only when the user asks. Never push without explicit instructions.
Two-part implementation requires CREW_IMPLEMENTER=codex. Cloud jobs require cloud-run.
If `~/.config/agent-kit/crew-local.md` exists, read it and follow it.
