# REVIEW-ROUNDCAP-01 fix round 1 — mechanism-closed implementation design

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/e8c1289f` (branch
`worktree-e8c1289f`, clean except an untracked `docs/leadv2/.compact-freeze.md`). All line
numbers below are that worktree's tree, read directly.

---

## 0. Where code discovery contradicts the mission's framing

Two corrections. Design is against the code, not the framing.

**(a) "Wrap the read+increment+write critical section in the same lock" is not literally
possible as one section.** The read that gates (`_review_roundcap_read` at :1001) and the
write that increments (`_review_state_write` at :1141) are separated by ~140 lines of pool
resolution, fan-out list building and the A4 dedup guard (:1059–:1110). Holding a lock
across that span would serialise the entire pool-resolve for every concurrent lane in the
same handoff — a much larger behaviour change than the mission asks for, and one that would
make a hung resolver block every sibling for 10s.

The *actual* lost-increment race lives entirely **inside `_review_state_write`** (:767–:794):
that function re-reads `existing_attempts` / `existing_spawns` off disk (:772–:779),
increments (:785–:789), and `mv`s (:791). Two processes both reaching :773 before either
reaches :791 both read N and both write N+1. Wrapping *that function body* closes the
lost-increment defect completely. That is the design below.

`_review_roundcap_read` (:693–:712) is separately, mildly racy: three independent `sed`
invocations (:697, :698, :699) over the same file. Each `sed` sees a whole file (writes are
`mv`-atomic), but the three can straddle two different generations of the file — `attempts`
from generation N, `spawns` from generation N+1. The mission asks for it to be locked; it
should be, and the same lock closes it.

**(b) Locking does not close the gate TOCTOU, and the mission's framing implies it does.**
The roundcap gate reads at :1001 and compares at :1004; the increment for that round happens
at :1470/:1483, after the fan-out. Nothing this fix does makes check-and-increment atomic
across that span. See §4 COUNTEREXAMPLE — this is the honest residual and it must not be
described in the commit message as "the cap is now concurrency-safe".

---

## 1. CALLERS / CALLEES

### 1.1 `_review_state_write` — `plugins/leadv2/scripts/leadv2-review-run.sh:767`

| Caller | file:line | Mode | Reached when |
|---|---|---|---|
| round-0 selfcheck RED exit | `leadv2-review-run.sh:1051` | `verdict` (default) | `LEADV2_REVIEW_MACHINE_ROUND0!=0`, `selfcheck.md` has `verdict: RED` and a matching `diff_hash`; then `exit 7` |
| spawn backstop | `leadv2-review-run.sh:1141` | `spawn` | immediately before the fan-out `&` loop at :1145 |
| FAIL verdict exit | `leadv2-review-run.sh:1470` | `verdict` | `verdict == FAIL`; then `exit 7` |
| PASS verdict exit | `leadv2-review-run.sh:1483` | `verdict` | fall-through pass path; then `exit 0` |

Callees of `_review_state_write` today: `sed`, `printf`, `mv` only — no repo function. It
reads three globals it does not own: `REVIEW_DIFF_HASH_OK`, `REVIEW_ROUND`, `diff_hash`,
`REVIEW_DEDUP`, `_REVIEW_ROUND_FROZEN`, `HANDOFF`. It returns 0 unconditionally and writes
no shell state — **which is why a subshell wrapper is safe here.** After the fix it also
calls `lv2_lock_wait` (`plugins/leadv2/scripts/leadv2-portable-lock.sh:24`).

### 1.2 `_review_roundcap_read` — `leadv2-review-run.sh:693`

| Caller | file:line | Field consumed |
|---|---|---|
| roundcap gate | `leadv2-review-run.sh:1001–1002` | `attempts` (`${pair% *}`) |
| spawncap gate | `leadv2-review-run.sh:1118–1119` | `spawns` (`${pair#* }`) |

Callees: `sed`, `printf`. Pure stdout, no side effects — safe inside a subshell (it is
already invoked under command substitution, which already forks).

### 1.3 `_review_roundcap_limit` — `:718` · `_review_spawncap_limit` — `:736`

Callers: `:1003` (live), `:1120` (`_review_spawncap_limit`, live) and the dead
`$(_review_roundcap_limit)` fallback inside `:1120` — fix 4.

### 1.4 Callers of the engine itself (`leadv2-review-run.sh`) — the independent-path check

| Path | file:line | rc handling |
|---|---|---|
| product-close lane | `leadv2-dispatch-product-close.sh:2237` (`bash "${_ENGINE_BIN}" …`), dispatch `case` at :2239–:2250 | arms for `0`, `7`, `6`, `9`, `*`. **rc=8 falls to `*` → `review_engine_error`.** This is fix 3. |
| **lead / interactive Review phase** | documented at `plugins/leadv2/docs/phases.md:272–:281` — the LLM lead invokes the same engine over Bash | **This path has no `case ${rc}` at all.** The lead does not branch on the exit code; it reads `review-gate.md`'s `status:`/`reason:` lines (phases.md:288–:295, which already enumerate `review_roundcap` / `review_spawncap`). So rc=8 is *already* correctly interpreted here — no change needed, and no second copy of the `case` to update. This is the "independent copy nobody named"; it is benign, and the design must not add an rc table to it. |
| test harness stub | `plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh:139` | overrides `LEADV2_REVIEW_RUN_BIN` with a stub engine; unaffected by all four fixes. |

`_dl_note` and `_stamp_review_terminal` (`leadv2-dispatch-product-close.sh:252`) are the two
callees the new `8)` arm invokes. `_stamp_review_terminal` accepts exactly
`pass|fail|unreviewed|blocked` (:252 signature comment) — `blocked` is the only correct
argument for a roundcap refusal, and it matches what the engine already wrote into
`review-gate.md` (`status: blocked`, :1006 / :1123).

### 1.5 Lock primitive

`lv2_lock_wait <lockfile> <timeout>` — `plugins/leadv2/scripts/leadv2-portable-lock.sh:24`.
Contract (from its header, :11–:20): must be called **inside** a `( … ) 9>"$lockf"`
subshell; rc0 = acquired, rc3 = timeout; release is automatic on subshell exit (fd-9 close
under real `flock`, an `EXIT` trap under the `mkdir` fallback). Reference use of the exact
pattern: `leadv2-dispatch-code.sh:2570–2580` inside `atomic_review_check_and_record`.

**Constraint the mission does not mention:** `leadv2-review-run.sh:11` declares
*"OWNERSHIP: this script is self-contained. It does NOT source the lane"*. Sourcing
`leadv2-portable-lock.sh` unconditionally would break that stance and hard-fail the engine
if the lib is absent. Use the **guarded-source + no-op stub** pattern the same file already
uses for `leadv2-review-findings.sh` at :42–:47.

---

## 2. THE CHANGES

Four fixes + one census extension + one test. No refactors.

### C1 — guarded source of the lock primitive (new, prerequisite for C2)

Insert immediately after the existing guarded source block at `leadv2-review-run.sh:47`:

```sh
# REVIEW-ROUNDCAP-01 fix-round-1 H1: the attempts/spawns read-modify-write below needs the
# same cross-process lock the sibling diff-hash ledger uses
# (leadv2-dispatch-code.sh:2570 atomic_review_check_and_record). Guarded source + no-op
# stub, mirroring _REVIEW_FINDINGS_SH above: this script stays self-contained, and a
# missing lib degrades to today's unlocked behaviour rather than killing the engine.
_REVIEW_LOCK_SH="${SCRIPT_DIR}/leadv2-portable-lock.sh"
# shellcheck source=leadv2-portable-lock.sh
[[ -f "${_REVIEW_LOCK_SH}" ]] && source "${_REVIEW_LOCK_SH}"
if ! declare -F lv2_lock_wait >/dev/null 2>&1; then
  lv2_lock_wait() { return 0; }   # lib absent -> proceed unlocked (today's behaviour)
fi
```

`SCRIPT_DIR` is set at :39, before this point. `declare -F` (not `command -v`) so a
same-named external binary can never satisfy the check.

### C2 — lock the state read and the state read-modify-write (mission fix 1, HIGH)

New helper, placed directly above `_review_roundcap_read` (:693) so both users see it:

```sh
# _review_state_lock_file -> stdout = lock path, beside the state file it guards.
_review_state_lock_file() { printf '%s/.review-round.state.lock' "${HANDOFF}"; }

# Wait budget for that lock. Default 10s, matching atomic_review_check_and_record
# (leadv2-dispatch-code.sh:2570). Test seam only -- production never sets it.
_review_state_lock_wait_s() {
  local raw="${LEADV2_REVIEW_STATE_LOCK_WAIT_S:-}"
  [[ "${raw}" =~ ^[0-9]+$ ]] && { printf '%s' "${raw}"; return 0; }
  printf '10'
}
```

`_review_roundcap_read` — wrap the body's three `sed` reads plus the normalisation and the
final `printf` in the guarded subshell. The function's stdout contract (`"<attempts> <spawns>"`)
is unchanged because a subshell's stdout is the function's stdout:

```sh
_review_roundcap_read() {
  (
    lv2_lock_wait "$(_review_state_lock_file)" "$(_review_state_lock_wait_s)" || true
    ... existing body verbatim, :694-:711 ...
  ) 9>"$(_review_state_lock_file)" 2>/dev/null
}
```

`_review_state_write` — same shape, wrapping :770–:792 (everything after the `mode` local):

```sh
_review_state_write() {
  [[ "${REVIEW_DIFF_HASH_OK:-0}" -eq 1 ]] || return 0
  local mode="${1:-verdict}"
  (
    lv2_lock_wait "$(_review_state_lock_file)" "$(_review_state_lock_wait_s)" || true
    ... existing body verbatim, :770-:792 ...
  ) 9>"$(_review_state_lock_file)" 2>/dev/null || true
  return 0
}
```

**Fail-open is `|| true`, not `|| exit 3`.** The mission's phrasing — "fail-open on lock
timeout → run the review" — is correct for this mechanism and is *deliberately the opposite*
of `atomic_review_check_and_record`, which does `|| exit 3`. Rationale, stated so the critic
does not read it as a copy error: the ledger's lock guards a *duplicate-spend* decision
where refusing is the safe default; this lock guards a *counter* whose sole failure mode
under contention is losing one increment. Refusing on timeout would turn a 10s lock
contention into a lane that never records its round at all — strictly worse than the
under-count it is meant to prevent. The `mv -f` at :791 is atomic regardless, so a fail-open
write can lose an increment but can never leave a torn or partial state file.

Requirement: the lockfile must be created before `9>` can redirect to it — `9>` creates it
itself. `HANDOFF` always exists at both call sites (every prior write in the file targets
`${HANDOFF}/…`).

### C3 — escalation pointer must follow `--handoff` (mission fix 2, HIGH) + census

Four sites in the two cap blocks hardcode `docs/handoff/dispatch-${TASK}/…` while the file
is written to `${HANDOFF}/…`:

| file:line | Kind | Change |
|---|---|---|
| `:1006–1007` | `escalation:` field in `review-gate.md` | `escalation: %s/review-roundcap-escalation.md` ← `"${HANDOFF}"` |
| `:1022` | stderr operator hint | same substitution |
| `:1123–1124` | `escalation:` field (spawncap mirror) | same substitution |
| `:1138` | stderr operator hint (spawncap mirror) | same substitution |

The mission names only :1006 and :1122. **:1022 and :1138 are the same defect shape in the
same two blocks** — under a non-canonical `--handoff` they print a path that does not exist,
straight to an operator's terminal. The census lens will flag them if left; fix all four.

`${TASK}` remains in use elsewhere in both blocks (journal lines :1019/:1135, `emit` lines,
the escalation-file prose) — those are correct and untouched.

**OUT OF SCOPE, do not touch:** `:1467` and `:1480` (`render_gate_findings`'s
`docs/handoff/dispatch-${TASK}/review-${reviewer_primary}.md` argument). Same shape,
pre-existing, explicitly excluded by the mission.

**Boundary note the implementer must not silently resolve:** `--handoff` is passed relative
by the documented lead path (`phases.md:277`: `--handoff "docs/handoff/${LEADV2_TASK_ID}"`)
but may be **absolute** from the product-close lane (`leadv2-dispatch-product-close.sh:2237`
passes that lane's `${HANDOFF}`). After this fix the `escalation:` field is therefore
relative-or-absolute depending on caller, where today it is always relative. That is the
correct trade — a correct absolute path beats a wrong relative one — and no consumer parses
the field today (it is a human-read pointer, like `selfcheck:` at :1048). State this in the
commit message; do not add path normalisation (that is a refactor).

### C4 — rc=8 arm in the product-close dispatch (mission fix 3, MED)

`leadv2-dispatch-product-close.sh`, in the `case ${_engine_rc}` at :2239–:2250, insert
between the `7)` arm (:2247) and the `6)` arm (:2248):

```sh
    8) _dl_note dead review_roundcap "engine=1 rc=${_engine_rc}"; _stamp_review_terminal blocked ;;
```

Wording mirrors the existing arms exactly (`_dl_note dead <event> "engine=1 rc=…"`). Note
for the implementer: **rc=8 means roundcap OR spawncap** — the engine exits 8 from both
:1023 and :1139. One arm covers both, and `review_roundcap` is the journal event the mission
specifies; the precise discriminator is already on disk in `review-gate.md`'s `reason:` line
(`review_roundcap` vs `review_spawncap`) and in the engine's own journal append at :1019 /
:1135. Do not add a second arm or a `reason:` re-parse.

### C5 — dead fallback (mission fix 4, LOW)

`leadv2-review-run.sh:1120`:

```sh
-_review_spawncap_max="$(_review_spawncap_limit "${_review_roundcap_max:-$(_review_roundcap_limit)}")"
+_review_spawncap_max="$(_review_spawncap_limit "${_review_roundcap_max}")"
```

Verified safe: `_review_roundcap_max` is assigned unconditionally at top level (:1003), in
the same straight-line flow, with no intervening `unset` and no branch that can skip it. The
only exits between :1003 and :1120 are `exit 8` (:1023), `exit 7` (:1053), `exit 9` (:1077)
and `exit 2` (:1106) — all terminal. Under `set -u` the bare expansion is therefore always
defined.

### C6 — test (mission requirement)

`plugins/leadv2/scripts/tests/test-review-roundcap.sh`. Existing shape: `case_tN()` bodies at
:128–:270, registered as one `if case_tN; then pass …; else fail …; fi` line each at
:271–:280. Add `case_t11` and its registration line after :280.

Two assertions, both deterministic, no sleep-race:

**T11a — the lock is actually taken during increment.** Run one normal round via `run_rrc`,
then assert `${h}/.review-round.state.lock` exists. The lockfile is created by the `9>`
redirection and by nothing else in the engine, so its presence is proof the guarded path
executed. Cheap, exact, and it fails against the pre-fix code.

**T11b — fail-open under contention, bounded.** Set `LEADV2_REVIEW_STATE_LOCK_WAIT_S=1` for
the run (this is precisely why C2 introduces the seam), hold the lock externally for ~3s so
the holder provably still holds it when the engine's 1s budget expires, and assert the engine
still completes and `attempts` advanced. Because the platform decides which primitive
`lv2_lock_wait` uses (`leadv2-portable-lock.sh:26`), the holder must branch:

- `command -v flock` present → `( flock -x 9; sleep 3 ) 9>"${lockf}" &`
- otherwise (mkdir fallback) → `mkdir -p "${lockf}.d"; printf '%s' $$ > "${lockf}.d/pid"`,
  and `rm -rf "${lockf}.d"` in the case's cleanup. Keep the hold under
  `LV2_LOCK_STALE_S` (default 120, `leadv2-portable-lock.sh:22`) so the reaper does not
  make the test's meaning ambiguous.

Wall-clock cost: ~3s, bounded, no race. Reap the background holder with `wait` before the
case returns so `trap 'rm -rf "${STUB_DIR}"' EXIT` (:44) is not fighting a live child.

The suite's `T-red` baseline block (:283–:319) archives `plugins/leadv2/scripts` from
`LEADV2_TEST_BASELINE_REF` and runs the *old* engine — it must keep passing. It does not
touch the lockfile, so T11 must not assert anything about the baseline tree.

---

## 3. STATES AND RETURN CODES

### 3.1 Engine exit codes and what each caller does

| rc | Engine state | product-close (`:2239`) after C4 | Lead/interactive path (`phases.md:288`) | User-visible consequence |
|---|---|---|---|---|
| 0 | pass verdict written (`:1483`→`exit 0`) | `review_verdict_pass`, `_stamp_review_terminal pass`, phase recorded done | reads `status: pass` → ACCEPT, proceed to Phase 6 | the change moves on to deploy |
| 2 | duplicate arm in fan-out list (`:1106`) | `*` → `review_engine_error`, terminal blocked | no `status:` written this run; lead sees stale/absent gate | lane dies as an engine error; a human has to look |
| 6 | (arm declared in the `case`; no `exit 6` exists in the engine today) | `review_blocked` | — | unreachable |
| 7 | FAIL verdict (`:1470`) or selfcheck-RED round 0 (`:1053`) | `review_verdict_fail`, terminal fail | `status: fail` → spawn developer fix round, re-run engine | the diff is sent back for a fix round |
| 8 | **roundcap (`:1023`) or spawncap (`:1139`) refusal** | **before C4:** `*` → `review_engine_error` — the lane's journal claims the engine crashed. **after C4:** `review_roundcap`, terminal blocked | `status: blocked` + `reason: review_roundcap`\|`review_spawncap` → already handled correctly, no change | **before C4** the founder reading the journal sees "the review engine broke" when in fact the engine deliberately stopped spending — the wrong operator response (retry) instead of the right one (escalate or PARK). **after C4** the journal says the cap fired and points at the escalation file. |
| 9 | no reviewer seatable (`:1077`) | `all_arms_unavailable`, terminal unreviewed | `status: unreviewed` | nobody reviewed it; merge stays blocked |

### 3.2 `.review-round.state` states the mechanism can be in

| State on disk | `_review_roundcap_read` yields | Gate behaviour |
|---|---|---|
| file absent | `0 0` | round 1 proceeds |
| `attempts=N spawns=M`, both sane | `N M` | cap fires at `N >= max` / `M >= spawnmax` |
| `round=N` only (legacy, pre-upgrade lane) | `N 0` (:703–:708) | caps immediately — deliberate, T7 |
| `attempts=` empty / non-numeric / `>99999` | falls back to legacy `round=`, else `0` (:701–:709) | fails open, one more round is paid — T6 |
| `spawns=` empty / non-numeric / `>99999` | `0` (:702, :710) | spawn backstop fails open |
| file truncated mid-`mv` | **cannot occur** — `mv -f` (:791) is atomic on the same filesystem | — |
| **torn read across two generations** (attempts from gen N, spawns from gen N+1) | possible today (three separate `sed`s) | closed by C2 |
| **lost increment** (two writers both read N, both write N+1) | possible today | closed by C2 |

### 3.3 New lock states introduced by C2

| Lock state | `lv2_lock_wait` rc | Design behaviour | User-visible consequence |
|---|---|---|---|
| free | 0 | critical section runs serialised | nothing observable |
| held by sibling, released < wait budget | 0 | waits, then runs | the review starts up to 10s later; nothing else changes |
| held past the wait budget | 3 | `|| true` → proceed unlocked | worst case one increment is lost, exactly today's behaviour; **never a refusal to review** |
| `leadv2-portable-lock.sh` missing | stub returns 0 | proceeds unlocked | engine still runs; identical to pre-fix |
| lock dir stale (mkdir fallback, holder SIGKILLed) | reaped after `LV2_LOCK_STALE_S`=120 (`leadv2-portable-lock.sh:22`) | acquires after reap | up to 120s extra wait in the pathological case; still bounded by the 10s budget per attempt → fail-open |

---

## 4. CONFIGURATION BOUNDARIES

Every input the mechanism reads, at each boundary.

### `LEADV2_REVIEW_MAX_ROUNDS` (`_review_roundcap_limit`, :718)

| Input | Behaviour | Correct? |
|---|---|---|
| absent | `2` (:720–:723) | yes |
| empty string | `2` (`:-` then `-z`) | yes |
| `0` | passed through verbatim; gate at :1004 requires `>0`, so cap disabled | yes, documented kill-switch |
| `1` | caps after the first attempt | yes |
| very large (`999999999`) | passed through; gate never fires | acceptable — an unbounded cap is the same as `0` |
| non-numeric (`abc`, `-1`, `2.5`, `1 2`) | warns to stderr, returns `2` (:728–:729) | yes; note `-1` and `2.5` are caught by `^[0-9]+$` |
| contains shell metacharacters | never `eval`'d, only regex-tested, always quoted at :1004 | yes |

### `LEADV2_REVIEW_MAX_SPAWNS` (`_review_spawncap_limit`, :736)

| Input | Behaviour |
|---|---|
| absent / empty / non-numeric / `0` | falls back to `max_rounds * 3` (:747) — note `0` does **not** disable the spawn cap, only `LEADV2_REVIEW_MAX_ROUNDS=0` does (:738–:741). Pre-existing, correct-by-design, unchanged. |
| positive integer | used verbatim |
| `max_rounds == 0` | returns `0` → spawn cap disabled too |

### `LEADV2_REVIEW_STATE_LOCK_WAIT_S` (new, `_review_state_lock_wait_s`)

| Input | Behaviour |
|---|---|
| absent / empty | `10` — matches `atomic_review_check_and_record` |
| `0` | `0` → `flock -w 0` = try-once, fail-open immediately. Legitimate; used by nothing but a future test |
| positive integer | used verbatim |
| non-numeric / negative / float | `10` (regex-gated, never passed to `flock` unvalidated) |
| absurdly large (`86400`) | **would stall one lane for a day.** Bounded only by the fact that nothing in production sets it. Since this is a test seam, that is acceptable; the implementer must not wire it into `.claude/settings.json` or any override, and must not document it as an operator knob. |

Naming check: `LEADV2_` prefix, consistent with `LEADV2_REVIEW_MAX_ROUNDS` /
`LEADV2_REVIEW_MAX_SPAWNS` / `LEADV2_LOCK_STALE_S`. No `LEAD_V2_` drift. Grep before commit
to confirm the name is unused elsewhere.

### `--handoff` / `${HANDOFF}` (touched by C2's lockfile and C3's pointer)

| Input | Behaviour |
|---|---|
| absent | already rejected at :68 with a usage error — all five args required |
| relative (`docs/handoff/dispatch-X`) | lockfile at `docs/handoff/dispatch-X/.review-round.state.lock`; `escalation:` field relative — identical to today |
| absolute | lockfile absolute; `escalation:` field now absolute where it used to be a wrong relative path — **the fix** |
| directory does not exist | `9>` fails → subshell errors → `|| true` swallows it → unlocked write, which then also fails and is swallowed by :792's `|| true`. Same as today: the engine does not create `HANDOFF`, every caller does |
| contains spaces | every expansion is quoted (`"${HANDOFF}"`, `"$(_review_state_lock_file)"`) — safe. The `escalation:` line is `printf '%s'`, so a space in the path makes an ugly-but-correct pointer |
| path traversal / attacker-controlled | out of scope; `--handoff` is caller-supplied by the lane, same trust boundary as today |

### `.review-round.state.lock` (new artifact in `${HANDOFF}`)

Dotfile-prefixed, so it stays out of `${HANDOFF}/*` globs the way `.review-round.state`
already does. Never read, never parsed; under real `flock` it stays a zero-byte file, under
the `mkdir` fallback a sibling `.review-round.state.lock.d/` appears and is removed by the
`EXIT` trap. **Implementer must confirm before commit** that no handoff-artifact sweeper
(`leadv2-phase8-assert.sh`, the handoff compaction path) treats an unexpected dotfile in
`${HANDOFF}` as a violation — one `grep -rn 'review-round.state' plugins/leadv2` plus a run
of the two named suites is sufficient evidence.

### `.review-round.state` file itself

Absent → `0 0`. Empty → `0 0`. Unreadable (mode 000) → `sed` errors to stderr, fields empty
→ `0 0`, fail-open. Enormous (a 1GB file) → `sed … | head -n1` is streaming but reads to
EOF per field; three passes over 1GB is slow but bounded, and the `<=99999` guard rejects
the value. **An over-cap or malformed state file degrades exactly one lane's counter — it
never blocks a sibling lane**, because the lock is per-`HANDOFF` (per-task), not global.
This is the property C2 must preserve: do **not** put the lock file in a shared directory.

---

## 5. COUNTEREXAMPLE — what still violates the invariant after all four fixes

**Invariant:** *no task consumes more than `LEADV2_REVIEW_MAX_ROUNDS` verdict-producing
review rounds, or more than `LEADV2_REVIEW_MAX_SPAWNS` fan-out launches.*

After C1–C5 the counter can no longer be corrupted — but the **gate can still be passed by
two processes at once, and the fixes do not touch that.** Two concurrent engine runs on the
same `HANDOFF` both execute `_review_roundcap_read` at :1001, both see `attempts=1` with
`max=2`, both pass the `>=` test at :1004, and both proceed to a full fan-out. The
increments that follow are now correctly serialised — the state file ends at `attempts=3` —
but three rounds have already been paid for and the escalation file is written only on the
*fourth* invocation. The lock makes the counter honest; it does not make the decision
atomic, because the check (:1004) and the increment (:1470/:1483) are separated by the
entire review. Same shape at the spawncap: :1121's check and :1141's increment are adjacent
enough that they *could* be fused into one locked check-and-increment — the exact shape of
`atomic_review_check_and_record` — but that is a restructure the mission excludes, and the
roundcap gate cannot be fused at all without holding a lock across the fan-out. In plain
words: **under two truly concurrent lanes on one task, the founder can still be billed for
one review round more than the configured cap allows.** The bound is `max + (concurrent
runners - 1)`, not `max`.

Two smaller residuals, for completeness. First, the fail-open on lock timeout is a
deliberate hole: a lane that waits out 10s of contention proceeds unlocked and can lose its
increment, which under-counts and buys a free round — chosen over the alternative (refusing
to review), and bounded because a 10s contention on a per-task lock requires an already-
pathological system. Second, `_review_state_write` returns early at :768 whenever
`REVIEW_DIFF_HASH_OK != 1`, so a task whose diff can never be hashed never increments
`attempts` **or** `spawns` at all and is uncapped forever — pre-existing (M1, documented at
:754), untouched by this fix, and worth a follow-up ticket rather than a scope expansion here.

What I checked to reach this: every caller of the two functions (§1.1, §1.2), every exit
path between :1003 and :1141, the four `_review_state_write` sites, both callers of the
engine, and the `lv2_lock_wait` contract at `leadv2-portable-lock.sh:11–:32`.

---

## 6. OUT OF SCOPE — the implementing agent must not do these

1. Fusing the roundcap or spawncap gate into an atomic check-and-increment (§5). Follow-up.
2. `leadv2-review-run.sh:1467` / `:1480` — the same-shaped `docs/handoff/dispatch-${TASK}/`
   convention in `render_gate_findings` args. Explicitly excluded by the mission.
3. The `REVIEW_DIFF_HASH_OK != 1` early return at :768 (§5, residual 2).
4. Adding an rc dispatch table to the lead/interactive path — it correctly reads
   `review-gate.md` instead (§1.4).
5. Normalising `${HANDOFF}` to a repo-relative path (§C3 boundary note).
6. Touching `_review_roundcap_limit` / `_review_spawncap_limit` semantics, the `0`-means-
   unlimited asymmetry, or the legacy `round=` fallback.
7. `leadv2-plan-run.sh`, which mirrors this engine's structure (its own header, :4) but has
   no roundcap mechanism. Not in this task.
8. Any edit outside the worktree at `.claude/worktrees/e8c1289f`.

---

## 7. Verification the implementer owes

- `bash -n` and `/bin/bash -n` (bash 3.2) on `leadv2-review-run.sh`,
  `leadv2-dispatch-product-close.sh`, `tests/test-review-roundcap.sh`. The suite already
  runs the first two itself at :24–:25.
- `shellcheck -x -e SC1091,SC2034` on `leadv2-review-run.sh` — the suite asserts this at
  :27–:31, so a `source` added in C1 without the `# shellcheck source=` directive will turn
  a passing assertion red.
- `bash plugins/leadv2/scripts/tests/test-review-roundcap.sh` → all pass, `FAIL=0`,
  including the new T11 and the unchanged `T-red` baseline block.
- `bash plugins/leadv2/scripts/tests/test-review-round-exhaustive.sh` → 24/24, no regression.
- Commit inside the worktree, message naming `e8c1289f`.

---

## acceptance:

```yaml
acceptance:
  authored_at: 2026-08-24T00:00:00Z
  items:
    - surface: file_artifact
      observable: >-
        After a review round runs against a handoff directory, that directory contains a
        file named ".review-round.state.lock" sitting next to ".review-round.state".
        Before this change no such file is ever created.
    - surface: file_artifact
      observable: >-
        When the round cap fires for a task whose handoff directory is somewhere other
        than docs/handoff/dispatch-<task>/, the "escalation:" line inside review-gate.md
        names a path that a person can open and read, and opening it shows the page
        titled "Review round cap reached". Today that line names a path that does not
        exist on disk.
    - surface: log_line
      observable: >-
        In the task journal, a lane stopped by the round cap reads as
        "review_roundcap" rather than "review_engine_error", so a founder scanning the
        journal sees that the engine deliberately stopped spending rather than that it
        crashed.
    - surface: log_line
      observable: >-
        The review-roundcap test suite prints "review-roundcap: PASS=<n> FAIL=0" with a
        new passing line about the state lock, and the exhaustive review-round suite
        still prints 24 of 24 passing.
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-review-roundcap.sh

DELIVERABLE_COMPLETE
