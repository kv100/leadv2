# PANEL-MERGE fix round 1 — implementation design

Resume target: `.claude/worktrees/b98371eb` (branch `worktree-b98371eb`), 164/154 on
`plugins/leadv2/scripts/leadv2-status-surface.sh` + untracked
`plugins/leadv2/scripts/leadv2-lane-class.py`. Direction is right; do not restart.

Measured, not assumed: `bash tests/test-status-surface-single-lead.sh` → **12 passed, 11 failed**.

---

## 1. Root cause — one defect, not eleven

`classify()` in `leadv2-lane-class.py` is the **lanes path's** process-liveness branch chain lifted
verbatim (its docstring says so). Every route it has to `cls="live"` is a *process* signal:

| branch | fact required |
|---|---|
| `live` | `pid_alive_session` |
| `live(pid N)` | `pid_alive_handle` |
| `live(argv)` | `argv_alive` |
| `live(close pid N)` | `close_alive` |
| `live(fresh)` | `max_mtime` within 120s |

The **single-lead renderer discovers lanes from the dispatch reservation ledger**, not from a process
census. Its evidence that a lane is running is `state ∈ {pending, confirmed}` + unexpired
`created_epoch` + an assigned `arm`. `_project()` (status-surface.sh, single-lead heredoc) hands
classify `pid_alive_session=False, pid=None, max_mtime=None, motion_mtime=None`, so the chain falls
straight through to `else: cause, cls = "dead(no-signal)", "dead"`, and then
`if not lc["live"]: continue` **deletes the lane**.

Confirmed against fixtures — every "got `⚪ idle`" failure is a reservation-only row with
`"state":"confirmed"` and `PS_STUB="1 sleep 1"` (no matching process):

- `active dispatch` — `task_sig:abcdef1234567890, arm:codex, state:confirmed, −120s`
- `bogus state filtered`, `(g)`, `(T-multi)`, `(T-unverifiable)`, `(T-name-1)`, `(T-name-2)` — same shape
- `(c) expected 3, got 2` — the undercount is the same drop, one lane of three

The old code expressed this rule directly and the refactor deleted it:

```python
# removed by the refactor, single-lead path (b)
if tstate is None and age > ttl:
    continue          # else: the reservation IS an active lane
```

**The classifier has no vocabulary for a dispatch reservation.** That is the whole bug.

Two independent, smaller defects ride along:

- **(d) / (T-term-2)** — `state = "closing"` was deleted outright. A fresh terminal row used to render
  a detail line while staying out of the active count. This one is a *deliberate* behaviour change
  demanded by the founder ("no terminal lanes in title or body"); the tests must move, see §5.
- **(f)** — `clip_name()` snaps the cut back to the last `-`/`_`, so `FEED-SCAN-USABLE-CANARY` at
  n=20 renders `FEED-SCAN-USABLE…` (17 chars) instead of using the 20 the column has. The `…` marker
  is a genuine improvement; the snap-back throws away information for free.

---

## 2. The conflation to fix in the code

`if not lc["live"]: continue` collapses four genuinely different facts into one silent drop:

1. lane has a **TERMINAL row** → not active (founder rule) → drop
2. **queued/reserved ledger row with no arm** → backlog (89217a1) → drop
3. reservation **state outside the known vocabulary** (`aborted`, junk) or **past TTL** → stale/foreign → drop
4. **no usable signal at all** → *unclassifiable* → **must render, never drop**

The mission is explicit: "'Not active' … does NOT mean 'a lane I failed to classify'. An
unclassifiable lane must render as a lane with unknown fields, never be dropped." Note that case 3
is **not** case 4: a row that says `aborted` has been classified — as not-active. Only a row with no
state signal at all is unknown. This distinction is what keeps `bogus state filtered` green while
still honouring "silence is always wrong".

---

## 3. Changes

### 3.1 `plugins/leadv2/scripts/leadv2-lane-class.py`

**Module constants** (new, top of file):

```python
RES_LIVE_STATES  = ("pending", "confirmed")          # real dispatch-ledger writer values
RES_KNOWN_STATES = RES_LIVE_STATES + ("queued", "reserved")
```

**New LaneFacts fields** — all optional, absent = "this renderer has no such signal", so the lanes
path is untouched:

| field | type | meaning |
|---|---|---|
| `arm` | str | assigned executor; `""` / `"unknown"` = unassigned |
| `res_state` | str | the reservation row's own `state` field |
| `res_age_s` | int/None | `now − created_epoch` |
| `res_ttl` | int/None | renderer's reservation TTL |

**New branches**, inserted *after* every process-liveness branch and *before* the existing
`kind == "worker" and ledger_state in (...)` queued branch. Ordering is the contract: a real process
always wins, and the lanes path never sets `res_state`, so all three branches are inert there.

```python
elif res_state in RES_LIVE_STATES and _arm_assigned and not terminal_token \
        and (res_ttl is None or res_age_s is None or res_age_s <= res_ttl):
    cause, cls = "live(dispatch %s)" % res_state, "live"
elif res_state in RES_LIVE_STATES and res_ttl is not None \
        and res_age_s is not None and res_age_s > res_ttl:
    cause, cls = "expired(%s)" % age_label(res_age_s), "dead"
elif res_state and res_state not in RES_KNOWN_STATES:
    cause, cls = "foreign(state=%s)" % res_state, "dead"
```

with `_arm_assigned = bool(arm) and arm != "unknown"`.

Fall-through when `_arm_assigned` is false lands on the existing `queued` branch — 89217a1's
backlog rule survives untouched.

**Return dict gains two fields**; `cls`, `cause`, `live`, `terminal` keep their exact current
semantics and cause strings (the stated parity contract):

```python
"live_process": bool(_pid_alive_session or _pid_alive_handle or _argv_alive or _close_alive),
"unknown":      cause == "dead(no-signal)" and not res_state and not terminal_token
                and pid in (None, "", 0) and ec in (None, "") and motion_mtime is None,
```

`live_process` exists so the single-lead renderer can honour "a running process is a running lane"
**without** touching the `no_work` / `.outcome` overrides at lines 103–117, which currently demote
even a live pid to `dead`. Changing those overrides would move the lanes path and risk
`test-status-surface.sh`; adding a parallel signal does not. The lanes renderer keeps keying on
`cls` alone.

**`clip_name()`** — drop the separator snap-back, keep the `…` marker:

```python
def clip_name(s, n):
    if len(s) <= n:
        return s
    return s[:n - 1] + "…"
```

### 3.2 `plugins/leadv2/scripts/leadv2-status-surface.sh` (single-lead heredoc only)

- `_project()` gains `arm`, `res_state`, `res_age_s`, `res_ttl` and populates them from the
  reservation row (`e["row"].get("arm")`, `e["row"].get("state")`, `now − e["when"]`, `ttl`). Path (a)
  passes the same fields from `res_entry` when one exists, `""`/`None` otherwise.
- Both worker loops replace `if not lc["live"]: continue` with the explicit four-way:

```python
if lc["terminal"]:            continue           # founder rule: no terminal lanes anywhere
if lc["cls"] == "queued":     continue           # backlog, no arm
if lc["cls"] == "dead" and not lc["unknown"]:
                              continue           # expired / foreign / classified-dead
if not (lc["live"] or lc["live_process"] or lc["unknown"]):
                              continue
w["unknown"] = lc["unknown"]
```

- Unknown lanes render with explicit unknown fields, never silently:
  `join_fields([clip_name(name, 24), "unknown", join_fields([arm or "?", age], " "), repo])`
- The zero-lane case keeps exactly one plain line (`нет активных lane`) — already correct, do not
  regress it.
- `warnings` stays removed / stderr-only under `LEADV2_STATUS_DEBUG=1`; `unverifiable_repos` keeps
  suppressing those repos' rows. That is the founder's "no `terminals unreadable` rows at all".

### 3.3 `tests/test-status-surface-parity.sh` (to-create)

A `python3` harness that `exec()`s `leadv2-lane-class.py` once, then for each shape builds **both**
the lanes-path LaneFacts and the single-lead LaneFacts and asserts `classify()` returns the same
`cls` and `terminal` for both. Shapes (10 required, these are the mission's):

| # | shape | expected `cls` |
|---|---|---|
| 1 | live worker **with** pid | `live` |
| 2 | live worker **without** pid (reservation `confirmed`, in TTL, arm set) | `live` |
| 3 | terminal `landed` | `done` |
| 4 | terminal `dead` | `dead` |
| 5 | terminal `no_work` | `dead`, cause `no-work(...)` |
| 6 | ledger-only `queued`, no arm | `queued` |
| 7 | `reserved`, no arm | `queued` |
| 8 | unreadable repo ledger (no facts at all) | `unknown == True`, not dropped |
| 9 | missing `model`/`arm` field on an otherwise live row | `queued` (no arm ⇒ backlog) |
| 10 | name longer than the column | `clip_name` ends in `…`, `len == n` |
| 11 | reservation state `aborted` | `dead`, cause `foreign(state=aborted)` |
| 12 | reservation past TTL | `dead`, cause `expired(...)` |

Style: mirror `tests/test-status-surface-fast-names.sh` (same `ok`/`bad` helpers, same
`suite: N passed, M failed` trailer) so the runner picks it up unchanged.

### 3.4 `tests/test-status-surface-single-lead.sh` — three deliberate expectation changes

Each is a behaviour change the founder ordered, not a failing case being deleted. One-line
justification each, to be repeated in the report:

- **(T-term-2)** was `idle title + 'M1A-FACT-QUALITY-01 · terminal' detail`. Becomes `idle title +
  no trace of the lane` (identical to T-term-1). *Justification: the founder requires no terminal
  lanes in the title or the body; a "closing" detail row is a terminal lane in the body.*
- **(d)** same change, same justification.
- **(T-unverifiable)** was `no REPO-C lane AND '⚠ repo-c terminals unreadable'`. Becomes `no REPO-C
  lane` only. *Justification: the founder requires no `terminals unreadable` rows at all; the
  suppression it asserted still holds and is still asserted.*
- **(f)** expectation moves from `FEED-SCAN-USABLE-CAN` to the 20-char `…`-marked form.
  *Justification: truncation is now marked, so a rendered name ending in a letter or digit is always
  a complete task id.*

Every other failing case must go green **without** touching the test.

---

## 4. Data flow (single-lead, after the fix)

1. `census_workers(PS_SNAPSHOT)` ∪ `codex_census(...)` → live process map, supervise sentinel removed.
2. `res_entries` ← dispatch reservation ledger rows across `SOURCES` (repos with unreadable
   terminals contribute nothing, silently).
3. For each candidate: `_terminal_hit(repo, sig8, name, lane_label)` → terminal token or `None`.
4. `_project(...)` → LaneFacts (process signals **+** the four new reservation signals).
5. `classify(facts)` → `{cls, cause, live, live_process, terminal, unknown}`.
6. Renderer disposition (§3.2): terminal → drop; queued → drop; classified-dead → drop; live or
   live_process → render; unknown → render with unknown fields.
7. Title = `active <N> <clip_name(name,20)> <arm> <age>`; N = 0 → one plain line.

---

## 5. Risks

| risk | mitigation |
|---|---|
| The new branches leak into the lanes path and move `test-status-surface.sh` / `-bash32` | The lanes path never sets `res_state`/`arm` in its LaneFacts, so all three branches are unreachable there. Run all four existing suites, not just single-lead. |
| Re-showing dead lanes — the founder's *original* complaint returning | Terminal, expired and foreign rows each get their own dropping branch **before** `unknown` can fire. Only a row with literally no signal reaches `unknown`. Parity shapes 11 and 12 pin this. |
| `no_work` / `.outcome` overrides demote a genuinely live process to `dead` | Not fixed in `classify()` (would move the lanes path). `live_process` lets the single-lead renderer ignore the demotion. Parity shape 1+5 combined documents the divergence. |
| `unknown` fires more broadly than intended and floods the panel | `unknown` requires *simultaneously*: no pid, no exit code, no motion, no res_state, no terminal token, and cause exactly `dead(no-signal)`. |
| `exec(open(LEADV2_LANE_CLASS_PY))` fails at runtime → silent zero | Already handled: lanes path re-`raise`s to the warn route, single-lead calls `fail(...)`. Keep both. |
| `leadv2-lane-class.py` is untracked | It must be `git add`-ed with the change or the merge ships a script that `exec()`s a missing file. Call this out at handoff. |

## 6. Constraint checklist

1. **Env vars** — `LEADV2_LANE_CLASS_PY`, `LEADV2_STATUS_DEBUG`, `LEADV2_SS_*`, `LEADV2_STATUS_PS_SNAPSHOT`: all `LEADV2_*`. No `LEAD_V2_*` drift. Neither new var needs a `.claude/settings.json` entry — both are set by the script itself or by the test harness.
2. **Paths** — all four write paths verified on disk except `tests/test-status-surface-parity.sh` **(to-create)**.
3. **`claude -p`** — none introduced. N/A.
4. **Concurrent access** — none; the surface is read-only rendering, no shared writes.
5. **Config contradiction** — `RES_LIVE_STATES = ("pending","confirmed")` must match the dispatch-ledger writers. The test comment at `tests/test-status-surface-single-lead.sh:120` states it directly: "Real writer values are ONLY 'pending'/'confirmed'". Consistent.

---

## 7. Non-goals

- Do **not** run `run-core-offline.sh`. Its failures are the codex quota lockout (until 2026-08-08) and will mislead.
- Do **not** fix `product_close ... author=codex` or the missing `review-sonnet.md` — environment, not code.
- Do **not** change the lanes-path branch chain, its cause strings, or `#LIVE/#DEAD/#DONE_RECENT/#QUEUED` header arithmetic.
- Do **not** touch the multi-project aggregation, quota rows, questions, or the `Refresh` footer.
- Do **not** delete any test case.
- **No commit, no push.** The lead merges.

---

acceptance:
- surface: rendered_line
  observable: With one dispatched lane in the reservation ledger and no matching OS process, the SwiftBar menu-bar title reads `🛠 abcdef12 codex 2m` instead of `⚪ idle`, and the dropdown shows that lane's row.
  authored_at: 2026-08-05T00:00:00Z
- surface: rendered_line
  observable: With only a terminal (`landed`/`dead`/`no_work`) row present, the title reads `⚪ idle` and the dropdown shows exactly one plain line `нет активных lane` — no lane row, and no `terminals unreadable` row anywhere in the panel.
  authored_at: 2026-08-05T00:00:00Z
- surface: rendered_line
  observable: A ledger row that cannot be classified renders as a dropdown lane row whose fields read `unknown` — the panel never omits it.
  authored_at: 2026-08-05T00:00:00Z
- surface: log_line
  observable: The suite trailers read `test-status-surface-single-lead: 23 passed, 0 failed`, `test-status-surface-bash32: 15 passed, 0 failed`, `test-status-surface-fast-names: 12 passed, 0 failed`, and `test-status-surface-parity: 12 passed, 0 failed`.
  authored_at: 2026-08-05T00:00:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-class.py, plugins/leadv2/scripts/leadv2-status-surface.sh, tests/test-status-surface-parity.sh, tests/test-status-surface-single-lead.sh

DELIVERABLE_COMPLETE
