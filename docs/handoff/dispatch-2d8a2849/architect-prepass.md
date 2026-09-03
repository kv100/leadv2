# GATE-FALSE-SILENT-01 — architect prepass (mechanism-closed design)

Target: `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`, function `pc_silent_arm_probe`
(L1243-1276) and its single call site (L2026-2034).

---

## 0. What the tree says happened on lane `4d5aabd0` — and where the mission's framing is wrong

Measured on disk, 2026-08-23 (all local times, same clock as the mission's table):

```
$ stat -f '%N birth=%SB mod=%Sm' -t '%H:%M:%S' docs/handoff/dispatch-4d5aabd0/{developer.stream.jsonl,arm-registered,review-gate.md,review.diff,.arm-advanced-codex}
developer.stream.jsonl birth=08:48:23 mod=08:51:36
arm-registered         birth=08:33:14 mod=08:48:24
review-gate.md         birth=08:48:22 mod=08:48:22
review.diff            birth=08:48:24 mod=08:48:25
.arm-advanced-codex    birth=08:48:23 mod=08:48:23

$ cat docs/handoff/dispatch-4d5aabd0/arm-registered
arm=codex  handle=task-mt5dfn6n-td7lok ... epoch=1787463194 ...
arm=sonnet handle=PID=63565 LABEL=developer-dispatch-4d5aabd0-1787464103 ...
           STREAM=/Users/kostiantyn.vlasenko/Projects/leadv2/docs/handoff/dispatch-4d5aabd0/developer.stream.jsonl
           epoch=1787464104 ...

$ git worktree list | grep 4d5aabd0
.../.claude/worktrees/4d5aabd0   4d340e2 [worktree-4d5aabd0]
$ git -C .claude/worktrees/4d5aabd0 status --porcelain    # (empty — clean)
$ cat ~/.claude/cache/dispatch-4d5aabd0.start-sha
aed1f2bc5abefbe42fa044434a2101a6f476525a
$ git -C .claude/worktrees/4d5aabd0 rev-list --count aed1f2b..HEAD
1
```

Three facts follow, and the third contradicts the mission.

1. **Defect 1 is exactly as the mission states.** The lane worktree HEAD is `4d340e2`, one commit
   ahead of the recorded start sha `aed1f2b`, and the worktree is clean. `pc_silent_arm_probe`'s
   final two lines (L1272-1273) ask only "is there a lane root, and is it dirty" — a committed lane
   is indistinguishable from an untouched one.

2. **The stream file did not exist when the verdict was written.** `review-gate.md` was created at
   08:48:22; `developer.stream.jsonl` was created at 08:48:23 — **one second later**. So at probe
   time `[[ -f "${stream}" ]]` was false, `_PC_SILENT_STREAM_STATE` stayed `absent`, and the whole
   growth-guard block (L1259-1270) was skipped because it is itself wrapped in `if [[ -f
   "${stream}" ]]`. That is why the 60 s guard did not fire. This confirms the mission's
   parenthesised hypothesis.

3. **The stream that "kept growing until 08:51" was NOT the judged arm's stream.** The judged arm
   was `codex` (`review-gate.md` says `arm: codex`; the advance marker is `.arm-advanced-codex`).
   `developer.stream.jsonl` is the **sonnet** stream convention — `leadv2-dispatch-code.sh:2107`
   and `:3375` build that exact path for sonnet spawns, and this lane's own `arm-registered` line
   for `arm=sonnet` names it verbatim in `STREAM=`. It was born at 08:48:23, i.e. it was created by
   the *replacement* sonnet arm that `_pc_arm_advance` spawned at 08:48:23 as a consequence of the
   false verdict. The codex worker was not alive at 08:48:22; it had committed at 08:48:09 and
   exited.

   Therefore the mission's "the probe runs while the worker is still alive" is a **misreading of the
   artifact for this lane**. The true shape of defect 2 is worse and more general:

   > **A codex arm never writes `developer.stream.jsonl` at all.** For `AUTHOR=codex` the stream is
   > structurally absent, not racily absent. Condition (1) of the probe ("zero assistant events") is
   > therefore vacuously satisfied for **every** codex arm, on every run, and the growth guard —
   > gated on the file existing — is permanently inert for codex. The probe's only remaining
   > discriminator for a codex arm is the dirty-check, which defect 1 already showed is wrong for a
   > committing worker.

   The race the mission describes is real too, but for **sonnet** arms: `arm-registered` for sonnet
   is written at spawn, and the stream file appears fractions of a second to seconds later, so a
   close gate that reaches the probe in that window sees `absent` and skips the guard. Both the
   structural case (codex) and the racy case (sonnet) are closed by the same change.

Design consequence: fix 2 must not be written as "handle the race". It must be written as "the
absence of a stream is never evidence of silence", which covers both.

---

## 1. CALLERS / CALLEES

### 1a. Callers of `pc_silent_arm_probe`

| Caller | file:line | Path | Notes |
|---|---|---|---|
| main flow, post-`pc_await_worker_exit` | `leadv2-dispatch-product-close.sh:2026` | the only production caller | Runs **after** both worker-wait branches (L1975-2013) and **before** `pc_scope_diff` (L2036). `_lane_root` is (re)resolved immediately above at L2021-2024. |
| `tests/test-dispatch-silent-arm.sh` (cases 1-5) | `test-dispatch-silent-arm.sh:57, 106, 138, 168, 196` (approx — each case `bash "$PRODUCT_CLOSE_SH" ...`) | drives the real script end-to-end, never a reimplementation | **Not wired into `run-core-offline.sh`** — `grep -n silent-arm plugins/leadv2/scripts/tests/run-core-offline.sh` returns nothing. Must be run explicitly. |

`grep -rl pc_silent_arm_probe .` → exactly three files: the script, that test, and
`docs/handoff/ARM-PRODUCES-NOTHING-01-fix1.md` (prose). **There is no independent second copy of
this probe.** (One-copy note: the shared trees carry per-file symlinks to canonical, so editing
`plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` in this repo is the single edit.)

### 1b. Callees of `pc_silent_arm_probe` (today)

| Callee | file:line | Contract |
|---|---|---|
| `_pc_arm_registered` | :1210 | rc0 iff `arm-registered` names `arm=<AUTHOR>` (anchored first-field match) |
| `_pc_arm_registered_file` | :1197 | `$LEADV2_DISPATCH_ARM_REGISTERED_FILE` or `${HANDOFF}/arm-registered` |
| `_pc_stat_mtime` | :1163 | darwin `-f %m` then linux `-c %Y`; rc1 on any failure |
| `_pc_lane_dirty` | :1149 | rc0 dirty, excluding `_PC_PORCELAIN_EXCLUDE_RE` (orchestration-owned paths) |
| `grep -c`, `date +%s`, `basename` | — | external |

### 1c. Callees added by this design

| Callee | file:line | Why it is safe to call from the probe |
|---|---|---|
| `_pc_diff_base <repo_abs>` | :1650 | Pure: reads `LEADV2_LANE_START_SHA` or `${CACHE_BASE}/dispatch-${TASK}.start-sha`, prints a merge-base or empty. Sets no globals, writes no files. **Definition order:** it is defined at L1650, the probe is *defined* at L1243, but the probe is *called* at L2026 — bash resolves function names at call time, so L1650 has already executed. Safe, and this is the same reason `pc_scope_diff` can use it. |
| `_pc_process_alive <run_dir> [pid]` | :788 | Pid-file-only liveness; explicitly never `pgrep -f` (self-match bug). Already used by `pc_worker_alive`. |
| `_pc_run_dir_for <author> <handle>` | :555 | run-dir path for glm/kimi/codex handles |
| `_pc_meta_value <meta> pid` | (defined near :555) | reads `pid:` from `meta.yaml` |

### 1d. Callers of the verdict this probe gates

`_pc_arm_advance` (:1282) has **two** callers, and only one is affected here:

- `:2031` — the silent-arm branch. **This design narrows its reachability.**
- `:772` — `_pc_maybe_quota_advance`, reached from `pc_worker_alive`'s glm/kimi `status==failed`
  branch (:~1035) and from the codex quota path. **Untouched**, and it is the reason a genuinely
  dead codex arm still advances the chain even after this change (see §4).

---

## 2. STATES AND RETURN CODES

`pc_silent_arm_probe` returns rc0 = "this arm produced nothing" (silent) or rc1 = "not silent".

### 2a. Caller behaviour per rc (unchanged by this design)

| rc | Caller does (`:2026-2034`) | Terminal user-visible consequence |
|---|---|---|
| 0 | writes `review-gate.md` = `status: blocked / reason: arm_produced_nothing / arm: <AUTHOR>`; `emit decision review_gate ... terminal=no_work cause=arm_produced_nothing`; `_dl_note no_work`; `_pc_arm_advance`; `_stamp_review_terminal blocked`; `exit 5` | The lane is closed as having produced nothing, **review and e2e never run**, and a fresh arm is spawned on the same mission. If the arm in fact committed, the founder is told nothing was produced while a correct commit sits in the lane worktree, and a second (paid) arm redoes work that already exists. This is the 4d5aabd0 outcome. |
| 1 | falls through to `pc_scope_diff` (:2036) | Ordinary path: a real diff → selfcheck → e2e → review; an empty diff → `empty_diff`/`unscoped_lane_work` no_work verdict. **No arm advance from this path** — `_pc_arm_advance` is not called by the empty_diff branch. Consequence of a wrong rc1 on a genuinely silent arm: the lane is still blocked, but the chain does not move to the next arm — the task stops and nothing retries it, until `_pc_maybe_quota_advance` fires (quota-shaped deaths only). |

### 2b. Probe state table — today vs designed

`R` = arm registered for AUTHOR; `S` = stream state; `A` = assistant-event count; `G` = stream mtime
inside growth window; `C` = commits ahead of base; `W` = worktree dirty; `P` = worker process
provably alive.

| # | R | S | A | G | C | W | P | today | designed | why |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | no | * | * | * | * | * | * | rc1 | rc1 | not our path — `empty_diff` owns it (unchanged) |
| 2 | yes | absent | — | — | — | clean | — | **rc0 (bug)** | **rc1** | absent stream = too early / codex has no stream. **This is the 4d5aabd0 case and test Case 1.** |
| 3 | yes | absent | — | — | — | dirty | — | rc1 | rc1 | unchanged |
| 4 | yes | present | ≥1 | * | * | * | * | rc1 | rc1 | real assistant turns (unchanged, L1257) |
| 5 | yes | present | 0 | yes | * | * | * | rc1 | rc1 | growth guard (unchanged, test Case 3) |
| 6 | yes | present | 0 | no | 0 | clean | no | rc0 | **rc0** | the genuinely-silent path — preserved (test Case 4, mission verification #3) |
| 7 | yes | present | 0 | no | **≥1** | clean | no | **rc0 (bug)** | **rc1** | committed work is production — mission fix #1 |
| 8 | yes | present | 0 | no | 0 | dirty | * | rc1 | rc1 | unchanged (L1273) |
| 9 | yes | present | 0 | no | 0 | clean | **yes** | rc0 | **rc1** | live process is never silent — mission fix #2 |
| 10 | yes | present | 0 | no | — | no `_lane_root` | * | rc1 | rc1 | unchanged (L1272) |
| 11 | yes | present | 0 | no | *stat failed* | clean | no | rc1 | rc1 | fail-open on stat (unchanged, L1268) |
| 12 | yes | present | 0 | no | *base unresolvable* | clean | no | rc0 | **rc0** | see §3, `C` boundary — no base means no commit can be *proven*, and today's behaviour ignores commits entirely, so this cannot be a regression. Keeps test Cases 4 (and the fixture repos, which have no `origin/main` and no start-sha). |

### 2c. Rows 2 and 7 are the whole bug

Row 7 is defect 1. Row 2 is defect 2, and row 2 is the one that actually fired on 4d5aabd0 (the
codex arm never had a stream at all), with row 7 as the second, independent reason the same lane
would have been misjudged even if the stream had existed.

---

## 3. CONFIGURATION BOUNDARIES

Every input the mechanism reads, at absent / empty / minimum / maximum / malformed.

| Input | Read at | absent | empty | minimum | maximum / over-cap | malformed | Verdict on the boundary |
|---|---|---|---|---|---|---|---|
| `LEADV2_PC_SILENT_GROWTH_S` | :1260 | `60` | regex fails → `60` | `0`: `now-mtime < 0` is never true → guard never fires; a just-written stream can be judged silent | e.g. `999999999`: **every** arm is permanently NOT-silent → `arm_produced_nothing` becomes unreachable → the chain never advances for any lane, not just this one. **This is a defect, not a safety feature** — it takes down the whole advance mechanism, not one operation. Mitigation: clamp to `[1, 3600]`, journal `growth_s_clamped`. | non-numeric → `60` | Clamp added; `0` folded into the clamp minimum of 1. |
| `${HANDOFF}/developer.stream.jsonl` | :1247 | **designed: rc1 (NOT silent)** — was the bug | zero-byte file: `grep -c` → 0, mtime governs; unchanged | 1 line | multi-MB (this lane: 323 KB): `grep -c` is a full scan; acceptable, it is already the status quo | invalid JSON lines: `grep -c '"type":"assistant"'` is a byte match, unaffected | absent is the only changed cell |
| `${HANDOFF}/arm-registered` (or `LEADV2_DISPATCH_ARM_REGISTERED_FILE`) | :1197, :1213 | rc1 → not our path | zero-byte → `-s` fails → rc1 | one `arm=` line | many lines (this lane has 2) → linear scan, fine | garbage lines → no anchored `arm=<AUTHOR>` first field → rc1 | unchanged |
| `LEADV2_LANE_START_SHA` / `${CACHE_BASE}/dispatch-${TASK}.start-sha` | :1651-1653 (via `_pc_diff_base`) | falls back to `origin/main` merge-base; if that also fails → empty base → row 12 | same as absent | a sha equal to HEAD → `C=0` → silent-eligible, correct | a sha from a *different repo* (documented multi-repo case, :1647) → `cat-file -e` fails → `origin/main` fallback | non-sha text → `cat-file -e` fails → fallback | unchanged; **the design deliberately reuses this exact function so the probe and `pc_scope_diff` cannot disagree about the base (mission fix #1)** |
| `_lane_root` / `LEADV2_LANE_WORK_ROOT` | :2021-2024, :1272 | resolves via `leadv2-lane-worktree.sh path-of`; still empty → rc1 (row 10) | rc1 | — | points at the **shared main checkout** instead of a lane worktree → other lanes' commits count as production → false rc1 (over-conservative). Acceptable: fails toward "not silent", which is the safe direction, and matches `_pc_lane_dirty`'s existing exposure. | non-git dir → `rev-list` fails → `C=0` (no proof), `_pc_lane_dirty` already rc1 → row 10/12 | new commits-ahead read must fail closed to `C=0`, never abort the gate |
| lane HEAD (new read) | new helper | unborn HEAD (`rev-list` fails) → `C=0` | — | 1 commit → rc1 (the fix) | 10k commits → `--count` is O(n) on the range only, bounded by `base..HEAD` | detached HEAD → still resolvable; `merge-base` may fail → empty base → row 12 | never fatal |
| worker run dir / `meta.yaml pid` (new read) | :555, :788 | no run dir → skip liveness check, continue | empty pid → `_pc_process_alive` handles (rc1) | — | — | garbage pid → `kill -0` fails → treated as not alive | liveness is an *additional* NOT-silent trigger only; its failure never manufactures silence |
| `LEADV2_ARM_ADVANCE`, `LEADV2_DISPATCH_CANDIDATE_ARMS`, `LEADV2_DISPATCH_LANE_MISSION` | :1289-1313 | unchanged | unchanged | — | — | — | out of scope |

**Env-var naming check:** every variable named above already carries the `LEADV2_` prefix. **This
design introduces no new environment variable.** The clamp reuses `LEADV2_PC_SILENT_GROWTH_S`.

**Path existence check:** `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` ✓,
`plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` ✓,
`plugins/leadv2/scripts/tests/run-core-offline.sh` ✓,
`plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh` **(to-create)**.

**Concurrent access:** the probe reads `${HANDOFF}/developer.stream.jsonl` while a worker may be
appending, and reads the lane worktree while a worker may be committing. Both reads are
single-shot and both new failure directions resolve to "NOT silent", so a torn read cannot
manufacture a false silent verdict. No lock is required or recommended. `_pc_arm_advance`'s
`.arm-advanced-<AUTHOR>` marker (:1283-1288) remains the one-shot guard.

---

## 4. COUNTEREXAMPLE — what can still violate the invariant after every finding here is fixed

The invariant: *a lane that produced work is never closed as `arm_produced_nothing`.*

After this fix, three things can still violate it or its dual.

**(a) Work that is neither a commit nor a dirty file.** The probe proves production from exactly two
surfaces — commits ahead of base, and worktree dirt (plus assistant events). A worker whose entire
output went somewhere else — a cross-repo checkout the lane root cannot see, a `docs/handoff/` or
`docs/leadv2/` path (both hard-excluded by `_PC_PORCELAIN_EXCLUDE_RE` in `_pc_lane_dirty`, :1155,
and by `_pc_git_diff`), or a commit on a branch that is not the worktree's HEAD — is still
invisible, and if its arm is registered with no stream it will still be called silent. The
`docs/handoff` case is partly covered upstream by `pc_precheck_writes` (:1367) but only when the
write-set is *declared*; an undeclared handoff-only lane still lands here.

**(b) The dual violation this fix creates: a genuinely silent codex arm now stops advancing the
chain.** Because `developer.stream.jsonl` is the sonnet convention and codex never writes it,
"absent ⇒ NOT silent" makes `arm_produced_nothing` **unreachable for every codex arm**. A codex arm
that truly does nothing now falls through to `pc_scope_diff`'s `empty_diff` verdict — still a
blocked/no_work terminal, so the founder is not lied to, but the empty_diff branch does **not** call
`_pc_arm_advance`, so the chain does not move to the next arm. The only remaining advance for a dead
codex arm is `_pc_maybe_quota_advance` (:762-773), which fires solely on quota-shaped deaths. Net:
this fix trades a false-blocked-with-advance for a true-blocked-without-advance on the codex arm.
That is the right trade (never discard a real commit), but it is a real, named coverage loss and the
follow-up is to give codex arms a stream/exit anchor of their own — **out of scope here**, and it
should be a separate task, not smuggled into this diff.

**(c) A stale `.arm-advanced-<AUTHOR>` marker.** Untouched by this design: if a prior run left the
marker, a later legitimately-silent arm is journaled `already_advanced` and the chain still does not
move (:1284-1287). Pre-existing, unrelated to the two defects, flagged not fixed.

What I checked to reach this: the full body of `pc_silent_arm_probe` and its four callees, both
`_pc_arm_advance` call sites, `pc_worker_alive`/`pc_await_worker_exit`, `_pc_diff_base`/
`_pc_repo_diff`, `_pc_lane_dirty`'s exclusion regex, all five cases of the existing test, and a
repo-wide `grep -rl pc_silent_arm_probe` to rule out a second copy.

---

## 5. THE CHANGE — exact files and edits

### 5a. `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh`

**Edit 1 — new helper, inserted immediately after `_pc_lane_dirty` (after :1157).** Bash 3.2 safe,
no associative arrays, no GNU-only flags.

```
_pc_lane_commits_ahead()   # <root> -> stdout integer count (0 when unprovable); always rc0
```

Behaviour: return `0` unless *all* of — root non-empty and a directory; `git rev-parse
--is-inside-work-tree` succeeds; `_pc_diff_base <root>` yields a non-empty base; `git rev-list
--count <base>..HEAD` prints digits — hold. Any failure prints `0`. It must never `set -e`-abort the
gate; every git call is `2>/dev/null || true`-guarded.

Rationale for "unprovable ⇒ 0": today the probe ignores commits entirely, so treating an
unresolvable base as "no commits proven" is byte-identical to today for that state (row 12) and
cannot regress any lane. Resolving the base through `_pc_diff_base` is what satisfies mission fix #1
("take the base from the same source `pc_scope_diff` uses").

**Edit 2 — new helper, inserted next to it.**

```
_pc_worker_process_alive()   # -> rc0 iff a worker process for AUTHOR/HANDLE is provably alive
```

For `AUTHOR=sonnet` with a numeric `HANDLE`: `kill -0`. Otherwise: `_pc_process_alive
"$(_pc_run_dir_for "${AUTHOR}" "${HANDLE}")" "$(_pc_meta_value .../meta.yaml pid)"`. Empty `HANDLE`
or missing run dir → rc1 (not provably alive), never rc0. It must **not** call `pc_worker_alive` —
that function has side effects (`_pc_maybe_quota_advance`, `_pc_reap_worker`, journal emissions) and
returns rc0 for *unknown* states, which would invert the meaning here.

**Edit 3 — rewrite `pc_silent_arm_probe`'s conditions (2)-(3), L1256-1275.** New order, each step
returning rc1 on the first proof of production:

| step | check | rc |
|---|---|---|
| 0 | `_pc_arm_registered "${AUTHOR}"` fails | rc1 (unchanged, :1246) |
| 1 | `assistant_n >= 1` | rc1 (unchanged, :1257) |
| 2 | **stream absent** (`_PC_SILENT_STREAM_STATE == absent`) | **rc1 — new.** "Too early to tell / this arm has no stream convention", never evidence of silence. |
| 3 | stream present and mtime within clamped growth window; **or** `_pc_stat_mtime` failed | rc1 (today's logic, now unconditional on the file existing because step 2 already returned) |
| 4 | `_pc_worker_process_alive` | **rc1 — new** |
| 5 | no `_lane_root` / not a directory | rc1 (unchanged, :1272) |
| 6 | `_pc_lane_dirty "${_lane_root}"` | rc1 (unchanged, :1273) |
| 7 | **`_pc_lane_commits_ahead "${_lane_root}" >= 1`** | **rc1 — new.** Defect 1. |
| 8 | otherwise | rc0 — silent; set `_PC_SILENT_LANE_BASENAME` as today |

**Edit 4 — evidence string.** `_PC_SILENT_STREAM_STATE` keeps its two existing values; `absent` is
now unreachable at rc0 (it returns rc1 at step 2), so the only rc0 value is `no_assistant_events`.
Extend the caller's evidence at :2027 with `commits_ahead=0` so the journal records that the commit
check ran and found nothing — a silent verdict that does not say it checked commits is
indistinguishable from the old buggy one in the ledger.

**Edit 5 — growth-window clamp** at :1260-1261: after the existing numeric-regex fallback to 60,
clamp to `[1, 3600]`; when clamping changes the value, `emit decision "silent_probe_growth_clamped
task=${TASK} requested=<v> used=<clamped>"`. Closes the over-cap boundary in §3.

**Not touched:** `pc_scope_diff` and its classifier, `_pc_git_diff`, `_pc_repo_diff`,
`_pc_diff_base` (read-only reuse), `_pc_arm_advance`'s body, `_pc_maybe_quota_advance`, the e2e
gate, the `empty_diff` / `unscoped_lane_work` / `asked_into_void` verdict paths, `review.diff`
production, and every ledger/journal key except the added evidence field.

### 5b. `plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh` — a conflict the lead must rule on

**Case 1 (L50-95) asserts the defect.** It sets up "no stream file + clean worktree" and asserts
`reason: arm_produced_nothing`. That is row 2 — the exact state that produced the false verdict on
4d5aabd0. Mission fix #2 ("an absent stream must be treated as too early to tell, never as evidence
of silence") makes Case 1 fail by construction.

The mission's off-limits says "do not touch ... any test assertion". Taken literally, fix #2 cannot
be implemented at all. Taken as intended — do not weaken assertions that guard *other* paths — Case
1 is the one assertion that must be re-authored, because it is the encoded bug.

**Recommendation (needs the lead's yes before the developer starts):** re-author Case 1 to assert
the corrected behaviour — absent stream + clean worktree + registered arm → **NOT**
`arm_produced_nothing`, falls through, and **no** `arm_advance` decision line is emitted — keeping
its existing exit-code and no-e2e-line assertions where they still apply. Cases 2, 3, 4 and 5 are
unchanged and become the regression lock for "we did not widen anything": Case 4 in particular is
mission verification #3, the positive control.

There is no design that satisfies fix #2 and leaves Case 1 byte-identical. Saying so here is
cheaper than discovering it in review round 2.

### 5c. `plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh` **(to-create)**

New suite, same harness idiom as the existing one (drives the real close gate; sandboxed via
`CLAUDE_PROJECT_ROOT` / `LEADV2_DISPATCH_CACHE_DIR` / `LEADV2_DISPATCH_TERMINAL_LEDGER_FILE` /
`LEADV2_LANE_WORK_ROOT`; `LEADV2_ARM_ADVANCE=0` except where the advance itself is asserted):

| case | fixture | asserts | maps to |
|---|---|---|---|
| A | lane repo with a seed commit, a `.start-sha` cache file naming the seed, a **second commit**, worktree clean, stream present with 0 assistant events and a **stale** mtime, arm registered | `review-gate.md` does **not** say `arm_produced_nothing`; no `arm_advance` journal line | mission verification #1, row 7 |
| B | stream **absent**, clean, registered | not `arm_produced_nothing` | mission verification #2a, row 2 |
| C | stream present, 0 events, mtime **now**, clean, registered | not `arm_produced_nothing` | mission verification #2b, row 5 |
| D | registered, stream present with 0 events and stale mtime, **no commit ahead** of the recorded start sha, clean, no live pid | **still** `arm_produced_nothing`, ledger row `no_work`/`arm_produced_nothing`, and with `LEADV2_ARM_ADVANCE=1` + a candidate chain exactly **one** `arm_advance` line and the `.arm-advanced-<arm>` marker present | mission verification #3, row 6 |

Wire the new suite into `plugins/leadv2/scripts/tests/run-core-offline.sh`. **Also propose (one
line, do not do it in this diff): `test-dispatch-silent-arm.sh` is currently not in
`run-core-offline.sh` at all** — that is why Case 1 never caught this before it shipped.

### 5d. Order of work

1. Edit 3 step 7 + Edit 1 (defect 1) — the smaller, uncontested half.
2. Case A of the new suite RED → GREEN.
3. Edit 3 step 2/4 + Edit 2 (defect 2), then Cases B, C.
4. Case D (positive control) — must be green both before and after every step above.
5. Edit 5 (clamp). 6. Case 1 re-author, only after the lead rules on §5b.

---

## 6. Out of scope for the implementing agent

- `pc_scope_diff`, its classifier, and the `empty_diff` / `unscoped_lane_work` / `asked_into_void`
  verdicts. The e2e gate. Any assertion in any test other than Case 1 of
  `test-dispatch-silent-arm.sh`.
- Giving codex arms a stream/exit anchor (counterexample (b)) — a separate task.
- The stale `.arm-advanced-<AUTHOR>` marker behaviour (counterexample (c)).
- Anything inside `.claude/worktrees/4d5aabd0` — that lane's commit `4d340e2` is a separate
  deliverable awaiting its own re-gate. Do not merge, rebase, or re-run its gate.
- Main's unrelated uncommitted files. No `git stash` / `reset` / `clean` anywhere.
- Any new environment variable, any new dependency, any GNU-only tool, any bash-4 construct.

---

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| `_pc_diff_base` picks a base that is not an ancestor of lane HEAD → `rev-list --count` prints a count that is not "this lane's work" | `_pc_diff_base` already returns a `merge-base`, which is an ancestor by definition; on failure it returns empty → count 0 → row 12, today's behaviour |
| The commits-ahead read aborts the gate on a broken lane repo | every git call `2>/dev/null || true`; helper always rc0 and always prints a digit |
| `_lane_root` points at the shared main checkout → other lanes' commits read as production | fails toward NOT-silent, the safe direction; same exposure `_pc_lane_dirty` already has |
| Calling `pc_worker_alive` instead of `_pc_process_alive` for liveness would re-enter quota/reap side effects and treat "unknown" as alive | Edit 2 explicitly forbids it; use `_pc_process_alive` only |
| `arm_produced_nothing` becomes unreachable for codex → chain stalls | named in §4(b); accepted trade, follow-up task, must be stated in the report, not silently absorbed |
| Function-definition order (`_pc_diff_base` at :1650, probe at :1243) | call site is :2026; verified safe, and the helper must be placed after `_pc_lane_dirty` (:1157) with the same call-time reasoning, or after :1663 — either works; do not move `_pc_diff_base` |

---

## 8. Acceptance

```yaml
acceptance:
  - surface: file_artifact
    observable: >
      For a lane whose worktree is clean and whose HEAD carries a commit its recorded start
      commit does not, docs/handoff/dispatch-<sig8>/review-gate.md no longer reads
      "reason: arm_produced_nothing" — the lane proceeds to its ordinary review verdict for
      that commit, and no replacement arm is started on the same mission.
    authored_at: 2026-08-23T05:54:25Z
  - surface: file_artifact
    observable: >
      For a lane whose developer stream file does not exist yet at close time, and again for
      one whose stream was written seconds ago, review-gate.md does not read
      "reason: arm_produced_nothing".
    authored_at: 2026-08-23T05:54:25Z
  - surface: log_line
    observable: >
      For an arm that was registered, whose worker has exited, that produced no commit, left a
      clean worktree and wrote a stream with no assistant turns, the task journal still shows a
      review_gate line with cause=arm_produced_nothing followed by exactly one arm_advance line
      naming the next arm — one advance, not two, not zero.
    authored_at: 2026-08-23T05:54:25Z
  - surface: log_line
    observable: >
      The core offline test run prints its per-suite pass/fail tally with no new failing suite;
      the two pre-existing failures (deferred-GLM ladder V3-GLM-LADDER-01, and fanout
      classifier/runner guard) are the only failures listed.
    authored_at: 2026-08-23T05:54:25Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/tests/test-dispatch-silent-arm.sh, plugins/leadv2/scripts/tests/test-silent-arm-commits-ahead.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
