# WRITESET-REFUSAL-NEVER-NAMES-THE-BLOCKER-01 — make the refusal name what blocked it

Repo: `~/Projects/leadv2` (shared plugin tree). Founder standing permission for this session is
recorded at `persona-engine/.claude/leadv2-overrides/extensions.md:748`
(`SHARED-TREE-STANDING-PERMISSION-01`); approved scope is **this task only**. Anything wider — stop
and ask.

## The defect, measured (do not re-derive)

`dispatch_refused reason=writeset_conflict` prints the **refused lane's own** write set and never the
incumbent it collided with. The registry already computes and prints the answer:

    plugins/leadv2/scripts/leadv2-active-registry.sh:399
      print(f"[registry] writeset conflict: other={other.get('task_id')} reason=pending_resolution", file=sys.stderr)
    plugins/leadv2/scripts/leadv2-active-registry.sh:419
      hit = sorted({a for a in cand_paths for b in other_paths if _lv2_ws_overlaps(a, b)})

…and `plugins/leadv2/scripts/leadv2-dispatch-code.sh:7240` calls
`leadv2_active_register ... >/dev/null 2>&1`, discarding it. (The sibling call at :7056 needs the
same treatment — check both.) Refusal emitted at :7245 and :7065.

**Cost, measured 2026-09-04:** two leads hit this independently and neither could tell what blocked
them. One narrowed her declared writes to a single file and learned nothing; the other had to
reimplement the overlap predicate in Python against `active.yaml` to get an answer the code had
already computed. Both lost a round to a fact sitting in swallowed stderr.

## Two failures wear one name — this is the sharper half

`exit 5` is emitted for **two different situations**, and both surface as `writeset_conflict`:

1. **`pending_resolution`** (`leadv2-active-registry.sh:388-400`) — an incumbent with *no* write set
   that is still inside `_lv2_ws_pending()`'s window (`LEADV2_WRITESET_PENDING_WINDOW_SEC`, default
   900 s). This refuses **before any path comparison happens at all**.
2. **`overlap`** (:419) — a genuine path collision with a declared write set.

Because both print the same word, a blocked lead reasonably narrows their write set — which is
useless against case 1, where paths were never compared. That is exactly what happened today.

**Requirement: the refusal must name the case and the incumbent.** Something of the shape

    dispatch_refused reason=writeset_pending  task=<sig> blocked_by=<task_id> age_s=<n> window_s=<n>
    dispatch_refused reason=writeset_overlap  task=<sig> blocked_by=<task_id> paths=<a>|<b>,...

Keep `writeset_conflict` working as a prefix/alias if anything greps for it — check before changing
the token, do not break a caller to make the log prettier.

## Worth knowing, do not re-derive

A row that is **recreated** every couple of minutes never leaves the 900 s window: its `started_at`
resets. So "the window expires" is true of the code and false in practice for a resurrecting row —
which is why cleaning 40 stale rows did not unblock anything today. Do not "fix" this by shortening
the window; that is suppression. It is tracked separately as
`RECOVERY-ATTACHES-A-BYSTANDER-PID-TO-A-LANE-01`.

## Acceptance — behavioural, with a negative control

1. **It names the blocker.** Provoke each case against a scratch registry and show the refusal line
   carrying `blocked_by=<task_id>`: once for a pending incumbent with no write set, once for a real
   path overlap. Paste both lines.
2. **The two cases are distinguishable** from the refusal text alone, without reading the registry.
3. **Negative control, mandatory.** Re-swallow the stderr (restore `2>/dev/null`) and show the
   blocker's name disappears from the refusal. Without this, "the name is there" cannot be
   distinguished from "the name was always there and we never looked".
4. No existing caller that greps `writeset_conflict` breaks — name the callers you checked.

## Constraints

- One commit, reasoning in the body, revertable in one `git revert`.
- Do not touch `tests/known-red-suites.txt` — it may only shrink.
- Never `git add -A`: this checkout carries other sessions' uncommitted files. Stage by path.
- Do not run the core-offline suite while another lane is inside its e2e gate.

## Measured for you 2026-09-04 (lead) — do not re-derive

**Both call sites, exact:**

    :7056  _register_out="$(... leadv2_active_register ... 2>/dev/null)"   # captures stdout, drops stderr
    :7240  ... leadv2_active_register ... >/dev/null 2>&1 || _ws_rc=$?     # drops both
    :7065 / :7245  the two `5)` branches that emit `dispatch_refused reason=writeset_conflict`

**Nothing outside this file consumes the token.** `grep -rn writeset_conflict plugins/leadv2/`
returns exactly: the six lines at :7065-7067 and :7245-7247, one comment in
`leadv2-active-registry.sh:33`, and one comment in `tests/test-glm-flash-handle.sh:161`. No test
asserts on the string. So you may rename the reason cleanly — just update the two comments in the
same commit so they do not become lies.

**A live reproduction is sitting in the registry right now.** `~/.claude/leadv2-state/leadv2/active.yaml`
carries `GLM-PEAK-RULE-IS-MODEL-BLIND-01` with `phase: recovered`, **no write set**, age ~400 s — inside
the 900 s window. It refuses every incoming dispatch to this repo through `pending_resolution`,
before any path comparison. If your own dispatch is refused, that is not an accident, it is case 1 of
this very defect. Say so in the report and use it as evidence, not as a blocker to route around.

## Scope is ONE file — the registry already prints both answers

Verified at `leadv2-active-registry.sh:399` and `:420`:

    [registry] writeset conflict: other=<task_id> reason=pending_resolution
    [registry] writeset conflict: other=<task_id> paths=<a>,<b>

Both cases already carry the blocker's id, and the two are already distinguishable by
`reason=` vs `paths=`. **So the whole fix is in `leadv2-dispatch-code.sh`:** stop discarding
stderr at :7056 and :7240, parse `other=` / `reason=` / `paths=` out of it, and emit two distinct
refusal reasons.

**Do NOT edit `leadv2-active-registry.sh`.** It is claimed by a concurrent lane
(`DOD-GATE-CHARGES-LANES-FOR-HARNESS-WRITES-01`). If you become convinced the registry must change,
stop and say so — do not edit it.

Declared write set for this lane, and nothing beyond it:

    plugins/leadv2/scripts/leadv2-dispatch-code.sh
    plugins/leadv2/scripts/tests/test-writeset-refusal-names-blocker.sh
    docs/handoff/WRITESET-REFUSAL-NEVER-NAMES-THE-BLOCKER-01/

## Addendum — most of the fix already exists, uncommitted, in your worktree

A first attempt got most of the way before the lead killed its worker on a false liveness reading.
The edit survived: `plugins/leadv2/scripts/leadv2-dispatch-code.sh` in
`~/Projects/leadv2/.claude/worktrees/WRITESET-REFUSAL-NEVER-NAMES-THE-BLOCKER-01` carries
**82 insertions, 11 deletions, uncommitted** — a `_emit_writeset_refusal()` helper that parses the
registry stderr into `writeset_pending` (with `blocked_by`, `age_s`, `window_s`) and
`writeset_overlap` (with `blocked_by`, `paths`), plus a documented fallback to the legacy
`writeset_conflict` line when the stderr parses to neither shape.

**Review it, finish it, do not rewrite it.** What it still needs, and what your acceptance is:

- the two call sites at `:7056` / `:7240` actually wired to it (stderr captured, not discarded);
- the suite `plugins/leadv2/scripts/tests/test-writeset-refusal-names-blocker.sh`;
- the mandatory negative control from the acceptance section above;
- the two stale comments (`leadv2-active-registry.sh:33`, `tests/test-glm-flash-handle.sh:161`)
  left truthful.

If you judge part of that edit wrong, say what and why in the report — do not silently replace it.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-d3884817" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.

Before you finish, run your own falsification set and paste its raw output into
your final report: `bash -n` every shell file you changed, `python3 -m
py_compile` every Python file you changed, and the repo's changed-scope test
runner. Show the red output you got and the green output after your fix. A lane
whose self-check is missing or red is refused before any reviewer is spent on
it -- you will have burned the lane for nothing.

Commit your work on the lane branch before ending your session; an uncommitted
exit is treated as an incident.