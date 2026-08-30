# Scheduled decisions

One row per deferred decision: an id, status, the condition that triggers it, and the
exact reversible action to take when it fires. Anything promised for later goes here the
same turn it is promised (task-anchor DIRECTIVE #4).

---

## PROMISE-GUARD-BLOCK-FLIP-01

STATUS: CONDITION_BOUND (no fixed date — gated on journal evidence, not the calendar)

CONTEXT: PROMISE-GUARD-BIND-01 (2026-08-30) fixed the promise extractor and
`ACTION_BASH_RE`/action-kind binding in `plugins/leadv2/hooks/leadv2-promise-guard.sh` so
a promise of a classifiable kind (dispatch / commit / write / test-run) is only "kept" by
an action of that same kind, not by any tool call. It ships log-only:
`LEADV2_PROMISE_GUARD_BLOCK` defaults to `"0"` — the hook journals every verdict
(`~/.claude/leadv2-promise-guard.jsonl`, one row per turn with a commitment shape,
`verdict: "fired"` meaning "would have blocked") but never emits `decision:block`.

GO-CONDITION (query over the journal, evaluate before flipping):
```
python3 -c "
import json
rows = [json.loads(l) for l in open('$HOME/.claude/leadv2-promise-guard.jsonl') if l.strip()]
fired = [r for r in rows if r.get('verdict') == 'fired']
# Consecutive tail: no fired row is a false positive (manually reviewed — a promise
# that really was kept by an action of a DIFFERENT kind than what was promised, or a
# promise/action-kind misclassification). Require >=20 consecutive fired rows with
# zero flagged false positives, spanning >=3 distinct session_ids.
print(len(fired), len({r['session_id'] for r in fired}))
"
```
Flip when: the last 20 consecutive `fired` rows have zero known false positives (checked
by hand against the quoted transcript) AND those rows span at least 3 distinct
`session_id`s (not one session's repeated pattern). Re-run the query above after adding
any new `PROMISE_KIND_PATTERNS` / `ACTION_KIND_BASH` entry — widening the kind taxonomy
resets the evidence window for the newly-covered kind.

FLIP (exact): set `LEADV2_PROMISE_GUARD_BLOCK=1` in the environment that runs the Stop
hook (repo-level `.claude/settings.json` `env` block, or the shell profile that starts
`claude`). No code change — the hook already reads this var.

ROLLBACK (one step): unset `LEADV2_PROMISE_GUARD_BLOCK` (or set it back to `"0"`). The
hook falls back to log-only immediately on the next Stop event; no state to clean up,
the journal keeps accumulating either way.
