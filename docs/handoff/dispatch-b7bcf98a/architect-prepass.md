# Architect prepass — CORE-OFFLINE-RED-ON-MAIN-01

Design only. No implementation performed. All findings below were read from the tree at
`main` (6fa4823) plus a live reproduction of the failing case.

---

## 0. Verdict up front

**The renderer side is broken, not the test fixture.** The counter *is* computed
correctly and *is* rendered — but into `founder-status-full.md`, not into
`founder-status.md`, which is the artifact the founder actually reads (RELAY=full pastes
`founder-status.md` verbatim). The test asserts on the founder-facing artifact and is
right to.

**Mission item 3 (untrack committed lock/state fixtures) is already done on main.** See §5.
Designing against the code, not the mission's framing.

### Reproduction (live, not inferred)

`bash plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh` on the current tree:

```
PASS: (a) park row written before sonnet fallback worker spawn (ordering holds)
PASS: (a) poison fence held
PASS: (b) glm-deferred --list prints the parked sig8
PASS: (b) glm-deferred --list prints 'no deferred glm tasks' when empty
PASS: (c) two credit-empty computations within 24h emit exactly ONE journal line
PASS: (c) a third computation after the stamp ages past 24h emits a second journal line
FAIL: (d) expected sonnet-fallback line missing from rendered artifact -- content=2026-08-20T00:00:00Z [BROAD_STATUS] dispatched=1
⚠ ДОСКА ПУСТА — ничего не выполняется, 0 мин
04:14 · посты н/д · комменты н/д · реплаи н/д
| Линия | Что делает | Состояние |
|---|---|---|
| (живых линий нет) | — | — |
С прошлого удара: +0 линии подняты, 0 закрыто.
Решений не ждёт.
(скрыто: 6 строк очереди — docs/leadv2/founder-status-full.md)
[BROAD_STATUS_END]
PASS: (d) a day with no fallback renders no sonnet-fallback line
PASS: (e) shared-cache double refusal: count=2, both distinct sig8s recorded
... (e2)(g)(h)(i)(f) all PASS ...
  glm-deferred-ladder suite: FAIL=1
```

Instrumented the harness (temp copy, since deleted) to dump state at the moment case (d)
renders:

```
DBG exc: count=1
last_reason=glm_refused_quota_gate
sig8=38131d44
DBG today=20260823
DBG-FULL: 11:sonnet-фолбэков сегодня: 1 (glm_refused_quota_gate)
DBG-FULLEXISTS: founder-status-full.md
```

So: the sidecar file is correct, the count is correct, the reason string is correct, and
the exact asserted line **is rendered — at line 11 of `founder-status-full.md`**. The
short artifact the test greps contains only `(скрыто: 6 строк очереди …)`.

Note that `(скрыто: 6 строк очереди)` is itself a second, quieter defect: the health line
is being *counted as queue content* in the hidden-lines tally.

---

## 1. CALLERS / CALLEES — the whole mechanism

### 1a. Producer side (`leadv2-dispatch-code.sh`)

| Site | file:line | Role |
|---|---|---|
| `_leadv2_arm_exceptions_path()` | `plugins/leadv2/scripts/leadv2-dispatch-code.sh:877` | Builds `${PROJECT_ROOT}/docs/leadv2/.arm-exceptions-<YYYYMMDD>` |
| `_arm_exception_bump()` | `plugins/leadv2/scripts/leadv2-dispatch-code.sh:1199` | Read-modify-write of `count=` / `last_reason=` / `sig8=` lines under fd-8 sidecar lock |
| sole caller of the bump | `plugins/leadv2/scripts/leadv2-dispatch-code.sh:5135` | `[[ -n "${_exc_reason}" ]] && { _arm_exception_bump "${_exc_reason}" "${sig8}" \|\| true; }` |
| `_glm_park_deferred()` | `plugins/leadv2/scripts/leadv2-dispatch-code.sh:~881` | Sibling writer of `glm-deferred.jsonl` (also read by the renderer) |
| `_leadv2_codex_credits_stamp_path()` | `plugins/leadv2/scripts/leadv2-dispatch-code.sh:879` | Sibling writer of `.codex-credits-empty.stamp` (also read by the renderer) |

`_arm_exception_bump` has exactly one caller (line 5135). There is no second/independent
copy of the writer — grep for `arm-exceptions` across `plugins/leadv2/scripts/`
(excluding `tests/`) returns exactly two hits: the writer at `leadv2-dispatch-code.sh:877`
and the reader at `leadv2-broad-status.sh:626`.

### 1b. Consumer side (`leadv2-broad-status.sh`, current working tree line numbers)

| Step | file:line | What it does |
|---|---|---|
| read `.arm-exceptions-<today>` | `leadv2-broad-status.sh:622-638` | Sets `sonnet_fallbacks_today`, `sonnet_fallback_last_reason` |
| read `.codex-credits-empty.stamp` | `:640-649` | Sets `codex_credits_empty_since` |
| read `glm-deferred.jsonl` | `:651-679` | Sets `glm_deferred_count` |
| build `_provider_health_lines` | `:681-690` | Up to 3 lines |
| **fold into `queue_md`** | **`:691-692`** | ⬅ **THE DEFECT** |
| `full_md = "\n\n".join([full_table_md, detail_md, queue_md, …])` | `:772-777` | `queue_md` goes to `founder-status-full.md` only |
| `_queue_line_count = len(queue_md.splitlines())` | `:790` | Health lines get counted as "строк очереди" |
| `render.json` payload | `:809-822` | Keys: `table_md, detail_md, closed_paragraph, queue_md, rows, tail_facts, product_line, delta_line, decisions_line, hidden_note, empty_headline`. **No provider-health key.** |
| bash reads render.json | `:842-848` | Reads `table_md, rows, product_line, delta_line, decisions_line, hidden_note, empty_headline`. **`queue_md` is never read back into bash.** |
| `BLOCK=$(…)` — the short artifact | `:873-887` | stamp / empty_headline / product_line / table_md / delta_line / decisions_line / hidden_note / `[BROAD_STATUS_END]` |
| write `founder-status.md` | `:890` | `printf … > "$FOUNDER_STATUS_PATH.tmp" && mv …` |

**Callers of the composer itself** (the "independent copy nobody named" check):

- `plugins/leadv2/scripts/leadv2-pulse-beat.sh:40` — `BROAD_STATUS_SH="${LEADV2_BROAD_STATUS_BIN:-${SCRIPT_DIR}/leadv2-broad-status.sh}"`. This is the real clock-driven beat path; it drives the *same* composer, no second renderer.
- `plugins/leadv2/hooks/leadv2-single-lead-beat.sh:18` — explicitly documented as *not* invoking the composer ("never touches leadv2-broad-status.sh"), it only re-emits the stamp. **This is the near-miss to be aware of: it produces founder-facing pulse text without going through the composer, so it will never carry a provider-health line. Out of scope here (see §6).**
- `plugins/leadv2/scripts/leadv2-lane-detail.sh`, `plugins/leadv2/scripts/lib/leadv2_lane_naming.py` — reference the composer in comments/paths only.

**Second writer of `founder-status.md` inside the composer**: `_write_degraded_status()` at
`leadv2-broad-status.sh:117-132`. It replaces the artifact with a canned degraded block
and **emits no provider-health content at all**. Called from the collector-failure path and
from the render-failure path (`:834`). This is a genuine independent copy of the artifact
writer and it is on the founder-visible path.

### 1c. Tests that read `founder-status.md` (blast radius of adding a line)

`test-broad-status-lanes-blind.sh` (untracked, another session),
`test-broad-status-renderer-truth.sh`, `test-pulse-empty-board.sh`,
`test-pulse-readable-rendering.sh`, `test-broad-status-relay-scope.sh`,
`test-glm-deferred-ladder.sh`, `test-broad-status-duty.sh`, `test-single-lead-beat.sh`.

**Hard constraint discovered:** `test-pulse-readable-rendering.sh:147-154` asserts the whole
compact beat is **≤14 lines**. Any design that unconditionally adds up to 3 lines to
`founder-status.md` risks tripping that gate. See D2.

---

## 2. STATES AND RETURN CODES

### 2a. Sidecar-file states → rendered outcome → user-visible consequence

`root` = `LEADV2_PROJECT_ROOT` (or resolved project root); file =
`<root>/docs/leadv2/.arm-exceptions-<UTC-today>`.

| State | Renderer branch | `sonnet_fallbacks_today` | Line emitted today | Line emitted after fix | Founder sees |
|---|---|---|---|---|---|
| file absent | `os.path.isfile` false, `:625` | 0 | none | none | nothing (correct) |
| file exists, `count=0` | `:632` | 0 | none | none | nothing (correct) |
| file exists, `count=N>0` | `:632` | N | **into `founder-status-full.md` only** | into `founder-status.md` | **today: nothing. This is the bug.** |
| `count=` non-integer | `ValueError` → `:635` | 0 | none | none | nothing — a corrupt sidecar silently under-reports |
| file is a directory | `isfile` false | 0 | none | none | nothing |
| file unreadable (perm) | `OSError` → `:638` | 0 | none | none | nothing |
| `last_reason=` absent, `count>0` | `:683` `or 'glm quota'` | N | `… (glm quota)` | same | generic reason, still loud |

### 2b. Return codes along the path

| rc source | file:line | Value | Caller behaviour | Terminal user-visible consequence |
|---|---|---|---|---|
| `_arm_exception_bump` | `:5135` | any | `\|\| true` — swallowed | A failed bump is invisible; the beat under-reports fallbacks by one. Never aborts a dispatch (by design, R8). |
| python render step `$RC` | `leadv2-broad-status.sh:829-840` | ≠0 | `_write_degraded_status` then `_emit_ready_line "-" degraded` | Founder gets "СТАТУС НЕ СОБРАН" — **and no provider-health line even if fallbacks happened**. |
| `_write_degraded_status` | `:117` | 0 = replaced | rc≠0 → `_emit_fail_line` | rc≠0: no READY, no relay at all — founder gets silence for that beat. |
| composer overall | `:890` `printf … && mv … && _stamp_epoch` | — | `_emit_ready_line "$ROWS_N"` | Normal beat: relay fires, founder pastes `founder-status.md`. |
| test-suite `fail()` | `test-glm-deferred-ladder.sh:34` | sets `FAIL=1` | file exits non-zero → `run-core-offline.sh` marks suite FAILED | **Every lane whose changed-scope e2e gate runs core-offline closes `status: fail / reason: e2e_regression`.** That is today's board-wide block. |

The rc chain is the important one: `_arm_exception_bump`'s `|| true` means there is **no
retry and no alarm** on a failed bump — the loop that would have surfaced it does not
exist. In plain words: if the sidecar write ever fails, no one is told that a day's worth
of sonnet fallbacks went uncounted.

---

## 3. CONFIGURATION BOUNDARIES

Every input the mechanism reads, at each boundary.

### 3.1 `<root>/docs/leadv2/.arm-exceptions-<YYYYMMDD>`

| Boundary | Behaviour | Assessment |
|---|---|---|
| absent | count 0, no line | correct |
| empty file | loop reads nothing → 0 | correct |
| minimum (`count=1`) | line rendered | correct after fix |
| over-cap (`count=99999999999`) | rendered verbatim; no digit cap | harmless — one long-ish token, cannot break the block |
| malformed (`count=abc`) | `ValueError` caught `:634-635` → 0 | **silent under-report**, but contained to this one counter |
| binary / non-UTF-8 | `open(..., encoding="utf-8")` raises `UnicodeDecodeError`, which is **NOT an `OSError`** — the `except OSError` at `:638` does not catch it → **traceback → render rc≠0 → whole beat degrades** | ⚠ **Defect, not a safety feature.** A corrupt one-line sidecar takes down the entire status beat. Must be widened to `except Exception` (D4). |
| `last_reason=` extremely long | rendered inline into `founder-status.md` after the fix | bound it (D3) |
| `last_reason` containing `[BROAD_STATUS_END]` | would terminate the relay block early | see §4 |
| UTC-midnight rollover between bump and beat | writer used day X, renderer reads day X+1 | counter reads 0 for the first beat after midnight; the day's fallbacks are never shown. Pre-existing, out of scope (§6). |

### 3.2 `<root>/docs/leadv2/.codex-credits-empty.stamp` (`:640-649`)

absent → `None`, no line. Empty → `readline()` returns `""`, no `since=` prefix → `None`.
Malformed first line → `None`. Non-UTF-8 → same `UnicodeDecodeError` escape as 3.1.
Over-long `since=` value → rendered verbatim. Same D3/D4 treatment.

### 3.3 `<root>/docs/leadv2/glm-deferred.jsonl` (`:651-679`)

absent → 0. Empty → 0. Malformed JSON line → `continue` (`:667-668`), robust. `_truncated`
marker rows skipped. Over-cap handled upstream by the writer's 500-row / 7-day trim
(`leadv2-dispatch-code.sh`, R1). Non-UTF-8 → same `UnicodeDecodeError` escape. Note this
read is **unlocked** while `_glm_park_deferred` writes under `${path}.lock` — a torn read
yields a bad JSON line, which is skipped, so the count can be off by one during a
concurrent park. Acceptable; naming it for the record.

### 3.4 Env inputs

| Var | absent | empty | notes |
|---|---|---|---|
| `LEADV2_PROJECT_ROOT` | falls back to resolved project root | same | determines which sidecar is read — see §4 |
| `LEADV2_BROAD_STATUS_BEAT_AT` | `_now_iso()` | same | **only stamps line 1; the counter's day comes from `datetime.now(utc)`, not from this var** (`:624`). A test that pins `BEAT_AT` to a past date still reads today's sidecar. Confirmed live: `DBG today=20260823` while `BEAT_AT=2026-08-20T00:00:00Z`. |
| `LEADV2_BROAD_STATUS_DISPATCHED` | `unavailable` | same | line-1 field only |
| `LEADV2_FOUNDER_STATUS_FULL_PATH` | defaults `:44` | — | full-doc override |

---

## 4. COUNTEREXAMPLE — what still violates the invariant after every finding is fixed

The invariant this mechanism exists to protect: *a provider degradation the founder is
relying on cannot happen silently — it must appear in the artifact the founder actually
reads.* After the fix below, four things still break it, and I checked each in the tree:

1. **The degraded path has no health line.** `_write_degraded_status()`
   (`leadv2-broad-status.sh:117-132`) replaces `founder-status.md` with a canned block that
   contains no provider-health content, and it is exactly the path taken when the collector
   or the renderer fails. So on any beat where the status collector is down, a day of 100%
   sonnet fallbacks is invisible — the same class of silence the V3-GLM-LADDER-01 incident
   was about.
2. **The counter is keyed to `PROJECT_ROOT`, and lanes have a different one.**
   `_leadv2_arm_exceptions_path` (`leadv2-dispatch-code.sh:877`) interpolates `PROJECT_ROOT`,
   which resolves from a pinned root or the **cwd git root**
   (`leadv2-dispatch-code.sh:373-384`). A dispatch executed inside a lane worktree therefore
   bumps `<worktree>/docs/leadv2/.arm-exceptions-…`, while the beat reads the main
   checkout's. Those fallbacks are counted into a file no beat ever opens.
3. **UTC-midnight rollover.** The writer's day and the renderer's day are computed
   independently (`date -u +%Y%m%d` vs `datetime.now(utc)`), so the first beat after
   00:00 UTC reports 0 regardless of the preceding day's refusals.
4. **`RELAY=none`.** In that relay mode the lead is instructed to relay only the single
   ready line — the health line, wherever it sits in the artifact, never reaches the
   founder.

Additionally, a `last_reason` value is written from `LAST_ARM_OUTCOME` and rendered
verbatim into the relay block; a value containing `[BROAD_STATUS_END]` would truncate the
block. `LAST_ARM_OUTCOME` is an internal enum today, so this is latent rather than live —
D3 closes it anyway because it costs one line.

Items 1–4 are named, not fixed, by this design. They are §6 out-of-scope; item 1 is the
one I would open a follow-up on first.

---

## 5. Mission item 3 is already done — evidence

The mission asks to `git rm --cached` eight lock/state fixtures added by `4077109`. They
are **already untracked on `main` (6fa4823)**:

```
$ git ls-files | grep 'tests/docs\|tests/.claude'
rc=1                     # no output
$ git ls-tree -r --name-only HEAD | grep 'tests/docs\|tests/\.claude'
rc2=1                    # no output
```

And `.gitignore` already carries the rules, with the matching rationale comment:

```
# PROJECT_ROOT-leak residue from an unisolated dispatch run under tests/ (L5 fix,
# V3-GLM-LADDER-01 R3) -- must never be tracked, or the leak becomes invisible.
plugins/leadv2/scripts/tests/docs/
plugins/leadv2/scripts/tests/.claude/
```

Design against the code: **item 3 is a no-op; the implementer must not spend a step on it,
and must not "re-fix" it.** Verification #3 (`git status --porcelain` clean after a suite
run) already holds — a full run of the ladder suite left the working tree byte-identical
(the suite roots under `mktemp -d`, and the parallel session's pre-existing modifications
to `leadv2-broad-status.sh` / `leadv2-review-run.sh` were unchanged by the run).

---

## 6. THE CHANGE

One file. One mechanism: **promote the provider-health block from a `queue_md` suffix
(full doc only) to a first-class render.json field emitted into the compact beat.**

### D1 — separate `_provider_health_lines` from `queue_md`

`leadv2-broad-status.sh:691-692` — delete the `queue_md = queue_md + …` fold. Build
`provider_health_md` instead. Append it to `full_md` (`:772-777`) as its own joined
section so the full doc keeps the information. This also repairs `_queue_line_count`
(`:790`) so `(скрыто: N строк очереди)` stops counting health lines as queue rows.

### D2 — one line, not three (protects the 14-line gate)

`test-pulse-readable-rendering.sh:147-154` caps the compact beat at 14 lines. Emit the
health block as **exactly one line**, joining the (≤3) health facts with `" · "` — the same
separator `product_line` already uses (`:753`). This is deterministically ≤1 added line, so
the cap cannot be tripped by a triple degradation.

The asserted substring `sonnet-фолбэков сегодня: 1 (glm_refused_quota_gate)` survives
joining unchanged, so case (d)'s positive assertion passes and its negative assertion
(no line when zero fallbacks) is unaffected — with zero health facts, `provider_health_md`
is empty and nothing is printed. Neither assertion is weakened; the test file is not
touched.

### D3 — bound the interpolated free-text values

`last_reason` and `since=` are rendered into a relay block. Truncate each to 80 chars and
strip control characters / any `[BROAD_STATUS` substring before interpolation. One-line
guard; closes §4's latent block-truncation.

### D4 — widen `except OSError` to `except Exception`

At `:638`, `:649`, `:679`. A non-UTF-8 sidecar currently raises `UnicodeDecodeError`,
which is not an `OSError`, and takes the **entire beat** down to the degraded path. An
over-cap or malformed input that takes down more than the operation it belongs to is a
defect. Each of the three reads must degrade to its own zero/absent case only.

### D5 — placement in the compact beat

Insert after `PRODUCT_LINE`, before `TABLE_MD`, in the `BLOCK=$(…)` subshell
(`:873-887`):

```
line 1: <BEAT_AT> [BROAD_STATUS] dispatched=<N>     # relay contract — unchanged
line 2: <EMPTY_HEADLINE>                            # when set — unchanged
line 3: <PRODUCT_LINE>
line 4: <PROVIDER_HEALTH_LINE>                      # NEW, only when non-empty
        <TABLE_MD> …
```

Line 1 stays the machine-parseable stamp (relay contract). The empty-board headline keeps
its position ahead of everything else. Health reads near the top, above the table.

Requires: add `"provider_health_md"` to the `render.json` payload (`:809-822`) and a
matching `PROVIDER_HEALTH_LINE="$(python3 -c … .get('provider_health_md') or '')"` read
alongside the existing seven (`:842-848`).

### Exact edit sites

| # | file:line (working tree) | Change |
|---|---|---|
| D1a | `leadv2-broad-status.sh:691-692` | Replace `queue_md +=` fold with `provider_health_md = " · ".join(_provider_health_lines)` |
| D1b | `:772-777` | Add `provider_health_md` as its own `full_md` section when non-empty |
| D3 | `:681-690` | Sanitise/truncate `sonnet_fallback_last_reason` and `codex_credits_empty_since` before f-string interpolation |
| D4 | `:638`, `:649`, `:679` | `except OSError:` → `except Exception:` |
| D5a | `:809-822` | Add `"provider_health_md": provider_health_md` to the render.json dict |
| D5b | `:842-848` | Add the `PROVIDER_HEALTH_LINE` read |
| D5c | `:873-887` | Emit `PROVIDER_HEALTH_LINE` after `PRODUCT_LINE` when non-empty |

### Implementation hazards

- **The working tree already has an uncommitted diff in this exact file** (another
  session's `LANE-DETAIL-BLIND-01` work, 47 insertions at `:192-215`, `:453-464`,
  `:483-500`). The mission forbids `stash`/`reset`/`clean`. **All edits must be additive
  against the working-tree file, and `git diff plugins/leadv2/scripts/leadv2-broad-status.sh`
  must be re-read immediately before staging** — the line numbers above are working-tree
  numbers, not HEAD numbers (HEAD's counter block is at `:577-659`).
- `leadv2-broad-status.sh` is a canonical plugin `.sh`. With `LEADV2_LEAD_GUARD=1` the Edit
  tool is blocked on it; the implementer may need the `/tmp` python-patcher + Bash route.
- After the edit, `bash -n plugins/leadv2/scripts/leadv2-broad-status.sh` must pass — the
  ladder suite hard-aborts on a syntax check of this file at
  `test-glm-deferred-ladder.sh:39-41`.

### Regression tests to re-run (no new test authored — case (d) already is the test)

1. `test-glm-deferred-ladder.sh` — all cases, incl. the negative.
2. `test-pulse-readable-rendering.sh` — the ≤14-line cap (T3).
3. `test-broad-status-renderer-truth.sh`, `test-pulse-empty-board.sh`,
   `test-broad-status-relay-scope.sh`, `test-broad-status-duty.sh`,
   `test-single-lead-beat.sh` — the other `founder-status.md` readers.
4. `run-core-offline.sh` — must exit 0.

---

## 7. NON-GOALS — explicitly out of scope

- **Do not revert `389820a`** (mission). Do not revert `4077109` either — its
  `.gitignore` hunk is the fix that already landed item 3.
- **Do not touch `test-glm-deferred-ladder.sh`.** No skip, no weakened assertion, no
  deleted case. The test is correct.
- **Do not touch the e2e gate** in `leadv2-dispatch-product-close.sh`.
- **Do not `git rm --cached` anything** — §5, already done.
- **Do not touch the parallel session's uncommitted hunks** in
  `leadv2-broad-status.sh` / `leadv2-review-run.sh`, or the untracked
  `ZZ-pre-review-run.sh`, `test-broad-status-lanes-blind.sh`,
  `test-review-fanout-visibility.sh`.
- **Do not fix §4 counterexamples 1–4 here** — the degraded-path blind spot, the
  worktree `PROJECT_ROOT` split-brain, the UTC-midnight rollover, and `RELAY=none`. Each is
  a separate mechanism; folding them in would turn a board-unblocking fix into a redesign.
  Follow-ups, named in §4, item 1 first.
- No change to `leadv2-dispatch-code.sh`. The producer is correct — proven by case (e)
  passing with `count=2` and by the live `DBG exc: count=1` dump.

---

## 8. Acceptance

```yaml
acceptance:
  - surface: file_artifact
    observable: >
      docs/leadv2/founder-status.md — on a day when at least one glm→sonnet
      quota fallback happened, the founder reading the pulse artifact sees the
      Russian sentence naming how many sonnet fallbacks happened today and why,
      sitting between the "посты · комменты · реплаи" line and the lane table.
      Today that sentence appears nowhere in that file; it is buried in
      founder-status-full.md, which the founder is never shown.
    authored_at: 2026-08-23T04:22:00Z
  - surface: file_artifact
    observable: >
      docs/leadv2/founder-status.md — on a day with no fallbacks, no codex
      credit outage and no deferred GLM tasks, that sentence is absent
      entirely; the founder sees no provider-health text at all, and the beat
      is no longer than it is today.
    authored_at: 2026-08-23T04:22:00Z
  - surface: rendered_line
    observable: >
      The parenthetical hidden-content note at the bottom of the pulse no
      longer counts the provider-health sentence among the "строк очереди" it
      claims are hidden — the number it reports matches the number of queue
      rows actually withheld.
    authored_at: 2026-08-23T04:22:00Z
  - surface: log_line
    observable: >
      A run of the core-offline suite reports every case of the deferred-GLM
      ladder as passing and ends with a zero failure count, so a lane touching
      plugin scripts no longer closes with a failed end-to-end gate.
    authored_at: 2026-08-23T04:22:00Z
  - surface: file_artifact
    observable: >
      After a full suite run, the repository shows exactly the same set of
      changed and untracked files it showed before the run — the run leaves
      nothing behind.
    authored_at: 2026-08-23T04:22:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-broad-status.sh

DELIVERABLE_COMPLETE
