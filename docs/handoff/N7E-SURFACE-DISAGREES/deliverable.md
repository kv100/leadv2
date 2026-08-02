# N7E-SURFACE-DISAGREES — architect prepass

Repo: `~/Projects/leadv2` (canonical plugin). Base `f0ed7bb`. Design only — no implementation.

---

## 0. What was verified on disk (evidence, not memory)

| Fact | Evidence |
|---|---|
| The bar's codex row is computed from live quota, never from the lockout file | `leadv2-limits-refresh.sh:177-209` `_refresh_codex()` → `leadv2-quota-live.sh --no-cache codex` → `windows[0].limit_reached` |
| The env knob for the lockout file exists but is dead | `leadv2-limits-refresh.sh:22-23` — `LEADV2_STATUS_CODEX_LOCKOUT ... (unused now that codex reads leadv2-quota-live.sh)` |
| The enforcing gate reads a different file | `codex-task.sh:98` `_CODEX_LOCKOUT_FILE="$HOME/.claude/cache/codex-lockout.state"`; parsed at `codex-task.sh:271-286`, `exit 2` + `LEADV2_DISPATCH_REFUSED: quota_gate` |
| The router turns that into the founder-visible refusal | `leadv2-dispatch-code.sh:1568-1570` `arm_refused by=router model=codex ... reason=codex_refused_${refusal}` |
| The available-branch string stamps *now*, not an expiry | `leadv2-limits-refresh.sh:203` `доступен (lockout истёк $(date -u ...))` — the timestamp is the refresh instant; it is meaningless as an expiry |
| Sentinel writers | only `leadv2-supervise.sh:163` (+ read at `leadv2-lane-status-line.sh:142`) |
| The resume path is contractually write-free | `leadv2-supervise-resume.sh:1-32` — *"NO new state file … zero writes"*; `leadv2-supervise.sh --print` **execs straight into it, explicitly bypassing sentinel writes** (`:10-12`) |
| A read-only guarantee is already bonded by a test | `plugins/leadv2/tests/test-supervise-sentinel-readonly.sh` |
| Heartbeat is already the primary signal | `leadv2-status-surface.sh:252-257, 334-347` — beat mtime, TTL 300s |

**Root cause, both defects, one shape:** a surface computes a fact from a source *adjacent to* the
one that enforces it. Defect 1 = wrong source (live quota instead of the lockout memory). Defect 2 =
right source, but the surface additionally reports a *second* signal (`.supervise-active`) whose
writer does not run on the path the founder is actually on, and names its absence as if it were a
finding.

---

## 1. Defect 1 — design

### 1a. New shared reader: `plugins/leadv2/scripts/leadv2-codex-lockout.sh` (to-create)

Single-purpose, no deps, bash 3.2, `set -euo pipefail`.

| Item | Contract |
|---|---|
| File read | `${LEADV2_STATUS_CODEX_LOCKOUT:-$HOME/.claude/cache/codex-lockout.state}` — the env override is **resurrected**, not invented (it is already documented at `leadv2-limits-refresh.sh:22`) |
| Parse | byte-identical to `codex-task.sh:274-284`: `grep -E 'CODEX_JOB_FAILED_QUOTA until=' \| tail -1 \| sed -n 's/.*until=\([0-9T:+Z-]*\).*/\1/p'`, then `_u="${_until%%.*}"; _u="${_u%Z}Z"` |
| Clock compare | `date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$_u" +%s` (BSD), falling back to `date -u -d` (GNU); `-gt 0 && -gt now` — same predicate as the gate |
| stdout, locked | `locked <until_iso>` |
| stdout, clear | `clear` |
| stdout, file absent / unparsable / expired | `clear` (fail-open — identical to the gate, which only refuses on a parsed future timestamp) |
| exit | always `0`; a non-zero would make a detached refresher lose the row |

Rationale for a new file rather than editing the gate: `codex-task.sh` is off-limits this lane.
The duplication is therefore unavoidable — it is made *safe* by the agreement test in §3, which
drives the real `codex-task.sh` and this helper against the same fixture and asserts they never
disagree. That test, not a comment, is the anti-drift bond.

### 1b. `leadv2-limits-refresh.sh` — `_refresh_codex()` rewrite

New precedence (lockout first — it refuses unconditionally, so it dominates any live-quota reading):

```
_refresh_codex():
  lk = leadv2-codex-lockout.sh          # check 0, offline, no network
  if lk == "locked <until>":
      _write_kv codex ok "lockout до <until>" ""      # <- same shape as the existing
      return                                          #    limit_reached branch (:200)
  ... existing quota-live path, unchanged ...
  available branch: val="доступен"       # <- drop the fake "(lockout истёк <now>)"
```

- `state=ok` is correct for a locked arm: `ok` means *"we know the answer"*, and
  `unavailable` means *"we could not read"*. A lockout is known. This also means **zero render-side
  change** — `_print_limit_line` (`leadv2-status-surface.sh:2280+`) already prints `ok` values verbatim,
  and `lockout до …` is a string it already renders today for `limit_reached`.
- Resolve the helper via `${LEADV2_CODEX_LOCKOUT_SH:-${SCRIPT_DIR}/leadv2-codex-lockout.sh}`,
  matching the existing `QUOTA_LIVE`/`PROBE` override idiom (`:31-32`) so tests can inject.
- TTL stays 300s (`:53`). Acceptable: the lockout row is offline and cheap, and a ≤5-min lag on a
  multi-day lockout is not the defect being fixed. Do **not** lower it — the same `_refresh_codex`
  still makes the quota-live network call on the clear path.

### 1c. Audit of the other three arms (mission asks for the finding even where unchanged)

| Arm | Surface computes from | Enforcing gate reads | Verdict |
|---|---|---|---|
| **codex** | `leadv2-quota-live.sh codex` | `codex-lockout.state` (`codex-task.sh:98`) | **DISAGREES — this defect.** Fixed above. |
| **glm** | `leadv2-quota-live.sh glm` (`_refresh_glm`) | `leadv2-glm-quota-gate.sh`, which also reads `leadv2-quota-live.sh` — `glm-coder.sh:117,133` refuses on its `REROUTE` at ≥80% | **Same source — but a softer variant of the same disease.** The bar prints the raw percentage; the gate refuses at ≥80%. At 82% the bar shows a number that reads as fine while every dispatch is rerouted. Not a wrong-source bug, so **not changed in this lane**; recorded as a follow-up (§6). |
| **claude** | `leadv2-ratelimit-probe.sh` → `burn/history.db` kv `rate_limit_anthropic` (`:130-142`) | no dispatcher gate — sonnet is the fallback arm, never refused on quota | **Agrees vacuously.** Nothing to fix. |
| **kimi** | hardcoded `"quota API отсутствует (free-tier TokenRouter)"` (`:212`) | `kimi-coder.sh:143-151` — no quota concept; a live `GET /v1/models` probe instead | **Honest today**, but it does not surface the one thing that *can* refuse a kimi dispatch (the launch probe failing). Recorded as a follow-up (§6), not changed. |

---

## 2. Defect 2 — design and the decision

### The decision: **the surface stops reporting a signal it cannot obtain. No sentinel is faked, and no write is added to the resume path.**

Why not "write the sentinel on resume":

1. `leadv2-supervise-resume.sh` declares itself write-free in its own header and is bonded by
   `tests/test-supervise-sentinel-readonly.sh`. Making it write inverts a contract another lane
   depends on.
2. `leadv2-supervise.sh --print` **execs into** resume precisely to skip sentinel writes
   (`leadv2-supervise-resume.sh:10-12`) — that bypass is deliberate, not an oversight.
3. There is no hook on the compact/resume path that could carry the write without inventing one.

Why the surface loses nothing by dropping it: the heartbeat is a *better* signal and is already
primary. `leadv2-supervise-loop.sh` writes `.supervise-loop.heartbeat` from a detached process that
survives a compact/resume of the chat session — so on the exact path the founder reported, the beat
is fresh and true while the sentinel is absent and meaningless. The surface was leading with the
weaker of two signals.

### The rendering contract after the fix

`supervisor:` resolves to exactly one of three words, from the beat alone:

| State | Condition | Reason string |
|---|---|---|
| `ON` | beat age ≤ `SUP_BEAT_TTL` (300s) | `beat <label>` |
| `STALE` | beat exists, age > TTL | `beat <label> old` |
| `OFF` | no beat file at all | `no supervise loop running` |

Sentinel handling changes from *reported* to *corroborating-only*:

- **absent** → contributes nothing. The strings `no sentinel`, `sentinel unparsable, no beat`, and
  the whole canonical-sentinel-absent branch's reason text stop mentioning it
  (`leadv2-status-surface.sh:375-413`).
- **present with a dead pid** → still appended (`, sentinel pid <pid> gone`). This is a real file
  with a real, actionable inconsistency — a true statement, kept.
- **present with a live pid** → still appended (`, pid <pid>`), unchanged from today.
- The legacy-sentinel branch (`:413-437`) is untouched — it fires only when a real file exists.

Net effect on the founder's two reported lines:
`STALE (no sentinel, beat 6h old)` → `STALE (beat 6h old)`;
`ON (heartbeat only, no sentinel)` → `ON (beat 40s)`.
A supervised and an unsupervised session differ by `ON` vs `OFF`, and neither says `no sentinel`.

**Scope guard:** `SUP_PID`, `SUP_SHORT`, `SUP_STATE`, and the sentinel-discovery walk
(`:314-332`) are untouched. Only `SUP_WHY` composition changes.

---

## 3. Tests

### New — `plugins/leadv2/scripts/tests/test-codex-lockout-agreement.sh` (to-create)

The load-bearing one. Per fixture, in a `TMPDIR` sandbox with `HOME` overridden (this is why no
edit to `codex-task.sh` is needed — it resolves its lockout path from `$HOME` at `:98`):

| Fixture | Expected helper | Expected `codex-task.sh task` | Expected `codex.kv` |
|---|---|---|---|
| lockout `until=` in the future | `locked <until>` | `exit 2` + `LEADV2_DISPATCH_REFUSED: quota_gate` | `value=lockout до <until>` |
| lockout `until=` in the past | `clear` | not refused for `reason=lockout` | `value=доступен` |
| file absent | `clear` | not refused | `value=доступен` |
| file present, no matching line | `clear` | not refused | `value=доступен` |
| two lines, newest is the live one | `locked <newest until>` | refused | matches newest |

`CODEX_SKIP_QUOTA_GATE` must be **unset** in this test (`codex-task.sh:265` short-circuits on it).
The kv column is driven with `LEADV2_LIMITS_CACHE_DIR` + `LEADV2_QUOTA_LIVE_SH` pointed at a stub,
so no network is touched.

### New — `plugins/leadv2/scripts/tests/test-supervisor-reason-honest.sh` (to-create)

Asserts, against a sandboxed `LEADV2_STATE_ROOT`: fresh beat + no sentinel → line matches `ON` and
`grep -qv 'no sentinel'`; old beat + no sentinel → `STALE`, no `no sentinel`; no beat at all →
`OFF`; sentinel present with a dead pid → the `pid … gone` clause survives.

### Existing four — must stay at their exact counts

`scripts/tests/test-status-surface.sh`, `…-cwd.sh`, `…-handle-identity.sh`,
`test-dispatch-ledger-task-id.sh`.

**RISK (highest in this lane):** `test-status-surface.sh` very likely asserts on literal `SUP_WHY`
substrings, including `no sentinel` — those assertions are exactly what §2 removes. The implementer
must, **before writing any code**, run `grep -n 'sentinel' scripts/tests/test-status-surface.sh`. If
assertions exist, the correct move is to *update the assertion to the new true string* (same test
count, same test names) — never to delete a case, and never to keep the old string alive by
preserving the lie.

All new files: bash 3.2 — no `declare -A`, no `${var^^}`, no `mapfile`, no `readarray`, no `**`
globstar. Verify with `bash --posix -n` and `/bin/bash -n` (macOS system bash *is* 3.2).

---

## 4. Symlink obligation (per mission off-limits §3)

Both new `scripts/` files need a per-file symlink in **both** trees — a real copy in
`~/.claude/leadv2-shared/` is the failure that ate three rounds on 2026-08-01:

```
~/.claude/leadv2-shared/scripts/leadv2-codex-lockout.sh   -> canonical
<repo>/.claude/scripts/leadv2-codex-lockout.sh            -> canonical
```

Test files under `scripts/tests/` follow whatever the existing four do — the implementer must
`ls -l` one of them and match, not assume.

Verification after linking: `readlink` both paths resolve into `~/Projects/leadv2/plugins/leadv2/scripts/`,
and `test ! -e` returns false for neither.

---

## 5. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | Duplicated lockout parse drifts from `codex-task.sh` | §3 agreement test drives the real gate binary, both directions |
| R2 | `test-status-surface.sh` asserts the removed `no sentinel` strings | Grep the test file *first*; update assertions in place, keep the count |
| R3 | BSD-vs-GNU `date` parse of the `until=` timestamp | Copy the gate's BSD form verbatim, add a GNU fallback; the helper fails **open** (`clear`) so a parse failure degrades to today's behaviour, never to a false lockout |
| R4 | `state=ok` + a lockout value could read as "available" to a future consumer | The value string leads with `lockout до` — same string the existing `limit_reached` branch already emits, so no new vocabulary is introduced |
| R5 | Concurrent access: `codex-task.sh` appends to `codex-lockout.state` while the refresher reads it | Read is `grep | tail -1` on a line-appended file; a partial final line yields no `until=` match → `clear` → next 300s tick corrects. No lock needed, but **note it** rather than pretend it cannot happen |
| R6 | `LEADV2_STATUS_CODEX_LOCKOUT` is documented as unused; resurrecting it could confuse | Update the comment block at `:22-23` in the same diff — a stale "unused" comment on a now-live knob is the same disease |
| R7 | Removing the sentinel from the reason hides a genuinely broken sentinel | Present-but-dead is still reported; only *absent* goes quiet, and absent is unactionable by construction |

## 6. Out of scope (for the implementer — do not do these)

- Editing `codex-task.sh`, `leadv2-dispatch-code.sh`, `leadv2-portable-lock.sh`, `glm-coder.sh`, `kimi-coder.sh`.
- Adding any write to `leadv2-supervise-resume.sh` or to the `--print` path.
- The **glm 80%-threshold surfacing** finding (§1c) — recorded, deliberately not fixed here; it needs
  the gate's threshold exposed to the refresher, which is a `glm-coder.sh`-adjacent change.
- The **kimi launch-probe surfacing** finding (§1c) — recorded, not fixed here.
- Any change to `SUP_STATE`/`SUP_PID`/`SUP_SHORT` semantics or to the sentinel-discovery walk.
- Lowering the codex kv TTL.

---

## 7. Constraint checklist

1. **Env naming** — `LEADV2_STATUS_CODEX_LOCKOUT` (pre-existing, `leadv2-limits-refresh.sh:22`),
   `LEADV2_CODEX_LOCKOUT_SH` (new, matches the `LEADV2_QUOTA_LIVE_SH` / `LEADV2_RATELIMIT_PROBE_SH`
   idiom at `:31-32`). No `LEAD_V2_*` drift.
2. **Paths** — every path in §1/§2 verified present on disk except the four marked `(to-create)`.
3. **`claude -p`** — this lane invokes none. N/A.
4. **Concurrent access** — R5 covers the one read+write surface (`codex-lockout.state`).
5. **Config contradiction** — R6: the `(unused)` comment must die in the same diff as the knob's
   resurrection.

---

```
acceptance:
  authored_at: 2026-08-02T00:00:00Z
  items:
    - surface: rendered_line
      observable: "with a future-dated lockout line in codex-lockout.state, the limits block's codex row reads a lockout with the same until-time that the dispatcher's refusal names, and a codex_fitting_dev dispatch attempted at that moment is visibly refused rather than quietly served by sonnet"
    - surface: rendered_line
      observable: "with the lockout file absent or its until-time already past, the codex row reads as plainly available, with no parenthetical timestamp claiming an expiry"
    - surface: rendered_line
      observable: "the supervisor row in a supervised session and in an unsupervised one read differently at a glance — one ON, one OFF — and neither mentions a missing sentinel"
    - surface: rendered_line
      observable: "a supervisor row whose sentinel file exists but whose process is gone still says so"
    - surface: file_artifact
      observable: "the four named existing suites report the same pass counts as on f0ed7bb, and every touched script parses under macOS system bash 3.2"
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-codex-lockout.sh, plugins/leadv2/scripts/leadv2-limits-refresh.sh, plugins/leadv2/scripts/leadv2-status-surface.sh, plugins/leadv2/scripts/tests/test-codex-lockout-agreement.sh, plugins/leadv2/scripts/tests/test-supervisor-reason-honest.sh, plugins/leadv2/scripts/tests/test-status-surface.sh

DELIVERABLE_COMPLETE
