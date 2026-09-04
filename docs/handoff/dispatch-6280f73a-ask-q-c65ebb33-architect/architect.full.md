# Decision — N6 pulse-reader wiring for `dead_with_unlanded_work`

DECISION_OPTION: a
RATIONALE: option (b) is not "gap left open" but an active regression — the in-scope ledger fix starts emitting a token the untouched readers currently turn into `done`.

## Why (a), decisively

The asymmetry is that the two halves are not independent. The ledger-side allowlist + taxonomy
land **either way** (stated in the question). That is the *producer*. The moment it lands, the
string `dead_with_unlanded_work` starts appearing in `terminal_token` / lane verdicts, and the
untouched readers do not merely fail to render it — they render it **wrong, in the founder's
direction of maximal harm**.

Verified on the live tree (worktree `/Users/kostiantyn.vlasenko/Projects/leadv2`, base 53247bc):

- `grep -rn "dead_with_unlanded_work" plugins/leadv2/scripts/` → **zero hits**. The token does not
  exist yet anywhere in the plugin. So today there is no mislabel; the mislabel is *created* by
  this round's in-scope ledger change.
- `plugins/leadv2/scripts/leadv2-lane-class.py:143`
  `terminal = _is_terminal(status, ledger_state) or (terminal_token != "")`
  — any non-empty terminal token forces `terminal=True` via the OR-fallback.
- `leadv2-lane-class.py:146-149` (stale reinterpretation):
  ```
  if terminal and cls == "dead" and cause.startswith("stale(") and ledger_state != "no_work":
      cause = "done(%s)" % (ledger_state or status or "terminal")
      cls   = "done"
  ```
  A lane that died with unlanded work and whose only remaining motion signal is a stale mtime
  (which is the *normal* shape of a dead lane — `cls="dead"`, `cause="stale(... silent)"` from
  lines 119-121) satisfies all three conditions and is rewritten to `cls="done"`. The one terminal
  that most needs to be loud becomes the one terminal that reads as success.
- `plugins/leadv2/scripts/leadv2-broad-status.sh:545`
  `is_dead = bool(verdict) and (str(verdict) == "dead" or str(verdict).startswith("dead:"))`
  — `dead_with_unlanded_work` is neither exactly `dead` nor `dead:`-prefixed, so it falls through
  the `elif is_dead` branches at 571/590 (the ones the file's own comments at 537-545 and 590-593
  describe as "exactly the silence this fix exists to" break). Same class of miss the colon-vs-bare
  fix already had to correct once.

So option (b) ships a round whose net effect on the founder pulse is **negative**: before, a
dirty dead lane showed as `dead(...)`; after the producer-only change it shows as
`done(dead_with_unlanded_work)`. Deferring does not preserve the status quo — it degrades it. A
follow-up ticket does not protect the founder during the window, and this round's whole premise
(D2: a dirty lane can never land; the terminal must read `pass_unlanded`, not `landed`) is
about eliminating exactly this green lie at the ledger. Fixing the ledger while the pulse still
says "done" reproduces the lie one layer up.

## Why the write-set extension is cheap and bounded

The stated risk of this round ("this dispatcher launches every lane in every repo; a regression is
total") applies to the **dispatcher control path** — D1's containment verdict, D2's downgrade
choke point, D4's class floor. The two files in question are on neither.

| File | Role | Change shape | Blast radius |
|---|---|---|---|
| `leadv2-lane-class.py` | pure read-side classifier (stdin/JSON → verdict) | exclude the unlanded-work token from the 146-149 reinterpretation, i.e. keep `cls="dead"` | pulse/SwiftBar rendering only; no dispatch decision consumes `cls="done"` from here |
| `leadv2-broad-status.sh` | status surface renderer | widen the `is_dead` predicate at :545 to admit the new token | founder-status rows only |

Neither is in `off_limits`. The off_limits list forbids write fences, auto-commit, force-commit of
handoff, a second class-ordering ladder, and real copies of plugin files into consuming repos — an
extension of `LANE_WRITES` to two reader files violates none of them. The "no second class-ordering
ladder — extract and reuse `_lv2_class_rank`" constraint is in fact an argument *for* (a): the
correct fix is to make the existing single taxonomy know the new token, not to teach a follow-up
round a second place where death is spelled differently.

## What (a) obliges, concretely (for the implementing agent — not implemented here)

1. Extend this round's `LANE_WRITES` with `plugins/leadv2/scripts/leadv2-lane-class.py` and
   `plugins/leadv2/scripts/leadv2-broad-status.sh`. Record as an append-only decision, not a
   rewrite of an existing one.
2. `leadv2-lane-class.py`: the stale-reinterpretation guard at 146-149 must not fire for an
   unlanded-work terminal. Preferred shape: a single named predicate/constant set for
   "terminal tokens that mean death, not completion", tested at both the 146 guard and anywhere
   else `terminal_token` implies success — do **not** special-case one string inline in two places.
3. `leadv2-broad-status.sh:545`: `is_dead` widened so any `dead`-family verdict (bare, colon-
   qualified, or `dead_*`-underscored) is dead. Keep it one predicate; the file already carries the
   scar tissue of this having been wrong once.
4. Mutation control: one test that a lane record with `terminal_token=dead_with_unlanded_work` and
   a stale motion mtime classifies `cls=dead` (never `done`), and one that the same verdict renders
   as a dead row in the broad-status surface. Both belong beside the existing
   `tests/test-dirty-lane-never-lands.sh` — the D2 live signal and this reader assertion are the
   same fact observed at two layers.

## Risks of (a), with mitigation

| Risk | Mitigation |
|---|---|
| Widening `is_dead` in broad-status catches an unrelated verdict that merely starts with `dead` and changes an existing row's rendering | Constrain to the enumerated dead-family token set, not a bare `dead`-prefix `startswith`; assert existing status-surface tests (`tests/test-status-surface.sh`, flagged critical/high-entropy in the repo health list) stay green |
| Narrowing the 146-149 reinterpretation accidentally strands a genuinely-done lane in `dead` | The guard is narrowed only for the new token; every previously-reaching value of `terminal_token` keeps its current path. Verify with the existing lane-class tests before and after |
| Scope creep — an extended write-set invites more reader edits | Extension is exactly two files and two predicates; anything beyond that is a follow-up |
| Two parallel steps touching `leadv2-broad-status.sh` (it is a high-churn file, 21+ commits/90d in the repo card) | Sequence the reader fix after the ledger taxonomy step so the token constant has one definition to reference; do not run them as parallel groups |

## Out of scope (implementing agent: ignore)

- Any change to the dispatcher control path beyond D1-D4 as already planned.
- SwiftBar/menu-bar presentation formatting; only the `cls`/`is_dead` classification changes.
- Retro-classifying historical ledger rows written before the taxonomy existed.
- Consuming repos — fix once here, per off_limits (per-file symlinks make it one inode).

## Self-check notes

- Env vars: none introduced. No `LEADV2_*` / `LEAD_V2_*` surface touched.
- Paths: both files existence-verified above with `ls`; both are real files in
  `plugins/leadv2/scripts/`. No `(to-create)` paths in this decision.
- No `claude -p` invocation introduced.
- Concurrent access: noted in the risk table (broad-status is high-churn; serialize the two steps).
- MD-02: this decision respects the round's `off_limits` verbatim and adds no decision that
  contradicts D1-D4; the write-set extension is additive.

DECISION_OPTION: a
RATIONALE: option (b) is not "gap left open" but an active regression — the in-scope ledger fix starts emitting a token the untouched readers currently turn into `done`.

DELIVERABLE_COMPLETE
