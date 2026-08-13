# PHASES-ARE-THE-ONLY-PATH-01 — implementation design (architect prepass)

Binding inputs: `~/Projects/persona-engine/docs/handoff/DISPATCH-KILLED-BY-FG-TIMEOUT-01/c4-design.md`
(§1–§4, §2b, §2c), `C4-founder-ruling.md`, `observability-findings.md`. The design is settled —
this document only turns it into files, functions, call sites and tests. No design decision is
re-opened; the three places where the mission's own constraints collide are raised in §9 as
decisions, not as substitutions.

Repo: `~/Projects/leadv2`. All paths below are repo-relative unless prefixed `~`.

---

## 0. Anchor verification (line numbers drifted from the design doc — use these)

Verified against `69ad929` (current `main` tip at prepass time). The implementer must re-verify
after the mandated `git fetch origin && git rebase origin/main`, since these shift again.

| Design doc says | Actual at `69ad929` | Symbol |
|---|---|---|
| dispatch-code.sh:1419-1440 | **1439-1463** | `_lane_writes_guard` |
| dispatch-code.sh:1443-1466 | **1465-1487** | `_acceptance_guard` |
| dispatch-code.sh:2389 | **2410** | first `_stamp_active_phase … prepass` |
| dispatch-code.sh:2684 / :2714 | **2705 / 2735** | `_stamp_active_phase … build` |
| dispatch-code.sh:2916 | **2937** | `_stamp_active_phase` in `cmd_advance_arm` |
| dispatch-code.sh:350-353 | **354** | `_stamp_active_phase` definition |
| dispatch-code.sh:582-588 | **586 / 596** | `LANE_LIVENESS_BIN` probe calls (bin defined :1641) |
| status-surface.sh:3035-3050 | **3035-3049** (confirmed) | `lane_phase`, called :3138, :3198 |
| backlog-pump.sh:253 | **250-256** (comment block) | "never registers an active.yaml session" |

Confirmed as-is: `cmd_resolve()` :2240, `cmd_advance_arm()` :2891, `REVIEW_LEDGER_DIR` :366,
`JOURNAL_BIN` :306, `_prepass_file` :1334, `ARCHITECT_GATE` :388, `REQUIRE_LANE_WRITES` :414,
`REQUIRE_ACCEPTANCE` :420, `leadv2_active_register` active-registry.sh:507,
`leadv2_active_update_phase` :577.

---

## 1. Layers affected

| Layer | File | Change |
|---|---|---|
| phase truth (new) | `plugins/leadv2/scripts/leadv2-phase-record.sh` | **new** — sole writer + sole `phases.yaml` reader + `assert` |
| dispatch door | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | `_phase_precondition_guard`, `--phase-waiver`, record at existing stamp sites, active.yaml registration |
| close path | `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | record `review` + `e2e` |
| close path | `plugins/leadv2/scripts/leadv2-phase8-close.sh` | record `close` |
| surface | `plugins/leadv2/scripts/leadv2-status-surface.sh` | `lane_phase()` reads the record, corroborates liveness |
| doc contract | `plugins/leadv2/docs/phases.md` | remove CX-03 `model=skip` (R7) |
| guard honesty | `plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh` | R9 `setsid` — **see decision D3** |
| tests | `plugins/leadv2/scripts/tests/` | 3 new suites + fixtures + registration in `run-core-offline.sh` |

Not touched (non-goals, enforced): `leadv2-router.sh`, `routing.yaml`, arm resolution, quota gates,
`.claude/leadv2-overrides/gate1.sh`, anything in persona-engine.

---

## 2. Data flow (numbered)

1. A lane is dispatched: `leadv2-dispatch-code.sh resolve --mission-file … --task-id … --class C`.
2. `cmd_resolve()` parses args, computes `sig8`, resolves `founder_task_id` and lane name.
3. **`_phase_precondition_guard "${sig8}" "${task_class}" "${lane_writes}"`** runs at the same
   structural slot as `_lane_writes_guard`/`_acceptance_guard` — after arg validation, before any
   spawn side effect and before `_stamp_active_phase … prepass` (:2410).
4. The guard shells `leadv2-phase-record.sh assert <sig8> --class C [--waiver p=r …]`.
5. `assert` resolves the mandatory set = class table (§4) ∪ `phases.yaml:class_overrides`, minus
   accepted waivers; then for each mandatory phase reads `docs/handoff/dispatch-<sig8>/phases.d/<phase>.yaml`
   and re-verifies the artifact (exists + sha256 matches + content assertion).
6. `assert` exit 0 ⇒ guard returns 0. Exit 3 (`missing=plan,gate1` on stdout) ⇒ guard branches on
   `LEADV2_REQUIRE_PHASES` (§6). Exit 4 (usage / bad `phases.yaml` / refused waiver) ⇒ **always
   refuses, in every mode including `0`** — a malformed override is a configuration error, not a
   phase gap.
7. Dispatch proceeds. At each existing stamp site the dispatcher now calls
   `leadv2-phase-record.sh record` *first*, and `record` itself then calls
   `leadv2_active_update_phase` — so `phases.d/` and the active.yaml/pulse.json mirror are written
   by one code path and cannot disagree.
8. `leadv2-dispatch-product-close.sh` records `review` (at :1436) and `e2e` (at :1335);
   `leadv2-phase8-close.sh` records `close`.
9. `leadv2-status-surface.sh:lane_phase()` reads `phases.d/`, picks the newest `running` record,
   corroborates its `handle` against `LANE_LIVENESS_BIN`, and renders.

**Nothing else in the tree writes a phase anywhere.**

---

## 3. Interface contracts

### 3.1 `leadv2-phase-record.sh` (new — the ONE writer)

```
leadv2-phase-record.sh record <sig8> <phase> [flags]
    --artifact <repo-relative path>     # required unless --status running|n/a|waived
    --status running|done|n/a|waived    # default: done
    --handle <worker handle>            # required when --status running
    --reason <text>                     # required when --status n/a|waived
    --task-id <founder task id>         # for the active.yaml mirror; optional
    --owner <script:function>           # default: $(basename "$0")

leadv2-phase-record.sh assert <sig8> --class <Trivial|Light|Standard|Heavy>
    [--waiver <phase>=<reason>]...      # repeatable
    [--writes <csv>]                    # feeds the derived conditions in §4

leadv2-phase-record.sh show      <sig8>          # human-readable table of phases.d/
leadv2-phase-record.sh plan-for  --class <C>     # prints resolved mandatory set, one per line
```

Exit codes (contract — the guard depends on these):

| Code | Meaning | stdout |
|---|---|---|
| 0 | ok / all mandatory phases satisfied | — |
| 3 | one or more mandatory phases missing or unproven | `missing=<csv>` |
| 4 | usage error, malformed `phases.yaml`, refused waiver | error text on stderr |

Record file: `${PROJECT_ROOT}/docs/handoff/dispatch-<sig8>/phases.d/<phase>.yaml`.
`record` does its own `mkdir -p` (migration item: Trivial/Light lanes may have no
`docs/handoff/<id>/` at all — c4 §5.3).

Schema — **flat, single-level, no nesting**, so `flat_yaml()` (status-surface.sh:975) parses it
with no new dependency:

```yaml
phase: review
status: running
owner: leadv2-dispatch-product-close.sh
handle: dispatch-1a2b3c4d-review
artifact: docs/handoff/dispatch-1a2b3c4d/review-verdict.md
artifact_sha256: 3f9a…
started_at: 2026-08-05T14:22:07Z
ended_at: ""
reason: ""
```

Write discipline: `mktemp` in the *same directory* + `mv -f` (atomic rename on one filesystem).
One file per phase, never appended — dispatch and product-close touch the same lane concurrently
but never the same phase file, so no `flock` is needed.

Every `record` also emits `phase_recorded phase=<p> task=<sig8> status=<s>` via `JOURNAL_BIN`
(dispatch-code.sh:306) — observability, explicitly **not** proof.

Mirror: after a successful record with `status: running|done`, `record` sources
`leadv2-active-registry.sh` and calls `leadv2_active_update_phase`. A non-zero return journals
`phase_mirror_miss task=<sig8> phase=<p>` and returns 0 — the mirror must never fail a dispatch,
but the miss is no longer invisible (today `_stamp_active_phase` swallows it with
`>/dev/null 2>&1 || true` at dispatch-code.sh:354).

### 3.2 `_phase_precondition_guard` (dispatch-code.sh)

```
_phase_precondition_guard <sig8> <class> <writes> -> 0 proceed, 1 refuse
```

- Reads `REQUIRE_PHASES="${LEADV2_REQUIRE_PHASES:-warn}"`, declared next to `REQUIRE_ACCEPTANCE`
  (:420) with the same one-flip-rollback comment convention.
- `0` ⇒ `return 0` before any work, before any subprocess. Output byte-identical to today.
- Any value that is not `0`, `warn` or `1` ⇒ journal `phase_precondition_badmode value=<v>` and
  treat as `warn` (fail-soft on operator typo; a typo must not silently disable the gate, and must
  not brick the fleet either).
- Uses `PHASE_RECORD_BIN="${LEADV2_PHASE_RECORD_BIN:-${SCRIPT_DIR}/leadv2-phase-record.sh}"`,
  same pattern as `JOURNAL_BIN` (:306) / `LANE_LIVENESS_BIN` (:1641).

Journal lines (exact strings — the acceptance in §10 depends on them):

```
phase_precondition_warn    task=<sig8> class=<C> missing=<csv> mode=warn
phase_precondition_refused task=<sig8> class=<C> missing=<csv> mode=1
phase_waived               task=<sig8> phase=<p> reason=<r>
phase_precondition_config_error task=<sig8> detail=<text>
```

On refusal the guard also `log_err`s the literal remediation commands, one per missing phase:
`leadv2-phase-record.sh record <sig8> plan --artifact <path>`.

### 3.3 Waiver flag

`--phase-waiver <phase>=<reason>` added to **both** `cmd_resolve()`'s option loop (:2255+) and
`cmd_advance_arm()`'s (:2893+ — that loop `exit 4`s on unknown args, so omitting it there breaks
the product-close → advance-arm call at product-close.sh:1021). Repeatable; accumulates into a
bash array passed through as repeated `--waiver` flags.

All validation lives in `phase-record.sh assert` (single place):
1. Format `<phase>=<reason>` with non-empty reason, else exit 4.
2. `<phase>` ∈ the known phase ids, else exit 4.
3. `<phase>` ∈ `{review, close}` ⇒ **exit 4 unconditionally**, hard-coded in plugin code, checked
   *before* consulting `phases.yaml`. No project declaration can unlock it.
4. `<phase>` ∈ `waivers_allowed` of `.claude/leadv2-overrides/phases.yaml`, else exit 4. File
   absent ⇒ empty list ⇒ every waiver refused.
5. Accepted ⇒ write `phases.d/<phase>.yaml` with `status: waived`, `reason`, `owner`,
   `started_at == ended_at == now`; journal `phase_waived`.

### 3.4 `phases.yaml` override reader

`.claude/leadv2-overrides/phases.yaml`, schema exactly as c4 §4. Single plugin reader:
`leadv2-phase-record.sh` (embedded `python3`, matching the repo's existing style — status-surface
is python-in-bash). Parse rules:

- `version:` must be `1`; anything else ⇒ exit 4 `phases.yaml: unsupported version <v>`.
- `class_overrides.<Class>.mandatory:` is an **ADD list with union semantics** — never a
  replacement. `Light: { mandatory: [e2e] }` means base(Light) ∪ {e2e}.
- **Removal rejection:** any key under a class other than `mandatory` (`remove`, `exclude`,
  `skip`, `optional`, `drop`, or anything unrecognised) ⇒ exit 4 with
  `phases.yaml: class_overrides.<Class>: removals are not permitted (key '<k>'); shrink a class only via --phase-waiver`.
  Union semantics on `mandatory` means a shorter list is not a removal, so this key check is the
  complete removal surface.
- Unknown class name or unknown top-level key ⇒ exit 4 (strict; a typo'd class must not silently
  do nothing).
- `steps:` keys must be from the fixed plugin-owned hook point set: `plan.post`, `gate1.main`,
  `build.post`, `review.pre`, `review.post`, `deploy.main`, `deploy.post`, `verify.main`,
  `e2e.main`, `close.pre`. Unknown hook point ⇒ exit 4.
- File absent ⇒ base table, empty `waivers_allowed`, no steps. **Today's behaviour, unchanged.**

Note: `steps:` execution is *parsed and validated* here but its execution wiring is only required
at the hook points this task already writes (`plan.post`, `review.*`, `close.pre` via the record
sites). `deploy.main`/`verify.main`/`e2e.main` keep resolving through today's per-file overrides
(`deploy.sh`, `verify.sh`, `e2e.yaml:cmd`) — c4 §4 back-compat clause. Declaring them in
`phases.yaml` is accepted and recorded but does not yet supersede the per-file override; that
supersession is a follow-on, not this lane.

### 3.5 `lane_phase()` replacement contract (status-surface.sh:3035)

```python
def lane_phase(repo, sig8, in_census):
    # 1. foreign repo / no sig8 → degrade honestly, as today
    # 2. read docs/handoff/dispatch-<sig8>/phases.d/*.yaml via flat_yaml()
    # 3. no records → "~" + legacy_infer(...)   # pre-migration lane, visibly not equal
    # 4. running records → newest by started_at
    #      ended_at non-empty      → treat as done (crash between fields)
    #      liveness probe DEAD     → "<phase> (stalled, started <age> ago)"
    #      liveness probe ALIVE    → "<phase>"
    #      liveness probe UNKNOWN  → "<phase>"      # never claim stalled on probe failure
    # 5. no running records → newest done/n-a/waived by ended_at → "<phase> (done)"
    # 6. nothing → "worker" if in_census else "queued"
```

Deleted outright: the `os.path.isdir("dispatch-<sig8>-review")` → `"review"` inference (:3038-3041)
and the `dispatch-<sig8>-architect` → `"architect"` inference (:3044-3048). They move verbatim into
`legacy_infer()`, reachable only from step 3.

Liveness probe: `LANE_LIVENESS_BIN --project-root <root> --lane <sig8> --no-codex --json`, matching
dispatch-code.sh:596. **Bounded**: `subprocess` with `timeout=3`, memoized per `sig8` per render
(the surface renders many lanes and sits on the statusline hot path — one probe per lane per render,
never per record). Probe error / timeout / unparseable ⇒ UNKNOWN, not DEAD.

`in_census` remains an input but is now only a fallback (steps 4–5 outrank it): a lane with a live
`running` record renders its phase, not the generic `worker`.

---

## 4. Class → phase table (c4 §3, verbatim; lives in `leadv2-phase-record.sh`)

`M` mandatory · `O` optional (recorded when run) · `C` conditional-mandatory (else `status: n/a`
with a machine-derived reason) · `–` not in the subset.

| Phase id | Trivial | Light | Standard | Heavy |
|---|---|---|---|---|
| `classify` | M | M | M | M |
| `diverge` | – | – | O | M |
| `plan` | – | O | M | M |
| `gate1` | – | – | M | M |
| `build` | M | M | M | M |
| `test` | C | M | M | M |
| `review` | **M** | **M** | **M** | **M** |
| `deploy` | C | C | C | C |
| `live_verify` | – | C | M | M |
| `e2e` | – | – | C | M |
| `close` | **M** | **M** | **M** | **M** |

Derived conditions (computed, never judged):
- `test` on Trivial: mandatory iff `--writes` matches `stack.yaml` source globs, else `n/a reason=docs_only`.
- `deploy` (all classes): mandatory iff the diff touches a runtime path per `stack.yaml`, else
  `n/a reason=no_runtime_surface`.
- `live_verify` (Light) / `e2e` (Standard): mandatory iff `deploy` recorded `done`.

`review` and `close` are mandatory in every class and are hard-excluded from waivers in plugin code
(§3.3 rule 3).

Per-phase proof (`assert` re-verifies artifact existence + sha256 + the content assertion) — c4 §2:

| Phase | Artifact | Content assertion |
|---|---|---|
| plan | `docs/handoff/<id>/context.yaml` **or** `_prepass_file <sig8>` + its `.sig` | `decisions[]` non-empty (context.yaml) / non-empty design (prepass) |
| gate1 | `docs/handoff/<id>/.gate1-passed` or acceptance block | passes `_acceptance_guard` shape |
| build | worker diff | non-empty `git diff` vs lane base |
| review | review-ledger row under `REVIEW_LEDGER_DIR` (:366), keyed by diff-hash | diff-hash equals the build diff's hash |
| test | step stdout capture | step exit 0 |
| deploy | deploy log + commit sha | commit is an ancestor of `origin/main` |
| live_verify | verify output | `verify.sh` exit 0 |
| e2e | e2e result file | entrypoint exit 0 |
| close | `docs/handoff/<id>/phase8-passed.flag` (:964) | written by `leadv2-phase8-assert.sh` |

An empty file satisfies nothing: every assertion is a property of a *derived* artifact.

---

## 5. Record call sites (exact)

| File:line (at `69ad929`) | Today | Add |
|---|---|---|
| dispatch-code.sh — `cmd_resolve` before :2410 | — | `_phase_precondition_guard` |
| dispatch-code.sh :2410 | `_stamp_active_phase … prepass` | `record <sig8> classify --status done`; register lane in active.yaml (§7) |
| dispatch-code.sh `architect_prepass` success path (~:1510+) | writes prepass file | `record <sig8> plan --artifact <prepass file>` |
| dispatch-code.sh :2705 / :2735 | `_stamp_active_phase … build` | `record <sig8> build --status running --handle <h>` |
| dispatch-code.sh `cmd_advance_arm` after the confirmed-reservation check (~:2922) | — | `_phase_precondition_guard` |
| dispatch-code.sh :2937 | `_stamp_active_phase … build` | `record <sig8> build --status running --handle <h>` |
| product-close.sh :1436 | `_stamp_active_phase … review` | `record <sig8> review --status running --handle <h>`, then `done` with the ledger row as artifact |
| product-close.sh :1335 | `_stamp_active_phase … e2e` | `record <sig8> e2e …` |
| product-close.sh :1687 `record-review` | writes ledger row | `record <sig8> review --artifact <ledger row> --status done` |
| phase8-close.sh (flag write, dispatch-code.sh:964 path) | writes `phase8-passed.flag` | `record <sig8> close --artifact <flag>` |

`_stamp_active_phase` calls are **kept** — they become no-ops in practice once `record` drives the
mirror, but removing them in the same lane widens the blast radius for no gain. Convert them to
call `record` and let `record` do the mirroring; do not delete the function.

Guard call-site discipline (same rule as H6 at :1440): **one guard call per exit path that can
reach a spawn**, including the `ARCHITECT_GATE=0` kill-switch path and the
`provably_one_file` early return. No branch may dispatch unrecorded.

---

## 6. Migration (R8)

- `LEADV2_REQUIRE_PHASES` — three-valued `0 | warn | 1`, **default `warn`**.
- `warn`: record + journal `phase_precondition_warn` + print; never refuse.
- Grandfathering: a `sig8` whose `docs/handoff/dispatch-<sig8>/` directory mtime predates the
  rollout stamp file (`${CACHE_BASE}/phase-rollout.stamp`, written on first guard run) is journaled
  `phase_precondition_grandfathered` and passes even at `1`. Without this, the flip retroactively
  refuses every lane that existed before the record was invented.
- Rollback: `LEADV2_REQUIRE_PHASES=0` — guard returns 0 before any subprocess; output
  byte-identical to today. Same one-flip convention as `LEADV2_DISPATCH_ARCHITECT_GATE` (:388),
  `LEADV2_REQUIRE_LANE_WRITES` (:414), `LEADV2_REQUIRE_ACCEPTANCE` (:420).
- The flip to `1` is **not** in this lane — it is ledgered as `SD-PHASE-ENFORCE-01`.
- `leadv2-backlog-pump.sh` (auto-dispatches rows with no plan/gate1 record) and the parked
  `leadv2-fanout-lane-launcher.sh` both stay on `warn`; the pump is *not* modified here.

**Semantic to state plainly:** the guard sits *before* `architect_prepass`, so under enforce the
dispatcher's own prepass no longer counts as the `plan` phase for the dispatch that produces it —
which is exactly the bypass the founder ruled closed (C4-founder-ruling §5). A *re*-dispatch of the
same `sig8` does satisfy `plan`, because the successful prepass recorded it. This is why the flip
is a separate, ledgered decision and not part of this lane.

---

## 7. active.yaml registration (R4)

`leadv2_active_register` (active-registry.sh:507) is called once in `cmd_resolve`, after
`founder_task_id`/`DISPATCH_LANE_NAME` resolution (:2387-2391) and before the first record.
Without it `leadv2_active_update_phase` finds no row to patch and the mirror stays empty forever
(backlog-pump.sh:250-256 states this outright).

**Idempotency is a hard requirement and is unverified in this prepass:** the implementer must read
`leadv2_active_register` (:507-552) and confirm a second call for an existing task id updates
rather than appends. If it appends, wrap the call in an existence check via `leadv2_active_list`
(:770) — do **not** unregister-then-register (that races a concurrent reader of the same file).

Failure to register journals `active_register_miss task=<sig8>` and returns 0. Registration must
never fail a dispatch.

---

## 8. CX-03 removal (R7)

`plugins/leadv2/docs/phases.md:270` currently reads, inside the review-step routing instruction:
`` `model=skip` → no review (CX-03 light_low_risk)``.

Change: delete that clause and replace with an explicit invariant —
*"Review is mandatory in every class. The router may only select the **cheapest reviewer arm**; a
`model=skip` emission for the review step is ignored and the cheapest arm is used instead."*

Scope check performed: `CX-03` appears **nowhere else in the plugin**. The only related plugin
symbol is the signal string `"light_low_risk"` at `leadv2-cost-estimate.sh:139`, which is a
legitimate risk signal (it feeds router *input*, not the skip decision) and is **not changed**.
The CX-03 *rule itself* lives in the consuming project's `routing.yaml`, which is outside this
repo and outside the write set. The consumer of `model=skip` on the review step is the lead
following phases.md prose — so removing the prose is the complete plugin-side fix. If a project's
`routing.yaml` still emits `model=skip`, the plugin contract now says to ignore it. This satisfies
R7 without touching `leadv2-router.sh` (non-goal, respected).

---

## 9. Decisions required (mission-internal conflicts — flagged, not silently resolved)

**D1 — R9 needs a file outside the declared write set. BLOCKING for R9 only.**
R9 requires editing `plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh:172` (the bare
`grep -Eq 'setsid'` allow-rule). The mission's "Write set (allowed paths ONLY)" lists no `hooks/`
path. Proposed fix, pending orchestrator approval: add
`plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh` to the write set and change :171-172 to

```bash
# g. setsid — only counts as backgrounding where setsid actually exists (absent on macOS).
[[ $_allowed -eq 0 ]] && command -v setsid >/dev/null 2>&1 \
  && printf '%s' "$_seg" | grep -Eq '(^|[[:space:]])setsid([[:space:]]|$)' && _allowed=1
```

Two defects fixed in one line: the platform gate (R9 as written) **and** the unanchored pattern —
today `grep -Eq 'setsid'` matches the substring anywhere in the segment, including inside a mission
path or a comment, so any command line merely *containing* the letters passes the guard. Anchoring
to a whole word is required for the fix to be worth shipping.
Note also `WRAPPERS` at :42 lists `setsid` as a command wrapper — that entry is correct and stays
(it strips the token when identifying the real command; it is not a backgrounding claim).
**Deployment caveat (global CLAUDE.md):** a hook fix must additionally be copied into the plugin
*cache* and the session restarted, or it never loads. `claude plugin update` no-ops for
directory-source marketplaces when content changed but the version did not.

**D2 — `cmd_advance_arm` has no class.** Its option loop (:2893-2903) accepts no `--class`, and the
guard needs one. Proposed: resolve the class from the confirmed dispatch-ledger row already looked
up at :2917-2923 (`dispatch_ledger_file` grep for `task_sig`); if the row carries no class, default
to `Standard` and journal `phase_class_defaulted task=<sig8>`. Do **not** add `--class` to
`advance-arm` unless the ledger genuinely lacks it — a new required flag breaks
product-close.sh:1021.

**D3 — `steps:` execution scope.** c4 §4 defines ten hook points; this lane's write set only
touches code at `plan.post`, `review.pre/post` and `close.pre`. Design position taken (§3.4):
validate all ten at parse, execute only the reachable ones, leave `deploy`/`verify`/`e2e` on
today's per-file overrides per the c4 back-compat clause. Flagging in case the orchestrator reads
R6 as requiring full execution wiring — that would pull `leadv2-deploy-merge.sh` and
`leadv2-e2e-entrypoint.sh` into the write set.

---

## 10. Risks

| Risk | Mitigation |
|---|---|
| Guard becomes a rubber stamp (record with no artifact) | proof is artifact + sha256 + content assertion; `assert` re-hashes on every call, never trusts the record |
| False-RED on lanes whose phases really ran | ships at `warn`; product-close becomes a *recorder* in this same lane, before any flip; grandfather stamp (§6) |
| `--phase-waiver` becomes the new bypass | `waivers_allowed` is project-declared and founder-owned; `review`/`close` hard-excluded in plugin code before the file is even read; every waiver journals + surfaces |
| Two disagreeing truths about one lane | `phases.d/` is the only truth; `lane_phase()` reads it; active.yaml/pulse.json written by the same script, after the record |
| `status: running` outliving the worker (this incident's exact shape) | corroborated against `LANE_LIVENESS_BIN` by handle; never mtime, never directory existence |
| **New lie: rendering "stalled" when the probe merely failed** | probe error/timeout ⇒ UNKNOWN ⇒ render plain phase. Only an affirmative DEAD verdict renders `(stalled, …)` |
| Statusline latency from N liveness probes | one probe per lane per render, memoized, `timeout=3`; records are flat files in a directory the surface already stats (`close_dir_mtime`) |
| Concurrent writes to `phases.d/` (dispatch + product-close) | one file per phase, disjoint phase sets per writer, `mktemp`+`mv -f` atomic rename — no `flock` |
| active.yaml registration double-writes rows | D2/§7: idempotency must be verified in `leadv2_active_register` before the call is added |
| Malformed `phases.yaml` silently disabling the gate | parse error ⇒ exit 4 ⇒ guard refuses in **every** mode, including `0`; journals `phase_precondition_config_error` |
| Env-var drift | all new vars `LEADV2_*`: `LEADV2_REQUIRE_PHASES`, `LEADV2_PHASE_RECORD_BIN`. No `LEAD_V2_*` form. Verified: neither name exists in the tree today |
| Stale lane base makes the diff unreadable | mandated first action: `git fetch origin && git rebase origin/main`, record the SHA (a `--ff-only` merge fails once the lane has commits — this bit lane 40241035) |

---

## 11. Tests (`plugins/leadv2/scripts/tests/`, registered in `run-core-offline.sh`)

All offline, fixture-driven, no live lane, no network.

1. **`test-phase-record.sh`** — record/assert/show round-trip; `mkdir -p` on a lane with no
   `docs/handoff/<id>/`; atomic-rename leaves no `.tmp` behind; concurrent `record` of two different
   phases produces two intact files; `n/a` and `waived` require `--reason`.
2. **`test-phase-precondition.sh`** — the guard matrix:
   - Standard dispatch, no plan/gate1 record, `LEADV2_REQUIRE_PHASES` unset ⇒ journal contains
     `phase_precondition_warn … missing=plan,gate1`, dispatch proceeds.
   - Same call with `LEADV2_REQUIRE_PHASES=1` ⇒ refused, journal `phase_precondition_refused`,
     no spawn.
   - `LEADV2_REQUIRE_PHASES=0` ⇒ no journal line, no subprocess, behaviour identical to baseline.
   - `--phase-waiver review=anything` ⇒ refused in all four classes.
   - `--phase-waiver close=anything` ⇒ refused in all four classes.
   - `--phase-waiver plan=<reason>` with `plan` in `waivers_allowed` ⇒ accepted;
     `phases.d/plan.yaml` has `status: waived` + the reason; journal `phase_waived`.
   - `--phase-waiver plan=<reason>` with `plan` **not** in `waivers_allowed` ⇒ refused.
   - `--phase-waiver plan=` (empty reason) ⇒ exit 4.
   - `phases.yaml` with `class_overrides.Light.remove: [review]` ⇒ exit 4, message names the key.
   - `phases.yaml` with `version: 2` ⇒ exit 4.
   - `phases.yaml` with `class_overrides.Light.mandatory: [e2e]` ⇒ Light now requires e2e.
   - `cmd_advance_arm` path gets the same guard (regression: it spawns a worker too).
3. **`test-lane-phase-render.sh`** — pure fixture test against `lane_phase()`:
   - `status: running`, empty `ended_at`, stub `LANE_LIVENESS_BIN` reporting dead ⇒
     `review (stalled, started …)`.
   - Same record, stub reporting alive ⇒ `review`.
   - Same record, stub exiting non-zero / hanging past timeout ⇒ `review` (**never** `stalled`).
   - No `phases.d/` ⇒ `~review` (legacy inference, visibly prefixed).
   - All records done ⇒ `close (done)`.
   - Two `running` records ⇒ the newer `started_at` wins.
4. **Regression:** with no `phases.yaml` present and `LEADV2_REQUIRE_PHASES=0`, the full existing
   suite is green from the freshly-rebased base. `run-core-offline.sh` is the registry (128 files in
   `scripts/tests/`; it is the only thing referencing suite names) — new suites go in it.

---

## 12. Out of scope (implementer: ignore these)

Supervisor/fanout re-enablement · arm selection and quota ladders · `context.yaml` schema changes ·
adopting the orphan `.claude/leadv2-overrides/gate1.sh` (zero plugin readers) · any edit to
`leadv2-router.sh` or any `routing.yaml` · `leadv2-cost-estimate.sh` · flipping
`LEADV2_REQUIRE_PHASES=1` (that is `SD-PHASE-ENFORCE-01`) · modifying `leadv2-backlog-pump.sh` ·
anything in persona-engine · execution wiring for `deploy.main`/`verify.main`/`e2e.main` steps
(D3) · deleting `_stamp_active_phase` · board or plan edits.

---

## 13. Constraint checklist

1. **Env var naming** — `LEADV2_REQUIRE_PHASES`, `LEADV2_PHASE_RECORD_BIN`. Both `LEADV2_*`.
   Verified neither exists in the tree today; no `LEAD_V2_*` form introduced.
2. **File paths** — every path in §1 exists on disk except `leadv2-phase-record.sh`,
   `.claude/leadv2-overrides/phases.yaml`, `phases.d/`, and the three test suites, all marked
   **(to-create)**. `plugins/leadv2/scripts/leadv2-phase8-close.sh` and
   `leadv2-dispatch-product-close.sh` verified present.
3. **`claude -p` commands** — this lane introduces none.
4. **Concurrent access** — `phases.d/` is read+written by dispatch, product-close and the surface
   concurrently. Resolved by one-file-per-phase + disjoint writer phase sets + atomic rename;
   documented in §3.1. `active.yaml` write path is unchanged and already serialized by the registry.
5. **Config contradiction** — `LEADV2_REQUIRE_PHASES` is three-valued while the three sibling flags
   (:388, :414, :420) are two-valued. Deliberate (R8) and handled explicitly: unrecognised values
   fall back to `warn` with a journal line, and `0` remains the byte-identical rollback so the
   one-flip convention still holds.

---

## acceptance

```yaml
acceptance:
  - surface: log_line
    observable: >
      The lane journal for a Standard dispatch with no plan or gate1 record shows the line
      "phase_precondition_warn task=<sig8> class=Standard missing=plan,gate1 mode=warn",
      and the lane still starts.
    authored_at: 2026-08-05T14:35:00Z
  - surface: log_line
    observable: >
      The same dispatch run with LEADV2_REQUIRE_PHASES=1 shows
      "phase_precondition_refused task=<sig8> class=Standard missing=plan,gate1 mode=1"
      and no worker_spawned line follows it.
    authored_at: 2026-08-05T14:35:00Z
  - surface: log_line
    observable: >
      A dispatch carrying --phase-waiver review=whatever prints a refusal naming review as
      non-waivable, in each of the four task classes.
    authored_at: 2026-08-05T14:35:00Z
  - surface: file_artifact
    observable: >
      After an accepted --phase-waiver plan=<reason>, the file
      docs/handoff/dispatch-<sig8>/phases.d/plan.yaml exists and reads
      "status: waived" with the founder-supplied reason on its own line.
    authored_at: 2026-08-05T14:35:00Z
  - surface: log_line
    observable: >
      A phases.yaml whose class_overrides removes a phase makes the dispatch print an error
      naming the offending key and the class, and the lane does not start.
    authored_at: 2026-08-05T14:35:00Z
  - surface: rendered_line
    observable: >
      In the status surface, a lane whose only record is review/running with an empty ended_at
      and a dead liveness probe renders as "review (stalled, started 42m ago)" instead of "review".
    authored_at: 2026-08-05T14:35:00Z
  - surface: rendered_line
    observable: >
      With no phases.yaml present and LEADV2_REQUIRE_PHASES=0, run-core-offline.sh prints its
      all-suites-passed summary line with zero failures.
    authored_at: 2026-08-05T14:35:00Z
```

Rollback: `LEADV2_REQUIRE_PHASES=0`.

LANE_WRITES: plugins/leadv2/scripts/leadv2-phase-record.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-phase8-close.sh, plugins/leadv2/scripts/leadv2-status-surface.sh, plugins/leadv2/docs/phases.md, plugins/leadv2/hooks/leadv2-block-fg-dispatch.sh, plugins/leadv2/scripts/tests/test-phase-record.sh, plugins/leadv2/scripts/tests/test-phase-precondition.sh, plugins/leadv2/scripts/tests/test-lane-phase-render.sh, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/tests/fixtures/phases/**

DELIVERABLE_COMPLETE
