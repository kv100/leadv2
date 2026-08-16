# PLUGIN-REVIEW-ARMS-01 — architect prepass

## 0. Headline: the mission's stated cause is wrong; the real one is worse and single

The mission says the pool is empty **because this repo has no `routing.yaml`**. That premise does
not survive contact with the code. What is actually true:

1. The path is not `routing.yaml` but `${ROOT}/.claude/ref/leadv2-routing.yaml` (tenant tier).
2. Its absence has been self-healed since 2026-08-06 (`0445ca0`, ARM-LADDER-…-01 P3) — the
   dispatcher falls back to `${SCRIPT_DIR}/../config/leadv2-routing.yaml`, and the resolver has
   its own Python-side fallback since 2026-08-07 (`717b16f`).
3. `plugins/leadv2/config/leadv2-routing.yaml` **exists in this repo** (8086 bytes).
4. Running the shipped resolver right now, with a deliberately nonexistent routing yaml, returns a
   real author-excluding pool:

```
$ python3 plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py \
    --routing-yaml /nonexistent.yaml --job review --base-arm codex \
    --review-pool --author glm --signals '{"protected_path":true,"safety_touched":true}'
reviewer=opus
pool=codex:unknown:,glm:author:,kimi:excluded:safety,opus:ok:13,sonnet:ok:13
refusal=
```

So the shipped code, run from the plugin tree, already does the thing the mission asks us to
build. Author-exclusion already works (`glm:author:`). Nothing about routing config is missing.

### What actually happened to `4c9ddb05`

`~/Projects/leadv2/.claude/scripts/` is a **stale real-copy** of the plugin script tree (files
dated Jul 17 – Aug 4), not the per-file symlinks the global shared-trees policy mandates. The
`4c9ddb05` dispatch ran out of that tree. Every one of the three reported symptoms is a direct
consequence, and there is exactly one root cause:

| Symptom in `docs/leadv2/tasks/dispatch-4c9ddb05/journal.md` | Mechanism |
|---|---|
| `phase_precondition_warn … reason=unexpected_rc value=127` | `.claude/scripts/leadv2-phase-record.sh` does not exist (it *does* exist at `plugins/leadv2/scripts/leadv2-phase-record.sh`). `PHASE_RECORD_BIN` → 127 → warn-mode passthrough. |
| `routing_config_degraded … reason=no_routing_yaml_project_or_plugin` + `route_resolved … router=v1 rule=none reason=no_routing_yaml` | `SCRIPT_DIR=.claude/scripts` ⇒ the P3 fallback probes `.claude/scripts/../config/leadv2-routing.yaml` = `.claude/config/leadv2-routing.yaml`, which does not exist. `ROUTING_CONFIG_ABSENT=1` ⇒ v1 legacy hardcoded ladder. |
| `review_gate … status=no_reviewer … refusal=all_review_arms_unavailable pool=` | The string `status: no_reviewer` exists in **no shipped writer** (canonical and plugin-cache both emit `status: unreviewed` with 8 fields). It exists twice in `.claude/scripts/leadv2-dispatch-product-close.sh` — the pre-2026-07-30 writer. Confirming: `.claude/scripts/leadv2-review-run.sh` (the review engine added 2026-08-14) is absent there, and `.claude/scripts/lib/leadv2-glm-policy-resolve.py` is the Aug-1 build, predating the `717b16f` self-heal. |

This is the same defect class already logged as an open thread
(GATE-WRONG-ROOT-FALSE-DEAD-01 C3 / `.claude/scripts/tests/` copies). C3 fixed the *gate*'s
tree-preference; it did not fix the *dispatch* path.

**Therefore the design below is not "add a reviewer pool". It is: make the plugin repo dispatch
from the plugin tree, make a stale tree impossible to run silently, and make an unresolvable pool
loud. The reviewer pool then already exists.**

---

## 1. Layers affected

| Layer | Files | Nature of change |
|---|---|---|
| Repo-local stale tree | `.claude/scripts/…`, `.claude/config` | Replace copies with symlinks (narrow: dispatch-path files only) |
| Dispatcher | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | Provenance self-check → loud refusal |
| Review engine | `plugins/leadv2/scripts/leadv2-review-run.sh` | Unreviewed artifact gains the full 8-field diagnostic shape |
| Tenant config | `.claude/ref/leadv2-routing.yaml` (to-create) | Bash/markdown-appropriate protected paths + arm mix |
| Tests | `plugins/leadv2/scripts/tests/test-plugin-review-arms.sh` (to-create) | Regression pins for all four |
| Report | `docs/missions/PLUGIN-REVIEW-ARMS-01.report.md` (to-create) | Evidence |

---

## 2. Data flow (numbered)

Post-change dispatch of a lane inside `~/Projects/leadv2`:

1. Lead invokes the dispatcher. Whichever path it is invoked by, step 2 runs.
2. **(NEW)** `leadv2-dispatch-code.sh` computes `SCRIPT_DIR`. If `SCRIPT_DIR` does not end in
   `plugins/leadv2/scripts` **and** a sibling plugin tree is discoverable
   (`${PROJECT_ROOT}/plugins/leadv2/scripts/leadv2-dispatch-code.sh`), it emits
   `dispatch_refused reason=stale_script_tree from=<SCRIPT_DIR> canonical=<path>` to the journal
   and **exits non-zero**. No blind proceed. (Gate is *not* disabled — this adds a refusal, it
   removes none.)
3. `ROUTING_YAML` resolves: `${PROJECT_ROOT}/.claude/ref/leadv2-routing.yaml` (now present, step
   §4) → hit on the first tier. `ROUTING_CONFIG_ABSENT=0`. Router v2 path, real ladder.
4. `PHASE_RECORD_BIN=${SCRIPT_DIR}/leadv2-phase-record.sh` now resolves. `assert` returns 0 or 3
   with a real `missing=` list — never 127.
5. Build arm resolves (e.g. `glm`), lane runs, diff lands.
6. Close gate: `leadv2-review-run.sh` → `resolve_review_pool_call()` →
   `leadv2-glm-policy-resolve.py --review-pool --author glm --signals <from review-signals lib,
   matched against the tenant yaml's protected-path list>`.
7. Resolver returns `reviewer=opus`, `pool=codex:…,glm:author:,kimi:excluded:safety,opus:ok:N,sonnet:ok:N`.
   `glm` is present in the pool string but tagged `:author:` and never selectable.
8. Reviewer arm runs, emits `REVIEW_VERDICT:` / `REVIEW_FINDINGS:` / `FINDING:` lines; gate writes
   `docs/handoff/dispatch-<id>/review-gate.md` with a verdict.
9. **(NEW)** If step 7 yields no reviewer, the artifact carries `refusal:`, `resolver_rc:`,
   `resolver_stderr:` and `merge_blocked: true` — not a bare `pool:` line.

---

## 3. Interface contracts

### 3.1 `review-gate.md` — unreviewed shape (review-run.sh must match the lane writer)

Today `leadv2-review-run.sh:456-463` writes 5 fields; `_pc_write_unreviewed()`
(`leadv2-dispatch-product-close.sh:238-246`) writes 8. Two writers, two shapes — the engine path
is the lossy one, and the engine path is the future default. Unify on the lane writer's shape:

| Field | Source | Required |
|---|---|---|
| `status: unreviewed` | literal | yes |
| `reason: all_arms_unavailable` | literal | yes |
| `author:` | `${AUTHOR}` | yes |
| `pool:` | resolver `pool=` (`-` if empty) | yes |
| `tried:` | arms attempted (`-` if none) | yes |
| `refusal:` | resolver `refusal=` or `all_arms_unavailable` | **yes — currently missing** |
| `resolver_rc:` | resolver exit code (`-` if unknown) | **yes — currently missing** |
| `resolver_stderr:` | first stderr line (`-` if empty) | **yes — currently missing** |
| `merge_blocked: true` | literal | **yes — currently missing** |

`resolve_review_pool_call()` in `leadv2-review-run.sh:118` sends resolver stderr to `/dev/null`
and does not capture rc. It must capture both (mktemp + `$?`) and re-emit them as
`resolver_rc=` / `resolver_stderr=` lines, exactly as the lane's copy already does. This is the
"fail loudly, not silently" half of the mission — the reason is *already computed*, it is simply
discarded before it reaches the artifact.

### 3.2 Dispatcher provenance refusal

```
exit 4
journal: dispatch_refused reason=stale_script_tree task=<sig8> from=<SCRIPT_DIR> canonical=<path>
stderr:  dispatch refused: running from a stale script copy at <SCRIPT_DIR>.
         remedy: ln -sf <canonical>/<file> <SCRIPT_DIR>/<file>
```

Escape hatch for the transition: `LEADV2_ALLOW_STALE_SCRIPT_TREE=1` downgrades to a journal warn.
Default is refuse. Do **not** default it open — a default-open tripwire is what produced this bug.

### 3.3 Tenant routing yaml — the plugin-repo-appropriate delta

`.claude/ref/leadv2-routing.yaml` is a copy of `plugins/leadv2/config/leadv2-routing.yaml` with
two blocks adjusted for a bash+markdown repo (implementer: preserve every other key verbatim —
this file is parsed by both a regex extractor and `yaml.safe_load`, so key names and the
two-space `glm_policy:` indentation are load-bearing).

**Protected paths** (this repo has no DB, no auth, no payments; what breaks every consuming repo
simultaneously is the dispatch/gate/hook surface):

```
plugins/leadv2/scripts/**
plugins/leadv2/hooks/**
plugins/leadv2/config/**
plugins/leadv2/scripts/lib/**
.claude/settings.json
```

Deliberately **not** protected: `docs/**`, `plugins/leadv2/skills/**/*.md` (markdown-only edits do
not warrant a safety-tier review).

**Arm mix.** Keep `codex > glm > opus > sonnet` ordering and both thresholds unchanged. `kimi` is
already `excluded:safety` under a protected-path signal and stays excluded — do not add it. `glm`
stays a legitimate review arm at its own 90% band. Rationale: the resolver's live-quota ordering
is the thing that makes the pool robust; hand-pinning an order here would make the plugin repo
diverge from every tenant it ships to, which is the opposite of what this repo should model.

---

## 4. Migration plan (additive, ordered, each step independently revertible)

| # | Step | Revert |
|---|---|---|
| 1 | Create `.claude/ref/leadv2-routing.yaml` (tenant tier). Additive: today the tier is absent, so nothing regresses. | `rm` |
| 2 | `ln -s ../../plugins/leadv2/config .claude/config` — makes `SCRIPT_DIR/../config` resolve for *any* script under `.claude/scripts`, including ones we do not convert. Cheap belt. | `rm` |
| 3 | Convert the dispatch-path files under `.claude/scripts/` to per-file symlinks into `plugins/leadv2/scripts/`: `leadv2-dispatch-code.sh`, `leadv2-dispatch-product-close.sh`, `lib/leadv2-glm-policy-resolve.py`, `lib/leadv2-review-signals.sh`; and **create** `leadv2-phase-record.sh` + `leadv2-review-run.sh` as new symlinks. | restore from `git show` / plugin tree |
| 4 | Add the provenance refusal to `plugins/leadv2/scripts/leadv2-dispatch-code.sh`. Must land **after** step 3, or the next dispatch refuses before it can be fixed. | env flag or revert |
| 5 | Widen `leadv2-review-run.sh`'s unreviewed writer + stderr/rc capture. | revert |
| 6 | Add `plugins/leadv2/scripts/tests/test-plugin-review-arms.sh`. | — |
| 7 | Throwaway lane dispatch → evidence → report. | — |

Ordering constraint 3-before-4 is hard. Flag it in the lane mission.

---

## 5. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **Step 4 before step 3 bricks dispatch in this repo.** The refusal fires from the stale copy's caller and the operator cannot dispatch a lane to fix it. | Hard ordering (§4). `LEADV2_ALLOW_STALE_SCRIPT_TREE=1` is the manual unbrick. Implementer must verify a dispatch succeeds after step 3 *before* writing step 4. |
| R2 | `.claude/scripts/` has 219 entries; other tooling may read the stale copies we convert (a symlinked file is byte-different from the Aug-1 copy it replaces). | Convert only the 6 dispatch-path files named in §4.3. Full de-duplication is **out of scope** — it is already an open thread with its own blast-radius assessment. |
| R3 | The provenance check misfires in a git worktree (`.claude/worktrees/<id>/plugins/leadv2/scripts/…`), where `SCRIPT_DIR` legitimately is not the main repo's plugin tree. | Match on the **suffix** `plugins/leadv2/scripts` only, never on an absolute prefix. A worktree copy passes; `.claude/scripts` fails. Test both. |
| R4 | The plugin **cache** at `~/.claude/plugins/local/leadv2/…` is a third real copy (verified byte-identical to canonical today, but it drifts by policy — `claude plugin update` no-ops on unchanged version). A cache copy is a *legitimate* run tree and must not be refused. | Suffix match (R3) accepts it. Do not add a "must be under `$PROJECT_ROOT`" clause. |
| R5 | `LEADV2_LEAD_GUARD=1` blocks the `Edit` tool on canonical plugin `.sh`/`.py`. Steps 4 and 5 both edit canonical `.sh`. | Implementer fixes forward via a `/tmp` Python patcher invoked through `Bash`, per the known workaround. Budget for it. |
| R6 | Once phase-record actually runs (step 3), `assert` may return **3** with a genuine `missing=plan,gate1,…` list — the warn text will look unchanged, and someone will conclude the fix did nothing. | The distinguishing evidence is the *absence* of `reason=unexpected_rc value=127`. Pin that in the test and call it out in the report. **This is the second finding: it is load-bearing, not noise — do not silence it.** No phase has ever been recorded for plugin work. |
| R7 | Author-exclusion is claimed, not proven, for the *live* config. | The test must assert on the pool string for `--author glm` (`glm:author:`, `reviewer!=glm`) **and** for `--author opus`, against `.claude/ref/leadv2-routing.yaml` specifically. |
| R8 | Two writers of `review-gate.md` (lane inline + engine) drift again. | The test asserts the field set of both writers is identical. |
| R9 | Live-quota dependence: `codex:unknown:` in today's probe means a real dispatch may resolve a different reviewer than the test's. | Evidence requirement is "a real reviewer resolved and a verdict produced", not "opus specifically". Do not pin the arm identity in the acceptance. |

### Mandatory constraint checklist

1. **Env vars** — new names `LEADV2_ALLOW_STALE_SCRIPT_TREE` follow the `LEADV2_*` convention; no
   `LEAD_V2_*` drift. No `.claude/settings.json` `env` block change needed (default is refuse).
2. **Paths** — every path in §4 verified on disk except those marked `(to-create)`.
   `.claude/scripts/leadv2-review-run.sh` and `.claude/scripts/leadv2-phase-record.sh` confirmed
   **absent**; `.claude/config` confirmed absent; `plugins/leadv2/config/leadv2-routing.yaml` and
   `plugins/leadv2/scripts/leadv2-phase-record.sh` confirmed present.
3. **`claude -p`** — this design introduces no new `claude -p` invocation.
4. **Concurrent access** — step 3 rewrites files that a concurrent lane may be executing. Bash
   reads a script incrementally; replacing the inode under a running process is safe (the open fd
   keeps the old inode), but a *new* dispatch mid-conversion could read a half-written link. Do
   the conversion when no lane is active, and use `ln -sfn` (atomic rename), never `rm` + `ln`.
5. **Config contradiction** — `LEADV2_ROUTING_YAML` (explicit override) still wins over the new
   tenant file at every call site checked (`leadv2-review-run.sh:94`,
   `leadv2-router-v2.sh:70`, `leadv2-dispatch-code.sh:304`). No contradiction introduced.

---

## 6. Out of scope

- Full de-duplication of `.claude/scripts/` (213 other files). Existing open thread.
- Any change to `plugins/leadv2/config/leadv2-routing.yaml` — the shipped default is correct.
- Adding, removing, or reordering reviewer arms in the resolver.
- Changing `phase_precondition` mode from `warn` to `1` (enforce). Recording phases for plugin
  work is a follow-up finding, not this lane's build.
- Retrofitting `4c9ddb05` with a review.
- Anything in a consuming repo.

---

## 7. Acceptance

```yaml
acceptance:
  - surface: file_artifact
    observable: >
      docs/handoff/dispatch-<throwaway-id>/review-gate.md, opened by a human, shows a
      status line that is not "no_reviewer", names a reviewer arm that is not the
      author named on its own author line, and carries a REVIEW_VERDICT of PASS,
      PASS_WITH_NITS or FAIL.
    authored_at: 2026-08-15T00:01:53Z
  - surface: log_line
    observable: >
      The throwaway lane's docs/leadv2/tasks/dispatch-<id>/journal.md contains no line
      reading "routing_config_degraded", and no line containing
      "reason=unexpected_rc value=127".
    authored_at: 2026-08-15T00:01:53Z
  - surface: file_artifact
    observable: >
      A review-gate.md written when no reviewer can be resolved shows, on separate
      lines a human can read without opening any script, a refusal reason, a resolver
      exit code, the resolver's stderr, and "merge_blocked: true" — never a bare
      empty "pool:" as its last informative line.
    authored_at: 2026-08-15T00:01:53Z
  - surface: file_artifact
    observable: >
      docs/missions/PLUGIN-REVIEW-ARMS-01.report.md states, in prose a human can check,
      that the pool resolved with the diff's author present but marked as author and
      not chosen as reviewer, and quotes the pool line showing it.
    authored_at: 2026-08-15T00:01:53Z
```

---

LANE_WRITES: .claude/ref/leadv2-routing.yaml, .claude/config, .claude/scripts/leadv2-dispatch-code.sh, .claude/scripts/leadv2-dispatch-product-close.sh, .claude/scripts/leadv2-review-run.sh, .claude/scripts/leadv2-phase-record.sh, .claude/scripts/lib/leadv2-glm-policy-resolve.py, .claude/scripts/lib/leadv2-review-signals.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/tests/test-plugin-review-arms.sh, docs/missions/PLUGIN-REVIEW-ARMS-01.report.md

DELIVERABLE_COMPLETE
