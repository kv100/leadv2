# CONTINUATION-GUARD-PASSES-ANY-TURN-THAT-TOUCHED-A-TOOL-01 — lane report

- Date: 2026-09-17. Lane worktree: `.claude/worktrees/1eb1dbefe186`, branch `worktree-1eb1dbefe186`.
- Commits: `3416f5e8` (anchor) → `d70ad504` (fix) → this report.
- Platform boundary: everything below measured on **macOS Darwin 25.6.0** only. The probe uses
  BSD `ps -o lstart=` / `ps -o ppid=` / `lsof -a -p PID -d cwd -Fn` / `lsof FILE`; Linux has
  analogues but **nothing here is verified on Linux** (see "Still red / not proven").

## 1. The defect

`plugins/leadv2/hooks/leadv2-continuation-guard.sh` at `3416f5e8:332`:

```bash
# Had a tool call → pass through. A measured/reported turn is not silent.
[[ "$HAS_TOOL_CALL" == "yes" ]] && exit 0
```

The header (same file, `:8-14`) promised the guard enforces "(a) a tool call / **dispatched
worker / armed watcher** this turn, or (b) only the missing continuation/close line" — three
acceptable things in (a), one checked. Cause class: **real_regression** (the predicate was one
clause weaker than the documented contract).

Reproduction (before the fix, from the lane branch):

```
$ # fixture: active task + a turn that ran `task-close.sh x && git commit` + final prose,
$ # no registry row, no sentinel, no live bg task (LEADV2_GUARD_* pinned to empty fixtures)
$ LEADV2_CONTINUATION_GUARD_SENTINEL_DIR=… bash plugins/leadv2/hooks/leadv2-continuation-guard.sh <<<"$PAYLOAD"
OUTPUT: (empty) => ALLOW — guard passed a turn that armed nothing [RED before fix]
```

That ALLOW is the six-hour silence of 2026-09-17: a Stop hook can only decide **at the moment the
session tries to sleep**; once it passes, nothing re-enters the lead except a background-task
completion, a Monitor event, or a Monitor expiry — and all three were gone.

## 2. The new predicate

A Stop-time turn with an active task is safe iff **a waker exists** — something that fires while
the session sleeps — or the turn ended with the explicit continuation/close line (contract (b),
kept: it is what lets a finished worker lane say `DELIVERABLE_COMPLETE` and end). `has_tool_call`
is still computed and quoted back in the block message, but it no longer passes anything.

| Waker | Meaning | Detection (all inside the hook's Python body, budget-capped at 2 s) |
|---|---|---|
| **w1** | live lane/worker/dispatcher process attributable to this session | registry row (`~/.claude/leadv2-state/leadv2/active.yaml` + the cwd-relative actives) that is not `stale`/`dead_at`/`terminal_status`, whose `pid` is alive, whose `pid_birth` matches `ps -o lstart=` (a reused pid cannot ghost a lane alive), whose pid is outside the hook's own ancestry (the lead's own registry row must not count), and whose process cwd (`lsof -a -p PID -d cwd -Fn`) sits under the row's `worktree` — both sides `os.path.realpath`-resolved (lsof reports `/private/var/...`, rows carry `/var/...`). |
| **w2** | live harness-tracked background command | a `*.output` under this session's tasks dir (`/private/tmp/claude-<uid>/<transcript-slug>/<session-id>/tasks/`) still held open **for WRITE** by a live process. Its completion will notify. |
| **w3** | fresh armed-watcher sentinel | the lead's attestation that a Monitor is armed (see §3). |

Physical evidence for the detection choices (probed 2026-09-17, this session):

```
$ lsof $TASKS/b1levb3w4.output        # LIVE pulse bg task
zsh   84932   1w …  bash 84935   1w …  sleep 85105   1w …      # write-holders = producer tree alive
$ lsof $TASKS/b3jfy2975.output        # EXPIRED monitor task
(no output, rc=1)                                              # a finished task holds nothing
$ # live control-plane registry row: {'task_id': '1eb1dbefe186', 'pid': 1, 'stale': False, …}
# pid=1 (launchd) rows exist in the wild → pid<=1 gate + cwd attribution both required
```

Kept pass-throughs, unchanged: kill switch `LEADV2_CONTINUATION_GUARD=0`, `stop_hook_active`,
per-session anti-loop sentinel (one block max per turn), fail-open on crash / empty stdin /
unreadable transcript. The waker probe **fails toward "no waker"** — a false block costs one
nudge and is recoverable via the escapes; a false pass is the six-hour silence.

## 3. Sentinel design (w3) and the alternatives rejected

**Shape** — one JSON file per session in the control plane (never the repo, per
REGISTRY-MUST-LEAVE-GIT-01):

```
~/.claude/leadv2-state/leadv2/watchers/<session-id>.watch.json
{"kind":"monitor","watching":"…","armed_at":"2026-09-17T11:20:00Z","expires_at":"…Z"}
```

**Freshness**: `expires_at > now` AND `expires_at ≤ armed_at + LEADV2_GUARD_SENTINEL_MAX_HORIZON_S`
(default 3600 s) AND `armed_at ≤ now + 300 s`. The cap is the point: a sentinel is an attestation,
attestations rot, and a sentinel that never expires would re-create this exact bug in a new place
— the lead attests once and sleeps forever behind a stale file. The block message carries the
exact copy-paste arm command (real dir + session id interpolated), so arming is one paste.

A Stop hook cannot see Claude Code's internal Monitors; the sentinel is the lead's written
counterpart, refreshed on every wake (each pulse tick or monitor expiry wakes the lead, who
re-arms and re-writes in the same turn — the guard's block is what forces the first round of this).

**Rejected alternatives**:

1. **Anti-silence-pulse.sh auto-writes/refreshes the sentinel each heartbeat.** Rejected: the
   heartbeat attests the *producer*, not the *relay*. Live pulse + dead Monitor was precisely the
   measured failure (pulse wrote `[ПУЛЬС 07:16Z] live=0 — тишина` into a file nothing relayed);
   auto-refresh would have stamped that state "safe" forever.
2. **Counting read-mode fds on `tasks/*.output` (monitor `tail -f` readers) as a waker.**
   Rejected: an orphaned tail attests nothing — but an *expired* Monitor kills its tail (probed:
   `b3jfy2975.output` has zero holders after expiry), so r-holders are usually live relays; they
   are just not *verifiable* as such. Monitors are attested via w3 instead; keeps w2 meaning
   exactly "completion will notify".
3. **Process-tree descendant scan for "live background command".** Rejected: MCP servers and
   harness infrastructure are long-lived app descendants that wake nothing; the scan would be
   almost always-true and the bug would be back. An fd on the session's own tasks file is
   attribution by construction.
4. **Uncapped / 24 h sentinel horizon.** Rejected: 24 h still admits the six-hour silent window
   the founder reported; 3600 s bounds the lie to an hour and matches the refresh-on-wake cadence.

**Residual risks, named**: (a) the registry has no claude-session-id column, so "attributable" is
repo-level — another live lead's processes in the same repo count as w1 (tightening needs a schema
change; out of scope here); (b) a lead can write a sentinel and have its Monitor die a minute
later — the attestation is stale-proof only up to the horizon cap; (c) every probe step failing
toward "no waker" means a systematically broken `lsof`/`ps` environment degrades to
block-with-escapes, never to silent pass.

## 4. Mission controls (both run, outputs pasted)

**Control 1 — tool calls but no waker armed → must BLOCK** (the bug; red before fix, green after):

```
--- pre-fix  (3416f5e8): OUTPUT: (empty) => ALLOW — guard passed a turn that armed nothing [RED before fix]
--- post-fix (d70ad504):
{"decision": "block", "reason": "CONTINUATION-GUARD: активная задача CTL-TASK-01 (фаза: build)
 ещё не закрыта, но когда сессия заснёт — никто её не разбудит. Этот ход делал вызовы
 инструментов — но работа не будит: будит только завершение фоновой задачи или
 событие/истечение Monitor. … Не armed ни один пробудитель: w1 … w2 … w3 … [GREEN after fix]"}
```

**Control 2 — live background job / fresh sentinel → must PASS** (no false block):

```
(fixture bg pid 52258 alive: yes)
2a live background job: OUTPUT: (empty) => ALLOW [GREEN]
2b fresh sentinel:      OUTPUT: (empty) => ALLOW [GREEN]
```

## 5. Mutation controls — `leadv2-mutation-control.sh --live` artifacts

All five `rc=0` (mutation applied in the lane checkout, suite went red, file restored
byte-identical), `porcelain_clean=yes`, artifacts under `mutation-control/` next to this report:

| id | gate mutated | suite went red on |
|---|---|---|
| M1 | `waker_any = w1 or w2 or w3` → `True` | Cases 1/2/3/3b/4/5 (no-waker stops pass) |
| M2 | sentinel freshness `_fresh = …` → `True` | Cases 5c/5d (expired / over-horizon sentinel counts) |
| M3 | `pid_birth` vs `lstart` anti-reuse → skipped | Case 4c (ghost pid row counts live) |
| M4 | write-holder gate `_is_write` → `False` | Case 5e (live bg task no longer counts) |
| M5 | `pid<=1 or pid in ancestry` → skipped | Case 4e (hook's own harness row counts) |

## 6. Suite: red → green

`plugins/leadv2/scripts/tests/test-continuation-guard.sh` — hermetic (mktemp sandbox; waker
sources pinned to fixture paths on every invocation so live lanes on this machine cannot flip
outcomes). Cases 2/3/3b/4/5 previously encoded the superseded requirement "tool call → ALLOW";
per lane-rules this test change is backed by the founder decision quoted in the suite header and
in §1 above, and the new behaviour is itself asserted (the decision is guarded by the very cases
that flipped).

Old suite (bytes of `3416f5e8`) against the new hook — red exactly on the flipped expectations:

```
OLD_SUITE_vs_NEW_HOOK_RC=1
[TEST] FAIL: Case 2: should allow when Edit used (got: {"decision": "block", …
[TEST] FAIL: Case 3: should allow when git commit used (got: {…
[TEST] FAIL: Case 3b: should allow measured read-only Bash probe (got: {…
[TEST] FAIL: Case 4: should allow when Agent dispatched (got: {…
[TEST] FAIL: Case 5: should allow when Monitor armed (got: {…
[TEST] FAIL: Case 15: tail-window fast path should allow in-window action (got: {…
[TEST] ═══ Results: 10 passed, 6 failed ═══
```

New suite against the new hook — green:

```
SUITE_RC=0 (measured unpiped)
[TEST] ═══ Results: 26 passed, 0 failed ═══
```

Boundary: 26 of 26 cases, macOS Darwin 25.6.0 at `d70ad504`, ~13 s wall, no per-case ceiling
engaged (no timeouts; a timeout would be a different verdict and is not blended into this one).

## 7. How CI selects the suite

The suite carries `# run-all-triggers: leadv2-continuation-guard`; the stem map resolves it to
the changed hook:

```
$ LEADV2_RUN_ALL_LIST_TRIGGERS=1 bash tests/run-all.sh | grep continuation-guard
leadv2-continuation-guard:plugins/leadv2/scripts/tests/test-continuation-guard.sh
```

`bash tests/run-all.sh --scope changed` (range = merge-base(HEAD, main)..HEAD = exactly the two
lane files) → **`run-all: 5 passed, 0 failed, scope=changed`**, rc=0, 4 m 52 s wall, 96 % cpu,
no foreign core-offline runner live at start.

## 8. Self-check (falsification set, raw)

```
$ bash -n plugins/leadv2/hooks/leadv2-continuation-guard.sh && echo OK      → OK
$ bash -n plugins/leadv2/scripts/tests/test-continuation-guard.sh && echo OK → OK (suite syntax OK)
$ py_compile of both embedded PYEOF heredocs                                → heredoc 1: OK, heredoc 2: OK
$ bash tests/run-all.sh --scope changed                                     → run-all: 5 passed, 0 failed, scope=changed
```

(The suite's first draft failed Case 4b — lsof reports the resolved cwd `/private/var/...` while
the fixture row carried `/var/...`; fixed by realpath-resolving both sides, hook now does the
same for real registries.)

## 9. Still red / not proven

- Nothing in the lane's scope is red.
- **Linux is unproven**: `ps -o lstart=`, `lsof -d cwd`, and the `claude-<uid>` tasks-dir layout
  are verified on macOS only. Per the platform boundary rule this is a declared difference, not a
  pass; a Linux CI lane should pin `LEADV2_GUARD_*` fixtures the same way this suite does.
- Residual risks §3(a)–(c) are open by design and named for the next lane.
