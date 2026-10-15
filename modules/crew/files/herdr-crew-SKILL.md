---
name: herdr-crew
description: "Orchestrate a coding task in Herdr with a Sonnet scout and reviewer and a Sonnet or Codex implementer, ending with a reviewed commit on a task branch. Use when asked to use the crew, delegate implementation, or run /herdr-crew. Requires a Herdr pane."
argument-hint: "<task description>"
---

# Herdr crew

Read `~/.config/agent-kit/crew-local.md` if it exists; it overrides this file.
The lead only orchestrates: plan, write specs, decide from reports, commit, and
report. Sibling agents read and write the code. Finish with a reviewed commit on
its own task branch; never push or merge in the local lane.

Check `test "${HERDR_ENV:-}" = 1` before starting. Outside Herdr, explain and stop.
Run `herdr-crew status`; if a task is active, ask whether to resume or finish it.
Each task has a workspace, worktree, and branch `crew/<slug>`. The sidebar's `$crew`
line shows progress. During lead phases use `herdr-crew step "planning"` or another
short description. Prefixes `usage limit`, `blocked`, and `stalled` show red; `✓`
marks completion. The script updates the step around its own jobs.

| Role | Model or agent |
|---|---|
| Lead: plan, spec, decisions, commit | This session's model |
| Scout and fresh reviewer | Sonnet, agent `sonnet` |
| Implementer | Sonnet or Codex, according to `CREW_IMPLEMENTER` (default Sonnet) |
| Second implementer | Codex, agent `implementer-b` |
| Backup coder when Codex is unavailable | Sonnet |

## Budget rules

The lead does not read source, diffs, or test output and does not rerun tests.
Use scout and reviewer reports. One targeted read of about 50 lines is allowed
when a report leaves one specific question unresolved or appears wrong.
Sonnet scouts and reviews; it codes only when selected as implementer or backup.
Keep Codex effort at medium unless the task warrants high; never above high.
Write complete specs and batch accepted findings into one fix round.

Before starting, check the prompt's usage context, or run `usage-status` if absent.
At 80% or more on either required provider, explain and suggest waiting for reset
rather than starting a task likely to stop halfway. Codex readings update only
while Codex runs; an old `[as of HH:MM]` reading may understate current usage.
During work, watch `Usage update:` threshold messages. Switching Codex models does
not restore a shared exhausted allowance.

## Pick a lane and implementer count

Quick lane: roughly under 100 changed lines, one area, low risk. Skip scouting only
when the files and change are already clear; at most one fix round.
Full lane: larger work, or auth, secrets, data deletion or migration, concurrency,
or network-exposed services. Always scout; at most two fix rounds.

Default to one implementer. Two are allowed only with `CREW_IMPLEMENTER=codex`,
roughly 300+ changed lines overall, at least 100 lines of real work per part,
and disjoint owned files (including tests). Neither part may depend on unfinished
code from the other; specify any shared interface up front. Prefer two only when
Codex usage is at most 50%. Two saves elapsed time but adds usage overhead.
State the lane and implementer count, with a short reason.

## Nine-step loop

1. Start inside the repository: `herdr-crew task <slug>`. It creates the task
   worktree and starts agents. Existing uncommitted checkout changes are excluded;
   tell the user if the script reports them.
2. Scout when required: write a brief and run `herdr-crew scout <brief.md>`.
   Request relevant files, behavior, constraints, risks, size, exact test commands,
   and whether two disjoint parts are possible. Scouts never run tests.
3. Decide from the report. Ask only about material ambiguity; otherwise give a
   short plan and record reasonable assumptions for the final report.
4. Write a spec with goal, owned files, behavior, edge cases, constraints, and
   verification. With two implementers, write separate specs with explicit file
   ownership and the shared interface. Include this test budget: while working,
   run only test files added or changed; run the full suite once, at the end.
   No browser or visual checks unless the spec asks for them. Add tests for
   non-trivial logic, skipping glue, config, and UI wiring; use existing test
   tooling, or built-in tooling without new dependencies. Use quiet output and
   report exact test commands and results.
5. Run `herdr-crew implement <spec>` (or `<spec-a> <spec-b>`) with
   `run_in_background: true`, then wait for notification without polling.
   Part B uses its own checkout and is merged into the task worktree afterward.
6. Run `herdr-crew review` with `run_in_background: true`. The fresh Sonnet
   reviewer checks the real diff against the specs, runs checks, and reports
   self-contained findings with severity, confidence, location, excerpt, and a
   concrete failure scenario. Decide from that evidence; explain rejected findings.
7. If MUST-FIX findings remain, batch accepted findings and expected behavior into
   one file; run `herdr-crew fix <findings>` in the background, then review again.
   Later reviews verify earlier fixes. Respect the lane's fix-round limit and
   report anything left open rather than silently accepting a known defect.
8. Commit on the task branch with `herdr-crew commit "<type>: <summary>"`, then
   `herdr-crew finish`. This closes agents and marks `✓ ready to merge` while
   keeping the worktree available. Local crew commits autonomously; never push or
   merge. The user chooses when to merge and delete the worktree.
9. Report branch and commit, changes, implementer count and model, exact checks
   and results from review, accepted/rejected findings and reasons, assumptions,
   open items, and the merge command printed by `finish`.

Run long scout, implement, review, and fix commands with `run_in_background: true`
when the tool supports it; wait for completion notification instead of polling.

## Sonnet as backup coder

When Codex reaches its limit (exit 5), or starts at 80% and the user elects to
continue, use `herdr-crew implement --by sonnet <spec>` or
`herdr-crew fix --by sonnet <findings>`. One spec only, building on partial work.
Use this fallback only while Claude usage is at most 60%; otherwise preserve WIP
and wait. Review still starts fresh; disclose that Sonnet both coded and reviewed.

## When things go wrong

- Exit 3: an agent is blocked on a dialog. Show the user the question; do not
  approve on their behalf.
- Exit 4: no report. Inspect `herdr-crew read <name> 200` and status. A timeout
  does not prove nondelivery; reprompt only after confirming work has stopped.
- Exit 5: usage limit. Do not retry or switch Codex models. Use the backup if its
  budget permits; otherwise commit `wip: <progress>` and write `RESUME.md` in the
  reports directory with spec path, current step, and remaining work. Report the
  reset time. Do not finish. Resume later with `herdr-crew up`. Merge part B before
  the WIP commit if needed.
- Exit 6: overlapping parts. Part B is saved as `part-b.patch` in the reports
  directory. Send a findings file instructing the implementer to reconcile it by
  hand, then review.
- Startup failure may be a trust or login dialog. Tell the user which pane needs
  attention; after they handle it, run `herdr-crew up`.

## Optional cloud lane

Only if `cloud-run` is installed: run `cloud-run budget` and follow it. The cloud
lane requires an origin reachable by the cloud and work that needs no local-only
resources. Start `herdr-crew task --cloud <slug>`; scout, implement, review, and fix
then use cloud sessions. Use one spec, no part B. For a local-to-cloud transition,
commit WIP first, then `implement --by cloud` or `fix --by cloud`.
Cloud jobs necessarily push the task branch and reports; use the lane only within
the user's authorization for those pushes. They never merge or deploy.
`implement --model sonnet|opus` selects the implementation model. Reviews use a
fresh session; fixes return to the implementing session. Run jobs in the background.
Exit 4 means the report timed out: give the printed session link to the user.
`commit` folds cloud commits into one local commit and removes `.cloud/` files;
`finish` cleans up the remote task branch only when its work is preserved locally.
