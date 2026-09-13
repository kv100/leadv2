# ac8a48dc2939 round 2 — the fix does not reach the path humans look at

Round 1 landed real work on branch `worktree-ac8a48dc2939` in `~/Projects/leadv2`,
commit `776d5329`. Do not redo it. This round closes one BLOCKING gap an
adversarial review reproduced live, and writes the report round 1 never wrote.

Read `MISSION.md` (round 1) and `critic.full.md` in this directory first.

## What round 1 got right — keep it

- `account_key_for_config_dir` / the `resolve_active_account()` ladder is correct
  and was verified against the real keychain: `~/.claude` → `eb6c5b97`,
  `~/.claude-work` → `5a3c2328`.
- Both suites pass (14/14, 17/17) and both negative controls genuinely mutate the
  production function bodies and go red. That is the standard; keep it.
- No prohibited action in the diff (no login, no `ccswitch`, no routing.yaml cost
  edit, no credential write). Keep it that way.

## The BLOCKING gap

`leadv2-quota-read.py`, `normalize_payload()` (~:1123-1131) and
`_daemon_snapshot_get()` (~:1140-1158):

```python
if len([a for a in accounts if a.get("active")]) != 1:
    ...   # only here does the config-dir re-derivation run
```

A healthy cached blob always carries exactly one `active=True` — the same commit
adds that invariant — so the guard skips re-derivation on every cache hit. The
consequence, reproduced live by the reviewer: seed a cache blob with
`active=True` on `5a3c2328` (as written under `~/.claude-work`), then call
`normalize_payload()` under `CLAUDE_CONFIG_DIR=~/.claude` — it serves
`work_acct`, not `eb6c5b97`.

Why that matters: the cache dir (`~/.claude/state/leadv2/quota-cache`) and the
quota daemon snapshot are **shared and not keyed by `CLAUDE_CONFIG_DIR`**, and
the statusline's real chain is
`quota-fragment.sh → quota-refresh.sh → quota-live.sh` with **no `--no-cache`**
and a 300s TTL. Only `leadv2-ratelimit-probe.sh` forces `--no-cache`.

So round 1 fixed the write path that feeds `rate_limit_history` and
`drain-weights` — genuinely the foundation half — and left the human-facing half
exactly as the row describes it: the founder's statusline still shows an account
the session is not running under.

## What to build

1. **Key the cache and the daemon snapshot by the config dir.** A blob written
   under one `CLAUDE_CONFIG_DIR` must never be served to a session running under
   another. Either put the account key in the cache path, or store it in the blob
   and treat a mismatch as a miss. Pick one and say why in the report.
2. **The re-derivation guard must not depend on the blob looking healthy.** Under
   a known `CLAUDE_CONFIG_DIR`, the derived account wins over whatever the blob
   says, always.
3. **Cover the path that defeated the fix.** No test in either suite currently
   touches `normalize_payload`, `cache_get`, or `_daemon_snapshot_get`. Add
   cases, and a negative control that mutates the new keying inside the
   production function body — not a copy.

Do not change `remaining_pct` semantics: `~/.claude/burn/quota-fragment.sh` does
`pct = d.get("remaining_pct")`; those numbers are REMAINING.

## Write the report round 1 owed

`docs/handoff/ac8a48dc2939/REPORT.md`. It must carry the drain-weights numbers —
the reviewer already measured them, reproduce them yourself and state them:

| window | kept before → after | R² before → after |
|---|---|---|
| 5h | 18 → 99 | −0.743 → −0.3152 |
| 7d | 10 (NOT-ENOUGH-DATA) → 61 | n/a → −0.7937 |

And state the conclusion plainly, because it is the real result of this line:
**both R² are still negative, `max_abs_corr=1.000` with `degenerate_pairs=7`.**
Per-provider (not per-model) metering makes the model-token columns collinear, so
no volume of clean data separates per-model weights under this design. That is a
second honest negative and it is the finding — do not fit a number over it.

## Acceptance

- The reviewer's live reproduction must now fail to reproduce: seed a foreign
  cache blob, call under `~/.claude`, get `eb6c5b97`. Paste the before/after.
- Both existing suites still green at their current counts or better.
- New cases + the new negative control, red line pasted.
- `run-all.sh --scope changed` selection proof, taken **after** the commit —
  the selector reads `git diff origin/main...HEAD`, so it cannot see uncommitted
  work.
- Second-model review must actually complete. Round 1's aborted with
  `gate_engine_aborted rc: 143`; if it aborts again, say so rather than
  reporting a verdict that does not exist.
- Commit inside `~/Projects/leadv2`.
