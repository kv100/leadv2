# LANE-REGISTRY-SELF-DEADLOCK-01 — architect prepass (mechanism-closed design)

Base: `eb39d6f`. All line numbers read from the live tree on 2026-08-24.
Scope: `plugins/leadv2/scripts/leadv2-lane-liveness.sh`, `leadv2-dispatch-code.sh`,
`leadv2-active-registry.sh`, plus two test files. SessionStart worktree sweep is OUT
(SWEEPER-LANE-SAFETY-01 owns it).

---

## 0. Where the mission's framing and the code disagree (read this first)

The mission is right about the failure and right about the *shape* of both defects. Two
factual corrections, both of which change the diff:

**0.1 — `journal.md` is not a liveness input.** `grep -n 'journal\.md' leadv2-dispatch-code.sh`
returns nothing, and `leadv2-lane-liveness.sh` never opens
`docs/leadv2/tasks/*/journal.md`. The self-refreshed probe is a *different* file with the
same disease: the **architect-prepass child stream**
`docs/handoff/dispatch-<sig8>-architect/architect.stream.jsonl`, consumed at
`leadv2-lane-liveness.sh:506-531` and producing exactly the `starting:<age>` /
`prepass_stream_fresh` verdict the incident recorded (`:522`). That file is written by the
architect prepass *the dispatcher itself runs synchronously* at
`leadv2-dispatch-code.sh:4924` — i.e. by the attempt, not by a worker. The mission's
diagnosis ("the refusal path refreshes the probe it reads") is correct; the file is the
prepass stream, and the design below targets that.

**0.2 — the deadlock has two independent arms, and the mission names only one refusal
site.** The `--resume-lane` / `--worktree` refusal at `leadv2-dispatch-code.sh:787-820`
(`lane_placement_refused reason=lane_is_live`, exit 5) is the one the founder hit. But the
same `starting:*` verdict is *also* counted as a live lane by
`leadv2-lane-liveness.sh:713-716` (`count_live`), which `leadv2-backlog-pump.sh:260,371-443`
uses as the concurrency numerator. A self-refreshed prepass stream therefore both refuses
the explicit re-dispatch **and** silently consumes a cap slot for every other task. Fixing
only the refusal site leaves half the incident live.

**0.3 — `pid_birth` already exists.** `leadv2-active-registry.sh:562` stamps
`ps -o lstart=` at register time. The identity data the mission asks for is on disk today;
`leadv2-lane-liveness.sh:123-128 pid_alive()` simply ignores it. Defect 1's identity half is
a *read-side* fix, not a new write.

---

## 1. CALLERS / CALLEES

### 1.1 Functions being modified, with every caller

| Function (file:line) | Callers | Notes |
|---|---|---|
| `pid_alive(value)` — `leadv2-lane-liveness.sh:123` | `resolve()` :419 only | single call site; safe to replace |
| `resolve(tid)` — `:400` | `:687` (`--lane`), `:709` (`--all`) | both output paths |
| `sentinel_check(tid,row)` — `:305` | `resolve()` :617 | reads `row["pid_alive"]` at :377 — **must be re-read after the pid semantics change** |
| `age_from_started_at(session)` — `:150` | `:516`, `:544`, `:553`, `:575` | unchanged |
| `_resolve_pinned_placement()` — `leadv2-dispatch-code.sh:723` | `cmd_resolve` :4787 | the refusal site |
| `_spawn_worker_body()` (sonnet arm) — `leadv2-dispatch-code.sh:~3676-3700`, tail :3782-3790 | `spawn_worker` → `atomic_dispatch_reserve_spawn_confirm` :4342, `cmd_advance_arm` :5752 | **two** spawn paths; the new PID stamp must sit in `_spawn_worker_body`, not at one call site |
| `leadv2_active_register()` — `leadv2-active-registry.sh:533` | `leadv2-dispatch-code.sh:4877`; `leadv2-fanout.sh` (`_fanout_register_session`, independent second writer); gate1 self-reg | additive field only |
| registry python op dispatcher — `leadv2-active-registry.sh:158-440` | every `_leadv2_yaml_py_lock` caller | new op appended, no op renamed |

### 1.2 Consumers of `leadv2-lane-liveness.sh` output — the blast radius of "more lanes now read dead"

Verified by `grep -rn leadv2-lane-liveness.sh` in `plugins/leadv2/scripts/` (non-test):

| Consumer | What it does with `dead:*` | Risk of the change |
|---|---|---|
| `leadv2-dispatch-code.sh:791,801,2345` | not-live ⇒ allow the pin / re-dispatch | **this is the fix** |
| `leadv2-backlog-pump.sh:260,371-443` | dead ⇒ frees a cap slot | more dispatch throughput; intended |
| `leadv2-dispatch-ledger.sh:88,483-530` | dead + no commit ⇒ writes a terminal ledger row | **HIGH** — a false dead mints a false terminal for a live lane |
| `leadv2-worktree-cleanup.sh:27,32,67` | dead ⇒ **deletes the worktree** (guarded by unmerged/dirty checks) | **HIGHEST** — this is the only destructive consumer |
| `leadv2-writes-overlap.sh:71` | dead ⇒ ignores the row in collision checks | two lanes could overlap writes |
| `leadv2-lanes-snapshot.sh:317`, `leadv2-status-surface.sh:2457`, `leadv2-lane-status-line-tail.sh:259`, `leadv2-broad-status.sh:396`, `leadv2-lanes.sh:63` | display only | cosmetic |
| `leadv2-codex-planner.sh:206` | `--job` path | untouched (job branch not modified) |

Design consequence: **every new path to `dead:` must be gated behind an explicit
identity/role signal that only exists on rows written by the new code.** A legacy row (no
`pid_role`, no `worker_pid`) must resolve byte-identically to today. This is the single
hardest constraint in the change and it is what the kill switches below buy.

### 1.3 Callees the new code introduces

- `ps -o lstart= -p <pid>` — already used at `leadv2-active-registry.sh:562`; the trim
  (`tr -s ' ' | sed -e 's/^ *//' -e 's/ *$//'`) is load-bearing and is documented at :556-561
  as a prior regression. Reuse it verbatim on both sides; do not re-derive.
- `os.kill(pid, 0)` — unchanged primitive.
- No new external binaries. bash 3.2: no `declare -A`, no `${var^^}`, no `mapfile`.

---

## 2. STATES AND RETURN CODES

### 2.1 `leadv2-lane-liveness.sh --lane <id>` verdict states (post-change)

`row["verdict"]` strings are the contract; callers match on the `alive` / `starting:` /
`silent:` / `dead:` prefix families. **No new prefix family is introduced.**

| # | State | Verdict | Emitted at | Caller behaviour → user-visible consequence |
|---|---|---|---|---|
| 1 | child-suffix id | `child` | :413 | folded out of `--all`; never counted |
| 2 | worker stream fresh (`age ≤ 900`) | `alive` | :629 | re-dispatch refused (`exit 5`) → founder sees `REFUSE placement: lane_is_live` and is told to retry later. **Correct** when a worker really is running. |
| 3 | worker stream stale, `worker_pid` alive + birth matches | `silent:<age>` | :664 | not `alive`/`starting:` ⇒ placement pin **proceeds**; pump does not count it. Founder's re-dispatch succeeds. |
| 4 | worker stream stale, `worker_pid` alive, **birth mismatch** (recycled PID) | `dead:silent_<age>s_no_process` | :666 | pin proceeds; ledger may mint a terminal; worktree-cleanup may reclaim. **New reachable state — Defect 1b.** |
| 5 | worker stream stale, `pid_role=lead_durable`, no `worker_pid` | `dead:silent_<age>s_no_process` | :666 | pin proceeds. **New reachable state — Defect 1a, the deadlock-breaker.** Today this is state 3 forever. |
| 6 | no stream, registered, `age ≤ 300` | `starting:<age>` | :550 | refused as live. Bounded — self-clears at 300 s. |
| 7 | no stream, no artifact, `pid_role=lead_durable` only | `dead:no_log_artifact` / `dead:no_handoff_dir` | :565-567 | pin proceeds. **New** — today the C2 floor at :560 returns `silent:` forever. |
| 8 | prepass child stream fresh | `starting:<age>` (today, :522) → **removed**; falls to 6/7 | :506-531 | **Defect 2 fix.** Today: refused forever while any dispatch attempt keeps re-running the prepass. |
| 9 | `.finalized` sentinel + dead process group | `dead:sentinel_finalized` | :396 | unchanged |
| 10 | stat failure on the chosen log | `dead:log_stat_failed` | :576 | unchanged |
| 11 | provider terminal + not fresh | `dead:provider_<status>` | :608 | unchanged |
| 12 | wedged (`ps stat` contains `T`) | `dead:wedged_STAT=<s>` | :625 | unchanged; gated on `worker_pid` now (a wedged *lead* must never mark a lane dead) |

Process exit codes of `leadv2-lane-liveness.sh` are unchanged: `0` normal, `2` bad args.
Every caller reads stdout, not rc.

### 2.2 `leadv2-dispatch-code.sh` exit codes touched

| rc | Meaning | Site | What the caller does → user-visible consequence |
|---|---|---|---|
| 0 | dispatched / pinned | — | worker starts; `worker_spawned … handle=PID=<n>` on stdout |
| 2 | duplicate task signature | :5168-5175 | prints `dispatch_refused reason=duplicate_task_signature`; **not retried by any loop** → the task is simply never dispatched until a human clears the ledger |
| 4 | spawn failure | :3694 etc. | reservation rolled back; the next attempt is allowed |
| 5 | placement refused | :741,752,763,777,784,**819** | **This is the deadlock.** `leadv2-fanout.sh` / the backlog pump treat exit 5 as a hard refusal and do **not** retry with a different lane. Plain words: *the task is silently never worked on again, and the founder's only escape is to route around the dispatcher entirely — which is exactly what happened with EGRESS-STATUS-COLLECTOR-01.* |

**Nothing in the tree retries an exit-5.** Verified: the pump reserves before dispatch
(`leadv2-backlog-pump.sh:872`) and treats a non-zero dispatch as a failed attempt without
re-entering the placement path. That is why "no matter how many times" was literally true.

### 2.3 New registry op return contract

`set_worker_pid <task_id> <pid> <pid_birth>` — mirrors `set_worktree` (:240) and
`set_attempt` (:433): unknown `task_id` is a **silent no-op, rc 0**. Never creates a row.
Rationale: register/spawn ordering races must never kill a lane (stated at
`leadv2-active-registry.sh:588`). The bash wrapper is called with `|| true` at the call site,
matching `leadv2_active_set_log_path`'s call at :4885.

---

## 3. CONFIGURATION BOUNDARIES

Every input the changed mechanism reads, at each boundary.

### 3.1 `active.yaml` row fields

| Input | Absent | Empty (`""` / `null`) | Minimum | Maximum / over-cap | Malformed |
|---|---|---|---|---|---|
| `pid` | today: `pid_alive(None)` → `TypeError` caught → `False` (:127). Keep. | same as absent | `pid=1` → `os.kill(1,0)` raises `PermissionError` → today `False` (:127). **Keep this** — treating init as alive would be worse. | pid > `kern.maxproc` → `ProcessLookupError` → `False` | non-numeric → `ValueError` → `False` |
| `pid_birth` | fall back to bare `kill -0` and set `row["pid_identity"]="unverified"` | same | — | — | any string that `ps` cannot produce → mismatch is **not** asserted; degrade to `unverified`, never to `dead`. A malformed birth string must not kill a lane. |
| `pid_role` (**new**) | **legacy row → exact today's behaviour** (bare `kill -0`, C2 floor at :560 active) | treated as absent | — | — | any value other than `lead_durable` / `worker` → treated as absent |
| `worker_pid` (**new**) | fall through to `pid`/`pid_role` | treated as absent | `0` or negative → treated as absent (never `kill(0,0)`, which signals the whole process group) | — | non-numeric → absent |
| `worker_pid_birth` (**new**) | `pid_identity=unverified`; worker pid still trusted via `kill -0` | same | — | — | same as `pid_birth` |
| `started_at` | `age_from_started_at` → `None` + stderr WARN (:161-169). Unchanged. | same | — | — | unparseable → `None`, never a fabricated epoch (:137-148) |
| `log_path` | falls to the S1 candidate ladder (:477-490) | same | — | — | points at a nonexistent file → ignored for liveness, still recorded as `raw_log_path` (:446-457). Unchanged. |

**`active.yaml` file-level:** absent → `load_yaml` returns `{}` (:172-179) → every lane
resolves with `session=None`. Empty file → same. Malformed YAML → same. **This is a
fail-open to "no pid evidence"**, which after this change means lanes resolve on stream age
alone. That is the correct degradation and it is unchanged from today.

**Over-cap note (mission's explicit ask):** a single malformed row must not poison the
`--all` pass. `load_yaml` already swallows the whole-file failure; the per-row guard at
`:182-183` (`isinstance(s, dict) and s.get("task_id")`) drops bad rows individually. The new
field reads must be `session.get(...)` with the same tolerance — **no `int()` outside a
`try`, no `[]` indexing** — so one bad `worker_pid` cannot abort the pass and take every
other lane's verdict down with it.

### 3.2 Env flags

| Flag | Absent (default) | Empty | Min | Max | Malformed |
|---|---|---|---|---|---|
| `LEADV2_LANE_PID_IDENTITY` (**new**, liveness) | `1` — identity check on | `1` | `0` = restore bare `kill -0` | — | anything ≠ `0` ⇒ on (matches `sentinel_dead` idiom at :317) |
| `LEADV2_LANE_PREPASS_LIVE` (**new**, liveness) | `0` — prepass child stream is **not** a live signal | `0` | `1` restores :506-531 verbatim | — | anything ≠ `1` ⇒ off |
| `LEADV2_LANE_SILENT_MAX_S` | 900 (:76) | default | `_int_env` clamps `max(0,…)` | no cap — a huge value makes every lane permanently `alive` (pre-existing; do not "fix" here) | `ValueError` → default (:70-74) |
| `LEADV2_LANE_STARTING_MAX_S` | 300 | default | `max(0,…)` | same caveat | default |
| `LEADV2_LANE_ABANDON_MAX_S` | 3600 | default | — | — | default |
| `LEADV2_DISPATCH_ARCHITECT_TIMEOUT_SEC` | 420 (:574) | regex-validated → 420 (:575) | — | — | → 420 |
| `LEADV2_LEAD_GUARD` | `0` in this session | — | — | — | see §6 |

All new flags follow the `LEADV2_*` prefix and are threaded through **argv** into the python
heredoc, exactly like every existing tunable (`leadv2-lane-liveness.sh:63`) — never
`os.environ` inside the heredoc, except for the two documented runner-owned vars
(`GLM_RUNS_DIR` / `KIMI_RUNS_DIR`, :232-234). Adding a 17th argv slot means the unpack at
`:65-68` must be extended in lockstep; that tuple unpack is the single most likely place to
break the script silently for **every** consumer.

### 3.3 `ps -o lstart= -p <pid>` boundaries

- pid gone → empty stdout → **`unverified`**, not `mismatch`. (A dead pid is already caught
  by `kill -0`; letting an empty `ps` mean "mismatch" would double-count.)
- pid owned by another user → macOS `ps` still prints `lstart` → match works.
- `ps` missing / times out → treat as `unverified`. Bound it: the existing `ps_stat()`
  helper (:130-135) uses `timeout=2`; reuse the same shape.
- Darwin right-pads the field; the trim at `leadv2-active-registry.sh:562` is byte-exact and
  was a prior regression (:556-561). Writer and reader **must** use the identical trim.

---

## 4. COUNTEREXAMPLE — what can still deadlock after all of this

After both fixes land, one hole remains and it is reachable. **The `worker_pid` stamp
happens after a successful spawn (`_spawn_worker_body`, ~:3691-3700), but the `active.yaml`
row is created earlier, at `:4877`, and the two are not atomic.** Every dispatch that
registers the row and then dies before the spawn confirm — a burn-gate park (:1450), a
duplicate-signature refusal (:5168), a prepass park after N attempts (:4929), an arm-refusal
cascade, or a `kill -9` on the lead — leaves a row whose only pid is `lead_durable`. With
this design that row now correctly resolves dead once its stream ages past
`STARTING_MAX`/`SILENT_MAX`, so it *does* clear — but **it stays live-looking for up to
`starting_max` (300 s) or, if a stream exists, `silent_max` (900 s) after every attempt.**
A retry loop tighter than that window still cannot converge; it just fails for minutes
instead of forever. Closing that fully means making registration and worker-pid stamping a
single locked transaction, which is a larger change than this lane should carry — I
recommend the implementer **not** attempt it here and instead record it as a follow-up.

Two smaller residual holes, both checked and both accepted:

1. **`leadv2-fanout.sh`'s `_fanout_register_session` is an independent second `active.yaml`
   writer** (named at `leadv2-active-registry.sh:214`). It will not stamp `pid_role`, so its
   rows keep today's legacy behaviour. A fanout-registered lane whose worker dies is
   therefore **still not reclaimable** by this fix. This is a deliberate scope boundary, not
   an oversight — but it means "the deadlock is fixed" is true only for
   `leadv2-dispatch-code.sh`-registered lanes. Say so in the close note.
2. **PID recycling within the same clock second** defeats `lstart` matching (1-second
   resolution). The failure direction is *false alive*, which is safe.

What I checked to write this paragraph: every `exit 5` site (:741,752,763,777,784,819),
every `return`/`row.update` path in `resolve()` (:413-667), the two `active.yaml` writers,
and every non-test consumer of the liveness binary.

---

## 5. THE CHANGE — exact files, exact edits

### 5.1 `plugins/leadv2/scripts/leadv2-active-registry.sh`

- **`register` op (:196-235):** add `"pid_role": "lead_durable"` to the new-row dict. Do
  **not** add it on the `refresh_existing` branch (:179-190) — refreshing must not
  retroactively relabel a row a fanout runner owns.
- **New python op `set_worker_pid`** (append after `set_attempt`, :433): args
  `(task_id, pid_str, birth)`; on the matching row set `worker_pid` (int or None),
  `worker_pid_birth`, `pid_role="worker"`, `updated_at=_now_iso()`; `break`. Unknown
  task_id ⇒ no-op.
- **New bash wrapper `leadv2_active_set_worker_pid <task_id> <pid> <pid_birth>`** beside
  `leadv2_active_set_log_path` (:598-601), same `_leadv2_yaml_py_lock` shape.
- **New bash helper `_lv2_pid_birth <pid>`** wrapping the exact trim from :562; make
  `leadv2_active_register` call it instead of inlining, so the writer and the new stamp can
  never drift.
- Do **not** touch `update_pid` (:287-295) — `leadv2-backlog-pump.sh:652` owns it.

### 5.2 `plugins/leadv2/scripts/leadv2-dispatch-code.sh`

- **:4874** — promote `local reg_id=…` to a script-scope `DISPATCH_REG_ID="${reg_id}"` so
  `_spawn_worker_body` can address the row. (`_spawn_worker_body` runs in a command
  substitution; it must **not** try to return the value — it writes to `active.yaml`, which
  escapes the subshell, exactly as `_dispatch_register_arm` at :3795 already does.)
- **`_spawn_worker_body`, sonnet arm, immediately after the `kill -0 "${pid}"` check passes
  (~:3697):** compute `birth="$(_lv2_pid_birth "${pid}")"` and call
  `leadv2_active_set_worker_pid "${DISPATCH_REG_ID}" "${pid}" "${birth}" 2>/dev/null || true`.
  Guard on `[[ -n "${DISPATCH_REG_ID:-}" ]]` (bash 3.2, `set -u` is on at :257).
  Other arms (glm/kimi/codex) expose no pid in the handle → **no stamp**, `pid_role` stays
  `lead_durable`, and they keep resolving on stream age + the sentinel path. Do not invent a
  pid for them.
- **`_resolve_pinned_placement` step 5 (:787-820):** restructure to **one** `--json` probe
  per candidate id (today it shells out twice, :791 and :801). From the row take `verdict`
  and `reason`. Derive `signal`: `pid_identity` if `reason` contains `process_alive` or
  `no_process`; `stream_fresh` if it contains `log_fresh` or `stream_fresh`; else `none`.
  Emit **on both branches**:
  `emit decision "lane_liveness verdict=<live|dead> task=${sig8:-?} signal=<…>"`
  — `live` when verdict is `alive`/`starting:*`, `dead` otherwise. This is deliverable #2.
  Keep the existing `lane_placement_refused` line unchanged on the live branch.
- Re-source guard: the registry sets `set -euo pipefail`; the file already re-asserts
  `set +e` after sourcing (:4886-4894). If the new wrapper is called from
  `_spawn_worker_body`, that function must ensure the registry is sourced **and** restore
  `set +e` in its own scope, per the note at :3428. Do not skip this — it is the documented
  root cause of E2E-GATE-RESIDUE-01 round 4.

### 5.3 `plugins/leadv2/scripts/leadv2-lane-liveness.sh`

- **argv (:63-68):** append `LEADV2_LANE_PID_IDENTITY` and `LEADV2_LANE_PREPASS_LIVE`;
  extend the unpack tuple in lockstep.
- **Replace `pid_alive` (:123-128)** with `pid_state(pid, birth, identity_on)` returning one
  of `("dead", "alive_verified", "alive_unverified")`, per §3.3. Keep a thin `pid_alive`
  shim if any other reference exists (there is only :419).
- **`resolve()` (:416-426):** choose the pid source — `worker_pid` if present, else `pid`.
  Record `row["pid"]`, `row["pid_alive"]`, and new `row["pid_source"]`
  (`worker` | `lead_durable` | `legacy`) and `row["pid_identity"]`
  (`verified` | `unverified` | `mismatch`). `legacy` = no `pid_role` field at all.
- **The three places pid evidence keeps a lane out of `dead:`** — the C2 floor (:560-563),
  the wedged check (:622-626), and the `pid_alive` branch (:663-664) — must first ask
  `row["pid_source"] != "lead_durable"`. When the source **is** `lead_durable`, pid evidence
  is ignored and the age ladder decides (states 5 and 7 in §2.1). `legacy` behaves exactly
  as today.
- **`sentinel_check` (:375-378)** reads `row["pid_alive"]`: a `lead_durable` pid must no
  longer block the sentinel from firing. Change the guard to
  `pid_recorded and row.get("pid_alive") and row.get("pid_source") != "lead_durable"`.
- **Prepass child-stream branch (:506-531):** when `LEADV2_LANE_PREPASS_LIVE != 1`
  (the new default), skip the branch entirely and fall through to tier A (:540-551). Keep
  the whole block behind the flag rather than deleting it, so the R-6 rationale and its
  fixture stay testable. Rationale for the default flip: the prepass runs **synchronously
  inside the dispatcher** (:4924, before any spawn), so by the time any *other* process
  probes that stream, the prepass is by construction finished or abandoned — a fresh mtime
  there is residue of a dispatch attempt, never proof of a running worker. That is precisely
  the mission's "never files the dispatcher/refusal path itself writes".
- `count_live` (:713-716) is unchanged in form; it simply stops seeing prepass residue.

### 5.4 Tests

**New — `plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh`** (fixtures only,
no real spawns, bash 3.2, `mktemp -d` project root, `--no-codex` on every probe):

- **(a)** row with `pid_role: lead_durable`, live pid (`$$`), no `worker_pid`, stale
  `developer.stream.jsonl` (mtime −7200) ⇒ verdict matches `^dead:` ⇒ reclaimable.
- **(b)** row with `worker_pid: $$`, `worker_pid_birth: "Jan  1 00:00:00 2000"` (deliberate
  mismatch), stale stream ⇒ `^dead:` and `pid_identity=mismatch`.
- **(c)** refusal idempotence: snapshot `--json` for the lane **and** an
  `ls -l`-style mtime census of `docs/handoff/<lane>*` + `docs/leadv2/tasks/<lane>/`; run
  the dispatcher's refusal path with `LEADV2_DISPATCH_SPAWN=0` and
  `LEADV2_JOURNAL_BIN=/bin/true` unset (journal **must** be written, that is the point);
  re-probe. Assert the verdict/`reason`/`source` triple is byte-identical and that no file
  the probe reads changed mtime. Sleep 2 s between the two probes so an unfixed
  self-refresh would be visible as an age reset.
- **(d)** `worker_pid: $$` with a birth string captured live from
  `ps -o lstart= -p $$ | tr -s ' ' | sed …`, plus a `developer.stream.jsonl` touched now ⇒
  `alive`, and the dispatcher's `--resume-lane` path exits 5 with
  `lane_liveness verdict=live … signal=stream_fresh` in the journal.

**Modified — `plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh`:** the R-6
prepass-stream assertion must set `LEADV2_LANE_PREPASS_LIVE=1` to keep asserting the old
behaviour, and gain a sibling case asserting the new default. Its D1/D2/C2 negative controls
must stay green **unchanged** — they are the legacy-row regression proof.

**Green bar:** `bash -n` on all three modified scripts, plus
`test-lane-liveness-authoritative.sh`, `test-lane-liveness-lies.sh`,
`test-lane-liveness-sentinel.sh`, `test-lane-placement-pin.sh`, `test-lane-truth-batch-01.sh`,
`test-dispatch-retry-dead.sh`, `test-dispatch-duplicate-caller-race.sh`,
`test-codex-worker-liveness.sh`, `test-pulse-liveness-job-registry.sh`, and the new file.

---

## 6. Risks and mitigations

| # | Risk | Mitigation |
|---|---|---|
| R1 | A new `dead:` path reaches `leadv2-worktree-cleanup.sh` and deletes a live lane's worktree. | Every new `dead:` path requires `pid_role` present — legacy rows are untouched. Cleanup's own unmerged/dirty guards remain. `LEADV2_LANE_PID_IDENTITY=0` is the one-flag rollback. |
| R2 | The 17-slot argv unpack at `:65-68` is edited out of lockstep ⇒ `ValueError` on every liveness call ⇒ every consumer silently degrades. | `bash -n` will not catch it. Require one live `--all --json` smoke run against the real repo root in the test file. |
| R3 | `pid_role` on the `refresh_existing` branch would relabel a fanout runner's row. | Explicitly only on the new-row branch (§5.1). |
| R4 | `set -e` leaking from the sourced registry into `_spawn_worker_body` turns a stamp failure into a dead dispatch. | `|| true` on the wrapper call + the documented `set +e` restore (:4886). |
| R5 | `worker_pid` stamped for the wrong lane when `DISPATCH_REG_ID` is stale across `cmd_advance_arm`. | Guard on non-empty; `cmd_advance_arm` (:5752) must set it too or skip the stamp. Prefer skip over guess. |
| R6 | Mission/code divergence (§0) makes the review round argue about `journal.md`. | Stated up front, with the grep that proves it. |

---

## 7. Out of scope (implementer: ignore)

- SessionStart worktree sweep and every sweep hook — SWEEPER-LANE-SAFETY-01.
- `leadv2-fanout.sh` `_fanout_register_session` (the second `active.yaml` writer).
- `update_pid` op and `leadv2-backlog-pump.sh:652`.
- The codex `--job` branch of liveness (:681-685).
- Making registration + worker-pid stamping atomic (§4 residual hole) — follow-up lane.
- Any change to `silent_max` / `abandon_max` defaults.
- `one-copy` drift regressions reported by the SessionStart hook.

---

```
acceptance:
  - surface: log_line
    observable: "The task journal for the lane shows a line reading `lane_liveness verdict=dead task=<sig8> signal=pid_identity` on the attempt that reclaims a lane whose worker has died, and `verdict=live … signal=stream_fresh` on an attempt that is correctly refused while a worker is still writing."
    authored_at: 2026-08-24T09:47:00Z
  - surface: rendered_line
    observable: "Re-running the same dispatch command against a lane whose worker process is gone prints the pinned-placement line instead of `REFUSE placement: lane_is_live`, and the founder is not told to `Re-run once it clears` for a lane that will never clear."
    authored_at: 2026-08-24T09:47:00Z
  - surface: file_artifact
    observable: "`docs/leadv2/active.yaml` shows, for a lane dispatched through leadv2-dispatch-code.sh with a sonnet worker, a `worker_pid` whose value is the same number the dispatcher printed in `worker_spawned … handle=PID=<n>`, and that number is not the lead session's pid."
    authored_at: 2026-08-24T09:47:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-liveness.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-active-registry.sh, plugins/leadv2/scripts/tests/test-lane-registry-self-deadlock.sh, plugins/leadv2/scripts/tests/test-lane-liveness-authoritative.sh

DELIVERABLE_COMPLETE
