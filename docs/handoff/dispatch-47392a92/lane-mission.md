Product implementation task dispatch-47392a92. Implement ONLY the scoped design below; preserve its non-goals. Before closing, run the required end-to-end gate and the cross-provider review gate recorded for this task.

===== SCOPED DESIGN (authoritative) =====
# LANE-LIVENESS-IGNORES-ITS-OWN-COMPLETION-SENTINEL-01 — architect prepass

Repo: `/Users/kostiantyn.vlasenko/Projects/leadv2` (plugin repo, single source).
Canonical script tree: `plugins/leadv2/scripts/`.

---

## 1. Ground truth established (evidence, not assumption)

| Fact | Evidence |
|---|---|
| Liveness returns `alive/log_fresh` whenever log age ≤ `silent_max` | `plugins/leadv2/scripts/leadv2-lane-liveness.sh:390,421-422` |
| `silent_max` default 900s | same file `:81` |
| B8 rule: terminal provider status only applies when NOT fresh | same file `:401-411` |
| Dispatcher refuses placement on `alive`/`starting:` | `leadv2-dispatch-code.sh:599-624` (probes `dispatch-<key>` then `<key>`, with `--no-codex`) |
| Dispatcher probe passes `--no-codex` | `leadv2-dispatch-code.sh:603` — so the provider/codex mapping is *off* on the exact path that produced the bug; only the log-mtime path decides |
| glm run dir = `$GLM_RUNS_DIR/<run_id>`, default `~/.claude/cache/glm-runs` | `leadv2-glm-session-runner.sh:40,368` |
| glm run_id persisted per lane at `docs/handoff/<TASK_ID>/.glm-session-runner.run-id` | `leadv2-glm-session-runner.sh:51,60,365` |
| kimi run dir = `$KIMI_RUNS_DIR/<run_id>`, run-id at `docs/handoff/<TASK_ID>/.kimi-session-runner.run-id` | `leadv2-kimi-session-runner.sh:55,79,397` |
| `<run_dir>/pgid` holds the setsid child pid used as the run's process-group leader | `glm-coder.sh:1294-1296`, `kimi-coder.sh:1355-1357` |
| `<run_dir>/.finalized` = "this run is fully finalized (finalize_meta + deadhand_check both ran)" | `glm-coder.sh:1512-1516`, `kimi-coder.sh:1585` |
| `<run_dir>/.done` = child process exited; it is the **watchdog stop condition**, explicitly documented as NOT a finalization marker | `glm-coder.sh:1308` + comment at `:1512-1515` |
| `<run_dir>/.outcome` is written by `leadv2-lane-outcome.sh` (called from glm-coder/kimi-coder), key=value block `outcome=completed\|died-with-work\|died-clean` | `leadv2-lane-outcome.sh:19,177`; parsed precedent `leadv2-status-surface.sh:1046-1075` |
| Runner retry gap is short: `RETRY_SLEEP_S` default 5s, `MAX_ATTEMPTS` 6 | `leadv2-glm-session-runner.sh:34-35`, kimi `:49-50` |
| Live observed run dir contents confirm all three sentinels + `pgid` | `~/.claude/cache/glm-runs/260806-041752-472b95ed-776a/` → `.done .finalized .outcome pgid exit_code meta.yaml journal.jsonl …`, `pgid=4445`, `.outcome` → `outcome=completed` |

### Runner sentinel inventory (mission requirement 1)

| Runner | Run dir | Lane→run-dir mapping | Completion sentinel | pgid file |
|---|---|---|---|---|
| **glm** (`leadv2-glm-session-runner.sh` → `glm-coder.sh`) | `${GLM_RUNS_DIR:-~/.claude/cache/glm-runs}/<run_id>` | `docs/handoff/<tid>/.glm-session-runner.run-id` | **`.finalized`** (yes) | yes |
| **kimi** (`leadv2-kimi-session-runner.sh` → `kimi-coder.sh`) | `${KIMI_RUNS_DIR:-~/.claude/cache/kimi-runs}/<run_id>` | `docs/handoff/<tid>/.kimi-session-runner.run-id` | **`.finalized`** (yes) | yes |
| **codex** (`codex-task.sh`) | no run dir; state lives in `<state_root>/*/jobs/<id>.json` | `docs/handoff/<tid>/codex-plan.json` → `job_id` | **NONE — no filesystem completion sentinel.** Already covered by the existing `provider_status` path (`liveness:383-411`) | no |
| **claude-subsession** (`leadv2-claude-subsession.sh`, `claude-subsession.sh`) | no run dir | n/a | **NONE.** No sentinel exists; do not invent one in this lane | no |

Report this table verbatim in the lane's return.

---

## 2. Root cause

A cleanly-exited glm/kimi run flushes its stream file at completion. `resolve()` computes
`age_s` from that flush, `is_fresh` is true for the next 900s, and line 421 unconditionally
emits `alive/log_fresh`. The runner-written finalization sentinel and the run's own recorded
`pgid` are **never read by the liveness script at all** — there is no code path that opens the
run dir. The dispatcher then refuses `--resume-lane` with `lane_is_live` for up to 15 minutes
after a provably finished run.

B8 (`:401-411`) is not the gap and must not be touched: it governs *provider self-reports*,
and its guard (`not is_fresh`) is deliberate.

---

## 3. Design

### 3.1 What is proof vs. what is a report

- A **provider status** ("cancelled"/"completed") is a *report by a third party about a job* —
  it can be wrong about whether anything is still writing. B8 correctly subordinates it to a
  fresh log.
- `<run_dir>/.finalized` is written by **the runner itself, in its own finalize path, after its
  child has been reaped**. Combined with the run's own `pgid` process group being gone, nothing
  from that run can still be writing. That is proof, and it outranks log freshness — the fresh
  mtime *is* the completion flush.

`.done` is deliberately **rejected** as a sentinel: `glm-coder.sh:1512-1515` states it is the
watchdog's stop condition, set the instant the child is reaped and before finalization. Using it
would declare lanes dead during finalize. `.outcome` is accepted only as a *corroborating*
signal (see 3.3), never on its own.

### 3.2 "No live process" — positively established (mission requirement 2)

The observed failing case had `pid: null` in the row, so a design that requires an
explicitly-recorded-then-dead `active.yaml` pid **would not fix the reported bug**. The mission's
fallback ("require sentinel AND recorded-then-dead pid") is therefore not adopted; instead a
*better positive* signal exists and is used:

**`<run_dir>/pgid`.** It is written by the coder itself (`glm-coder.sh:1296`) and holds the
setsid process-group leader of the actual model run. Death is established the same way
`glm-coder.sh:352` establishes it: `kill(-pgid, 0)` raising `ProcessLookupError`.

Rules — all must hold for the new dead verdict:

1. Resolved run dir exists AND contains `.finalized`.
2. `pgid` file exists, parses as a positive int, and `os.kill(-pgid, 0)` raises
   `ProcessLookupError` (group gone). `PermissionError` ⇒ the group **exists** ⇒ treat as ALIVE
   (do not fire). A missing/unparseable `pgid` ⇒ do not fire (we cannot positively establish
   death; fall through to existing behaviour).
3. The `active.yaml` pid, **if and only if it was explicitly recorded** (`session` exists and
   `session.get("pid")` is not `None`/`""`), must fail `kill -0`. A recorded-and-alive pid ⇒ do
   not fire. A never-recorded pid (`pid: null`, the observed case) is neither evidence of life
   nor of death and does **not** block the verdict, because condition 2 already carries the
   positive proof.
4. **Settle window:** `mtime(.finalized)` must be at least `LEADV2_LANE_SENTINEL_SETTLE_S`
   (default **60s**) old. This closes the only real race: the session runner loops up to 6
   attempts with `RETRY_SLEEP_S=5`, so between attempt *N*'s `.finalized` and attempt *N+1*
   rewriting the run-id file there is a ≤ ~10s window in which the lane is finished-but-retrying.
   60s is ≥ 6× that gap and far below the 581s of the observed case. Once attempt *N+1* starts,
   the run-id file names a **new** run dir with no `.finalized`, so the check self-heals.

Row fields recording which branch fired: `pid_recorded` (bool), `pgid`, `pgid_alive`.

### 3.3 Verdict and reason (mission requirement 3)

- verdict: **`dead:sentinel_finalized`**
- reason: **`sentinel_finalized`** — no provider suffix appended, so it is unambiguous in a
  journal and never collides with the `provider_*` family produced by B8/`:395-411`.
- Additional row keys for journal readability (added only when the run dir resolves):
  `arm` (`glm`|`kimi`), `run_dir`, `sentinel_path`, `sentinel_age_s`.

`.outcome`, when present and parseable, is surfaced as `lane_outcome`
(`completed`|`died-with-work`|`died-clean`) for readers. It never gates the verdict.

### 3.4 Placement in `resolve()` (mission requirement 4 — behaviour preservation)

Insert a single new block **after** the existing v2/B8 provider block (`:391-411`) and
**before** the wedged-process check at `:415`. Consequences, all deliberate:

- Every earlier return path is untouched → `child_suffix_fold`, prepass tiers, `starting:`,
  `dead:no_handoff_dir`, `dead:no_log_artifact`, `dead:log_stat_failed`, the
  `LEADV2_LANE_LIVENESS_V2=0` rollback branch and B8 all keep byte-identical behaviour.
- **B8 wins on ties.** A not-fresh log + terminal provider status returns `dead:provider_*`
  before the new block is reached, exactly as today.
- The B8 *scenario* (fresh log, no pid, provider "cancelled", **no sentinel**) never reaches a
  dead verdict: B8's `not is_fresh` guard fails, and the new block's condition 1 fails. It stays
  `alive/log_fresh+provider_cancelled`. Locked by test S2.
- The new block fires **regardless of `is_fresh`**, which is the whole point.

### 3.5 Kill switch

`LEADV2_LANE_SENTINEL_DEAD` — default `1` (on). `=0` restores exactly today's behaviour
(one-flag rollback, matching the `LEADV2_LANE_LIVENESS_V2` precedent at `:70-73`). Threaded
through the existing `python3 - "$@"` argv list, not read from `os.environ`, consistent with
every other tunable in this script.

### 3.6 Run-dir resolution contract

```
resolve_run_dir(tid) -> (arm, run_dir) | (None, None)
  for arm in ("glm", "kimi"):
      idfile = <root>/docs/handoff/<tid>/.<arm>-session-runner.run-id
      run_id = first non-empty stripped line of idfile        # else continue
      reject run_id containing "/" or ".." or empty           # path-traversal guard
      base = ${GLM_RUNS_DIR|KIMI_RUNS_DIR} if set
             else ${LEADV2_LANE_RUNS_ROOT:-$HOME/.claude/cache}/<arm>-runs
      if isdir(base/run_id): return (arm, base/run_id)
  return (None, None)
```

No globbing by sig8. The run dir name embeds the sig8 (`260806-041752-472b95ed-776a`), which is
tempting and wrong: a lane retried N times has N such dirs and the newest-by-name is not
reliably the current attempt, whereas the run-id file *is* the runner's own record of the
current attempt (`leadv2-glm-session-runner.sh:365`).

Env vars, cross-checked against existing usage: `GLM_RUNS_DIR` / `KIMI_RUNS_DIR` are honoured
because the runners themselves define them (`glm-session-runner:40`, `kimi-session-runner:55`) —
tests that set them get a coherent world. New vars added by this lane use the `LEADV2_` prefix:
`LEADV2_LANE_RUNS_ROOT`, `LEADV2_LANE_SENTINEL_SETTLE_S`, `LEADV2_LANE_SENTINEL_DEAD`. No
existing `LEADV2_LANE_*` var is redefined (`LEADV2_LANE_SILENT_MAX_S`,
`LEADV2_LANE_STARTING_MAX_S`, `LEADV2_LANE_ABANDON_MAX_S`, `LEADV2_LANE_LIVENESS_V2`,
`LEADV2_LANE_CHILD_SUFFIXES` all keep their meanings). `LEADV2_STATUS_RUNS_ROOT` /
`LEADV2_SS_RUNS_ROOT` belong to `leadv2-status-surface.sh` and are **not** reused here —
different consumer, different lifetime; no contradiction introduced.

---

## 4. Files

### Writes

| File | Change |
|---|---|
| `plugins/leadv2/scripts/leadv2-lane-liveness.sh` | argv threading for 3 new tunables; `resolve_run_dir()`, `pgid_group_alive()`, `sentinel_check()` helpers; one new block between `:411` and `:415`; new row keys |
| `plugins/leadv2/scripts/tests/test-lane-liveness-sentinel.sh` | **(to-create)** unit scope, cases S1–S6 |
| `plugins/leadv2/scripts/tests/test-dispatch-resume-sentinel.sh` | **(to-create)** dispatcher e2e, case S7 |
| `.claude/scripts/leadv2-lane-liveness.sh` | **only if it is a real file rather than a symlink to canonical** — it is currently a 25446-byte regular file dated Aug 1, i.e. drifted. Per the shared-trees policy, replace the copy with a symlink to `plugins/leadv2/scripts/leadv2-lane-liveness.sh`; never hand-apply the patch twice. If it is already a symlink, do not touch it. |

### Reads (existence verified)

`plugins/leadv2/scripts/leadv2-dispatch-code.sh`, `leadv2-glm-session-runner.sh`,
`leadv2-kimi-session-runner.sh`, `glm-coder.sh`, `kimi-coder.sh`, `leadv2-lane-outcome.sh`,
`plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh`.

### Off limits

- Lane `759ec34f` (this repo), lanes `92954b82` / `472b95ed` (persona-engine). Note
  `~/.claude/cache/glm-runs/260806-043334-759ec34f-41dc` is a **live** run dir — read-only, and
  no test may write under the real `~/.claude/cache`; every test sets `GLM_RUNS_DIR` /
  `KIMI_RUNS_DIR` to a `mktemp -d` fixture.
- `git reset --hard`, `git clean`, `git stash` — forbidden.
- B8 (`:401-411`), the `v2_mode==0` rollback branch, the prepass/child-fold tiers, `count_live`
  semantics, `leadv2-dispatch-code.sh` refusal logic (the fix lands entirely in liveness; the
  dispatcher needs **no** edit).
- No new real copy of any plugin file inside a project.

---

## 5. Test plan

All tests are pure-fixture: `PROJECT_ROOT` = `mktemp -d` with a synthetic
`docs/handoff/<tid>/` + `docs/leadv2/active.yaml`; `GLM_RUNS_DIR`/`KIMI_RUNS_DIR` = `mktemp -d`;
`--no-codex` on every probe. **No test spawns a real provider session.**
Dead pgid is produced deterministically by `(exit 0) & echo $! > pgid; wait` — a reaped pid whose
group is provably gone — or by an unused high pid confirmed absent via `kill -0` before use.

| # | Case | Setup | Expected |
|---|---|---|---|
| **S1** | **RED→GREEN, the reported bug** | glm run dir with `.finalized` mtime = now−600s, `pgid` = dead group; stream `developer.stream.jsonl` mtime = now−581s (< 900s); `active.yaml` row with `pid: null` | `verdict=dead:sentinel_finalized`, `reason=sentinel_finalized`. **Fails on HEAD** (HEAD → `alive`/`log_fresh`) |
| **S2** | **B8 lock — must stay alive** | fresh `session.log`, no pid, mapped codex job status `cancelled`, **no sentinel/run dir** | `verdict=alive`, reason starts `log_fresh` |
| **S3** | sentinel + **live** pgid | `.finalized` old, `pgid` = a live `sleep 60` process group | `alive` (unchanged) |
| **S4** | sentinel inside settle window | `.finalized` mtime = now−5s | `alive` (unchanged) |
| **S5** | kill switch | S1 fixture + `LEADV2_LANE_SENTINEL_DEAD=0` | `alive` (exact HEAD behaviour) |
| **S6** | kimi arm | S1 fixture rebuilt under `.kimi-session-runner.run-id` + `$KIMI_RUNS_DIR` | `dead:sentinel_finalized`, `arm=kimi` |
| **S7** | **dispatcher e2e** | S1 fixture + `--resume-lane` on that lane, `LEADV2_DISPATCH_SPAWN=0` (or `LEADV2_DISPATCH_*_BIN` fakes) | placement **accepted**; no `lane_placement_refused … reason=lane_is_live` for that lane in the decision journal. **Fails on HEAD** |
| **S8** | `.done` alone is not a sentinel | run dir with `.done` + dead pgid, **no** `.finalized` | `alive` — guards against a future "widen it to `.done`" regression |

Additional required evidence in the return: full-scope run of
`plugins/leadv2/scripts/tests/test-lane-liveness-*.sh` and `test-dispatch-*.sh`, with pass/fail
counts **before and after**, and the failing-then-passing run of S1, S7 shown explicitly.

Test discovery: tests in this tree are `tests/test-*.sh`; no central registry file references
`test-lane-liveness-authoritative.sh`, so no registration file needs editing — **verify this
before finishing** and, if a runner manifest turns out to exist, register both new suites.

---

## 6. Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **False-dead during runner retry** — `.finalized` of attempt N read while attempt N+1 is about to start ⇒ a live lane declared dead ⇒ a concurrent dispatch on a live worktree | 60s settle window (§3.2 rule 4), ≥6× the ≤10s gap; plus attempt N+1 repoints the run-id file at a sentinel-free dir. Test S4 |
| R2 | **`pgid` reuse** — the OS recycles the pgid onto an unrelated process ⇒ `kill(-pgid,0)` succeeds ⇒ false ALIVE | Fail-safe direction: a false *alive* only preserves today's (already conservative) behaviour. Accepted, documented in-code |
| R3 | **`PermissionError` on `kill(-pgid,0)`** — group exists but is not ours | Treated as alive (never fire). Explicit branch, not a bare `except` |
| R4 | **B8 regression** by a future widening | Test S2 is the lock; the new block is physically *after* B8's `return`, so B8 is unreachable-from-below |
| R5 | **`.claude/scripts/` copy drift** — the fix lands in canonical while a stale 25446-byte copy at `.claude/scripts/leadv2-lane-liveness.sh` keeps serving some callers | Explicitly in scope: convert to a symlink (§4). Never patch both copies |
| R6 | **Concurrent access** — the session runner rewrites `.<arm>-session-runner.run-id` (`printf > file`, non-atomic) while liveness reads it | Read is best-effort: empty/partial/absent ⇒ resolver returns `(None,None)` ⇒ no verdict change. No lock needed; the failure mode is "no new verdict", never a wrong one |
| R7 | **Row schema growth** — `--all` consumers parse the row JSON | New keys are additive only; `provider_status` (`:388`) is existing precedent for conditional keys. No key removed or retyped. `count_live` (`:484-487`) counts only `alive`/`starting:` and is unaffected by a new `dead:*` label |
| R8 | **Extra stat syscalls per lane on the statusline hot path** — `--all` resolves every lane every repaint | Cost is ≤3 `os.stat`/`open` per lane, and only for lanes that have a run-id file. No subprocess, no `ps`. Consistent with the D3/R-1 no-subprocess rule at `:100-107` |
| R9 | **Path traversal** via a crafted run-id file | Reject run_id containing `/` or `..` (§3.6) |
| R10 | codex + claude-subsession have **no** sentinel, so their lanes keep the 900s false-alive window | Out of scope for this lane; reported explicitly rather than papered over with an invented sentinel |

---

## 7. Non-goals (explicit — the implementer must ignore these)

1. Do **not** touch B8, invert it, or widen it.
2. Do **not** lower `silent_max` or change any existing tunable's default.
3. Do **not** edit `leadv2-dispatch-code.sh` — the dispatcher already consumes the liveness
   verdict correctly; a liveness fix is sufficient and is the only change needed.
4. Do **not** invent a sentinel for codex or claude-subsession.
5. Do **not** add sentinel checking to the `log_path is None` branches (prepass tier,
   `registered_no_stream`, `no_handoff_dir`, `no_log_artifact`). They already return dead or a
   bounded `starting:`; widening there is a separate blast radius.
6. Do **not** treat `.done`, `.outcome`, `exit_code` or `meta.yaml status` as the completion
   sentinel. `.finalized` only; `.outcome` is display-only.
7. Do **not** delete, prune, or rewrite any run dir under `~/.claude/cache`.
8. No changes to `count_live`, the statusline, `leadv2-status-surface.sh`, or the ledger sweep.

---

## 8. Constraint checklist

1. **Env var naming** — new vars `LEADV2_LANE_RUNS_ROOT`, `LEADV2_LANE_SENTINEL_SETTLE_S`,
   `LEADV2_LANE_SENTINEL_DEAD` all use the `LEADV2_` prefix and the existing `LEADV2_LANE_*`
   family convention. `GLM_RUNS_DIR`/`KIMI_RUNS_DIR` are consumed, not defined, matching the
   runners. PASS.
2. **File paths** — every path in §4 verified on disk; the two test files are marked
   `(to-create)`. PASS.
3. **`claude -p`** — this lane introduces no `claude -p` invocation. N/A.
4. **Concurrent access** — R6 (run-id file read vs. runner write) analysed; fail-soft, no lock
   required. PASS.
5. **Config contradiction** — `LEADV2_STATUS_RUNS_ROOT`/`LEADV2_SS_RUNS_ROOT` deliberately not
   reused (§3.6); no existing var's semantics change. PASS.

---

## 9. Acceptance

```yaml
acceptance:
  - surface: log_line
    observable: >-
      In the dispatch decision journal, resuming the lane whose glm run dir carries
      .finalized with a dead process group no longer produces a
      "lane_placement_refused ... reason=lane_is_live" line for that lane; the resume
      is accepted and proceeds.
    authored_at: 2026-08-06T00:00:00Z
  - surface: rendered_line
    observable: >-
      Running the lane-liveness probe for that lane prints a verdict line reading
      "dead:sentinel_finalized" where it previously read "alive".
    authored_at: 2026-08-06T00:00:00Z
  - surface: rendered_line
    observable: >-
      The B8 lane (fresh log, no recorded pid, provider reporting cancelled, no run-dir
      sentinel) still prints "alive" — its verdict line is unchanged from before.
    authored_at: 2026-08-06T00:00:00Z
  - surface: file_artifact
    observable: >-
      docs/handoff/<TASK_ID>/ contains a report naming, per runner, whether a completion
      sentinel was found: glm and kimi with .finalized, codex and claude-subsession with
      none.
    authored_at: 2026-08-06T00:00:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-liveness.sh, plugins/leadv2/scripts/tests/test-lane-liveness-sentinel.sh, plugins/leadv2/scripts/tests/test-dispatch-resume-sentinel.sh, .claude/scripts/leadv2-lane-liveness.sh

DELIVERABLE_COMPLETE
===== END SCOPED DESIGN =====

===== ORIGINAL MISSION (context only; the design above wins on any conflict) =====
# LANE-LIVENESS-IGNORES-ITS-OWN-COMPLETION-SENTINEL-01

Repo: `/Users/kostiantyn.vlasenko/Projects/leadv2` (the plugin repo — the single source; never create
a real copy of a plugin file inside a project).

Do NOT touch lane `759ec34f` (plugin repo) or lanes `92954b82` / `472b95ed` (persona-engine).
Never run `git reset --hard`, `git clean` or `git stash` — shared trees with live work.

## The bug, observed live on 2026-08-06

Round 2 of a lane was refused with `lane_placement_refused reason=lane_is_live ref=472b95ed`
(`leadv2-dispatch-code.sh:~610`) while the worker was provably finished:

- the glm run dir `~/.claude/cache/glm-runs/260806-041752-472b95ed-776a/` carried `.done`,
  `.finalized` and `.outcome`;
- `ps` showed no process for that run;
- `leadv2-lane-liveness.sh` nevertheless returned
  `{"verdict":"alive","reason":"log_fresh","age_s":581,"pid":null}`.

The stream file had just been flushed at completion, and `silent_max` is 900s
(`leadv2-lane-liveness.sh:81`), so a cleanly-exited lane reads as alive for up to 15 minutes.

## Why the obvious fix is wrong — read this before you touch anything

`leadv2-lane-liveness.sh:~401` carries the B8 rule (SUPERVISOR-AUDIT-01 fix-round-3) with an explicit
comment: a FRESH log must never be overridden by a terminal provider self-report, because a reviewer
found a real case of a fresh session.log, no PID, and a mapped provider job reporting "cancelled" —
that must resolve alive, since *something is still actively writing*.

That rule is correct and stays. Do not invert it. Do not widen it.

The gap is narrower: a provider saying "I finished" is a self-report, but **the run's own completion
sentinel written by the runner, combined with no live process, is proof, not a report.** Today that
proof is never consulted at all.

## What to build

A new, narrow dead-verdict path: **completion sentinel present AND no live process ⇒ dead**,
evaluated regardless of log freshness, and distinct in its `reason` string from the provider-status
path so the two can be told apart in a journal.

Requirements:
1. Locate the runner-written sentinels (`.done` / `.finalized` / `.outcome` in the glm run dir; find
   the equivalents for the other runners — claude-subsession and codex — do not assume glm is the
   only one). If a runner has no sentinel, say so in the report rather than inventing one.
2. "No live process" must be positively established (pid absent or `kill -0` fails), not assumed
   from `pid: null`. A `pid: null` that merely means "we never recorded one" is NOT evidence of
   death — distinguish these two cases and say which one you treat as dead. If you cannot tell them
   apart, the safe answer is to require the sentinel AND an explicitly-recorded-then-dead pid; state
   the choice you made and why.
3. The verdict must carry a distinct `reason` (e.g. `sentinel_finalized`) so a reader can see this
   path fired.
4. B8 and every existing verdict path must keep their current behaviour. The B8 scenario (fresh log,
   no pid, provider says "cancelled", NO sentinel) must still resolve alive — lock that with a test
   so nobody re-breaks it later.

## Verification — mandatory
- A test that reproduces the exact observed case: sentinel present, no process, log mtime younger
  than `silent_max` ⇒ verdict dead. It must FAIL against current HEAD and pass after. Show both runs.
- A test locking the B8 scenario as still-alive (fresh log + terminal provider status + no sentinel).
- An end-to-end proof at the dispatcher level: with the sentinel present, `--resume-lane` on that
  lane is ACCEPTED rather than refused with `lane_is_live`. Use the test harness / fake launchers
  (`LEADV2_DISPATCH_SPAWN=0` or the `LEADV2_DISPATCH_*_BIN` overrides) — **no test may spawn a real
  provider session.**
- Run the full lane-liveness and dispatch test scopes; report counts before and after.

## Return
`PASS|FAIL|BLOCKED` + commit sha + the failing-then-passing run of each new test + the suite counts +
the list of runners you found sentinels for and the ones you did not. Commit in the lane before you
finish.

---
If you hit a decision you cannot safely make yourself (including destructive
options, a policy conflict, or missing authorization), ask via the async
question channel and wait for the answer rather than guessing or stalling:
  bash "${CLAUDE_PLUGIN_ROOT}/../../scripts/leadv2-ask.sh" "dispatch-47392a92" "<question>" \
    --option "a|<reversible label>" --option "b|<label>" --default-option "a" [--timeout <sec=1800>]
It blocks until answered via `/leadv2 reply <q-id> <option>` and prints the
chosen option. Every question must declare its clearly reversible option with
`--default-option`; on timeout the lane proceeds on it and the decision is
journaled and surfaced in open-threads. Without a default, the task is parked
human-needed and its slot is freed. Do not use this for routine progress or
confirmation-seeking; only for a decision you cannot make yourself.