# Guard blind ratios — how much of the live population each early `return 0` swallows

GUARD-BLIND-RATIO-UNMEASURED-FOR-14-01, measured 2026-09-06.

An early `return 0` inside a function that calls itself a protection is not a defect by itself:
"nothing to check" is a legitimate answer. It becomes one when **the empty input is the
population** — then the guard is inert, and if it says nothing, "I could not check" is
indistinguishable from "I checked, and it is fine". That is the defect already fixed in
`_foreign_check` (`leadv2-reply-router.sh:67`): `owner_session` is written on 8283 live question
rows and is `null` on every one of them, so the blind branch took 100% of calls, silently.

This file is the ratio for the other 15 sites, from the second-pass census (64 candidates → 16
inside self-declared protections). Every number carries the command that produced it. **Both 0%
and 100% are results. "Checked, clean" is not** — where a ratio could not be produced, the entry
says UNMEASURABLE and why.

> **Corpus correction, 2026-09-06 (the trap was found by the lead, on a different symptom).**
> Lane journals live in **two** layouts at once, and the first pass of this file read only one:
> `<repo>/docs/leadv2/tasks/dispatch-*/journal.md` (21 lanes, the pre-fix per-checkout layout named
> in `leadv2-journal.sh:87`) and `~/.claude/leadv2-state/persona-engine/tasks/*/journal.md`
> (17 lanes, where the writer puts them today — resolve it with
> `leadv2-journal.sh path <task>`, never by building the path from the repo root). Both are live:
> the repo layout's newest file was 12:28 today, the central one's 17:14. Every journal-derived
> number below has been **recounted over the union**, and the numbers in the entries are the union
> figures. Anything that builds a journal path from the repo root — a suite, a guard, or a census
> like this one — reads a real but partial corpus and cannot tell that from a complete one.

---

## `codex-task.sh:406` `_codex_quota_gate` — `[[ -z "$_threshold" ]] && return 0`

- INPUT: `_threshold` ← `_codex_quota_thresholds "$SUB" "$_cfg"` (codex-task.sh:405), whose config
  path comes from `_codex_quota_routing_yaml` → `leadv2_phase_policy_path "$_root"`, falling back
  to `$_root/.claude/ref/leadv2-routing.yaml`.
- CORPUS: the two live repo roots a lane can run from.
- CMD: `grep -nE '^\s*codex_quota_gate\s*:' <root>/.claude/ref/leadv2-phase-policy.yaml`
- RATIO: **0% from a persona-engine root** (`codex_quota_gate:` at line 137, `build_threshold_pct:
  80`, `review_threshold_pct: 95`) — **100% from a leadv2 root**, where no phase-policy file exists
  and the fallback `.claude/ref/leadv2-routing.yaml` contains the key 0 times. The gate is live for
  engine work and blind for plugin work, and the blindness is silent on that side.
- My first count of this site said "the key exists nowhere" — a false zero from searching `config/`
  directories, which is not where the resolver looks. Derived a second way (`grep -rl` across both
  project trees) before reporting.

## `deadhand_check` — `[[ -n "${path}" ]] || return 0`  (glm:1537, kimi:1377, freepool:1584)

- INPUT: `path` ← `cat "${run_dir}/.deliverable"`, one line above; the branch above it already
  returns when the file is absent.
- CORPUS: every real run directory under `~/.claude/cache/{glm,kimi,freepool}-runs/`.
- CMD: `ls ~/.claude/cache/glm-runs/*/.deliverable | wc -l` against `ls -d ~/.claude/cache/glm-runs/*/ | wc -l`
- RATIO: glm **243/265 = 92%** · kimi **83/93 = 89%** · freepool **178/183 = 97%**.
- Derived twice (`find -maxdepth 2 -name .deliverable` and the glob above); both agree exactly
  (22 / 10 / 5 runs carry the file).
- Read this as scope, not as a defect: a run with no deliverable contract has nothing for the
  dead-hand to enforce. What the number says is that the dead-hand governs ~9% of runs, so no
  claim about worker liveness may be made from its silence.

## `deadhand_check` — `[[ -z "${reason}" ]] && return 0`  (glm:1567, kimi:1407, freepool:1641)

- INPUT: `reason`, accumulated over the preceding ~30 lines from the deliverable checks.
- CORPUS: the runs that reach this line, i.e. those carrying `.deliverable` (22 / 10 / 5).
- CMD: `ls ~/.claude/cache/glm-runs/*/.no-deliverable | wc -l` (the sentinel written when `reason`
  is non-empty)
- RATIO: glm **5/22 = 23%** · kimi **3/10 = 30%** · freepool **0/5 = 0%**.
- Derived twice: the `.no-deliverable` sentinel and the `LEADV2_WORKER_NO_DELIVERABLE` line in
  `progress.log` — 17 / 7 / 5 both ways.
- This is the healthy shape: the guard fires on most of the population it can see.

## `leadv2-dispatch-code.sh:1877` `_burn_gate` — `[[ -n "${governor_line}" ]] || return 0`

- INPUT: `governor_line` ← `bash "${BURN_GOVERNOR_BIN}" verdict` (line 1876).
- CORPUS: the live governor.
- CMD: `bash plugins/leadv2/scripts/leadv2-burn-governor.sh verdict`
- RATIO: **0%** — it prints `verdict=ok burn24h=0 soft=800000000 hard=1300000000 reason=disabled`.
- Nuance worth keeping: the blind branch is not taken, and the gate still changes nothing, because
  the governor answers `reason=disabled`. A 0% blind ratio is not the same as an effective guard.

## `leadv2-dispatch-code.sh:4158` `_lane_writes_guard` — `[[ -z "${missing}" ]] && return 0`

- INPUT: `missing` ← `leadv2_writeset_missing "${writes}"` (line 4184).
- CORPUS: 38 lane journals across both layouts (21 in the repo, 17 in the central state root).
- CMD: `grep -rhoE 'writeset_[a-z_]+' dispatch-*/journal.md | sort | uniq -c`
- RATIO: the line is not reached at all in **17 of the 21 repo-layout lanes (81%)** — the gate exits earlier with
  `mission_writeset_gate_disabled … reason=REQUIRE_MISSION_WRITESET=0 note=no_write_scope_check_ran`.
  The ratio of the `missing`-empty branch itself is **UNMEASURABLE: only the refusal path emits, so
  a pass leaves no record.**
- This site is the counter-example the whole row should be read against: it self-disables on 81% of
  lanes **and says so, in the journal, naming the variable that disabled it**. That is exactly the
  shape the `_foreign_check` fix adds. The pattern already exists in this codebase; it is just not
  applied uniformly.

## `leadv2-dispatch-product-close.sh:1926,2195` `pc_precheck_writes` — `[[ -n "${WRITES_CSV:-}" ]] || return 0`

- INPUT: `WRITES_CSV`, the lane's declared write set.
- CORPUS: both layouts — 38 lane journals, 289 `product_close` events.
- CMD: `grep -rlE 'writes=[^ <0]' <both roots>/*/journal.md | wc -l`  → 9 of 38
- RATIO: **29/38 lanes = 76%** never name a non-empty write set, so the precheck (and with it the
  undiffable/scope-writes computation it exists to perform) is skipped for them. Corroborated from
  the other end: `undiffable` appears twice in all 289 closes.
- Unlike `protection_derived`, which resolves an empty write set to `writes_protected=1` and errs
  toward protection, this one resolves it to "return 0, compute nothing", silently.

## `leadv2-dispatch-product-close.sh:2034` `pc_stop_gate_autocommit` — `[[ -n "${_PC_SCOPE_WRITES_CSV:-}" ]] || return 0`

- INPUT: `_PC_SCOPE_WRITES_CSV`, set only by `pc_precheck_writes` above.
- CORPUS: both layouts, 289 `product_close` events.
- CMD: `grep -rh 'stop_gate' <both roots>/*/journal.md | wc -l`  → 0
- RATIO: **289/289 = 100%.** The function emits `stop_gate_autocommit`,
  `stop_gate_autocommit_failed` and `stop_gate_skipped_foreign_repo` on its working paths (verified
  in the source, so the zero is not a pattern that cannot match), and none of the four strings
  occurs anywhere in the corpus. The stop gate has never run to completion in these lanes.

## `leadv2-dispatch-product-close.sh:2055` `pc_stop_gate_autocommit` — `[[ -n "${_sg_lane_root}" ]] || return 0`

- RATIO: **UNMEASURABLE: unreachable in this corpus** — the guard 20 lines above short-circuits on
  100% of the closes, so this branch has no live calls to have a ratio over.

## `lib/leadv2-freepool-gate.sh:104,106` `check_pin_drift` — `[[ -n "${pinned}" ]]` / `[[ -n "${live}" ]]`

- INPUT: `pinned` ← `sed -n 's/^pinned_commit: *//p' "${FREEPOOL_PIN_FILE}"`;
  `live` ← `git -C "${FREEPOOL_INSTALL_DIR}" rev-parse HEAD`.
- CORPUS: the live pin file `plugins/leadv2/config/freepool-arm.yaml` and the install checkout
  `~/tools/free-claude-code`.
- CMD: `grep -c '^pinned_commit:' plugins/leadv2/config/freepool-arm.yaml` (=1) and
  `git -C ~/tools/free-claude-code rev-parse HEAD` (=6b3f16f41d4b…)
- RATIO: **0%** for both. Both inputs are present, so drift is genuinely checked.

---

## Tally

- **100% blind:** 2 — `pc_stop_gate_autocommit` (`_PC_SCOPE_WRITES_CSV`), and `_codex_quota_gate`
  when the lane runs from a leadv2 root.
- **High but legitimate scope:** 3 — the `deadhand_check` path branches (89–97%), which measure how
  many runs carry a deliverable contract at all.
- **0% blind:** 5 — `_burn_gate`, both `check_pin_drift` branches, `_codex_quota_gate` from a
  persona-engine root, and freepool's `reason` branch.
- **Middling, healthy:** 2 — glm/kimi `reason` (23%, 30%).
- **Announced self-disable, 81%:** 1 — `_lane_writes_guard`, which is the model the others should
  follow.
- **UNMEASURABLE:** 2 — `_lane_writes_guard`'s own `missing` branch (no marker on the pass path)
  and `pc_stop_gate_autocommit:2055` (unreachable behind a 100% short-circuit).

Nothing here is reported as "checked, clean".
