Product implementation task dispatch-604ed16d. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# DISPATCH-KIMI-ARM-MISMATCH-01 — architect prepass

Scoped implementation design. No code written here.

Repo: `~/Projects/leadv2` (the plugin's single source). All paths below are repo-relative
from that root. Canonical tree is `plugins/leadv2/`, **not** `.claude/scripts/` — the mission
cites `scripts/leadv2-dispatch-code.sh` and `config/leadv2-routing.yaml`, which resolve to
`plugins/leadv2/scripts/...` and `plugins/leadv2/config/...`. `.claude/scripts/*` are per-file
symlinks to canonical; never edit through them.

---

## 1. What the discovery changed about the mission's model

The mission's root-cause read is correct but **incomplete in one load-bearing way**, and one of
its prescribed fixes does not touch the live failure path. Both are stated here so the
implementer does not ship a fix that looks right and changes nothing.

### 1a. Where `arm=kimi reason=codex_quota_gate_80pct` actually comes from

Not from `router_v2.arms` in `leadv2-routing.yaml`. It comes from the T-q codex-quota-gate spill
walk in the resolver:

`plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py:505-517`

```python
blocked = {"codex"} if codex_blocked else set()
if arm in blocked:
    skip = {arm, base_arm} | blocked
    nxt = [a for a in spill if a not in skip and not (job == "review" and a in exclusions)]
    arm = nxt[0] if nxt else "sonnet"
    rule = "codex_quota_gate_%dpct" % int(threshold)
```

`spill` = `gate["build_spill_order"]`, defaulting to
`DEFAULT_BUILD_SPILL = ["glm", "kimi", "codex", "sonnet"]` (`:42`).
With `base_arm=glm` and codex blocked, `skip = {codex, glm}` → `nxt[0]` = **`kimi`**, and
`rule` = `codex_quota_gate_80pct`. That is the live log line, exactly.

### 1b. The tenant yaml lists kimi explicitly — the plugin edit alone does not stop it

`~/Projects/persona-engine/.claude/ref/leadv2-routing.yaml:110`:

```yaml
build_spill_order: [glm, kimi, codex, sonnet]   # ... kimi added KIMI-CHANNEL-01 (2026-07-31)
```

Because the tenant declares the key explicitly, the `DEFAULT_BUILD_SPILL` default is never
consulted there. **Changing `DEFAULT_BUILD_SPILL` in the plugin will not, by itself, stop
persona-engine from resolving `arm=kimi`.** Two consequences the implementer must accept:

- The **launcher fail-safe (item 3) is the fix that actually protects the repo where this
  happened.** It is not the "durable half" — it is the whole half. Build it first.
- Editing `persona-engine/.claude/ref/leadv2-routing.yaml` is **out of scope for this lane**
  (repo-local tenant config; global shared-trees policy says project-specific config is edited
  in the project). It is a follow-up for the lead, recorded in §6.

To close the gap inside the plugin, §3.3 adds a **resolver-side allowlist** so a stale tenant
`build_spill_order` cannot resurrect a retired arm.

### 1c. `router_v2.arms` has no `enabled:`/`disabled:` mechanism

`plugins/leadv2/scripts/leadv2-router-v2.py` was grepped for `enabled|disabled|deprecated`:
**zero hits.** `leadv2-router-v2.sh:132` reads `router_v2.arms` verbatim and passes the whole
list to `filter`. Adding `enabled: false` to the kimi entry would be inert decoration — the arm
would still be emitted as eligible on the v2 path.

The mission says "use whatever mechanism the file already supports; do not invent a new key
shape." Since no such mechanism exists, the reversible retirement that IS honoured is
**commenting the block out with a dated one-line reason** — which is already this file family's
idiom (`persona-engine/.claude/ref/leadv2-routing.yaml:103`: *"comment out this
`codex_quota_gate:` key"*). This is a deliberate deviation from a literal reading of item 1, and
it is the only reading under which item 1 has any effect.

### 1d. There is a SECOND candidate-chain switch the mission does not mention

`plugins/leadv2/scripts/leadv2-dispatch-code.sh:2775-2781`, inside the `glm_refused_lock_busy`
one-shot re-resolve:

```bash
case "${arm}" in
  glm)   candidate_arms=(glm kimi codex sonnet) ;;
  codex) candidate_arms=(codex sonnet) ;;
  sonnet) candidate_arms=(sonnet) ;;
  *) : ;;  # unknown arm: leave the chain; loop continues as-is
esac
```

Its `*)` is already non-fatal, but it carries the same kimi-in-glm-chain vocabulary. **Two
copies of the same chain table are precisely the drift that caused this incident.** The design
therefore extracts ONE helper and calls it from both sites.

---

## 2. Layers affected

| Layer | File | Role in the fix |
|---|---|---|
| Launcher (bash) | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | single chain-vocabulary helper + fail-safe unknown arm |
| Resolver (python) | `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py` | stop emitting kimi as PRIMARY; allowlist stale tenant spill entries |
| Registry (yaml) | `plugins/leadv2/config/leadv2-routing.yaml` | retire the v2 `kimi` arm entry, reversibly |
| Tests (bash) | `plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh` (to-create) | red-first coverage for all three |

Untouched by design: `kimi-coder.sh`, the `kimi)` spawn case (`:1790-1825`),
`_apply_kimi_admission` (`:1390`), `_kimi_admissible` (`:1353`), `_wait_kimi_verdict` (`:1974`),
`KIMI_BIN` (`:1591`). All become unreachable-but-working, per mission item 4.

---

## 3. The changes

### 3.1 `plugins/leadv2/scripts/leadv2-dispatch-code.sh`

**(a) Extract one chain-vocabulary helper.** Define near the other `_`-prefixed dispatch
helpers (suggested: immediately above `_apply_kimi_admission`, ~`:1388`), so both call sites can
reach it:

```
_candidate_chain_for_arm() { # <arm> <sig8> ; mutates candidate_arms
```

Contract:

| input `arm` | `candidate_arms` result | side effect |
|---|---|---|
| `glm` | `(glm codex sonnet)` | none |
| `codex` | `(codex sonnet)` | none |
| `sonnet` | `(sonnet)` | none |
| anything else | `(sonnet)` | `emit decision` + `log_err`, **return 0** |

The unknown-arm branch emits, on ONE line, in the existing `emit decision` grammar
(`<event> by=router key=value ...`):

```
arm_vocabulary_mismatch by=router arm=<unknown> fallback=sonnet task=<sig8> reason=launcher_unknown_arm
```

and a `log_err` carrying the same arm name so it is visible in the dispatch stdout the founder
reads. **It must not `exit`, must not `return` non-zero** — `set -e` is not in force in this
script (`set -uo pipefail` is the house style) but a non-zero return from a helper called
bare would still be a trap under `-e` if it is ever added. Return 0 unconditionally.

Note the mission's requirement that the fallback be "a working chain (`sonnet` at minimum)".
`sonnet` exactly, not `(glm codex sonnet)`: an arm the launcher does not recognise carries an
unknown policy intent, and GLM-FIRST-01 governs arms the resolver *did* pick deliberately.
Falling back to the always-available paid arm is the conservative choice and matches every other
fail-closed path in `resolve_arm()` (`:727`, `:770`).

**(b) Call site 1 — `:2577-2583`.** Replace the `case` (and its `# Kimi's presence is guarded
below` comment) with `_candidate_chain_for_arm "${arm}" "${sig8}"`. The `codex_quota_blocked`
strip at `:2584-2591` and the `_apply_kimi_admission` call at `:2594` stay exactly where they
are and keep working — `_apply_kimi_admission` becomes a no-op filter (kimi is never in the
array), which is correct and cheap.

**(c) Call site 2 — `:2775-2781`.** Replace the `case` with the same helper call. The behaviour
change here is intentional and small: an unknown re-resolved arm previously kept the old chain
silently; it now lands on `sonnet` and says so. That is the same failure-loud contract.

**(d) Do not touch** `:2519` (`arm_resolved` emission), the v2 branch at `:2572-2576`, or the
`ROUTER-QUOTA-DRIVEN-01` live-quota filter below `:2596`.

### 3.2 `plugins/leadv2/config/leadv2-routing.yaml`

Comment out the whole `- id: kimi` block, `:59-67` (the three `KIMI-CHANNEL-REHAB-01` comment
lines plus `id`/`model`/`bucket`/`reserve_threshold`/`reserve_allow`), and replace with a
dated one-line retirement reason, e.g.:

```yaml
    # RETIRED 2026-08-05 (DISPATCH-KIMI-ARM-MISMATCH-01, founder order 2026-08-04
    # «Кими убрать»): kimi is not a dispatchable build arm. Uncomment this block to
    # restore it — the launcher implementation (kimi) spawn case, _apply_kimi_admission,
    # _wait_kimi_verdict, KIMI_BIN) is intact and still works.
    # - id: kimi
    #   model: moonshotai/kimi-k3-free
    #   bucket: kimi
    #   reserve_threshold: 2
    #   reserve_allow: [review]
```

Rationale for comment-out over `enabled: false` — §1c. Verify after the edit that
`python3 -c 'import yaml,sys; d=yaml.safe_load(open(...)); print([a["id"] for a in d["router_v2"]["arms"]])'`
returns `['glm','codex','claude-haiku','claude-sonnet','claude-opus']` — `leadv2-router-v2.sh:141`
dies if `router_v2.arms` parses empty, so a mis-indented comment is a hard dispatch break, not a
soft one.

### 3.3 `plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py`

**(a)** `DEFAULT_BUILD_SPILL` (`:42`) → `["glm", "codex", "sonnet"]`, with the existing
KIMI-CHANNEL-01 comment block at `:35-41` rewritten to record the 2026-08-04 removal rather
than deleted.

**(b)** Add a module-level allowlist and apply it to the spill walk, so an explicit stale tenant
`build_spill_order` (persona-engine, §1b) cannot hand back a retired arm:

```python
DISPATCHABLE_BUILD_ARMS = {"glm", "codex", "sonnet"}   # launcher vocabulary, see
                                                       # leadv2-dispatch-code.sh:_candidate_chain_for_arm
```

and in the `nxt = [...]` comprehension at `:511`, add `and a in DISPATCHABLE_BUILD_ARMS`. With
`nxt` empty the existing `else "sonnet"` already does the right thing.

This is the one place where the resolver's and launcher's vocabularies are written down in two
languages. Both new definitions carry a comment naming the other, so the next editor sees the
pair. A shared data file was considered and rejected: it adds a read to the hot path and a
fourth thing to keep in sync, for a set of three strings.

**(c) Do not touch** `DEFAULT_REVIEW_ARM_ORDER` (`:62`), `kimi_review_available()` (`:225`),
`DEFAULT_REVIEW_EXCLUSIONS`, or any threshold. Kimi's review-pool membership is a *different
ladder* with a different admission gate (probe, not quota) and was not what the founder's
2026-08-04 order or this incident concerned. See §6.

---

## 4. Tests — `plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh` (to-create)

House style, matched from `test-dispatch-silent-arm.sh`: `#!/usr/bin/env bash`,
`set -uo pipefail`, `SCRIPT_DIR`/`SCRIPTS_ROOT` resolution, `PASS`/`FAIL`/`ERRORS`
counters, `log`/`pass`/`fail` helpers, `bash -n` syntax gate first, exit 0 = all pass.
Sandbox every path the script writes (`LEADV2_DISPATCH_TERMINAL_LEDGER_FILE`,
`CLAUDE_PROJECT_ROOT`, `LEADV2_DISPATCH_CACHE_DIR`, `LEADV2_LANE_WORK_ROOT`) — never touch the
real ledger or journal. Portable: no GNU-only `date`/`sed`/`timeout`.

Cases:

| # | Case | Drives | Assertion |
|---|---|---|---|
| 1 | resolver returns `kimi` as PRIMARY | real `leadv2-dispatch-code.sh`, resolver stubbed via `GLM_POLICY_RESOLVER` pointing at a fixture emitting `arm=kimi\nrule=codex_quota_gate_80pct\n...` | exit != 1; journal carries `arm_vocabulary_mismatch ... arm=kimi fallback=sonnet` |
| 2 | `arm=glm` chain | `_candidate_chain_for_arm` via a sourced-function harness or a `--dry-run` dispatch | chain is `glm codex sonnet`; **`kimi` absent** |
| 3 | `arm=codex` chain | same | `codex sonnet`, unchanged (regression guard) |
| 4 | `arm=sonnet` chain | same | `sonnet`, unchanged (regression guard) |
| 5 | resolver spill with kimi in an explicit `build_spill_order` | real `leadv2-glm-policy-resolve.py` CLI, fixture yaml declaring `build_spill_order: [glm, kimi, codex, sonnet]` + `build_threshold_pct: 80` + a quota reading ≥80 | stdout `arm=` is **not** `kimi` (§3.3b) |
| 6 | `router_v2.arms` parses non-empty and excludes kimi | `python3 -c` yaml load of the real `config/leadv2-routing.yaml` | id list has ≥3 entries, `kimi` not among them |

Case 1 is the one that must be shown RED before the patch. Case 5 is the one that proves the
tenant-yaml gap is closed inside the plugin. Cases 3/4/6 are guards and will be green both
sides — that is expected and must be stated, not hidden.

**Red-first evidence required in the deliverable:** run the new suite against the pre-patch
tree (`git stash` is forbidden by the mission — use `git show HEAD:<path>` into a temp dir, or
run the suite before applying edits) and paste both the before and after `PASS`/`FAIL` counts.
A suite where case 1 passes pre-patch is a broken test, not a passing fix.

Register the suite wherever this repo registers dispatch suites (check the runner that
enumerates `scripts/tests/test-*.sh` before assuming registration is automatic).

---

## 5. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **The plugin fix does not stop the live repo.** persona-engine's tenant yaml names kimi explicitly (§1b), so `DEFAULT_BUILD_SPILL` never applies there. | §3.3b allowlist closes it inside the plugin; §3.1 fail-safe makes it survivable regardless. Tenant yaml edit logged as follow-up (§6) — the lane must not silently claim persona-engine is fixed by the yaml default alone. |
| R2 | **YAML comment-out breaks `router_v2.arms` parse.** `leadv2-router-v2.sh:141` `die`s on an empty/missing arms list — a mis-indent turns a soft retirement into a hard dispatch failure. | Explicit post-edit parse check in §3.2; test case 6. |
| R3 | **Fail-safe masks a real config error.** An unknown arm now dispatches on sonnet instead of stopping, so a typo in a tenant yaml burns Anthropic quota quietly. | The `emit decision` line is mandatory and names the arm; it goes to the journal AND `log_err` to stdout. Loud-and-working beats silent-and-dead — that is the mission's explicit ruling. |
| R4 | **Two chain tables become three.** A future edit adds a fourth call site. | The helper is the single definition; both existing sites are converted in this lane. Neither site keeps a local `case`. |
| R5 | **Bash/Python vocabulary still duplicated** (`_candidate_chain_for_arm` vs `DISPATCHABLE_BUILD_ARMS`). | Cross-referencing comments in both; test case 5 fails if they diverge in the direction that matters (resolver emits something the launcher would not run). |
| R6 | `_apply_kimi_admission` / `_kimi_admissible` become dead filters over arrays that never contain kimi. | Intentional (mission item 4). No behaviour change: the functions return early. Leave them; deleting is a larger diff for no benefit. |
| R7 | **v2 router path (`router_label == v2`) is a different branch** and takes its chain from `v2_eligible`, not the `case`. | §3.2 removes kimi from `router_v2.arms`, which is the source of `v2_eligible` (`leadv2-router-v2.sh:132` → L1 `eligible=`). Test case 6 covers it. |
| R8 | Concurrent-access: none. All three files are read-at-dispatch, written only by this lane. No lock needed. | — |

Mandatory-checklist items 1 (`LEADV2_*` env naming — no new env vars introduced), 3 (`claude -p`
flags — no `claude -p` invocation introduced), 4 (concurrent access — R8), and 5 (config
contradiction — §1b/§3.3b IS the contradiction, surfaced not skipped) are all discharged above.
Item 2: every path listed is verified on disk except the test file, marked `(to-create)`.

---

## 6. Out of scope — the implementing agent must NOT do these

- Delete or modify the kimi launcher implementation: `kimi)` spawn case `:1790-1825`,
  `_apply_kimi_admission`, `_kimi_admissible`, `_wait_kimi_verdict`, `KIMI_BIN`,
  `kimi-coder.sh`, and the kimi branches in the run-id sanitiser (`:846`, `:872`) and rc=77
  handler (`:1714`).
- Touch `review_arm_exclusions`, `DEFAULT_REVIEW_ARM_ORDER`, `kimi_review_available()`, or any
  `*_threshold_pct`. **Kimi remains a review arm.** If the founder's 2026-08-04 order was meant
  to cover the review pool too, that is a separate decision and a separate lane — flag it, do
  not act on it.
- Edit `~/Projects/persona-engine/.claude/ref/leadv2-routing.yaml:110`. Tenant config, different
  repo. **Follow-up for the lead:** drop `kimi` from that `build_spill_order` list so the repo
  where this incident happened stops resolving a retired arm at all, rather than relying on the
  fail-safe every time.
- Change GLM's primacy (GLM-FIRST-01) or the `codex_quota_blocked` strip at `:2584-2591`.
- Create any copy of a plugin-owned file inside a consuming repo.
- `git add -A`, `reset --hard`, `clean`, `stash`. Stage only the four files below, by path.

---

## 7. acceptance

```yaml
acceptance:
  authored_at: 2026-08-05T00:00:00Z
  criteria:
    - surface: log_line
      observable: >
        A dispatch whose resolver hands back an arm the launcher does not know prints a
        line naming that arm and the arm it fell back to instead — and the dispatch keeps
        going. The founder reading the dispatch output sees the mismatch called out by
        name, followed by a normal spawn, not "ERROR: unsupported resolved dispatch arm"
        followed by nothing.
    - surface: log_line
      observable: >
        The task journal for that dispatch contains one arm_vocabulary_mismatch entry
        naming the unknown arm and sonnet as the fallback, alongside the usual
        arm_resolved and spawn entries for the same task.
    - surface: file_artifact
      observable: >
        docs/handoff/DISPATCH-KIMI-ARM-MISMATCH-01/deliverable.md shows the new test
        suite's pass/fail tally against the tree before the change and against the tree
        after it, and the two tallies differ — at least one case that fails before it
        passes after. It also shows the single commented-out block in
        plugins/leadv2/config/leadv2-routing.yaml that restores the kimi arm if
        uncommented.
    - surface: rendered_line
      observable: >
        A real code dispatch in a repo whose quota gate is tripped lands on a working arm
        and produces a spawned lane, where before it produced nothing.
```

---

## 8. Rollback

One edit: uncomment the `- id: kimi` block in `plugins/leadv2/config/leadv2-routing.yaml`.
Restoring kimi as a *build spill* target additionally requires re-adding `"kimi"` to
`DEFAULT_BUILD_SPILL` and `DISPATCHABLE_BUILD_ARMS` in
`plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py`, and to the `glm)` row of
`_candidate_chain_for_arm`. State all four in the deliverable — the mission asks for "the exact
one-edit rollback", and honestly it is one edit only for the v2 registry path; the fixed-order
path is three. Do not overstate it as one.

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py, plugins/leadv2/config/leadv2-routing.yaml, plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# DISPATCH-KIMI-ARM-MISMATCH-01 — the resolver can pick an arm the launcher cannot run, and the dispatch dies

## What happened (live, 2026-08-05, persona-engine)

A real code dispatch was lost to this. Verbatim:

```
[leadv2-dispatch-code] arm_resolved job=build arm=kimi reason=codex_quota_gate_80pct
[leadv2-dispatch-code] ERROR: unsupported resolved dispatch arm: kimi
```

Nothing spawned. Exit 1. The only reason the work happened at all is that the lead noticed and
re-dispatched by hand.

## Root cause

`scripts/leadv2-dispatch-code.sh:2577-2583` — the fixed-order candidate-chain switch enumerates
only three arms:

```bash
case "${arm}" in
  glm)   candidate_arms=(glm kimi codex sonnet) ;;
  codex) candidate_arms=(codex sonnet) ;;
  sonnet) candidate_arms=(sonnet) ;;
  *) log_err "unsupported resolved dispatch arm: ${arm}"; exit 1 ;;
esac
```

`kimi` appears INSIDE the glm chain (as a spill target) but has no case of its own, so the moment
the resolver hands back `kimi` as the PRIMARY arm — which it does under
`reason=codex_quota_gate_80pct` — the switch falls to `*)` and hard-exits. The resolver's arm
vocabulary and the launcher's arm vocabulary have drifted apart, and the drift is silent until it
costs a dispatch.

Note the launcher DOES have a working kimi arm further down (`kimi)` spawn case at ~:1790, plus
`_apply_kimi_admission`, `_wait_kimi_verdict`, `KIMI_BIN`). So this is purely a missing branch in
the candidate-chain switch, not a missing implementation.

## The founder decision that settles which way to fix it

**Kimi was removed from the ladder by founder order on 2026-08-04** («Кими убрать — да. ГЛМ конечно
оставить»). GLM stays as primary; Kimi is the only arm removed. So the fix is NOT "teach the
launcher to run kimi" — it is "stop the resolver from ever handing back kimi", plus a guard so this
class of drift can never again silently kill a dispatch.

## What to build

1. **Remove kimi from routing as a dispatchable arm.** `config/leadv2-routing.yaml:62-65` carries
   the `kimi` arm entry (`model: moonshotai/kimi-k3-free`, `bucket: kimi`). Retire it the
   reversible way — the way this repo already retires things: mark it disabled/deprecated with a
   one-line reason and the date, rather than deleting the block, so the removal reverses with one
   edit. Whatever mechanism the file already supports for a disabled arm, use that; do not invent
   a new key shape.
2. **Remove `kimi` from the `glm)` spill chain** at :2578 so it cannot be reached as a fallback
   either. The `codex_quota_blocked` strip immediately below (:2584-2591) is the existing pattern
   for removing an arm from the chain — match its shape.
3. **Make the `*)` branch fail SAFE, not fatal.** This is the durable half of the fix and it
   matters more than the kimi specifics: any arm the resolver emits that the switch does not know
   must fall back to a working chain (`sonnet` at minimum) and emit a loud `emit decision` line
   naming the unknown arm — never `exit 1`. A resolver/launcher vocabulary mismatch must degrade
   to "dispatched on a safe arm, loudly", not to "nothing ran".
4. **Leave the kimi implementation code in place** (`kimi)` spawn case, `_apply_kimi_admission`,
   `_wait_kimi_verdict`, `KIMI_BIN`). It is unreachable once 1+2 land, and deleting it is a much
   larger diff with no benefit today. If the founder re-enables the arm, it should still work.
5. **Tests.** Add unit coverage under `tests/` matching the existing dispatch-test style:
   - resolver returns `kimi` → dispatch does NOT exit 1; it lands on a working arm and emits the
     unknown-arm decision line;
   - `arm=glm` chain no longer contains kimi;
   - `arm=codex` / `arm=sonnet` chains unchanged (regression guard).
   Prove the suite FAILS against the pre-patch file — paste both counts in the deliverable. A test
   that passes before and after proves nothing.

## Off limits

- Do not change GLM's position as primary. GLM-FIRST-01 stands.
- Do not touch the codex quota-gate thresholds or `review_arm_exclusions`.
- Do not delete the kimi launcher implementation (item 4).
- This is the plugin's single source (`~/Projects/leadv2`). Do NOT create a copy of any
  plugin-owned file inside a consuming repo.
- Stage ONLY your own files by explicit path. Never `git add -A`, never `reset --hard`, never
  `clean`, never `stash`.

## Done means

- Diff on `scripts/leadv2-dispatch-code.sh` + `config/leadv2-routing.yaml` + tests.
- Test counts before and after, pasted.
- Deliverable at `docs/handoff/DISPATCH-KIMI-ARM-MISMATCH-01/deliverable.md` with the diff summary,
  the before/after counts, and the exact one-edit rollback.
- End with DELIVERABLE_COMPLETE.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-604ed16d" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.