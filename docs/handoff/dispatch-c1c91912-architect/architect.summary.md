verdict: APPROVE
next_action: continue

Scoped finisher design for lane eb2d7143: fix RED-1/RED-2 in 4 lane-owned files, no redo.

- Mission's RED-1 premise is wrong: `explicit_mission_fast_path` is correct for `plugin-only` fixtures; the real signal is rc=4 = `all_arms_exhausted`.
- Ranked leak hypotheses: inherited `DISPATCH_LEDGER_DIR` (`:398`), park path via `LEDGER_REPO_ROOT` (`:705/:732`), unsandboxed lockout dir.
- 19 dirty runtime files must not be staged.

Full: architect.full.md
