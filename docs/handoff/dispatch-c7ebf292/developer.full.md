# dispatch-c7ebf292 — developer deliverable (design mission, fable arm)

The full analysis is the mission's declared write target:
`docs/audits/seamless-account-switching-fable.md` (in this lane's worktree, committed on the lane branch).

## Outcome

1. Resume breaks on a switch because the transcript store is per `CLAUDE_CONFIG_DIR` root
   (`<root>/projects/<realpath-cwd>/<uuid>.jsonl`), and the founder's two accounts are two roots
   (`~/.zshrc` function + aliases). Not account-bound, not server-bound: measured by creating a
   session on the work root and resuming it on the personal root by absolute path (same uuid,
   appended to the origin root's file). Resume by uuid across roots fails; the control on the same
   root succeeds.
2. `~/ccswitch.sh --switch` rewrites the un-suffixed `Claude Code-credentials` record; both live
   roots use `Claude Code-credentials-<sha256(root)[:8]>` records. The un-suffixed token expired
   2026-08-25. `/switch` does not switch the founder's sessions.
3. A live session's account can only change by rewriting its root's record (`/login`), which is the
   documented 08-28/31 slot-collapse incident. Lanes record root + uuid at spawn and can be re-raised
   by path; the lead records neither.
4. The team max_5x account answered the usage endpoint with 200 on one live probe today; burn's
   `rate_limit_history` shows 94 ok vs 17 unauthenticated for the live max_5x key; the client caches
   its own usage per root. The D1 premise "401 by design" is refuted; D1's conclusion stands.
5. Three local zero-endpoint signals exist and none is read by the selector today.
6. Ranked proposals R1–R6 with costs are in the report §4.

## Self-check (docs-only lane)

No `.sh` or `.py` file changed; `bash -n` / `py_compile` / changed-scope runner have no targets.
Scope proof and `main...HEAD` are pasted in the final commit step of the lane transcript and
reproduced here after commit:

```
git diff --name-only main...HEAD -- .   → only .md files under docs/audits/ and docs/handoff/dispatch-c7ebf292/
```

## Deliberately left alone

- `docs/audits/seamless-account-switching-astra.md` and `-lead-verification.md`: not read (arm independence).
- `~/ccswitch.sh`, `~/.zshrc`, the `switch` skill, `leadv2-history-primer.sh:43` (dormant hardcoded root): findings only, no edits — design mission.
- No credential printed, refreshed by hand, or rotated; no account switched.

DELIVERABLE_COMPLETE
