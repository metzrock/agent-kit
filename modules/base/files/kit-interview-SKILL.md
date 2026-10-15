---
name: kit-interview
description: Interview the user to draft or revise their personal Claude instructions in CLAUDE.md.
---

Help the user write `~/.claude/CLAUDE.md` in their own terms. Ask two or three short
questions at a time; wait for answers before continuing. Let them skip any question.
Do not assume personal details or request credentials, tokens or API keys.

Start by asking whether this is a first setup or a revision of one section. Read only
an existing CLAUDE.md for context, with the user's agreement. For a revision, preserve
all unrelated sections and ask only about the selected area.

Cover these four areas over several exchanges:
- About the user: what they work on, experience, goals, and preferred level of explanation.
- How Claude should work: when to ask, how much initiative to take, desired checks,
  communication style, and boundaries for delegation, commits and publishing.
- Budget habits: subscription constraints, preferred everyday model, when to use cheaper
  models, and when to pause or ask before spending more. Never ask for billing secrets.
- Focus and attention style: useful pacing, question batch size, reminders, summaries,
  and what makes it easier to resume a task. Do not infer diagnoses.

Draft concise Markdown instructions using only preferences the user expressed. Omit
unanswered details. Show the complete draft, explain where it will go, and ask whether
to save it. Make requested edits and show the revised draft before asking again.

Only after explicit agreement to the displayed draft:
1. Re-read the destination. If it changed since drafting, show the differences and get
   agreement on an updated draft. If it is a symlink, explain its target and agree on
   which file to change before proceeding.
2. If the file exists, copy it to a unique timestamped file under
   `~/.local/state/agent-kit/backups/`. Confirm the backup succeeded; stop if it failed.
3. Write the approved draft to a temporary sibling file, then rename it to CLAUDE.md.
   Preserve existing permissions. Do not change other configuration or starter templates.
4. Report the destination and backup path. If the user declines, leave files untouched.

The user owns this file. Re-running the interview can revise any one of the four
sections while preserving the rest.
