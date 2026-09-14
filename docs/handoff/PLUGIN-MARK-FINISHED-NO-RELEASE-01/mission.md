# PLUGIN-MARK-FINISHED-DOES-NOT-RELEASE-THE-ROW-01 — round 2

Round 1 landed `132dd4b3`. Codex reviewed it and returned **FAIL: 2 High**, both in
`plugins/leadv2/scripts/leadv2-active-registry.sh`. Read
`docs/handoff/PLUGIN-MARK-FINISHED-NO-RELEASE-01/review-codex.md` first. All writes stay in
**`~/Projects/leadv2`**, in THIS worktree.

## H1 — only the FIRST duplicate row is released (`:969-1001`)
`next(...)` mutates only the first matching `task_id`, and the post-write verifier repeats that
same first-match lookup — so it confirms the row it just changed and never sees the others. A
second non-stale duplicate keeps its write-set claim and keeps blocking the next lane.

This defeats the row's entire purpose. The live registry carries dozens of `stale: true` rows and
the pulse reports `призраки: 8`; if only the first of N is released, the ghosts survive and the
lane cap stays consumed.

**Fix:** either define an unambiguous single-row selector, or atomically release ALL matching
claim rows that are safe to retire. State which you chose and why. The verifier must re-read the
file and confirm **zero** live rows remain for that task_id — not "the one I touched is gone".

**Test:** a fixture with two live rows sharing one task_id. After `mark_finished`, both are gone
and neither blocks a dispatch-time write-set check.

## H2 — the fallback write path can empty `active.yaml` (`:1143-1151`)
After `os.replace` fails, the code opens the live file with mode `w` — which **truncates it before
`yaml.dump` completes**. An I/O or serialization failure at that moment leaves `active.yaml` empty
or half-written. That is the live registry of every running lane in both repos.

This directly violates the round-1 contract: no failure path may leave `active.yaml` truncated or
half-written. Round 1 shipped the opposite.

**Fix:** remove the in-place overwrite fallback, or replace it with a same-directory atomic
strategy (temp file in the same directory + `os.replace`) that preserves the original on **every**
failure path.

**Test:** force the failure (make `os.replace` raise, then make `yaml.dump` raise mid-write) and
assert the original file content is intact byte-for-byte afterwards.

## Negative controls — one per finding, both RUN
Round 1's single control did not cover either of these. For H1: restore the first-match-only
release and show the duplicate-row test go RED. For H2: restore the truncating `w` open and show
the corruption test go RED. Paste both pairs (red, then restored green). One mutation is not a
control for two independent defects.

## Off limits — unchanged
- Do NOT sweep the live `~/.claude/leadv2-state/*/active.yaml`. Fixtures only; other sessions are
  live in both repos right now.
- Do not change the lane-cap resolution order or the write-set conflict taxonomy.
- `leadv2-active-registry.sh` stays a library, not a CLI.

## Report
Append `## Round 2` to `docs/handoff/PLUGIN-MARK-FINISHED-NO-RELEASE-01/report.md`: the selector
decision for H1, the atomic strategy for H2, both tests green, both controls red.
End with `DELIVERABLE_COMPLETE`.
