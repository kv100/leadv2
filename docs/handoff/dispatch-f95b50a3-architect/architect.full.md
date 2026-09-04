# PHASE-INTEGRITY-01 — architect prepass (mechanism-closed design)

Base: `70ecf14`. Every file:line below was read on this checkout.

---

## 0. Where the mission's framing and the code disagree

The mission is right about the outcome and wrong about two mechanisms. The code wins; here is what
it actually says.

**0.1 — "the dispatcher *invents* a class rather than refusing" is not what `source=fallback` means.**
`_admission_classify` (`leadv2-dispatch-code.sh:3488-3541`) always runs a classifier
(`leadv2-task-judge.sh`) and never reads `docs/leadv2/tasks/<id>/STATE.md` at all — grep for
`STATE.md` in `leadv2-dispatch-code.sh` returns **zero hits**. `source=fallback` is the
*task-judge's* `estimate_source` field surfacing through
`lib/leadv2-admission-class.sh:62-63`, i.e. "the judge's own code-only heuristic produced the
estimate, not haiku". So the lead's failure to write `class:` to STATE.md is invisible to the
dispatcher by construction — there is no coupling to break.

The genuine silent default is one line lower than the mission looked:

```sh
# lib/leadv2-admission-class.sh:63
[[ "$src" == "judge" || "$src" == "fallback" ]] || src="fallback"
```

An estimate with an absent, empty, or unknown `estimate_source` is **relabelled `fallback`** —
an unattributed classification is laundered into an attributed-looking one. And one level up,
total classifier failure lands on `ADMISSION_CLASS="Standard"; ADMISSION_SOURCE="classifier_error"`
(`:3528`) and proceeds. Both are defaults where the mission asks for a refusal.

**0.2 — the reason Phase 1 cost nothing this session is the class→mode table, not the class value.**
`_phase_precondition_guard` (`:3556-3657`) resolves, with `LEADV2_REQUIRE_PHASES` unset
(`:3574-3584`):

| class | mode | scope |
|---|---|---|
| Standard / Heavy / Strategic | `1` (enforce) | `pre-build` |
| Trivial / **Light** | `warn` | `full` |

`warn` journals `phase_precondition_warn` and **returns 0** (`:3629-3631`). This session's own
journal is the proof: `phase_precondition_warn task=f95b50a3 class=Light
missing=build,test,review,deploy,close mode=warn`. Every phase was missing and the dispatch
proceeded. A Heavy classification would have enforced — so "Heavy's ceremony on paper, Trivial's
rigour in fact" is produced by the *Light* branch, not by the Heavy default. Fixing the class
default alone changes nothing here.

**0.3 — `skipped` is 60% present already.** `record --status` accepts
`running|done|n/a|waived` (`leadv2-phase-record.sh:610-613`). `n/a` is machine-derived
(`_phase_derived`, `:157-209`); `waived` is human-declared but requires the phase to be listed in
`.claude/leadv2-overrides/phases.yaml: waivers_allowed` (`:780-783`), and `review`/`close` are
hard-excluded (`:767-769`). A lead deliberately skipping `diverge` on a Light task with no
`phases.yaml` in the repo has **no honest status available** — which is exactly why recording
`done` is the cheapest path. The founder's item 4 is real.

**0.4 — a load-bearing bug found in discovery, not in the mission.**
`leadv2-phase-record.sh:102-105`:

```sh
_emit() {
  [[ -x "$JOURNAL_BIN" || -f "$JOURNAL_BIN" ]] || return 0
  LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash "$JOURNAL_BIN" "$1" "$2" >/dev/null 2>&1 || true
}
```

`leadv2-journal.sh` takes `append <task-id> <type> <text...>` (`:29-42`, dispatch `:44-75`). This
call passes `MODE="phase_recorded"`, `RAW_TASK_ID="phase=… task=… status=…"`, hits the `*)`
branch, and **exits 1 having written nothing**. Compare `leadv2-dispatch-code.sh:1651-1665`, which
gets it right. Consequence: *every* journal line phase-record believes it emits —
`phase_recorded`, `phase_waived`, `review_ledger_tamper`, `review_sidecar_tamper`,
`phase_mirror_miss` — has never been written. This is not a side quest: item 2 and item 3 both ask
for proofs that trace to a *journal record*, and today phase-record cannot write one. **Fix `_emit`
first or the rest of this design has no writer.**

---

## 1. CALLERS AND CALLEES

### 1.1 `leadv2-phase-record.sh` — every caller in the tree

| Caller | file:line | Subcommand | On a stricter `record` |
|---|---|---|---|
| Gate-1 accept (**the legitimate planner path**) | `leadv2-gate1-prompt.sh:166-186` | `record <sig8> classify`, `record … plan --artifact …/context.yaml`, `record … gate1 --artifact …/.gate1-passed` | **Must be taught the new flags** — otherwise the honest flow breaks and test #3 goes red |
| Dispatch admission guard | `leadv2-dispatch-code.sh:3603` (bin at `:658`) | `assert` only | Reads the stricter verdict; no flag change |
| Phase-8 close | `leadv2-phase8-close.sh:285-286` | `record … close` | Untouched (`close` proof unchanged) |
| Product close — e2e running | `leadv2-dispatch-product-close.sh:2613-2614` | `record … e2e --status running` | Untouched |
| Product close — review running | `…:2719-2720` | `record … review --status running` | Untouched |
| Product close — review done (×2) | `…:2744-2745`, `…:3226-3227` | `record … review --status done` | Untouched (`review` proof unchanged) |
| Test: round-trip | `tests/test-phase-record.sh:7` | all | Extend |
| Test: precondition | `tests/test-phase-precondition.sh:12,36,368` | `assert` | Extend |
| Test: gate1 discipline | `tests/test-gate1-discipline.sh:20,31` (**copies the script into a temp tree**) | record+assert | Extend; note the copy — a new sibling file dependency would break it |

**The independent copy nobody named:** `leadv2-gate1-prompt.sh:166` resolves
`leadv2-phase-record.sh` from `dirname "${BASH_SOURCE[0]}"`, and
`tests/test-gate1-discipline.sh:31` `cp`s the script into `$TMP/scripts/`. Any helper the new
`record` path needs must live **inside `leadv2-phase-record.sh`**, not in a new
`lib/*.sh` sibling, or that test breaks with exit 127 exactly as
`hooks/leadv2-link-tree-heal.sh:9` documents happening before.

Also on a different path: `.claude/worktrees/ca7c1056/plugins/leadv2/…` holds a full stale copy of
all three scripts. It is a worktree, not a second source — **do not edit it**, but do not be
confused by grep hits there.

### 1.2 `leadv2_admission_class` — every caller

| Caller | file:line | Args |
|---|---|---|
| Dispatch door | `leadv2-dispatch-code.sh:3520` | `"$explicit" "$flagged" "$estimate"` |
| **Backlog pump** (independent path) | `leadv2-backlog-pump.sh:709` | `"" 0 "$estimate"` — never an explicit class |
| Unit test | `tests/test-admission-class.sh` | direct |

The pump **always** passes an empty explicit class. A refusal rule that demands `--task-class`
when the classifier is unattributed will therefore refuse *every pump-originated task* unless the
pump is given an explicit class or the guard is scoped to the dispatch door. See §4 risk R1.

### 1.3 Callees of the functions being changed

- `_verify_artifact` (`phase-record.sh:410-581`) calls `_prepass_file` (`:583`),
  `_artifact_integrity` (`:374-389`), `_resolve_lane_diff_base` (`:393-406`), `_repo_slug`
  (`:365-369`), `_sha256` (`:114`), `_emit` (`:102`), `python3`, `git`.
- `_verify_artifact` is called from **two** places — `cmd_record:675` (to stamp `proof:`) and
  `cmd_assert:819`. They must stay the same predicate or `record` will stamp `verified` on
  something `assert` later refuses (or the reverse). Any new input (`--producer`, `--run-id`) must
  therefore be readable from the **phase file**, not only from `record`'s argv.
- `_phase_precondition_guard` calls `bash "${PHASE_RECORD_BIN}" assert …` (`:3603`) and `emit`
  (`:1651`).
- `_admission_classify` calls `leadv2_admission_read_receipt`, `leadv2_admission_class`,
  `leadv2_admission_write_receipt`, `leadv2_admission_freepool_role`, `TASK_JUDGE_BIN`, `emit`.

---

## 2. STATES AND RETURN CODES

### 2.1 `phase-record.sh assert` — today and after

| rc | Meaning | Caller (`_phase_precondition_guard:3613-3656`) | User-visible consequence |
|---|---|---|---|
| 0 | all mandatory phases proven | `return 0` | dispatch proceeds |
| 3 | `missing=<csv>` on stdout | mode `1` → journal `phase_precondition_refused`, print a `remedy:` line per phase, `return 1`; mode `warn`/`0` → journal `phase_precondition_warn`, `return 0` | **enforce:** the operator sees `dispatch refused: missing mandatory phases: plan,gate1` and a remedy line, and no worker is spawned. **warn:** nothing visible; work proceeds unplanned — the 2026-08-29 outcome |
| 4 | config error / refused waiver | refuses in every mode except `REQUIRE_PHASES=0` (`:3561` returns before any subprocess) | dispatch refused, `phase precondition config error: <text>` |
| other (127, 1) | infra failure | mode `1` refuses; `warn` journals `reason=unexpected_rc` and proceeds | enforce: refused with the rc named. warn: proceeds |

**No new rc is introduced.** Every new refusal is expressed as rc 3 with the phase in `missing=`,
so the caller's existing remedy-printing loop (`:3622-3625`) already renders it. This is the
single most important compatibility constraint in the design.

### 2.2 `phase-record.sh record` — status × phase after this change

| status | `--artifact` | `--reason` | `--producer`/`--run-id` | `proof:` stamped | Satisfies a MANDATORY phase in `assert`? |
|---|---|---|---|---|---|
| `running` | not required | — | — | *(empty)* | no |
| `done`, phase ∈ {plan, gate1} | required | — | **required** | `verified` \| `unattributed` \| `stale` \| `unverified` | only when `verified` |
| `done`, phase ∈ {build, review, deploy, close} | required | — | optional | `verified` \| `unverified` | only when `verified` |
| `done`, phase ∈ {test, live_verify, e2e} | required | — | optional | `attested` \| `unverified` | only when `attested` |
| `done`, phase ∈ {classify, diverge} | not required | — | — | `verified` | yes (dispatch dir exists) |
| `n/a` | — | required | — | *(empty)* | yes — derived-inapplicable |
| `waived` | — | required | — | *(empty)* | only if in `waivers_allowed` and not `review`/`close` |
| **`skipped`** (new) | — | **required** | — | *(empty)* | **no for MANDATORY** — stays in `missing=`; yes for OPTIONAL |

New `proof:` values and the *plain-words* consequence when `assert` sees them:

| `proof:` | Cause | What a human sees |
|---|---|---|
| `unattributed` | `plan`/`gate1` recorded `done` with no `--producer`/`--run-id`, or a producer not in the allowlist | `dispatch refused: missing mandatory phases: plan` — the lead's hand-written `context.yaml` no longer buys a dispatch |
| `stale` | artifact's recorded `base_head` ≠ current lane base, or artifact predates the lane base commit | same refusal, with `reason=stale_artifact` in the journal — the 26KB six-day-old prepass copied into three fresh handoff dirs stops counting |
| `unverified` | existing semantics, unchanged | same refusal |

**Terminal-outcome trace.** In enforce mode (`Standard`/`Heavy`) an `unattributed` plan makes
`assert` return 3 with `plan` in `missing=`; `_phase_precondition_guard` returns 1 *before any
spawn side effect* (`:3543-3547` places it before `_stamp_active_phase`), so the dispatch dies at
the door. There is no retry loop around it — `cmd_resolve`'s caller at `:6217` uses `|| { … }`.
**Plain words: the task is not started, the operator is told which phase is missing and the exact
`record` command to fix it, and nothing is queued or half-written.** In `warn` mode (Light,
`LEADV2_REQUIRE_PHASES` unset) the same rc 3 still returns 0 — see the §3 decision on whether Light
moves to enforce, and R2.

### 2.3 `_admission_classify` — states after the class fix

| Estimate state | `ADMISSION_SOURCE` today | after | Caller behaviour |
|---|---|---|---|
| judge produced an estimate, `estimate_source: judge` | `judge` | `judge` | unchanged |
| estimate_source `fallback` (judge's code-only heuristic) | `fallback` | `fallback` | unchanged |
| estimate parses, `estimate_source` absent/empty/unknown | **`fallback` (laundered)** | `unattributed` | refuse unless `--task-class` given |
| task-judge rc≠0, empty, or unparseable | `classifier_error` → Standard | `classifier_error` → **refuse** unless `--task-class` given | refuse |
| `--task-class` given | `flag` (escalate-only) | `flag` | unchanged — **this is the documented remedy** |
| receipt already on disk, digest matches | reused, no journal line | unchanged | unchanged — re-entry is never re-refused |

Refusal message (exact text the operator must see):

```
dispatch refused: task class is unattributed (source=<unattributed|classifier_error>).
  remedy: re-run with --task-class <Trivial|Light|Standard|Heavy>
  or set LEADV2_ADMISSION_REQUIRE_CLASS=0 to restore the previous default-to-Standard behaviour.
```

rc: **the existing usage-error rc of `cmd_resolve`'s refusal path** — do not invent a new one; the
implementer must match whatever `_lane_writes_guard`/`_acceptance_guard` return at the same
structural slot so the caller's `|| { … }` at `:6098-6101` behaves identically.

---

## 3. CONFIGURATION BOUNDARIES

Every input the changed mechanism reads.

### 3.1 `LEADV2_ADMISSION_REQUIRE_CLASS` (new env var)

| Value | Behaviour |
|---|---|
| absent | **`1`** — refuse unattributed. This is the founder's item 1 |
| `0` | documented kill switch: byte-identical to today (Standard/classifier_error, proceed). Mirrors `REQUIRE_PHASES=0` at `:3561` |
| `1` | refuse |
| empty string | treated as absent → `1`. Must not crash under `set -u` |
| any other value | journal `admission_require_class_badmode value=<v>`, fall back to `1` (fail **closed** — this guard's whole point is that absence must not pick for you). Mirrors `phase_precondition_badmode` (`:3585-3588`) but with the opposite default, and say so in a comment |

Naming: `LEADV2_*`, consistent with `LEADV2_REQUIRE_PHASES`, `LEADV2_PREPASS_INVALIDATE`,
`LEADV2_PHASE_RECORD_BIN`. No `LEAD_V2_*` drift. `.claude/settings.json` is untracked
(`?? .claude/settings.json` in status) — **do not add the var there**; env defaults live in the
script, as `REQUIRE_PHASES` does.

### 3.2 `--producer` / `--run-id` (new `record` flags)

| Input | Behaviour |
|---|---|
| absent on `plan`/`gate1` `--status done` | `proof: unattributed`; `record` prints the same WARN shape as `:679` and exits **0** (recording is observability; refusing is `assert`'s job — keep the writer permissive and the reader strict, as today) |
| absent on any other phase | ignored, no behaviour change |
| empty string | identical to absent |
| producer not in the allowlist | `unattributed` |
| over-cap: value > 256 bytes, or containing newline / `:` / control chars | **truncate to 256 and strip to `[A-Za-z0-9._-]`** before writing. This is load-bearing: the phase file is flat single-level YAML parsed by `grep '^key:' \| awk` (`:808-815`) — an unsanitised value with a newline injects a forged `status: done` line into the record. An over-cap input must degrade this one record, never corrupt the parse of the whole `phases.d` directory |
| producer allowlist source | a constant in `leadv2-phase-record.sh`, overridable by `LEADV2_PLAN_PRODUCERS` (default `architect,codex,gate1,planner`), mirroring `REVIEW_ARMS` at `:112`. Malformed/empty override → fall back to the default list, journal once |

### 3.3 The `plan` artifact and its provenance sidecar

| State | Behaviour |
|---|---|
| `context.yaml` absent | `plan` unproven (today's behaviour, `:418-419`) |
| `context.yaml` present, 0 bytes | unproven (`-s` already) |
| `context.yaml` present, no `decisions` string | unproven (today) |
| `context.yaml` present with `decisions`, **no sidecar** | **`unattributed`** — this is the 2026-08-29 bypass, closed |
| sidecar present, `base_head` == current lane base | `verified` |
| sidecar present, `base_head` ≠ current lane base | **`stale`** |
| sidecar present, `base_head` absent/malformed/not 40-hex | `stale` (fail closed) |
| sidecar present but lane base unresolvable (`_resolve_lane_diff_base` returns empty — detached, no `origin/main`, no start-sha) | `unverified`, **not** `stale`; journal `plan_base_unresolved`. A repo state that cannot compute a base must not be reported as a staleness violation |
| `architect-prepass.md` present and non-empty (`:417`) | **must also require its `.head` sidecar** — that file already exists (`dispatch-code.sh:4322`) and already carries the generation HEAD. Reuse it; do not invent a second staleness format |
| `architect-prepass.md` present, `.head` absent | `stale` — consistent with `dispatch-code.sh:4109-4113`, which already treats an unstamped prepass as stale |

### 3.4 `.gate1-passed`

| State | Behaviour |
|---|---|
| absent | unproven (today) |
| present, 0 bytes (the legacy `touch` at `gate1-prompt.sh:147`) | unproven (today, `-s`) |
| present, arbitrary non-empty text | **today: PROVEN. After: `unattributed`** |
| matches `^gate1 accepted task=<id> class=<c> risk=<r> at=<ISO-8601>$` (what `gate1-prompt.sh:180-182` writes) **and** a ledger row `{"event":"gate1_decision","task_id":<id>,"rc":<n>,"outcome":…}` exists for that `task_id` (`gate1-prompt.sh:42-52` via `lv2-ledger-emit.py`) | `verified` |
| sentinel matches but no ledger row, **and** an answered question exists for the task in `$(leadv2-state-path.sh questions)` (verified present: `docs/leadv2/questions/q-*.yaml`) | `verified` — this is the "answered question in the control-plane question store" arm of item 3 |
| sentinel matches, no ledger row, no answered question | `unattributed` |
| ledger emitter missing (`lv2-ledger-emit.py` absent — `gate1-prompt.sh:47` returns 0 silently) | fall through to the question-store arm; if that is also empty, `unattributed`. Journal `gate1_ledger_unavailable` once so this is diagnosable rather than mysterious |
| task_id in the sentinel ≠ the task the record is for | `unattributed` — a foreign task's gate cannot satisfy this one |

### 3.5 `--status skipped`

| Input | Behaviour |
|---|---|
| `--reason` absent | usage error, exit 4 — identical to `n/a`/`waived` (`:628-631`) |
| `--reason` empty | exit 4 |
| `--reason` with newline / `:` | sanitise as §3.2 (same flat-YAML injection surface) |
| phase is MANDATORY for the class | record is written; `assert` still lists the phase in `missing=`. **This is the point** — an honest skip is recorded and still refused |
| phase is OPTIONAL or excluded | record written; `assert` unaffected (it only iterates `MANDATORY`, `:794`) |
| phase is `review` or `close` | allowed to *record* (it changes nothing — they are always MANDATORY so `assert` still refuses). Do **not** add a second hard-exclusion branch; one refusal path is enough |

### 3.6 `phases.yaml` (`.claude/leadv2-overrides/phases.yaml`)

Unchanged, and confirmed absent in this repo — `_read_phases_yaml:216-219` returns the empty
default. Boundaries already handled there (unknown key → exit 4, removals refused, PyYAML missing →
exit 4). **One consequence to state plainly:** because there is no `phases.yaml` here,
`waivers_allowed` is empty, so *every* `--waiver` is refused with rc 4 today. That is why `skipped`
cannot be built on top of `waived`.

---

## 4. COUNTEREXAMPLE — what still violates the invariant after all five items land

The invariant: *a phase record means the phase actually ran.*

Three things still violate it, and the honest answer is that two of them cannot be closed here.

**(a) Same-user forgery, unchanged and unclosable by this design.** The header doc-block already
concedes this for `review` (`:44-56`) and `gate1` (`:58-64`): the worker and the verifier run as
the same Unix user, so any process that can write `docs/handoff/` can also append a
`gate1_decision` row to the ledger, write a provenance sidecar with the current `base_head`, and
name an allowlisted producer. This design does not add an authority boundary; it raises the cost of
the bypass from *one `touch`* to *a deliberate multi-file forgery that shows up in `git diff`*. The
whole claim is "the cheapest path is no longer the dishonest one" — not "the dishonest path is
impossible." Any report that claims otherwise is overclaiming.

**(b) The `warn` mode remains a complete bypass for Light, and Light is the default for most
tasks.** Even with every proof tightened, `_phase_precondition_guard:3629-3631` returns 0 on rc 3
for class Light. If this design is landed without touching the mode table, the exact 2026-08-29
session replays byte-for-byte: `phase_precondition_warn … mode=warn`, dispatch proceeds. **This is
the single highest-value change in the whole task and the mission does not name it.** But flipping
Light to enforce is a scope decision with blast radius across three repos — see R2. My
recommendation: land the proof tightening *and* flip Light's default `mode` from `warn` to `1`
scoped to `pre-build` (so Light needs only `classify`; `plan`/`gate1` are `O`/`-` for Light per
`_phase_class_level:131,134` and are therefore *not* in the pre-build mandatory set). That makes
Light enforce something real without demanding a plan Light never needed. If the founder declines
the flip, say in the report that the bypass remains open.

**(c) `test`, `live_verify` and `e2e` remain integrity-only** by explicit declaration
(`:33-42, 547-552`). A recorded `test` phase proves a file's sha256 matches what was recorded — not
that a test ran, and not that it passed. Untouched here, correctly, but it means "all phases
green" still does not mean "the code was tested."

What I checked and found *not* to be a hole: the receipt path
(`leadv2_admission_write_receipt:174` never overwrites, and
`leadv2_admission_find_receipt_for_task:157-159` binds `task_id`, `digest`, and `sig8 ==
digest[:8]` together, so a foreign task's receipt cannot be adopted); and the `assert` waiver path
(`review`/`close` hard-excluded at `:767`, `waivers_allowed` membership required at `:780`).

---

## 5. CHANGES — exact files

### C1. `plugins/leadv2/scripts/leadv2-phase-record.sh`
1. **Fix `_emit`** (`:102-105`) → `bash "$JOURNAL_BIN" append "<task-id>" decision "<text>"`. Needs a
   task id in scope; thread the `--task-id` value (falling back to `dispatch-<sig8>`) into a
   script-level variable set early in `cmd_record`/`cmd_assert`. **Do this first** — §0.4.
2. Add `--producer` / `--run-id` to `cmd_record` argv (`:588-605`); sanitise per §3.2; write
   `producer:` and `run_id:` as flat fields (`:659-684`).
3. Add `skipped` to the status vocabulary (`:610-613`), to the `--reason`-required branch
   (`:628-631`), and to `cmd_assert`'s `case "$p_status"` (`:809-832`) as a **non-satisfying**
   state (fall through to `missing+=`).
4. `_verify_artifact` `plan` arm (`:413-421`): require producer allowlist + provenance/`.head`
   sidecar + `base_head` == `_resolve_lane_diff_base "$sig8"`. Return distinct reasons via a
   script-level `_VERIFY_REASON` variable so `cmd_record` can stamp `unattributed`/`stale` instead
   of a flat `unverified` (`:673-681`).
5. `_verify_artifact` `gate1` arm (`:422-426`): sentinel shape + ledger row / answered question per
   §3.4.
6. Extend the `proof:` vocabulary in `cmd_show`'s translation table (`:867-872`) — `unattributed` →
   `UNATTRIBUTED`, `stale` → `STALE`.
7. Update the header doc-block proof table (`:23-64`) — it is the contract other agents read.

### C2. `plugins/leadv2/scripts/lib/leadv2-admission-class.sh`
8. Line 63: replace the `|| src="fallback"` laundering with `|| src="unattributed"`.

### C3. `plugins/leadv2/scripts/leadv2-dispatch-code.sh`
9. `_admission_classify` (`:3488-3541`): after resolving `ADMISSION_SOURCE`, refuse when it is
   `unattributed` or `classifier_error` **and** `flagged != 1` **and**
   `LEADV2_ADMISSION_REQUIRE_CLASS != 0`. Emit the §2.3 message; return non-zero at the same
   structural slot the caller already handles (`:6098-6102`). Receipt-reuse re-entry (`:3496-3507`)
   returns before this and must stay untouched.
10. *(recommended, founder call — see §4(b))* `_phase_precondition_guard:3574-3584`: Light default
    `mode="warn"` → `mode="1"`, `scope="pre-build"`.

### C4. `plugins/leadv2/scripts/leadv2-gate1-prompt.sh`
11. `_gate1_accept` (`:166-186`): pass `--producer gate1 --run-id <task_id>:<utc>` on the `plan` and
    `gate1` records. **Without this the honest path fails the new proof and test #3 goes red.**

### C5. Tests
12. `tests/test-phase-integrity-bypass.sh` *(to-create)* — the 2026-08-29 reproduction: hand-write
    `context.yaml` + `.gate1-passed`, `record plan` + `record gate1`, `assert --class Standard` →
    **rc 3, `missing=plan,gate1`**. Red-first proof on `70ecf14` required.
13. `tests/test-admission-require-class.sh` *(to-create)* — unattributed estimate → refused with the
    remedy string; `--task-class Light` → admitted. Both directions.
14. `tests/test-phase-integrity-legit.sh` *(to-create)* — a producer-attributed plan at the current
    base satisfies `plan`; a `gate1_decision` ledger row satisfies `gate1`; `record diverge --status
    skipped --reason …` on a Light task dispatches fine.
15. Extend `tests/test-phase-record.sh` (`skipped` round-trip, new `proof:` values) and
    `tests/test-admission-class.sh` (the `unattributed` source).
16. Register the three new tests in `tests/run-core-offline.sh` beside `:308`.

### Out of scope — do not touch
- Which planning mechanism Standard+ should use; `architect_prepass` revival;
  `LEADV2_DISPATCH_ARCHITECT_GATE`. A separate Codex pass owns it.
- `review`, `build`, `deploy`, `close` proof logic (`:427-437, 438-546, 553-568, 569-573`).
- `test`/`live_verify`/`e2e` integrity-only declaration.
- The review provenance/token/sidecar machinery (`:452-544`).
- `phases.yaml` schema and the waiver rules.
- `.claude/worktrees/ca7c1056/**` — a stale worktree copy, not a source.
- `docs/leadv2/**`, `docs/handoff/**` — state, never code.

---

## 6. RISKS

| # | Risk | Mitigation |
|---|---|---|
| R1 | **The backlog pump is refused wholesale.** `leadv2-backlog-pump.sh:709` passes `"" 0 "$estimate"` — no explicit class ever. If its judge returns an unattributed estimate, every pumped task dies at the door and the board goes empty | Scope the refusal to `_admission_classify` (the dispatch door) only — the pump's own call site keeps today's behaviour. Verify by grepping the pump for how it consumes `pair` before landing |
| R2 | **Flipping Light to enforce is a three-repo blast radius.** Light is the common class; enforcing `pre-build` means every Light dispatch needs a `classify` record | `classify`'s proof is only "the dispatch dir exists" (`:574-577`), which every dispatch satisfies trivially — so pre-build enforcement for Light is nearly free. Prove this with test #3 before landing; if it is not free, do not flip and report the bypass as open |
| R3 | **Flat-YAML injection via `--producer`/`--reason`.** `cmd_assert` parses with `grep '^status:' \| awk` (`:808`) — a newline in a value forges a field | Sanitise to `[A-Za-z0-9._-]`, cap at 256 bytes, at the point of write (§3.2). Add a test with a `$'\n'`-bearing producer |
| R4 | **`record` and `assert` drift.** Both call `_verify_artifact` (`:675`, `:819`); new inputs read from argv in one and from the file in the other would diverge | `_verify_artifact` must read `producer`/`run_id` from the **phase file** in the assert path and from the about-to-be-written values in the record path — thread them as parameters, and assert in a test that a freshly recorded `proof:` matches what `assert` concludes |
| R5 | **`test-gate1-discipline.sh` copies the script** (`:31`) into a temp tree | No new sibling `lib/` file; all new logic inside `leadv2-phase-record.sh` |
| R6 | **`run-core-offline.sh` has 11 pre-existing LANE-PLACEMENT-01 failures** (mission, verified 2026-08-29) | Report the suite as a **delta**. Capture the count on `70ecf14` before the first edit |
| R7 | Concurrent access: `phases.d/<phase>.yaml` is written by `record` (atomic `mktemp`+`mv -f`, `:655-686`) while `assert` reads it (`:806-815`) | Existing atomicity is sufficient — `mv -f` within the same dir is atomic. **New sidecars must use the same tmp+mv pattern**, never a direct `>` redirect, or `assert` can read a half-written provenance file |
| R8 | The `_emit` fix suddenly starts writing journal lines that have never been written | Expected and desired, but it will change journal volume and any test asserting journal contents. Grep `tests/` for `phase_recorded` before landing |

---

## 7. Acceptance

```
acceptance:
  - surface: log_line
    observable: >
      An operator who hand-writes context.yaml and .gate1-passed, records plan and gate1
      against them, and then dispatches, sees the dispatch stop with
      "dispatch refused: missing mandatory phases: plan,gate1" followed by one
      "remedy:" line per missing phase, and no worker is started.
    authored_at: 2026-08-29T11:05:00Z
  - surface: log_line
    observable: >
      An operator dispatching a task whose class could not be attributed sees
      "dispatch refused: task class is unattributed" together with the remedy naming
      --task-class, and the same dispatch re-run with --task-class Light proceeds normally.
    authored_at: 2026-08-29T11:05:00Z
  - surface: file_artifact
    observable: >
      docs/handoff/dispatch-<sig8>/phases.d/plan.yaml written after a real planner run reads
      "proof: verified" and carries a producer and run_id; the same file written from a
      hand-authored document reads "proof: unattributed"; and one written against a plan
      generated before the lane's current base commit reads "proof: stale".
    authored_at: 2026-08-29T11:05:00Z
  - surface: file_artifact
    observable: >
      A lead deliberately skipping diverge on a Light task produces a diverge.yaml whose
      status reads "skipped" with the reason they gave, and `show` renders it as skipped
      rather than done.
    authored_at: 2026-08-29T11:05:00Z
  - surface: log_line
    observable: >
      docs/leadv2/tasks/<task-id>/journal.md gains a line for each phase recorded — today
      that file gains nothing at all when phase-record runs.
    authored_at: 2026-08-29T11:05:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-phase-record.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/lib/leadv2-admission-class.sh, plugins/leadv2/scripts/leadv2-gate1-prompt.sh, plugins/leadv2/scripts/tests/test-phase-integrity-bypass.sh, plugins/leadv2/scripts/tests/test-admission-require-class.sh, plugins/leadv2/scripts/tests/test-phase-integrity-legit.sh, plugins/leadv2/scripts/tests/test-phase-record.sh, plugins/leadv2/scripts/tests/test-admission-class.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
