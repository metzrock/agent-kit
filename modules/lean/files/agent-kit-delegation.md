# Delegation
Hand well-defined changes to implementer with the goal, acceptance criteria, files,
constraints and check commands. Small, fully known changes stay in the main session.
Run scoper before planning unfamiliar work unless it touches three or fewer unread files.
Spot-check its file references. Keep investigation, scope, architecture and final decisions
in the main session. Always review the real diff and run checks yourself. Send fixes back
to the same implementer through SendMessage. Use reviewer only when requested or for risky
changes. Keep architecture refactors, concurrency, security, migrations, state machines
and public API changes in the main session. Shipper runs only when asked; include its PR
link in the final reply.
