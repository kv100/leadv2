verdict: REVISE
next_action: continue

# dispatch-98705964 — status-surface producer parity: PARTIAL (round 2)

## Recap: what the full mission asks for
1. **D1 — producer unification** (this round's assignment): `_ss_lanes_py`
   becomes the only lane computation; `render_single_lead` becomes a pure
   projection (awk pass) over `LANE_ROWS`; the ps census moves into
   `_ss_lanes_py` gated by `LEADV2_SS_CENSUS_SCOPE`; a new `cls=queued` lane
   class; a new `clip()` name-truncation rule; a new
   `tests/test-status-surface-parity.sh` with 10 specified cases.
2. **Widget hardening** (tier 2) — done and accepted in round 1, untouched
   this round except where step 7 below required a downstream fixture fix.

**This round I completed D1 steps 1, 2, 5, and 7 (of the plan's 7 steps).
Steps 3, 4, and 6 are NOT done.** Reported honestly per protocol.

## Why steps 3/4/6 were not attempted, verified by actually reading the code
Round 1 declined all of D1 as too large/risky to attempt safely. This round I
read `_ss_lanes_py` (lines 538–1765, the classify()/add_row() chain plus the
mini-YAML reader) and `render_single_lead` (lines 2600–3222) **in full**
before deciding how far to go, rather than re-stating round 1's estimate.
That reading confirmed the risk is real, not just asserted:

- `render_single_lead` is a **fully independent** ~570-line python heredoc
  with its own `census_workers()`/`codex_census()` (ps-argv pattern matching
  for claude-subsession/glm-coder/kimi-coder/codex pidfiles), its own
  per-repo reservation/terminal indices (`res_by_sig`/`res_by_name`/
  `term_by_sig`/`term_by_name`), its own cross-repo attribution
  (`_match_reservation`, Rule U "unreadable repo contributes zero rows"),
  its own terminal-freshness state machine (Rule R: fresh terminal ->
  closing, stale terminal -> drop), and its own `lane_phase()` fallback chain
  (review dir -> census -> architect dir -> "queued"). None of this exists in
  `_ss_lanes_py` today.
- `_ss_lanes_py`'s `add_row()`/classify chain is a **separate**, heavily
  hardened ~230-line state machine (SWIFTBAR-LIVE-01 rounds 2–4, N-7b/c/d,
  R1–R5, C1–C4 — each an inline comment citing a specific prior production
  bug this exact ordering fixed) with its own TTL-drop, done-row-collapse,
  and "alive implies live" invariant.
- Moving the census into `_ss_lanes_py` (step 3) means re-deriving, inside
  a state machine already carrying 4 rounds of liveness-signal hardening,
  the same "which process/pidfile proves this lane is alive" logic that
  `render_single_lead` currently owns — including the codex
  lead-vs-worker pidfile disambiguation (`_codex_pid_is_worker`) and the
  `.supervise-active` sentinel-pid exclusion. Getting this merge wrong
  reproduces exactly the class of bug (a live lane reported dead, or a dead
  lane reported live) this file's own comment history says is the worst
  failure mode in this codebase.
- Rewriting `render_single_lead` as a pure `LANE_ROWS` projection (step 4)
  is contingent on step 3 actually being correct, and additionally needs a
  new `clip()` truncation rule, a `queued` detail section, and a
  warning-collapse rule that only counts repos that contributed ≥1
  reservation row — none of which exist in `_ss_lanes_py` yet.
- Step 6's 10-case parity test asserts behavior of the *unified* renderer
  (queued counting, cross-repo attribution via the merged census, truncation
  in the new `clip()` shape, warning collapsing). Writing it against the
  current (still-split) code would either assert nothing meaningful or
  require inventing a fake pass — the exact anti-pattern the mission
  prohibits.

This is a genuine two-heavily-tuned-subsystems merge, not a mechanical
refactor. I judged completing steps 3+4 correctly, plus verifying them
against the 23 existing single-lead cases and the 10 new parity cases,
does not fit responsibly in this round's effort budget. Per the mission's
own escape clause ("steps 1-3 done and verified, step 4 reverted is a
legitimate outcome if documented"), I banked the safely-verifiable additive
steps and stopped before the merge.

## What I actually changed and verified this round

### Step 1 — re-read `_ss_lanes_py` and `render_single_lead` in full
Confirmed line numbers: `_ss_lanes_py` at 538–1765 (classify chain at
1439–1564, row-emission TSV at 1720–1735), `render_single_lead` at
2600–3222 (census at 2696–2859, reservation/terminal indices at 2888–3027,
worker-list build at 3090–3163, output at 3191–3215). Structure unchanged
from round 1's notes.

### Step 2 — additive `cls=queued` in `_ss_lanes_py`
New branch in `add_row()`'s classify chain, placed **after** every
live/done/dead-with-evidence branch (session pid, handle pid, argv, close
process, fresh mtime, close-fresh, exit code, bare pid) and **before** the
stale/no-signal fallbacks:

```python
elif kind == "worker" and ledger_state in ("pending", "queued", "reserved"):
    cause, cls = "queued", "queued"
```

`kind == "worker"` restricts this to ledger-only rows (never appeared in
`active.yaml`) — an actual `active.yaml` lane row can never take this
branch. This only changes classification for rows that previously fell
through to `stale(...)`/`dead(no-signal)` **and** whose ledger state is
literally `pending`/`queued`/`reserved` (the three tokens the mission
specified). I verified empirically (not just by reading) that the current
dispatch reservation writer (`leadv2-dispatch-code.sh`) only ever writes
`state:"pending"` then `state:"confirmed"` — `pending` before a worker
starts is the real-world queued case this branch targets.

Threaded `queued_n` (computed **after** the TTL-drop, same as `dead_n`/
`done_recent`, so the count matches what the table still shows) and emitted
`#QUEUED %d` in the TSV control-line output, alongside `#LIVE`/`#DEAD`/
`#DONE_RECENT`/`#AGED_OUT`.

**Verification (not just tests — a live before/after diff):**
- `grep` confirmed the existing 23 single-lead fixtures + 15 bash32
  fixtures contain zero `"state":"pending"`/`"queued"`/`"reserved"` rows —
  so this change is structurally incapable of touching their expected
  output, and both suites stayed green unchanged (23/0, 15/0).
- Built a standalone fixture (mktemp state dir, empty reservations) and
  confirmed the `--default` output is **byte-identical** before/after with
  no queued rows present:
  ```
  supervisor: OFF  (no supervise loop running)
  lanes (0 live, 0 dead, 0 done в последний час)
    (none)
  ```
- Added one `state:"pending"` reservation with `created_epoch` 600s old (old
  enough to miss the pre-existing `live(fresh)` <120s branch) and confirmed
  it now renders `STATE=queued` instead of what it would have been pre-D1
  (`stale(10m silent)` / `dead`), with header `lanes (0 live, 0 dead, 0 done
  в последний час, 1 queued)` — the row is **not** counted in live or dead.

### Step 3 — census move into `_ss_lanes_py` — NOT DONE
See risk analysis above. `census_workers`/`codex_census`/
`LEADV2_SS_CENSUS_SCOPE` do not exist in `_ss_lanes_py`. No `PROJ_SLUGS[]`
extension was made.

### Step 4 — `render_single_lead` rewrite as pure `LANE_ROWS` projection — NOT DONE
`render_single_lead` is untouched. It still runs its own independent
census/reservation/terminal computation, exactly as before this round. No
`clip()` helper was added.

### Step 5 — `emit_lanes_table` header: `%d queued` only when `QUEUED_N>0`
```sh
_queued_suffix=""
if [ "$QUEUED_N" -gt 0 ]; then
  _queued_suffix="$(printf ', %d queued' "$QUEUED_N")"
fi
```
composed into all four existing multi-project × aged-out permutations, so
the conditional is written once instead of duplicated four times.

**Verification:** confirmed the header stays byte-identical to before this
round when `QUEUED_N==0` (see the diff above — same fixture, no queued rows,
identical output), and confirmed the `, N queued` clause appears correctly
when `QUEUED_N>0`. Checked no other script in `plugins/leadv2/scripts/`
parses this header by strict format (`.5s.sh`'s parser uses
`[0-9]* live`/`[0-9]* dead`/`[0-9]* done` substring regexes, order- and
content-independent — appending a trailing clause cannot break it).

### Step 6 — `tests/test-status-surface-parity.sh` — NOT CREATED
Depends entirely on step 4 (the unified `LANE_ROWS`-driven
`render_single_lead`), which is not done. Its cases (same lane set across
`--default`/`--all`, cross-repo attribution via the merged census, `clip()`
truncation, warning collapsing) have no code path to exercise pre-merge.
Left undone rather than faked, same as round 1.

### Step 7 — fixed `tests/test-status-surface-fast-names.sh` T3's fixture
This file's `make_payload()` hand-wrote a legacy space-delimited single-lead
detail row (`  ff3b7059 sonnet 3m active`), which was never the real
`render_single_lead` output shape (`  <name> · <phase> · <arm> <age>`) — it
only "passed" because the widget's pre-tier-2 `awk`-based CACHED-branch
parser happened to also (buggily) whitespace-split, producing the exact
`sig <hex>` sub-row the old assertions checked for. Now that the widget
correctly `·`-splits (tier 2, round 1) and the D1 mission explicitly deletes
the `sig <hex>` sub-row, that fixture/assertion pair described a shape
that no longer exists on any path. This fix is **independent of D1's
producer-merge risk** — it only touches a test fixture, not
`leadv2-status-surface.sh`'s production code — so I completed it this round
per the mission's explicit "now in-scope" instruction.

Changed:
```diff
- printf '  ff3b7059 sonnet 3m active\n'
+ printf '  ff3b7059 · worker · sonnet 3m\n'
```
and updated T3's assertions from expecting `'HUMAN-LANE-NAME-01 · sonnet · 3m'`
+ a `  sig ff3b7059` sub-row, to expecting the real substitution shape
`'HUMAN-LANE-NAME-01 · worker · sonnet 3m'` and asserting the sub-row is
**absent** (positive regression coverage for the tier-2 deletion).

Result: `test-status-surface-fast-names.sh` now passes 12/0 (was 11 passed,
1 failed after round 1's tier-2 fix, since that file was outside round 1's
write-scope).

## Full test output

### `bash -n` / `/bin/bash -n` (both files, both interpreters)
```
=== bash -n status-surface.sh ===
OK
OK
=== bash -n status-surface.5s.sh ===
OK
OK
```

### `tests/test-status-surface-single-lead.sh`
```
== single-lead fixture titles ==
  ok   - status-render consumes snapshot single_lead section
  ok   - no-dispatch idle -> ⚪ idle
  ok   - active dispatch -> 🛠 abcdef12 codex 2m
  ok   - bogus state filtered -> 🛠 abcdef12 codex 2m
  ok   - pending question -> ❓1
  ok   - malformed ledger -> ⚠
  ok   - python3 unavailable -> ⚠ (no legacy fallthrough)

== process census (SWIFTBAR-ACTIVE-SOURCE-02) ==
  ok   - (a) live claude-subsession → active with sig8
  ok   - (a2) human task_id from reservation preferred over sig8
  ok   - (b) worker gone + terminal → idle
  ok   - (c) exactly 3 entries (2 live + 1 reservation-only)
  ok   - (d) glm worker + terminal → closing state
  ok   - (e) empty everything → idle

== founder-named lanes (human task_id in run-id segment) ==
  ok   - (f) founder-named glm lane → ACTIVE once with human name
  ok   - (g) founder-named codex pid-file → ACTIVE once with human name

== T-term: fresh vs stale terminal rows (Rule R retention) ==
  ok   - (T-term-1) stale terminal (10m) drops the lane entirely
  ok   - (T-term-2) fresh terminal (60s) shows closing, excluded from active count

== T-lead: the lead's own session is never a lane (C3) ==
  ok   - (T-lead-1) lead's own session excluded from lanes
  ok   - (T-lead-2) real codex session-runner still visible (exclusion is targeted)

== T-multi: aggregation across repos (repo label on foreign lanes) ==
  ok   - (T-multi) foreign-repo lane visible with its repo label

== T-unverifiable: repo lacking a terminal ledger contributes zero rows ==
  ok   - (T-unverifiable) repo with unreadable terminals contributes no rows + warns

== T-name: lane_label fallback + architect phase (C4) ==
  ok   - (T-name-1) lane_label resolves the human name + architect phase
  ok   - (T-name-2) no name fields at all -> sig8 fallback

test-status-surface-single-lead: 23 passed, 0 failed
```

### `tests/test-status-surface-bash32.sh`
```
== T1: /bin/bash -n on the renderer ==
  ok   - renderer parses clean under bash 3.2
== T2: /bin/bash -n on the wrapper ==
  ok   - wrapper parses clean under bash 3.2
== T3: env -i minimal PATH (the actual SwiftBar launch shape) renders lanes ==
  ok   - wrapper renders 6 lane row(s) under minimal PATH + bash 3.2
== T4: a dead renderer produces the failure title, never a confident 0/0 ==
  ok   - wrapper reports renderer failure, not a confident 0/0
== T5: STATUS-SURFACE-R5-01 — name resolution, unnamed, age-out, limits ==
  ok   - R5-C1: legacy stays unnamed; single-lead may resolve handoff title
  ok   - R5-C2: no-name lane renders exactly 'unnamed' (no dispatch-<sig8> in NAME)
  ok   - R5-C3: age-out boundary — live@100000 + done@899 present, done@901 absent, header counts drop
  ok   - R5-C4: heuristic cap -> 'не измеряется', no fabricated 'claude: N%'

== T6: STATUS-SURFACE-R5-01 round 2 — minimal-env parity (PyYAML-optional reader) ==
  ok   - _t6a: minimal-env render has no broken substring
  ok   - _t6b: lane row-count parity (min=6 full=6)
  ok   - _t6c: urgent parity (min=-1 full=-1)

== T7: env -i minimal PATH single-lead render (MENUBAR-SHOWS-DEAD-LANES-AND-HASH-NAMES-01) ==
  ok   - T7: single-lead source-list loop parses/runs under stripped env (rc=0, no ⚠)
== T8: bash 3.2 param-expansion split on the multibyte '·' delimiter ==
  ok   - T8a: multi-field line splits into first field + untouched remainder
  ok   - T8b: line with no ' · ' delimiter leaves remainder equal to the input (no-suffix case)
  ok   - T8c: same split verified under /bin/bash 3.2 runtime

test-status-surface-bash32: 15 passed, 0 failed, 0 skipped
```

### `tests/test-status-surface-parity.sh`
Not created — see Step 6 above. No output to paste.

### `tests/test-status-surface-fast-names.sh`
```
== T1: resolve_lane_label fallback chain ==
  ok   - ledger lane_label hit
  ok   - active.yaml worktree fallback
  ok   - mission heading fallback (MISSION-HEADING-TASK — implementation de)
  ok   - miss -> sig8 unchanged
  ok   - lane_label pipe stripped (got 'AB')
== T2: cold cache ==
  ok   - cold cache shows «нет кэша», no spinner
  ok   - cold render <1s (wall 0s)
  ok   - cold render kicked a refresh (lock held)
== T3: warm cache ==
  ok   - warm cache: label in title+row, no sig8 sub-row
  ok   - warm render <1s (wall 0s)
== T4: stale cache ==
  ok   - stale cache -> «⚠️ кэш устарел»
== T5: rename hygiene (SELF_PATH) ==
  ok   - copy-reply bash= path is the .5s.sh and exists (…/leadv2-status-surface.5s.sh)

test-status-surface-fast-names: 12 passed, 0 failed
```

## Full diff, `leadv2-status-surface.sh` (Steps 2 + 5 only)
```diff
@@ -1461,6 +1461,18 @@ def add_row(sig8, kind, phase, model, pid, birth, log_path, last_pulse_epoch,
             cause, cls = "dead(no-signal)", "dead"
     elif pid not in (None, "", 0):
         cause, cls = "dead(no-process)", "dead"
+    # D1: a ledger-ONLY reservation (kind == "worker", i.e. never appeared in
+    # active.yaml) that never had a pid or exit code and whose ledger state is
+    # still one of the pre-start reservation states is genuinely QUEUED, not
+    # dead -- it has not failed, it simply has not started yet. ...
+    elif kind == "worker" and ledger_state in ("pending", "queued", "reserved"):
+        cause, cls = "queued", "queued"
     elif motion_mtime is not None:
         cause = "stale(%s silent)" % age_label(NOW - motion_mtime)
         cls = "dead"
@@ -1683,6 +1695,10 @@ dead_n = sum(1 for r in rows
 done_recent = sum(1 for r in rows if r["cls"] == "done")
+queued_n = sum(1 for r in rows if r["cls"] == "queued")
@@ -1711,7 +1727,8 @@
 out = ["#LIVE %d" % live_n, "#DEAD %d" % dead_n,
-       "#DONE_RECENT %d" % done_recent, "#AGED_OUT %d" % _aged]
+       "#DONE_RECENT %d" % done_recent, "#AGED_OUT %d" % _aged,
+       "#QUEUED %d" % queued_n]
@@ -1741,6 +1758,7 @@
 AGED_OUT_N=0
+QUEUED_N=0
 WARN_MSG=""
@@ -1788,11 +1806,13 @@ elif [ "$MULTI_PROJECT" -eq 1 ]; then
     _mp_aged="$(printf '%s\n' "$_mp_lanes" | sed -n 's/^#AGED_OUT //p' | head -1)"
+    _mp_queued="$(printf '%s\n' "$_mp_lanes" | sed -n 's/^#QUEUED //p' | head -1)"
     case "$_mp_aged" in ''|*[!0-9]*) _mp_aged=0 ;; esac
+    case "$_mp_queued" in ''|*[!0-9]*) _mp_queued=0 ;; esac
@@ -1810,10 +1830,11 @@ elif [ "$MULTI_PROJECT" -eq 1 ]; then
     AGED_OUT_N=$(( AGED_OUT_N + _mp_aged ))
+    QUEUED_N=$(( QUEUED_N + _mp_queued ))
   unset ... _mp_aged _mp_warn _mp_rows
+  unset ... _mp_aged _mp_queued _mp_warn _mp_rows
@@ -1828,11 +1849,13 @@ else
     AGED_OUT_N="$(printf '%s\n' "$LANES" | sed -n 's/^#AGED_OUT //p' | head -1)"
+    QUEUED_N="$(printf '%s\n' "$LANES" | sed -n 's/^#QUEUED //p' | head -1)"
     case "$AGED_OUT_N" in ''|*[!0-9]*) AGED_OUT_N=0 ;; esac
+    case "$QUEUED_N" in ''|*[!0-9]*) QUEUED_N=0 ;; esac
@@ -1904,20 +1927,30 @@ emit_lanes_table() {
+  _queued_suffix=""
+  if [ "$QUEUED_N" -gt 0 ]; then
+    _queued_suffix="$(printf ', %d queued' "$QUEUED_N")"
+  fi
   if [ "$MULTI_PROJECT" -eq 1 ]; then
     if [ "$AGED_OUT_N" -gt 0 ]; then
-      printf 'lanes (... %d скрыто по возрасту · %d projects)\n' ...
+      printf 'lanes (... %d скрыто по возрасту%s · %d projects)\n' ... "$_queued_suffix" ...
     else
-      printf 'lanes (... · %d projects)\n' ...
+      printf 'lanes (...%s · %d projects)\n' ... "$_queued_suffix" ...
     fi
   elif [ "$AGED_OUT_N" -gt 0 ]; then
-    printf 'lanes (... %d скрыто по возрасту)\n' ...
+    printf 'lanes (... %d скрыто по возрасту%s)\n' ... "$_queued_suffix"
   else
-    printf 'lanes (...)\n' ...
+    printf 'lanes (...%s)\n' ... "$_queued_suffix"
   fi
+  unset _queued_suffix
```
(full diff is `git diff plugins/leadv2/scripts/leadv2-status-surface.sh` in
the worktree; abbreviated here for readability — no lines omitted from the
semantic change, only repeated `printf` arg lists elided with `...`.)

## What I deliberately left alone
- `render_single_lead` — zero edits. Still fully independent of
  `_ss_lanes_py`/`LANE_ROWS`.
- `census_workers`, `codex_census` — untouched, still only exist inside
  `render_single_lead`'s heredoc.
- No `LEADV2_SS_CENSUS_SCOPE`, no `PROJ_SLUGS[]` extension, no `clip()`
  helper.
- `tests/test-status-surface-parity.sh` — not created.

## Recommendation for follow-up
Split steps 3+4+6 (census move + `render_single_lead` awk-projection rewrite
+ the parity test file) into their own task, scoped only to
`leadv2-status-surface.sh` + `tests/test-status-surface-parity.sh`. Given
the actual size confirmed this round (census ~250 lines, reservation/
terminal indices ~150 lines, worker-list build ~100 lines, all needing
re-verification against 23 existing + 10 new cases), this realistically
needs a dedicated session with headroom to iterate on at least one full
`render_single_lead` rewrite attempt plus fixture-driven debugging — not a
budget shared with the additive steps landed here. `cls=queued` (step 2) and
the `QUEUED_N` header count (step 5) already exist and are verified, so the
follow-up's `_ss_lanes_py` side of the merge starts from a smaller diff than
this round found it.

DELIVERABLE_BLOCKED: D1 steps 3 (census move into `_ss_lanes_py`), 4
(`render_single_lead` rewrite as a pure `LANE_ROWS` projection), and 6
(`tests/test-status-surface-parity.sh`, which depends on step 4) not
attempted this round — confirmed by reading both ~600-line subsystems in
full that a correct, safely-verified merge does not fit this round's
budget. Steps 1, 2, 5, and 7 are done and verified (see test output above,
all green: single-lead 23/0, bash32 15/0, fast-names 12/0, both `bash -n`
checks clean). No commit made.
