# ARM-LADDER-KIMI-RESURRECTED-01 — architect prepass (fix round 1)

Repo: `/Users/kostiantyn.vlasenko/Projects/leadv2` (plugin repo, single source).
Base: `1b8692e`. Scope: C1 (blocking), H1, H2, M1, M2, L1 from
`persona-engine/docs/handoff/arm-ladder-review-2026-08-06/review-r1.md`.

---

## 0. Verified ground truth (read at `1b8692e`, not assumed)

| Claim | Status | Evidence |
|---|---|---|
| Ladder loader already honours `dispatch: false` | **TRUE** | `leadv2-dispatch-code.sh:840-842` — `if e.get("dispatch", True) is False: continue` |
| `kimi` in yaml ladder with no `dispatch: false` | TRUE | `plugins/leadv2/config/leadv2-routing.yaml:118-122` |
| Legacy hardcoded fallback contains kimi | TRUE | `leadv2-dispatch-code.sh:854-856` |
| Unknown arm → full ladder, no journal line | TRUE | `leadv2-dispatch-code.sh:874` |
| `exit 1` guard unreachable | TRUE | `leadv2-dispatch-code.sh:2976`, given :854-856 + :874 |
| `_candidate_chain_for_arm` dead in prod | **PARTIALLY FALSE** | zero *production* callers, but `tests/test-dispatch-arm-vocabulary.sh:115-122` `sed`-extracts and calls it. Deleting it breaks that suite. |
| `_record_quota_lockout` zero prod callers | TRUE | grep: only its own definition + the p1 test file |
| `_quota_locked` returns 0 for "not locked" | TRUE | `:894-905`; single call site `:3001` reads it correctly but inverted-to-name |
| `_build_candidate_chain` has **two** call sites | **NEW — not in review** | `:2975` (primary) and `:3203` (glm-lock-busy re-resolve). Any signature change must cover both. |

**Consequence for C1:** the loader needs no change. The fix is config-only for the
yaml path — exactly the "never hardcode an arm out of routing" rule the mission demands.

---

## 1. Design — change by change

### C1 — retire kimi as a build/dispatch arm (config-expressed)

**C1.a — `plugins/leadv2/config/leadv2-routing.yaml`**
Add `dispatch: false` to the `kimi` entry (do NOT delete the entry — keeping it
documents the retirement and keeps `_arm_provider` able to name the provider if a
stale tenant yaml ever hands back `arm=kimi`). Add a comment naming
`3398d11` / DISPATCH-KIMI-ARM-MISMATCH-01 and the founder order (2026-08-04) so the
next merge conflict resolves the right way.

**C1.b — `leadv2-dispatch-code.sh:854-856`**
`_LADDER_IDS=(glm codex sonnet)` / `_LADDER_PROVIDERS=(glm codex anthropic)`.
Add a comment: this list is the degraded-mode mirror of `DISPATCHABLE_BUILD_ARMS`
in `lib/leadv2-glm-policy-resolve.py:46` and is asserted equal by
`tests/test-arm-ladder-vocabulary-drift.sh`. (L1 is satisfied by construction: a
hardcoded list has no `dispatch:` field, so the two paths agree only if the list is
kept equal to the dispatchable set — which the new test enforces.)

**C1.c — Test 1 in `tests/test-routing-enforcement-p1.sh:303-330`**
Currently asserts `candidate_chain arms == "glm,kimi"`. Rewrite to keep what it was
genuinely testing (ladder ORDER comes from the yaml, not from a hardcoded order)
while asserting kimi's absence. New fixture ladder: `codex, sonnet, glm` (kimi
present but `dispatch: false`), resolver picks glm → expected chain `glm` only, and
the assertion additionally requires `arms` to not contain `kimi`.
Rename the test to `ladder order from yaml, dispatch:false entries excluded`.

**C1.d — structural drift guard: NEW file
`plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh`**
Three cases, all offline, no dispatch invocation:
1. `_LADDER_IDS` legacy fallback (extracted via `sed -n '/^_load_dispatch_ladder()/,/^}$/p'`,
   forced down the fallback branch by pointing `ROUTING_YAML` at `/dev/null`) ⊆
   `DISPATCHABLE_BUILD_ARMS` read out of `leadv2-glm-policy-resolve.py`
   (`python3 -c "import ...; print(sorted(DISPATCHABLE_BUILD_ARMS))"` via importlib,
   NOT a regex over source).
2. Same subset assertion for the yaml-loaded ladder against the **production**
   `plugins/leadv2/config/leadv2-routing.yaml` — every entry the loader yields must
   be in `DISPATCHABLE_BUILD_ARMS`. This is the assertion that fails at `1b8692e`.
3. `kimi ∉` both lists, asserted by name, with a comment tying it to the founder order.

**C1.e — C1 dry-run proof (mission's "show a dispatch dry-run" requirement)**
The dispatch script already emits `candidate_chain task=… arms=…` at `:3080`. The
proof artifact is a run against the **production** routing yaml with `arm=glm`, GLM
faked to refuse, whose journal line reads `arms=glm,codex,sonnet`. Implemented as
Test 8 in the p1 suite (see §1.E below), not as a hand-run command.

---

### H1 — unknown arm ⇒ sonnet-only + journalled mismatch

Change `_build_candidate_chain()` (`:862-875`) to take `<arm> <sig8>` and replace the
terminal `|| candidate_arms=("${_LADDER_IDS[@]}")` with:

```
if [[ "${_found}" != "1" ]]; then
  candidate_arms=(sonnet)
  emit decision "arm_vocabulary_mismatch by=router arm=${_arm} fallback=sonnet task=${_sig8} reason=launcher_unknown_arm"
  log_err "arm_vocabulary_mismatch: unknown arm=${_arm} for task=${_sig8}, falling back to sonnet"
fi
```

Both call sites pass sig8: `:2975` → `_build_candidate_chain "${arm}" "${sig8}"`,
`:3203` → same. (The `:3203` site is the review's blind spot; missing it leaves the
re-resolve path emitting no mismatch line.)

**Dead-code resolution — one live fallback, zero dead ones:**
- Delete the `exit 1` guard at `:2976`. It is unreachable and, worse, is now
  *wrong*: the new behaviour is a safe fallback, not a fatal.
- Do **not** delete `_candidate_chain_for_arm` in this round. It has a live consumer:
  `tests/test-dispatch-arm-vocabulary.sh:115-122` extracts and calls it. Instead,
  demote it to an explicitly-labelled test fixture is the wrong shape — the correct
  move is to **repoint that test at `_build_candidate_chain`** (it now has identical
  unknown-arm semantics) and delete `_candidate_chain_for_arm` in the same commit.
  That keeps the mission's "do not leave two dead fallbacks" contract satisfiable.
  `tests/test-dispatch-arm-vocabulary.sh` cases 2/3/4 must be updated to source
  `_load_dispatch_ladder` + `_build_candidate_chain` and to expect ladder-derived
  chains (`glm → glm,codex,sonnet`; `codex → codex,sonnet`; `sonnet → sonnet`;
  `kimi → sonnet` + mismatch line). Case 1 (end-to-end, arm=kimi → sonnet +
  `arm_vocabulary_mismatch`) needs no change and becomes the regression anchor.

**Does H1 break `_apply_kimi_admission`?** No. With kimi out of the ladder,
`_apply_kimi_admission` becomes a no-op filter on the v1 path but stays live on the
**router-v2** path (`:2971`), where `candidate_arms` comes from `v2_eligible`, not the
ladder. Leave it. Out of scope: whether router-v2's `v2_eligible` can still emit kimi
— flagged in §5.

---

### H2 — quota-lockout write side

**Decision: wire it, do not delete.** A read-only precheck against a store nobody
writes is the defect; and there is a real, already-parsed signal to wire it to.

Wire point: `refusal_reason()` (`:2008-2045`) is the single funnel that classifies a
launcher's non-zero exit as an admission refusal. Its returned marker vocabulary
already includes quota-shaped reasons (`quota_gate` from the GLM quota gate's
REROUTE path, `:2029-2032`; and any `LEADV2_DISPATCH_REFUSED: quota*` marker).

Add, in `_spawn_worker_body`, at each arm's refusal branch — **via one shared helper,
not four copies**:

```
_maybe_record_quota_lockout() { # <arm> <refusal_reason>
  case "${2}" in quota|quota_gate|quota_exhausted|rate_limit*) ;; *) return 0 ;; esac
  _record_quota_lockout "$(_arm_provider "${1}")" \
    "$(date -u -v+"${LEADV2_QUOTA_LOCKOUT_MINUTES:-30}"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
       || date -u -d "+${LEADV2_QUOTA_LOCKOUT_MINUTES:-30} minutes" +%Y-%m-%dT%H:%M:%SZ)" \
    "launcher_refusal:${2}"
  emit decision "quota_lockout_recorded provider=$(_arm_provider "${1}") arm=${1} reason=${2} minutes=${LEADV2_QUOTA_LOCKOUT_MINUTES:-30}"
}
```

Called from the glm (`:2072`), kimi (`:2111`), sonnet (`:2157`), codex (`:2216`)
refusal branches, immediately after their existing `emit decision "arm_refused …"`.
Note the BSD/GNU `date` split — macOS is the primary platform; the `||` covers Linux CI.

`LEADV2_QUOTA_LOCKOUT_MINUTES` is a new env var. Convention check: `LEADV2_*` prefix,
consistent with `LEADV2_QUOTA_LOCKOUT_DIR` already in the file (`:891`). No
`LEAD_V2_*` drift. Not present in `.claude/settings.json` — default-only, no settings
change required.

**Test (proves a recorded lockout changes the next dispatch's arm):**
p1 suite Test 9 — run dispatch once with a glm launcher that exits 1 + emits
`LEADV2_DISPATCH_REFUSED: quota_gate`; assert `quota_lockout_recorded provider=glm`
in the journal AND that `${LEADV2_QUOTA_LOCKOUT_DIR}/quota-lockout-glm.json` exists.
Run dispatch a second time in the same ledger dir; assert
`quota_precheck_skip model=glm provider=glm` and `worker_spawned by=router model=codex`.
That second assertion is the "changes the next dispatch's arm" proof the mission asks for.

---

### M1 — `_quota_locked` name/return inversion

**Decision: rename, do not flip.** Flipping the return touches the one call site and
leaves the same trap for anyone who greps the old name in git history. Rename to
`_provider_available()` — `0 = available, 1 = locked` then reads correctly with no
inversion. Update `:3001` to `if _provider_available "${_qpc_prov}"; then`. Update the
doc comment. Grep-verify zero other references (currently: definition + one call site).

The p1 suite's Tests 2/3/4 already exercise this behaviour end-to-end through the
journal, so they are the rename's regression cover — no new test needed for M1 alone.

---

### M2 — no routing config anywhere ⇒ degraded mode must announce itself

At `:304-311`, after the plugin-config fallback, add:

```
if [[ ! -f "${ROUTING_YAML}" ]]; then
  ROUTING_CONFIG_ABSENT=1
fi
```

and, at the point `sig8` exists and `emit` is usable (immediately before
`_load_dispatch_ladder` at `:2974`), emit once:

```
[[ "${ROUTING_CONFIG_ABSENT:-0}" == "1" ]] && \
  emit decision "routing_config_degraded task=${sig8} reason=no_routing_yaml_project_or_plugin ladder=legacy_hardcoded arms=$(IFS=,; printf '%s' "${_LADDER_IDS[*]}")"
```

(Emit AFTER `_load_dispatch_ladder` so `arms=` is populated — implementer: order matters.)

**Test:** p1 suite Test 6 — `CLAUDE_PROJECT_ROOT` = an empty temp dir AND
`LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE` (new, test-only, defaulting to the real plugin
path) pointed at a nonexistent path, so both resolution steps miss. Assert
`routing_config_degraded` in the journal and that dispatch still proceeds (rc 0,
`worker_spawned`). This requires making `:309`'s `_plugin_routing_yaml` overridable —
a two-line change, and the only way to test the branch without deleting the repo's
own config.

---

### E — no test may spawn a real provider session (mission item C1.5)

Add to `tests/test-routing-enforcement-p1.sh` a preamble guard, and mirror it into
`test-dispatch-arm-vocabulary.sh` and the new drift test:

```
# Fail-closed spawn fence: every provider bin env var is pointed at a poison
# script that exits non-zero and prints a marker. Any test that forgets to
# override one gets a loud, offline failure instead of a live billed session.
export LEADV2_DISPATCH_GLM_BIN="${TMP_ROOT}/poison-glm.sh"
export LEADV2_DISPATCH_KIMI_BIN="${TMP_ROOT}/poison-kimi.sh"
export LEADV2_DISPATCH_CODEX_BIN="${TMP_ROOT}/poison-codex.sh"
export LEADV2_DISPATCH_SONNET_BIN="${TMP_ROOT}/poison-sonnet.sh"
```

each poison script printing `POISON: real provider spawn attempted` to stderr and
exiting 99 (an rc that `refusal_reason` does NOT classify as a refusal → `spawn_failed`,
loud). Individual tests then override only the bins they intend to exercise.

**Proof it cannot spawn (Test 7):** after the full suite runs, assert
`! grep -r "POISON:" "${TMP_ROOT}"/*-out.log` and that no `~/.claude/cache/kimi-runs/`
entry newer than the suite start exists. Implementer: capture suite-start epoch, then
`find ~/.claude/cache/kimi-runs -newermt @<epoch>` must return empty.

Implementer must verify the `SONNET_BIN` env var name against the sonnet branch at
`:2140-2160` before writing it — I did not confirm that one, and a wrong name silently
un-fences that arm. If sonnet dispatches in-process rather than via a bin, fence it
with the existing architect-gate/dry-run flag instead and say so in the commit.

---

## 2. Data flow after the change (numbered)

1. `ROUTING_YAML` resolves: project `.claude/ref/leadv2-routing.yaml` → plugin
   `config/leadv2-routing.yaml` → neither ⇒ `ROUTING_CONFIG_ABSENT=1`.
2. Resolver (`leadv2-glm-policy-resolve.py`) returns `arm=<id>`, constrained by
   `DISPATCHABLE_BUILD_ARMS = {glm, codex, sonnet}`.
3. `_load_dispatch_ladder` parses `router.dispatch_ladder`, skipping every entry with
   `dispatch: false` (kimi, fable) → `_LADDER_IDS=(glm codex sonnet)`. On parse
   failure/empty → same three ids from the legacy fallback.
4. If `ROUTING_CONFIG_ABSENT` → `emit decision routing_config_degraded`.
5. `_build_candidate_chain <arm> <sig8>` → arm's position onward; unknown arm ⇒
   `(sonnet)` + `arm_vocabulary_mismatch`.
6. `codex_quota_blocked` filter → `_apply_kimi_admission` (no-op on v1 now, live on v2).
7. Quota precheck: `_provider_available $(_arm_provider arm)` per arm; skips journalled;
   all-locked ⇒ `dispatch_rolled_back reason=all_arms_quota_locked`.
8. `emit decision candidate_chain arms=…` (`:3080`) — **the observable artifact**.
9. Spawn walk; a quota-shaped refusal calls `_maybe_record_quota_lockout` → writes
   `quota-lockout-<provider>.json` → step 7 of the NEXT dispatch skips that arm.
10. glm-lock-busy re-resolve (`:3203`) re-enters at step 5 with sig8 threaded.

---

## 3. Anti-tautology matrix — every test must fail at `1b8692e`

| Test | Fails at HEAD because | Passes after |
|---|---|---|
| p1 Test 1 (rewritten) | prod ladder yields `glm,kimi` | yields `glm` |
| drift Test 1 (legacy list) | `kimi ∉ DISPATCHABLE_BUILD_ARMS` | subset holds |
| drift Test 2 (yaml ladder) | kimi has no `dispatch:false` | filtered out |
| p1 Test 8 (prod-yaml dry run) | `arms=glm,kimi,codex,sonnet` | `arms=glm,codex,sonnet` |
| arm-vocabulary case for unknown arm via `_build_candidate_chain` | returns full ladder, no mismatch line | returns `sonnet` + mismatch line |
| p1 Test 9 (lockout write→read) | `quota_lockout_recorded` never emitted | emitted; 2nd run skips glm |
| p1 Test 6 (degraded mode) | no `routing_config_degraded` line exists | emitted |
| p1 Test 7 (spawn fence) | poison bins do not exist | no POISON, no new kimi-run dir |

M1 (rename) is the one change with no new test — covered by existing Tests 2/3/4.
State that plainly in the commit message rather than inventing a tautological test.

---

## 4. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Deleting `_candidate_chain_for_arm` breaks `test-dispatch-arm-vocabulary.sh` (it `sed`-extracts the function) | Update that suite in the SAME commit; it is listed in LANE_WRITES |
| `_build_candidate_chain` signature change misses `:3203` | Explicit call-site table above; grep `_build_candidate_chain` must show exactly 2 call sites + 1 definition after the edit |
| Emitting `routing_config_degraded` before `sig8`/`emit` exist → unbound var under `set -u` | Emit at `:2974`, after `_load_dispatch_ladder`, not at `:304` |
| macOS `date -v` vs GNU `date -d` in `_maybe_record_quota_lockout` | Both forms with `||` fallback; test asserts the JSON's `locked_until_epoch > now` |
| A stale project `.claude/ref/leadv2-routing.yaml` in persona-engine still lists kimi as dispatchable | The drift test asserts the PLUGIN config only. Add a runtime belt: after `_load_dispatch_ladder`, filter `_LADDER_IDS` to ids present in `DISPATCHABLE_BUILD_ARMS` and emit `arm_dropped_not_dispatchable` per drop. **This is the tenant-yaml resurrection guard `3398d11` intended and is required, not optional.** |
| Two parallel lanes read+write `quota-lockout-<provider>.json` | Write via temp file + `mv` (atomic rename on same fs). `_record_quota_lockout` currently writes in place — change to `.tmp` + `mv`. Readers tolerate a missing file by design (`:896`). |
| Test suite touches the real `~/.claude/cache/kimi-runs/` | Poison fence + the `find -newermt` assertion in Test 7 |
| The mission's two live persona-engine lanes (`92954b82`, `472b95ed`) | This lane touches only `plugins/leadv2/**` in the leadv2 repo; no persona-engine file is in LANE_WRITES. No `git reset --hard` / `clean` / `stash` anywhere. |

---

## 5. Explicitly out of scope

- Router-v2's `v2_eligible` list — whether it can still emit `kimi` is a separate
  code path (`resolve_v2_dispatch`, `:940+`) with its own config. **Flagged, not fixed.**
  Note it in the commit message as a known remaining surface.
- Deleting the `kimi)` spawn branch (`:2099-2120`) or the other ~50 kimi references —
  kimi remains a valid *session/channel* arm (`test-kimi-session-route.sh`); only the
  build-dispatch ladder is retired.
- `.claude/scripts/tests/` stale-copy de-duplication (open-threads item, separate lane).
- Any change to `leadv2-glm-policy-resolve.py`'s `DISPATCHABLE_BUILD_ARMS` — it is
  already correct and is the assertion target, not the thing under repair.
- Migrating the quota-lockout store to Supabase or any shared backend.

---

## 6. Constraint checklist

1. **Env var naming** — new: `LEADV2_QUOTA_LOCKOUT_MINUTES`, `LEADV2_ROUTING_YAML_PLUGIN_OVERRIDE` (test-only). Both `LEADV2_*`. No `LEAD_V2_*` drift. No `.claude/settings.json` change needed.
2. **File paths** — all four write targets exist on disk except `tests/test-arm-ladder-vocabulary-drift.sh` **(to-create)**.
3. **`claude -p` commands** — none introduced by this plan. N/A.
4. **Concurrent access** — `quota-lockout-<provider>.json` is the one file two lanes can race; mitigated by temp+`mv` (§4).
5. **Config contradiction** — `dispatch: false` semantics verified against the loader (`:840-842`) and against the only other user of the key (`fable`). Consistent.

---

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >-
      The dispatch journal for a task that resolved to the glm arm shows the line
      "candidate_chain task=<sig8> arms=glm,codex,sonnet" — the word "kimi" does not
      appear anywhere on that line.
    authored_at: 2026-08-06T00:00:00Z
  - surface: log_line
    observable: >-
      For a task whose resolver hands back an arm name the ladder does not know, the
      journal shows "arm_vocabulary_mismatch by=router arm=<that name> fallback=sonnet
      ... reason=launcher_unknown_arm", followed by a candidate_chain line reading
      "arms=sonnet".
    authored_at: 2026-08-06T00:00:00Z
  - surface: file_artifact
    observable: >-
      After a dispatch in which the GLM launcher refused for a quota reason, the file
      quota-lockout-glm.json exists in the dispatch ledger directory and its
      locked_until_epoch is in the future; the next dispatch's journal shows
      "quota_precheck_skip model=glm provider=glm" and then a worker spawned on codex.
    authored_at: 2026-08-06T00:00:00Z
  - surface: log_line
    observable: >-
      With no routing config present at either the project or the plugin location, the
      journal shows "routing_config_degraded ... reason=no_routing_yaml_project_or_plugin"
      and dispatch still proceeds rather than routing silently.
    authored_at: 2026-08-06T00:00:00Z
  - surface: rendered_line
    observable: >-
      The routing/dispatch test suite run prints a PASS line for
      "ladder order from yaml, dispatch:false entries excluded" and for the arm-ladder
      vocabulary-drift suite, with a final failure count of 0, and no line containing
      "POISON: real provider spawn attempted".
    authored_at: 2026-08-06T00:00:00Z
```

---

LANE_WRITES: plugins/leadv2/config/leadv2-routing.yaml, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh, plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh, plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh

DELIVERABLE_COMPLETE
