LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-liveness.sh, plugins/leadv2/scripts/leadv2-dispatch-ledger.sh, plugins/leadv2/scripts/leadv2-lanes-snapshot.sh, plugins/leadv2/scripts/leadv2-pulse-beat.sh, plugins/leadv2/scripts/leadv2-status-surface.sh, plugins/leadv2/scripts/leadv2-lane-status-line.sh, plugins/leadv2/scripts/leadv2-lane-heartbeat.sh, plugins/leadv2/scripts/leadv2-status-collector.sh, .gitignore, tests/run-all.sh, plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh (to-create), plugins/leadv2/scripts/tests/test-lane-verdict-pid-is-a-worker.sh (to-create), docs/handoff/D2-SINGLE-LIVENESS-VERDICT/**

# D2 — single verdict on liveness: implementation brief

Measured against `main` at `1d799734` (after the `3a4ec991` D3 merge). Every count below carries its
re-derivable command. **PLAN.md's D2 row is wrong on three separate points — read §1 before §6.**

---

## 0. The one-paragraph verdict

The one function already exists. `plugins/leadv2/scripts/leadv2-lane-liveness.sh` is 1065 lines with
a single `resolve(tid)` entry point (`:618`), and it already emits a **third** verdict class,
`finished:<age>s` (`:705`, tagged `LANE-LIVENESS-THREE-STATES-02`). D2 is therefore not an authoring
task. It is three separate failures of the same idea:

1. **The third state is emitted and read by nobody.** `grep -rn "finished:" plugins/leadv2/{scripts,hooks}`
   outside `leadv2-lane-liveness.sh` returns **zero** non-test hits. Every consumer falls through its
   `*)` arm. In `_dl_reap_one_lane` (`leadv2-dispatch-ledger.sh:1383-1386`) that arm logs
   `indeterminate, writing nothing` — a finished lane gets no terminal ledger row at all.
2. **The third state is defined too narrowly to have caught the incident.** `finished:` requires
   `commit_age_s(worktree)` (`:598-616`) — a commit in the lane's own worktree. Tonight's five workers
   produced no commit. They produced `docs/handoff/dispatch-<sig>/developer.full.md`, and the ladder
   has no rung that looks at it. So the lanes fell past `finished:` to `dead:no_log_artifact`, which
   `_dl_derive_lane_state` maps to `no_work` (`leadv2-dispatch-ledger.sh:995-1005`) — retryable —
   which is exactly the re-dispatch that erased the evidence.
3. **41 of 62 files that decide liveness never call the function.**

Fix the vocabulary and the ladder first (M1–M2), then convert the callers (M3–M4). That ordering is
the whole design, and it is load-bearing: **M1 alone converts a wrong *terminal* verdict into a safe
*non-terminal* one**, so it stops the incident before a single consumer changes.

---

## 1. What PLAN.md's D2 row gets wrong

> D2 | single verdict on liveness | one function answers "is this lane alive", by worktree write age — not by a status field | 0.5d

| # | claim | measured reality |
|---|---|---|
| W1 | "one function answers" — implies the function must be written | The function exists (`leadv2-lane-liveness.sh::resolve`, 1065 lines, 21 files call it). The deliverable is **adoption + a third rung**, not authorship. |
| W2 | "**by worktree write age**" | Worktree/stream write age is the one signal that must **never decide alone**, in both directions. The code already says so: `:689-691` — "a fresh stream mtime after the worker exited is the completion flush, not proof of continued work". And pre-evidence #11 is the mirror: a healthy lane in its first minutes has no journal and was published as `live=0`. PLAN.md prescribes as primary evidence the thing that is inadmissible alone. |
| W3 | "is this lane **alive**" — two-valued | The tree is already three-valued (`finished:*`) and needs to be five-valued (§2). Pre-evidence #14 restates it precisely: liveness is not "is this PID alive", it is "is this PID a live **worker for this lane**". |
| W4 | "not by a status field" | Correct, and the only part of the row to keep. |
| W5 | 0.5d | 62 files in the census, 18 genuine conversions, two new suites, a `.gitignore` change with 184 files behind it. **1.5d.** |

---

## 2. The verdict vocabulary

**Design rule: nothing is renamed, nothing is removed, two classes are added.** D3 matches on the
literal strings `alive`, `starting:*`, `silent:*`, `dead:*` at three sites
(`leadv2-dispatch-ledger.sh:981`, `:1380`, `:1409`) and the mission forbids breaking that contract.
Any rename is a silent break at those three `case` arms — see §7 C4/C5.

| verdict | state | status | meaning |
|---|---|---|---|
| `alive` | — | **KEEP verbatim** | a process that is *this lane's worker* is running now (§3 E2, all three checks agree) |
| `starting:<age>` | — | **KEEP verbatim** | registered, inside the grace window, no evidence yet. Non-terminal. |
| `silent:<age>` | — | **KEEP verbatim** | evidence stale, below the abandon ceiling. Non-terminal. |
| `finished:<age>s` | **1** | **KEEP verbatim** | done, and the work landed as a commit in the lane's own worktree |
| `finished_unlanded:<age>s` | **3** | **NEW** | done, and the work exists only as a non-empty deliverable and/or an uncommitted tree — invisible to `git log` |
| `dead:<cause>` | **2** | **KEEP verbatim**, causes unchanged | ran, ended, and *nothing exists* to show for it |
| `unknown:<reason>` | — | **NEW** | the check could not see. **Never coerced to dead.** |
| `child` | — | **KEEP verbatim** | a folded sub-agent id, not a lane |

Three notes the implementer must not soften:

- **`finished_unlanded` is a sibling of `finished`, not of `dead`.** Consumers match `finished*)`.
  A caller that wants only the strict case can still test the exact prefix; a caller that wants "the
  lane is done" gets both from one arm. The distinction is load-bearing for D4 ("no path loses
  work"): `finished:` needs nothing, `finished_unlanded:` names an artifact that must be preserved
  before the worktree is reclaimed.
- **`unknown:<reason>` is additive and safe today.** Bare `unknown` and the empty string both already
  land in every consumer's `*)` arm, which already means "write nothing". The change is that the
  reason becomes readable instead of the caller guessing. Reasons at minimum:
  `unknown:no_row`, `unknown:contradictory_rows` (#15), `unknown:pid_unobservable` (`ps` wedged),
  `unknown:yaml_unreadable`. Absence of a record is `unknown:no_row` — **never** `dead`; that default
  is pre-evidence's fifth false answer and it is still live in the shape c2 fixed at `c482bde99`.
- **One string's *meaning* changes without the string changing:** `dead:no_log_artifact` and
  `dead:no_handoff_dir` become unreachable when a deliverable exists, because the new rung fires
  first (§3 E4). Consumers keep working; the lane simply now arrives as `finished_unlanded:*`
  instead of the lie. This is the incident fix and it needs no consumer edit to be *safe* — only to
  be *useful*.

---

## 3. The evidence ladder

Evaluated top to bottom. **The first rung that fires wins**; nothing below it can promote a lane back
to alive.

| rung | evidence | what it can lie about | rank |
|---|---|---|---|
| **E0** | **contradiction check**: >1 live row for this `task_id`; or one PID recorded as owner of >1 lane; or the row's `worktree` == `PROJECT_ROOT` (#14's second corruption) | nothing — it is a structural fact about the registry | **decisive → `unknown:contradictory_rows`.** Never alive, never dead. Today `leadv2-dispatch-code.sh:4555` exits 2 on `len(rows)!=1`, so release is already structurally impossible; D2 must make the *verdict* say so instead of reporting a permanent `starting:N` that only counts up (#15). |
| **E1** | `dead_at` on the lane's own `active.yaml` row | trustworthy **only after D1 M1/M3** land (before that: duplicate rows make "the row" ambiguous, and `lane_deregister` returns 0 having removed nothing) | **decisive → `dead:*`.** Already consumed at `leadv2-lane-liveness.sh:212` (`pid_state(..., lane_dead_at)`). D2 consumes D1's field; it must not re-derive it. |
| **E2** | **process existence AND kind**: `os.kill(pid,0)` with the errno split, + `ps -o lstart=` birth equality, + `ps -o command=` **worker-shape** match | `ESRCH`→dead (true) but `EPERM`→"dead" today (`:169-175`, `:224-227`) is a **false zero** (#9). Birth-time equality defends against PID reuse (already real, `:229-240`). **Kind is not checked at all** — #14: `kill -0 79117` returned 0 on `claude --dangerously-skip-permissions`, an interactive session, and the lane was declared live for hours. | **decisive → `alive`, only when all three agree.** `os.kill` OK + birth match + kind match. Any single disagreement demotes to `unknown:*`, never promotes. |
| **E3** | commit in the lane's own worktree within `LEADV2_LANE_FINISHED_WINDOW_S` (default 1800) | a commit from an earlier unrelated round (the window is the mitigation); a `worktree` field pointing at the main repo (E0 catches it) | **decisive → `finished:<age>s`** when E2 says not-alive. Exists today (`:703-707`). |
| **E4** | **the deliverable**: a non-empty `docs/handoff/<lane>/*.full.md` (and `*.summary.md`) with `mtime >= spawn_epoch` | a stale report from a prior round → the mtime guard; a placeholder → the `-s` guard; a `DELIVERABLE_BLOCKED` report → **still state 3, never state 2** (it did work and said why it stopped) | **decisive → `finished_unlanded:<age>s`** when E2 says not-alive. **This rung does not exist today. It is the incident.** |
| **E5** | uncommitted tree in the lane's declared write-set | a worker still mid-write (E2 already answered `alive` and won); foreign dirt | **corroborating.** Raises `finished_unlanded` confidence and supplies D3's `dead_with_unlanded_work` payload. Alone it proves bytes exist, not that anything finished — `_dl_derive_lane_state:966-971` already says this in prose. |
| **E6** | worker stream tail → `stop_reason` (`end_turn` vs absent) | the file is buffered; a stream that just ends is ambiguous | **corroborating.** The best available disambiguator between "finished the turn" and "was killed", and the field that answers pre-evidence #10 (starvation-timeout vs death) for D3. Never decisive: absence is not death. |
| **E7** | file mtimes — stream mtime, journal presence | lies in **both** directions: fresh-after-exit = completion flush (`:689-691`); absent journal on a healthy new lane = published `live=0` (#11) | **inadmissible alone.** May only narrow `starting:` vs `silent:` *after* E2 has been consulted. This is the signal PLAN.md names as primary. |
| **E8** | `status:` / `phase:` field in `active.yaml` | it is intent, written before the fact | **inadmissible, full stop.** |

---

## 4. The gitignore blindness — decision

**Measured.** `.gitignore:49` is `docs/handoff/*/*`, with allowlist exceptions for `report.md`,
`brief*.md`, `round*-red`. Reports are not on that list.

```
ls docs/handoff/*/*.full.md | wc -l             -> 281
git ls-files 'docs/handoff/*/*.full.md' | wc -l ->  97
```

**184 reports are invisible to git; 97 are visible only because they predate the rule** (`.gitignore`
does not un-track). The live state is not "reports are ignored" — it is *"reports are ignored at
random"*, which is exactly why nobody noticed. The rule's own comment says "Allowlist the artifacts
that are actual evidence"; its author simply did not classify the reports as evidence.

**Decision: allowlist them in `.gitignore` (option a) AND add rung E4 to the ladder (option c).
Reject moving them (option b).**

| option | verdict | reason |
|---|---|---|
| (a) force-track via allowlist | **DO** | Two of the three blindnesses are inside git itself: the ignore rule, and `_dl_derive_lane_state`'s dirty probe using `git status --porcelain -uall`, which does not list ignored files at all. Any human or tool that looks at git stays blind until this lands. It is two lines and reverts in two lines. |
| (b) move out from under the rule | **REJECT** | `docs/handoff/<task-id>/<role>.full.md` is referenced in **19 distinct files** (`claude-subsession.sh` alone has 10) *and* in the subagent-protocol skill that every in-flight worker is currently running against. A rename is a fleet-wide coordinated cutover that cannot be reverted independently — the mission forbids exactly that. |
| (c) consumers read them explicitly | **DO, as E4** | (a) makes the reports *visible*; only (c) makes the verdict *consult* them. There is a third blindness (a) cannot touch: `_dl_derive_lane_state:914` builds its pathspec with `case "${e}" in docs/leadv2/*\|docs/handoff/*) continue ;;` — the deliverable path is **explicitly excluded** from the dirty probe by design, and correctly so (it is bookkeeping, not product work). E4 is a separate rung, not a widening of the pathspec. Do not widen the pathspec. |

**Consumers that must change for this decision:**

| # | file | change |
|---|---|---|
| 1 | `.gitignore` (after `:51`) | add `!docs/handoff/*/*.full.md` and `!docs/handoff/*/*.summary.md` |
| 2 | `plugins/leadv2/scripts/leadv2-lane-liveness.sh::resolve` | new rung E4 **before** the `dead:no_handoff_dir` / `dead:no_log_artifact` emission at `:882-884` |
| 3 | `plugins/leadv2/scripts/leadv2-dispatch-ledger.sh::_dl_derive_lane_state` (`:981-1015`) | new `finished*)` arm. Today `finished:*` hits `*)` → `unknown`. Note the function **already computes** `deliverable_state` at `:948-955` and **never uses it in the verdict** — the evidence was collected and discarded. |
| 4 | `plugins/leadv2/scripts/leadv2-dispatch-ledger.sh::_dl_reap_one_lane` (`:1380-1387`, `:1409`) | `finished*)` joins the non-terminal STOP arm. A finished lane must never be reaped as dead. |
| 5 | `plugins/leadv2/scripts/leadv2-lanes-snapshot.sh:862` | carries its own `LANE-LIVENESS-THREE-STATES-02` commit check — must consume the same rung or be deleted (§5). |
| 6 | `plugins/leadv2/scripts/leadv2-pulse-beat.sh` | the founder-facing surface, #11. Convert first among consumers (§6 M4). |
| 7 | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | **LOCKED — see §8.** Its `no_work` write is downstream of #3, so #3 alone fixes the behaviour without touching it. |

---

## 5. Who calls it — the census

Re-derive (note: `while read`, not `for f in $list` — zsh does not word-split an unquoted variable,
the fourth false zero named in the pre-evidence, and it reproduced in this very investigation):

```sh
grep -rln "leadv2-lane-liveness\.sh" plugins/leadv2/{scripts,scripts/lib,hooks}/*.sh | sort -u > /tmp/_a
grep -rln "kill -0\|os\.kill(\|ps aux\|pgrep\|ps -p \|ps -o " \
     plugins/leadv2/{scripts,scripts/lib,hooks}/*.{sh,py} | sort -u > /tmp/_b
comm -13 /tmp/_a /tmp/_b | while read -r f; do
  grep -q "worker_pid\|pid_role\|active\.yaml\|\bsessions\b" "$f" && echo "LANE $f" || echo "OWN  $f"
done
```

| group | count | disposition |
|---|---|---|
| **Union — files that decide liveness by any method** | **62** | the denominator |
| Adopters (invoke `leadv2-lane-liveness.sh`) | **21** | see below |
| Own-probe files (`kill -0` / `os.kill` / `ps` / `pgrep`) | **53** | |
| Own-probe **and not** adopter | **41** | |
| └ touching lane-registry state → **must convert** | **20**, minus `leadv2-lane-liveness.sh` (the implementation) and `lib/leadv2-lane-state.sh` (D1's writer, whose `os.kill` D2 **consumes**, never duplicates) = **18 genuine conversions** | call-site changes |
| └ probing their own child / lock / provider process → **correctly keep their own probe** | **21** | adopt unchanged, *out of scope*: `glm-coder.sh`, `kimi-coder.sh`, `freepool-{coder,proxy,install}.sh`, `leadv2-portable-lock.sh`, `leadv2-daemon.sh`, `leadv2-burn-governor.sh`, `leadv2-provider-quota-gate.sh`, `leadv2-claude-profile-select.sh`, `leadv2-session-spawner.sh`, `leadv2-queue-sweep.sh`, `leadv2-po-queue.sh`, `leadv2-next-mission.sh`, `leadv2-mark-mission.sh`, `leadv2-single-lead-beat-loop.sh`, `leadv2-suite-falsifiable.sh`, `lib/leadv2-builder-selfcheck.sh`, `lib/leadv2-watch-lifecycle.sh`, `lib/leadv2_pid_birth.py`, `leadv2-codex-lead.sh`, `codex-guard.sh`, `hooks/leadv2-lead-prose-guard.sh` |
| **Both** — an adopter that *also* keeps a private probe (two opinions in one file) | **12** | the most dangerous group: `claude-subsession.sh`, `codex-task.sh`, `leadv2-active-registry.sh`, `leadv2-backlog-pump.sh`, `leadv2-dispatch-code.sh`, `leadv2-dispatch-ledger.sh`, `leadv2-dispatch-product-close.sh`, `leadv2-lane-watch-v2.sh`, `leadv2-lanes-snapshot.sh`, `leadv2-lanes.sh`, `leadv2-stale-sweeper.sh`, `leadv2-status-surface.sh` |

**The 18 to convert** (lane-registry PID readers with no liveness call):
`hooks/leadv2-active-cache.sh`, `hooks/leadv2-orphan-monitor-sweep.sh`, `hooks/leadv2-task-anchor.sh`,
`hooks/leadv2-worktree-enforce.sh`, `hooks/leadv2-stale-pid-sweep.sh`, `leadv2-fanout.sh`,
`leadv2-fanout-lane-launcher.sh`, `leadv2-helpers.sh`, `leadv2-lane-heartbeat.sh`,
`leadv2-lane-pulse-watch.sh`, `leadv2-lane-status-line.sh`, `leadv2-merge-queue.sh`,
`leadv2-provider-canary.sh`, `leadv2-status-collector.sh`, `leadv2-pulse-beat.sh`,
`lib/leadv2-worktree-protected.sh`, `codex-guard.sh`, `leadv2-codex-lead.sh` — the last two are
borderline (they read `active.yaml` but may only be probing their own provider child). **A
name-based classification is a hypothesis, not a verdict: confirm each file's probe target before
converting it, and move any that turn out to be self-probes into the out-of-scope column with a
one-line note.**

**How many adopt unchanged?** For the *existing* verdicts, all 21 adopters. For the third state,
**zero of 21** — `grep -rn "finished:" plugins/leadv2/{scripts,hooks}` returns no non-test consumer.
So: the 21 keep working after M1–M2 (they route the new verdicts to their existing "write nothing"
arm, which is safe), and the subset that *branches* on the verdict needs one new `finished*)` case
each. Known branchers: `leadv2-dispatch-ledger.sh` (3 sites), `leadv2-lanes-snapshot.sh`,
`leadv2-status-surface.sh`, `leadv2-backlog-pump.sh`.

**Deletions:** `leadv2-lanes-snapshot.sh:545/:586/:862` carries a *duplicate* implementation of the
`LANE-LIVENESS-THREE-STATES-02` commit-age rule. Two copies of a rule is how the two diverge. Delete
the copy and call the function — or, if the snapshot's batching makes a per-lane call unaffordable,
have it consume the `--all --json` map like `_dl_reconcile` already does (`:1073-1074`).

---

## 6. Migration — ordered, each step independently landable and revertible

Live lanes are running against these paths. Every step below is safe to land alone and safe to
revert alone; no step depends on a later one for correctness.

| step | change | why it is safe alone | proof it landed | revert |
|---|---|---|---|---|
| **M0** | `.gitignore`: allowlist `*.full.md` + `*.summary.md` | no code path reads `.gitignore` | `git add --dry-run docs/handoff/<any>/developer.full.md` prints `add '...'` instead of "ignored by one of your .gitignore files"; **and** `git status --porcelain -uall docs/handoff \| grep -c 'full\.md'` > 0. **Do NOT use `git check-ignore` as the proof** — it exits **0** on a *negation* match too, so `check-ignore && echo ignored` reports an allowlisted path as ignored. Verified while writing this brief: `git check-ignore -v docs/handoff/D2-SINGLE-LIVENESS-VERDICT/brief.md` → exit 0, rule `.gitignore:51:!docs/handoff/*/brief*.md` — matched, and **not** ignored. | delete 2 lines |
| **M1** | liveness: rung **E4** + `finished_unlanded:*`, emitted **before** `dead:no_log_artifact` | consumers have no `finished*` arm yet, so these lanes land in `*)` = "indeterminate, write nothing". **That is strictly safer than today's `no_work`** — a non-terminal replaces a wrong terminal. The incident stops here, with zero consumer edits. | new suite green; `bash leadv2-lane-liveness.sh --lane <a real report-only lane>` prints `finished_unlanded:<n>s`; mutation-control pair C2 | one rung, one `if` |
| **M2** | liveness: E2 **process-kind** match + **EPERM/ESRCH** split in `pid_state` / `pid_alive` | tightens `alive` (kind) and loosens a false `dead` (EPERM) — both move toward `unknown`, never toward a new terminal | mutation-control pairs C1 and C3 | revert `pid_state` body |
| **M3** | consumers: `finished*)` arms in `_dl_derive_lane_state` and `_dl_reap_one_lane` | additive `case` arms; every existing arm is untouched, so D3's contract is preserved by construction | `test-reap-funnel-death-proof.sh` still green **and** its new `finished*` case; a finished lane now gets a terminal ledger row | drop the arms → back to `*)` |
| **M4** | convert the 18, in batches of **≤4**, `leadv2-pulse-beat.sh` **first** | each file is independent; the pulse is the founder-facing surface and #11 is its bug | per batch: the converted file's own suite, plus `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed` naming it | per batch |
| **M5** | E0 contradiction guard → `unknown:contradictory_rows` | **ordering dependency: land only after D1 M1.** D1 makes duplicate rows impossible to *create*; D2 makes surviving ones *legible*. Landing M5 first would flip live lanes with pre-existing duplicates to `unknown` with no writer able to repair them. | a fixture registry with 2 rows for one task returns `unknown:contradictory_rows`, and the **post-state** is asserted (§7) | one guard |
| **M6** | delete the duplicate three-states rule in `leadv2-lanes-snapshot.sh` | pure de-duplication after M3 proves the shared rung | snapshot output byte-identical on a fixture before/after | restore |

**Argv trap, mandatory for M1/M2.** `leadv2-lane-liveness.sh:84` passes 20 positional args into a
fixed unpack at `:90` (`... = sys.argv[1:]`). A new tunable must be **appended at the end**. Inserting
one anywhere else silently re-binds every downstream tunable — a whole-file behaviour change no suite
would attribute correctly. New env names follow the established prefix `LEADV2_LANE_*` (siblings:
`LEADV2_LANE_SILENT_MAX_S`, `LEADV2_LANE_STARTING_MAX_S`, `LEADV2_LANE_ABANDON_MAX_S`,
`LEADV2_LANE_FINISHED_WINDOW_S`). Propose `LEADV2_LANE_DELIVERABLE_GLOBS` and
`LEADV2_LANE_PID_KIND_CHECK`. **No `LEAD_V2_*` form exists anywhere in this repo — do not introduce one.**

---

## 7. Negative controls — one per changed function body

The unit is **the changed function body**, not the lane. Apply every mutation *inside* the body with
`plugins/leadv2/scripts/leadv2-mutation-control.sh <suite> <file> <sed-or-patch> [task_dir]`, which
requires `baseline_rc=0` / `mutated_rc=1` and writes `mutation-control/<run-id>.txt`. A top-level
insert that reddens every suite for the wrong reason reads as a pass — that happened on 2026-08-25.

| # | function (file:line) | mutation, inside the body | the assertion it must break |
|---|---|---|---|
| **C1** **(mandatory, #14)** | `pid_state` (`leadv2-lane-liveness.sh:197`) | delete the process-**kind** comparison — return `("alive_verified","verified")` as soon as birth matches | a fixture whose recorded PID is alive and birth-matching but whose `ps -o command=` is `claude --dangerously-skip-permissions` (an interactive session, not a `claude -p` worker) asserts **not `alive`**. Suite must go red. |
| **C2** **(mandatory, state 3 ≠ state 2)** | `resolve` (`leadv2-lane-liveness.sh:618`) | neutralise rung E4: `if False:  # D2 E4 mutation gate` on the deliverable check | a fixture lane with **no commit**, a **dead** PID, and a non-empty `docs/handoff/<lane>/developer.full.md` newer than spawn asserts `finished_unlanded:*` — **not** `dead:no_log_artifact`, and downstream **not** `no_work`. Suite must go red. |
| C3 | `pid_alive` (`:169`) and the errno branch in `pid_state` (`:224`) | fold `PermissionError` back in with `ProcessLookupError` | an `EPERM` fixture PID asserts **alive** (or `unknown:pid_unobservable`), never `dead` (#9) |
| C4 | `_dl_derive_lane_state` (`leadv2-dispatch-ledger.sh:906`) | delete the `finished*)` arm so the verdict falls to `*)` | a lane whose liveness verdict is `finished_unlanded:120s` asserts a terminal that is **not** `no_work` and **not** `unknown` |
| C5 | `_dl_reap_one_lane` (`:1358`) | move `finished*` out of the STOP arm into the `dead:*` arm | a `finished_unlanded:*` lane asserts **no rescue commit written** and **no `dead` terminal**; the ledger's post-state is read, not the return code |
| C6 | the pulse's verdict function (`leadv2-pulse-beat.sh`) | restore the journal-presence test as the decider | a registered lane with a live worker PID and **no journal file** asserts it is counted `live=1`, not `нет-журнала` (#11) |
| C7 | E0 guard (`resolve`, M5) | `if False:` the duplicate-row check | a two-row fixture asserts `unknown:contradictory_rows`; and a PID recorded as owner of two lanes asserts **at most one** lane alive (#15) |
| — | `commit_age_s` (`:598`) | **unchanged by D2** — no control required, stated so it is not silently assumed covered | — |

**Fixture rules — non-negotiable:**

1. **Assert the post-state, never the return code** (#16). After any registry helper, re-read the row
   and assert the field. `leadv2_active_unregister` without `LEADV2_PROJECT_ROOT` returned success
   while removing nothing. Every fixture that calls a registry verb pins `LEADV2_PROJECT_ROOT`
   explicitly **and** asserts the resulting row.
2. **Verify the fixture's own setup.** A `git commit` inside `( … )` whose status is discarded
   produced a false red in this repo tonight. Every setup command's exit status is checked and the
   check is asserted (`git -C "$wt" rev-parse HEAD >/dev/null || fail "fixture setup: no commit"`).
3. **No pipeline decides liveness.** `kill -0 "$pid" 2>/dev/null; rc=$?` then branch on `$rc`. Under
   `set -o pipefail` a pipeline carries an earlier stage's status and every genuine death reads as
   "unknown" (pre-evidence #12, fixed at `c482bde99`).
4. **`while read -r`, never `for p in $pids`** — zsh does not word-split; the loop iterates one blob
   and reports every lane dead.
5. The four pre-evidence acceptance cases (false zero / false life / mirror-dead / multi-PID) stay in
   the suite verbatim. **Any one of a lane's recorded PIDs alive ⇒ alive**; only "all recorded PIDs
   dead" is dead.

**Suites (to-create) and their registration.** `plugins/leadv2/scripts/tests/test-lane-verdict-three-states.sh`
(C2, C4, C5, C6) and `plugins/leadv2/scripts/tests/test-lane-verdict-pid-is-a-worker.sh` (C1, C3, C7).
Add to `EXTRA_SUITE_MAP` in `tests/run-all.sh` beside the existing rows at `:322-326`, keyed on
`leadv2-lane-liveness.sh`, `leadv2-dispatch-ledger.sh`, `leadv2-lanes-snapshot.sh`,
`leadv2-pulse-beat.sh`. Prove selection with a **real edit** (append a comment line and save —
`touch` does not work, git does not see it) followed by
`LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed`, and paste the lines naming
both suites. Nothing goes into `tests/known-red-suites.txt`; no assertion is weakened.

---

## 8. Constraints carried forward

- **`plugins/leadv2/scripts/leadv2-dispatch-code.sh` is held by another session — the worker must not
  edit it.** D2 **does not require it**, by design: the file's liveness use is already behind the
  `LEADV2_DISPATCH_LANE_LIVENESS_BIN` seam (`:3029`, `:5016`), and its `no_work` write is downstream
  of `_dl_derive_lane_state`, which lives in `leadv2-dispatch-ledger.sh` and is editable. Its 4
  `kill -0` + 2 `os.kill` + 2 `ps` sites stay as they are, on the "both" list, and are deferred.
  **If the implementer finds a case that genuinely needs the file, STOP and say so loudly** — the
  split to propose is: move the inline probes into a sourced `lib/leadv2-lane-verdict.sh` and leave
  `dispatch-code.sh` with a one-line `source`, landed in the *other* session's lane, not this one.
- Never `reset --hard`, `clean`, or `stash` in this shared tree. Never `git worktree prune` — it
  killed two live lanes on a prior evening.
- The mutation scratch repo is a plain `mktemp -d` + `git init`, never `git worktree add`
  (`leadv2-mutation-control.sh:38-40` already carries the rationale).
- D3's contract is a hard boundary: `_dl_reap_one_lane` calls
  `${LEADV2_REAP_LIVENESS_BIN:-${LANE_LIVENESS_BIN}}` twice (`:1378`, `:1408`) and computes no
  liveness of its own. D2 preserves that by adding `case` arms, never by renaming verdicts and never
  by moving the decision into the ledger. **What would break it:** renaming `alive` / `starting:` /
  `silent:` / `dead:`; emitting a *new terminal-looking* prefix that D3's `dead:*` arm matches;
  making the liveness binary slower than D3's two sequential calls tolerate; or moving the
  re-check-after-lock logic (`:1404-1409`) into the function.

---

## 9. What D1 already satisfies — D2 must consume, not fork

| D2 requirement | D1 status | D2's obligation |
|---|---|---|
| PID-reuse safety (a recycled PID must not read alive) | **satisfied twice**: D1's writer at `lib/leadv2-lane-state.sh:57-65` (`os.kill` + `pid_start_time` equality), and liveness' own `pid_state` birth check (`:229-240`) | **Do not add a third.** Keep liveness' check (it is the read path) and consume D1's `dead_at` as the short-circuit `pid_state:212` already implements. |
| Duplicate rows are an error | **D1 M1** makes them impossible to create and loud when found (rc 5) | D2 only *renders* the survivors as `unknown:contradictory_rows` (M5), and must land **after** D1 M1. D2 does not fix `dispatch-code.sh:4555`; D1's design makes it unreachable-by-duplicate. |
| Root resolution fails closed (#16) | **D1 M3** | D2 pins `LEADV2_PROJECT_ROOT` at every fixture and call site; it writes no resolver of its own. `leadv2-lane-liveness.sh:7` already takes `${LEADV2_PROJECT_ROOT:-$PWD}` and every consumer passes `--project-root` explicitly. |
| `dead_at` is authoritative and single-writer | **satisfied** — stamped only by `lane_reconcile` / `lane_deregister` | E1 consumes it. |
| Registry helpers assert post-state, not rc | **D1 §3.2 rule** | inherited as fixture rule §7.1. |
| `deregister` returning 0 having removed nothing | **D1 M1/M2** | out of D2's scope entirely. |

**D2 writes no lane state.** Every mutation it might have wanted belongs to D1's writer. If the
implementer finds themselves writing to `active.yaml`, the design has been misread.

---

## 10. Out of scope — the implementer must not do these

1. Do not edit `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (§8).
2. Do not touch the 21 own-child/lock/provider probes (§5) — a `glm-coder.sh` waiting on its own
   child is not a lane-liveness question, and routing it through the lane function would be worse.
3. Do not rename or remove any existing verdict string (§2, §8).
4. Do not widen `_dl_derive_lane_state`'s pathspec to include `docs/handoff/*` — the exclusion is
   correct; E4 is a separate rung.
5. Do not implement D4's rescue/preservation of the `finished_unlanded` artifact. D2 *names* the
   state; D4 acts on it.
6. Do not fix `leadv2-dispatch-code.sh:4555` — D1 owns it.
7. Do not add a timeout-based "assume dead after N" rung. Starvation is byte-identical to death from
   outside (#10); the answer is E6's exit cause carried to the caller, not a timer.

---

## 11. Self-check (architect)

| # | check | result |
|---|---|---|
| 1 | env naming | `LEADV2_LANE_*` confirmed against `leadv2-lane-liveness.sh:84` (4 sibling tunables). No `LEAD_V2_*` form exists in the repo. **PASS** |
| 2 | paths exist | every cited path and line verified on disk at `1d799734`; the two suites are marked `(to-create)`. **PASS** |
| 3 | `claude -p` flags | **N/A** — this brief invokes no `claude -p`. |
| 4 | concurrent access | `leadv2-dispatch-code.sh` is held by another session (§8, deferred). `tests/run-all.sh` and `.gitignore` are append targets a concurrent lane may also touch — **ordering constraint: M0 lands alone and first, and the `EXTRA_SUITE_MAP` rows land in the same commit as their suite**, so a collision is a two-line resolution rather than an interleave. |
| 5 | config contradiction | `LEADV2_LANE_FINISHED_WINDOW_S` (1800) sits deliberately between `LEADV2_LANE_SILENT_MAX_S` (900) and `LEADV2_LANE_ABANDON_MAX_S` (3600) (`:108-117`). The new E4 rung **must reuse the same window** — a second, different freshness window for deliverables would make `finished:` and `finished_unlanded:` disagree about the same lane at the same instant. **Flagged: reuse, do not add.** |

DELIVERABLE_COMPLETE
