# BURN-GOVERNOR-01 fix-round-1 — architect prepass (mechanism-closed)

Worktree: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/b22dc98b` (branch `worktree-b22dc98b`).
No `context.yaml` exists for this task — nothing to honour beyond the mission text. All findings below are
read from the worktree tree, not from the mission's framing.

---

## §0. What the tree says (and where it contradicts the mission)

### 0.1 Live probe — the finding-1 failure is real and reproducible right now

```
$ bash plugins/leadv2/scripts/leadv2-burn-governor.sh verdict
verdict=hard burn24h=1958424399 soft=800000000 hard=1300000000 reason=over_hard
```

The host's live 24h burn is 1.96B against a hard cap of 1.3B. Every test that drives
`leadv2-dispatch-code.sh` far enough to reach `_burn_gate` refuses with `exit 6` on this machine today.
This is host state, not test state — the suite is non-hermetic with respect to `$HOME/.claude/burn/history.db`.

```
$ command -v timeout gtimeout
/opt/homebrew/bin/timeout
/opt/homebrew/bin/gtimeout
```

Both exist on THIS host (homebrew coreutils). They are **not** guaranteed on a clean macOS PATH — the
repo already treats that as a live hazard (`plugins/leadv2/scripts/tests/test-codex-lockout-agreement.sh:25`
comment: *"a portable bounded runner so the agreement suite no longer depends on GNU coreutils `timeout`
(absent from a clean macOS PATH)"*). So finding 3 must implement the fallback, not assume the binary.

### 0.2 CONTRADICTION with the mission's framing of finding 1

The mission says subtest **(f)** of `test-glm-deferred-ladder.sh` "gets rc=6" from *"a real resolve"*.
That is true but under-describes the path, and the under-description is exactly the kind of thing that
produces a second review round:

- **(f) does not call `resolve` at all.** It invokes
  `bash "${DISPATCH_BIN}" glm-deferred --retry-all` (test line 528).
- `cmd_glm_deferred`'s `retry-all` branch re-dispatches each parked mission as a **child process**:
  `_child_out="$(bash "${BASH_SOURCE[0]}" "@${_mpath}" 2>"${_child_errf}")"`
  — `leadv2-dispatch-code.sh:1099`.
- That **child** enters `cmd_resolve`, hits `_burn_gate` (`leadv2-dispatch-code.sh:4769`), and exits 6.
- The parent sees `_child_rc=6`, prints `retry_failed ffffffff rc=6 …` (line 1107), never creates
  `${MARKER_F}`, and the test fails at line 533 with *"(f) retry-all did not spawn a new dispatch"*.

**Design consequence:** the fix must be an `export` (inherited by grandchildren), not a per-invocation
`VAR=0 bash …` prefix on the visible dispatch call. A prefix on the `glm-deferred --retry-all` call would
also work here (bash exports command-prefix assignments into the child's environment, and the child
re-exports nothing but does inherit), but `export` at the top of the file is the only form that is
uniformly correct across every invocation shape in these 51 files without per-call auditing.
The child is spawned with a plain `bash "${BASH_SOURCE[0]}"` — no `env -i`, no scrub — so inheritance holds.

### 0.3 CONTRADICTION with "the burn gate reads the real db, so tests fail"

Only *standalone* runs fail. `plugins/leadv2/scripts/tests/run-core-offline.sh:102-113` builds an
`env -u` denylist that unsets **every** `LEADV2_*`, `CLAUDE_*`, `GIT_CONFIG*` variable, and it sandboxes
`~/.claude`. Under the full runner, `$HOME/.claude/burn/history.db` is absent → `no_telemetry` → `verdict=ok`.
So:

- The bug bites the founder running one suite by hand (which is exactly what the mission's acceptance step asks for).
- Adding `LEADV2_BURN_GOVERNOR=0` to `run-core-offline.sh` would be **scrubbed away** by its own `env -u LEADV2_*`
  loop unless re-added after the scrub. It is not needed (HOME sandboxing already covers it) and is a
  NON-GOAL here (§5).

---

## §1. Mechanism closure

### 1.1 CALLERS / CALLEES

**`leadv2-burn-governor.sh` — callees (all internal, all in-file):**

| Callee | Site | Notes |
|---|---|---|
| `_lbg_resolve_thresholds` | `leadv2-burn-governor.sh:76-80` (called from `cmd_verdict`) | forks `python3`; **unbounded** |
| `_lbg_classify` | `leadv2-burn-governor.sh:131` | forks `python3`; **unbounded** |
| `sqlite3` | `leadv2-burn-governor.sh:114` | `-cmd '.timeout 2000'` only; **this is finding 3** |
| `command -v sqlite3` | `:99` | fail-open guard |

**`leadv2-burn-governor.sh` — callers. There are TWO, on different paths, and the mission names only one:**

| # | Caller | file:line | Path | What it gates |
|---|---|---|---|---|
| C1 | `_burn_gate` (from `cmd_resolve`) | invocation `leadv2-dispatch-code.sh:1424`; definition `:1422`; call site `:4769` | **every** lane dispatch, incl. `--force` | worktree creation, ledger row, worker spawn |
| C2 | `cmd_burn_deferred` → `retry-all` | `leadv2-dispatch-code.sh:1174` | founder-invoked drain of the burn-deferred park queue | whether parked missions are re-dispatched at all |

C2 is the "independent copy nobody named" for this mission. It re-implements the same
`sed -n 's/.*verdict=\([a-z]*\).*/\1/p'` parse and its own hard-cap refusal (`:1203-1206`,
prints `burn-deferred: still over hard cap (burn24h=… >= …) — 0 of N retried`, `return 0`).
Both parse sites must keep working after the finding-3 change — which they do, because the
output contract (`verdict=… burn24h=… soft=… hard=… reason=…`, exit 0) is unchanged.

A **third**, adjacent path is `cmd_glm_deferred → retry-all` (`:1097-1108`). It does **not** call the
governor; it inherits the refusal via the child dispatch (§0.2). Mission findings 4/5 live here and are
out of scope.

`BURN_GOVERNOR_BIN` is resolved once at `leadv2-dispatch-code.sh:3351`
(`${LEADV2_BURN_GOVERNOR_BIN:-${SCRIPT_DIR}/leadv2-burn-governor.sh}`).

**`hooks/leadv2-compact-trigger.sh` (finding 2) — callers/callees.**
Real path is `plugins/leadv2/hooks/leadv2-compact-trigger.sh` (the mission's `hooks/…` is the
plugin-cache view; the canonical tree has it under `plugins/leadv2/hooks/`). It is a Stop-hook script:
no function calls in or out. Its two consumers are:

- the interactive-block branch at `:307-317` — emits `{"decision":"block","reason":"/compact"}` on stdout;
- the pending-warn file `$HOME/.claude/leadv2-pending-warn-${SESSION_ID}.txt` (`:305`, appended at `:355`),
  read by `user-prompt-context.sh` and surfaced to the founder on the next turn.

**No test anywhere references `leadv2-compact-trigger.sh`, `COMPACT_NOW`, or
`LEADV2_COMPACT_INTERACTIVE_BLOCK`** (grep over `plugins/leadv2/scripts/tests`, `plugins/leadv2/hooks`).
Finding 2 therefore cannot regress a suite, and equally has no automated proof — its acceptance is the
rendered warn line (§4).

### 1.2 STATES AND RETURN CODES

**`leadv2-burn-governor.sh` — always `exit 0`. State is carried on stdout only.**

| # | State | stdout `verdict=` / `reason=` | What C1 (`_burn_gate`) does | What C2 (`burn-deferred retry-all`) does | User-visible consequence |
|---|---|---|---|---|---|
| G1 | `LEADV2_BURN_GOVERNOR=0` | `ok` / `disabled` | `case *) return 0` | proceeds to drain | dispatch proceeds; gate silent |
| G2 | burn < soft | `ok` / `under_soft` | `return 0` | proceeds to drain | dispatch proceeds |
| G3 | soft ≤ burn < hard | `soft` / `over_soft` | journals `burn_gate … verdict=soft`, prints `⚠ BURN GATE …` to stderr, **returns 0** (`:1436-1439`) | proceeds to drain | lane runs; founder sees an advisory warning line |
| G4 | burn ≥ hard, `LEADV2_BURN_OVERRIDE≠1` | `hard` / `over_hard` | journals, prints `⛔ BURN GATE … lane refused, task parked`, `_burn_park_deferred`, **`exit 6`** (`:1447-1451`) | prints `burn-deferred: still over hard cap … 0 of N retried`, `return 0` | **no worker is started for that task; the mission is parked in `docs/leadv2/burn-deferred.jsonl` and nothing runs until burn falls or the founder overrides.** Under C2: **the parked backlog stays parked and the founder is told "0 of N retried".** |
| G5 | burn ≥ hard, `LEADV2_BURN_OVERRIDE=1` | `hard` / `over_hard` | journals with `overridden=1`, prints `⚠ BURN GATE OVERRIDDEN`, `return 0` | (no override branch — C2 still refuses) | dispatch proceeds, loudly |
| G6 | sqlite3 missing / db unreadable | `ok` / `no_telemetry` | `return 0` | proceeds | dispatch proceeds; gate is a no-op |
| G7 | query returned empty / non-numeric | `ok` / `no_telemetry` | `return 0` | proceeds | dispatch proceeds |
| G8 | bad soft/hard config | any + `+bad_config` suffix | as per verdict | as per verdict | defaults are used; `reason=…+bad_config` appears in the journal line |
| G9 | `python3` resolver dead | `ok` / `no_telemetry+bad_config` | `return 0` | proceeds | dispatch proceeds |
| **G10 (new)** | **sqlite3 exceeded the 5s wall-clock bound** | **`ok` / `no_telemetry`** | `return 0` | proceeds | **dispatch proceeds after at most ~5s instead of hanging forever** |
| G11 | governor produced NO output at all (e.g. killed) | — | `[[ -n "${governor_line}" ]] \|\| return 0` (`:1425`) | `_bd_verdict` empty → not `hard` → proceeds | dispatch proceeds |

`_burn_gate`'s only non-zero terminal is `exit 6` at `:1450`. `exit 6` from `cmd_resolve` is **terminal for
that process** — there is no retry loop above it inside `leadv2-dispatch-code.sh`. Traced to the end:

- direct founder/fanout dispatch → the lane never exists; nothing is drafted, nothing is committed.
- `glm-deferred --retry-all` → parent prints `retry_failed <sig8> rc=6 <last stderr line>` and moves to
  the next row; the glm-parked mission is **never marked retried**, so it stays in
  `docs/leadv2/glm-deferred.jsonl` and reappears on the next `--list`. No infinite loop, but also no progress.
- in `test-glm-deferred-ladder.sh` (f) → `${MARKER_F}` is never created → `fail "(f) retry-all did not
  spawn a new dispatch for the parked mission"`.

**Return codes after the fix: unchanged.** No new rc is introduced anywhere. G10 collapses into the
existing G6/G7 shape by construction — that is the point of the design.

### 1.3 CONFIGURATION BOUNDARIES

Every input the governor reads, at each boundary. `H` = current behaviour, `→` = required behaviour after this change.

| Input | Absent | Empty (`VAR=`) | Minimum | Maximum / over-cap | Malformed |
|---|---|---|---|---|---|
| `LEADV2_BURN_GOVERNOR` | default `1` → gate ON (**this is finding 1's root cause**) | `""` ≠ `"0"` → gate ON | `0` → G1 disabled | any non-`0` string → ON (no over-cap surface) | anything ≠ `0` is treated as ON. Fail-safe direction: a typo (`LEADV2_BURN_GOVERNOR=false`) leaves the gate armed. Keep as-is; it is the conservative direction for a cost gate. |
| `LEADV2_BURN_SOFT_24H` | `800000000` | `.isdigit()` false → defaults + `bad_config` | `0` accepted (`hard>soft` holds) → everything is ≥ soft → permanent `soft` advisory | a 21-digit value is handled in python arbitrary-precision (`:33-37` comment, D6) → no bash `(( ))` overflow → thresholds simply never trip | non-numeric / negative (`-1` fails `isdigit`) → defaults + `bad_config`. **Never blocks dispatch.** |
| `LEADV2_BURN_HARD_24H` | `1300000000` | as above | must satisfy `hard > soft`, else both reset to defaults + `bad_config` | as above | as above |
| `LEADV2_CLAUDE_BURN_DIR` | `$HOME/.claude/burn` | `""` → `db = "/history.db"` → not readable → **G6 `no_telemetry`, exit 0** (verified by inspection of `:96-102`; the `[[ ! -r ]]` guard catches it) | — | a path longer than `PATH_MAX` → `[[ ! -r ]]` false → G6 | a directory where `history.db` is a directory → `-r` may be true, `sqlite3` errors, stdout empty → G7 |
| `history.db` file | G6 | 0-byte file → sqlite3 treats as empty db, `no such table: hourly` → stderr suppressed, stdout empty → G7 | 1 row → sums fine | a multi-GB db → **this is the wall-clock hazard finding 3 exists for**; `.timeout 2000` does not bound a slow *scan*, only lock contention → currently unbounded → **after the fix: bounded at 5s → G10** | WAL-corrupt / locked-by-a-hung-writer → currently blocks past `.timeout 2000` in the `-shm`/`-wal` attach phase → **after the fix: bounded at 5s → G10** |
| **wall-clock bound (new)** | hardcoded `5` — **deliberately not an env var** (§2.3 rationale) | n/a | n/a | n/a | n/a |
| `LEADV2_BURN_OVERRIDE` (read by C1 only) | `0` | `""` ≠ `"1"` → no override | `1` → G5 | — | anything ≠ `1` → no override |
| `LEADV2_BURN_GOVERNOR_BIN` (read by C1/C2) | `${SCRIPT_DIR}/leadv2-burn-governor.sh` | `""` → `bash ""` → bash errors, stdout empty → G11 → proceed | — | — | a nonexistent path → `bash: no such file` on stderr (suppressed by `2>/dev/null`), stdout empty → G11 → proceed |

**Over-cap rule check (mission's explicit bar — "an over-cap or malformed input that takes down more than
the one operation it belongs to is a defect"):** every row above collapses to *proceed* or *use defaults*.
The single input that can take down more than its own operation is the **wall-clock hang** — a hung
`sqlite3` today hangs `_burn_gate`, which hangs `cmd_resolve`, which hangs the whole dispatch and every
caller waiting on it (fanout, the lane launcher, a founder's terminal). That is precisely finding 3, and
the fix converts it to G10.

### 1.4 COUNTEREXAMPLE — what still violates the invariant after all three fixes

The invariant the burn governor exists to protect: *a cost-telemetry problem must never become a dispatch
outcome, and the gate must never cost more than the query it wraps.* After findings 1–3 are fixed, three
things can still violate it, and I could not honestly reduce the list to zero.

**(a) The wall-clock bound covers `sqlite3` only, not `python3`.** `_lbg_resolve_thresholds` (`:35`) and
`_lbg_classify` (`:57`) each fork an interpreter with no bound at all. On a host where `python3` is a
shim that stalls (a corrupted pyenv shim, an NFS-mounted site-packages, a `PYTHONSTARTUP` that blocks),
`cmd_verdict` hangs before it ever reaches the sqlite call — and the caller `_burn_gate` puts **no bound
on the governor process itself** (`leadv2-dispatch-code.sh:1424` is a bare command substitution). So the
"a hung telemetry read cannot hang dispatch" property is only *mostly* restored by finding 3. Closing it
properly means bounding the governor at C1/C2, which is a larger change than this round; I am flagging it,
not smuggling it in (see §5 NON-GOALS, and §6 follow-up).

**(b) A `SIGKILL`-proof child.** The portable fallback runner sends `TERM` then `KILL`. A `sqlite3` blocked
in an uninterruptible disk wait (`D` state — NFS, a stalled external volume) ignores both, and the
`wait "${pid}"` that follows will block past the nominal 5s. Bounded in practice on a local APFS volume;
unbounded in principle. GNU `timeout` has the same limitation, so this is not a fallback-specific defect.

**(c) The next test somebody writes.** Finding 1's fix is 51 independent `export` lines, not a mechanism.
Nothing in the tree forces a *new* `plugins/leadv2/scripts/tests/test-*.sh` that drives
`leadv2-dispatch-code.sh` to disable the governor, so the same class of host-state red returns the first
time a suite is added without it. A mechanism (a sourced test preamble; a `--test-mode` that implies the
governor off) would close it — there is currently **no shared test helper at all**: of the 51 files, zero
source a common lib (verified by grep for `source .*(test-helpers|leadv2-common|lib/)` across them), so
introducing one is a refactor the mission explicitly forbids this round.

What I checked and found clean: the output contract of the governor is unchanged by finding 3, so both
`sed`-based parse sites (C1 `:1427-1431`, C2 `:1175-1177`) keep working; `_burn_gate`'s `exit 6` has no
retry loop above it, so no fix can create a refusal storm; and `run-core-offline.sh`'s HOME sandbox
already makes the full-runner path immune, so the 51 exports cannot change full-runner results.

---

## §2. The design

### 2.1 Finding 1 — test hermeticity (HIGH)

**Change.** Insert exactly one line into each affected test file, in (or immediately after) its
ambient-env scrub block — i.e. after the `unset LEADV2_…` lines where one exists, otherwise immediately
after the `set -uo pipefail` / path-resolution preamble and before the first tool invocation:

```bash
# BURN-GOVERNOR-01: the burn gate defaults ON and reads the host's real
# ~/.claude/burn/history.db — a hot host would red this suite on `exit 6`.
export LEADV2_BURN_GOVERNOR=0
```

`export`, not a bare assignment: the refusal in `test-glm-deferred-ladder.sh` (f) happens in a
**grandchild** process (§0.2), which only an exported variable reaches.

**Scope: all 51 files** under `plugins/leadv2/scripts/tests/` that match
`grep -rl "leadv2-dispatch-code" *.sh`, **excluding `test-burn-governor.sh`** (which keeps its own
`unset LEADV2_BURN_GOVERNOR …` at `:27-30` and sets the variable explicitly per subtest — do not
blanket-disable inside it).

Blanket rather than "only the ones that really execute it" is a deliberate call. Two independent
regex passes over the same 52 files disagreed on which ones execute the binary (one said 17, the
other said 22, and they disagreed on `test-glm-first-recovery.sh`, which has 10 `resolve` mentions
and zero regex-detected executions because it dispatches through a local helper function). An
unused `export` in a test that only greps the source costs nothing and changes no assertion; a
missing one in a test that does execute it is a red on the founder's laptop. The asymmetry decides it.

The two non-`.sh` grep hits — `fixtures/lane-view-ps.txt` and `fixtures/plan-run/stub-architect.sh` —
are fixtures, not tests, and are excluded.

**Root `tests/` directory:** `grep -rl "leadv2-dispatch-code" tests/` returns **nothing**. No changes there.
(The mission's "and tests/ at repo root if they exercise dispatch-code resolution" resolves to a no-op.)

**Per-file check the implementer must make before inserting:** if a file assembles a curated child
environment (`env -i …`) around a dispatch invocation, the export will not reach that child and
`LEADV2_BURN_GOVERNOR=0` must be added to that `env -i` argument list as well. Across the 51 files
`grep -n 'env -i'` returns hits only in suites that do **not** invoke dispatch-code (`test-leadv2-router-glm.sh`,
`test-leadv2-mem-backup.sh`, `test-leadv2-regression-gate.sh`, `test-leadv2-shadow-promotion-gate.sh`,
`test-leadv2-router-recovery.sh`, `test-diagnose-codex-disabled-degrades.sh`, `test-codex-session-runner.sh`),
so on today's tree the export alone is sufficient — but the check is cheap and must be re-run, not assumed.

### 2.2 Finding 2 — emergency warn text (MED)

**File:** `plugins/leadv2/hooks/leadv2-compact-trigger.sh`, the `emergency)` arm of the `case` at `:328-329`.

**Do not change** the `LEADV2_COMPACT_INTERACTIVE_BLOCK` default (`:309` reads `${…:-0}`) — it is
already OFF per founder order 2026-08-19 / commit 7daf57f, and `:299-301` documents why.

**Change** the `MSG` string only. It must, in the founder's language (this file's warn strings are
Russian and must stay Russian), state two things the current text does not:

1. plainly, that the session is **past the emergency context width** — naming the estimated tokens and
   the emergency threshold `${EMERG_T}` (currently only `${EST_K}` is printed, with no threshold, so the
   reader cannot tell "emergency" from "hard");
2. that `LEADV2_COMPACT_INTERACTIVE_BLOCK=1` is the **opt-in** that makes the hook auto-block the turn on
   `/compact`, and that it is **off by default** — so the founder knows why nothing was auto-compacted.

Required content, not required wording:

```bash
  emergency)
    MSG="[COMPACT_NOW] Сессия ПРЕВЫСИЛА аварийный порог контекста: ~${EST_K}K токенов (порог ${EMERG_T} токенов, файл ${KB}KB${TASK_NOTE}). Каждый следующий ход стоит ${EST_K}K input. Авто-/compact сейчас НЕ включён (по умолчанию OFF): чтобы хук сам блокировал ход и вызывал /compact, экспортируй LEADV2_COMPACT_INTERACTIVE_BLOCK=1. Скажи фаундеру одной строкой: 'Нужен /compact — контекст ${EST_K}K токенов.' Потом жди."
    ;;
```

`EMERG_T` is in scope at that point (assigned `:228`, unconditionally). `KB`, `EST_K`, `TASK_NOTE` are
already used by the neighbouring arms. Nothing else in the `case` changes.

### 2.3 Finding 3 — hard wall-clock bound on the sqlite read (MED)

**File:** `plugins/leadv2/scripts/leadv2-burn-governor.sh`.

**Pattern to copy — the repo already has one, twice.** `lib/leadv2-builder-selfcheck.sh:59-84`
(`_lv2_selfcheck_timeout_run`) is the canonical form and carries a hard-won comment (`:44-57`) about the
exact trap to avoid: a watcher subshell that inherits the caller's command-substitution pipe keeps the
write end open, so the caller blocks for the FULL timeout even after the child is killed. Its fix — detach
the watcher's own I/O (`>/dev/null 2>&1 </dev/null`) and use `set -m` + `kill -TERM -"${pid}"` to reach the
whole process group — is mandatory here, because the governor's sqlite call **is** inside a command
substitution. `tests/test-codex-lockout-agreement.sh:31-58` (`_run_bounded`) is the second, simpler
instance and confirms the `rc=124` convention.

**Add**, near the other helpers:

```bash
# Hard wall-clock bound on the telemetry read. `-cmd '.timeout 2000'` bounds
# SQLITE_BUSY only -- it does NOT bound a slow scan, a WAL/-shm attach against a
# hung writer, or a db on a stalled volume. Without this, a telemetry problem
# hangs cmd_verdict, which hangs _burn_gate, which hangs the whole dispatch.
# Mirrors lib/leadv2-builder-selfcheck.sh:_lv2_selfcheck_timeout_run, including
# its detached-watcher fix: the watcher must not inherit our command-substitution
# pipe or the caller blocks for the full bound even after the child dies.
# rc 124 == timed out (GNU convention). Never configurable: a gate whose own
# bound can be misconfigured to `0` or `999999` reintroduces the hang it fixes.
_LBG_SQL_TIMEOUT_S=5

_lbg_bounded_sqlite() {   # $1=db $2=sql ; stdout = query result ; rc 124 on timeout
  local db="$1" sql="$2" out rc=0
  out="$(mktemp 2>/dev/null || printf '/tmp/lbg-sql.%s' "$$")" || return 1
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${_LBG_SQL_TIMEOUT_S}" sqlite3 -cmd '.timeout 2000' "${db}" "${sql}" >"${out}" 2>/dev/null
    rc=$?
  elif command -v timeout >/dev/null 2>&1; then
    timeout "${_LBG_SQL_TIMEOUT_S}" sqlite3 -cmd '.timeout 2000' "${db}" "${sql}" >"${out}" 2>/dev/null
    rc=$?
  else
    local pid watcher
    set -m
    { sqlite3 -cmd '.timeout 2000' "${db}" "${sql}" >"${out}" 2>/dev/null & } 2>/dev/null
    pid=$!
    set +m
    ( sleep "${_LBG_SQL_TIMEOUT_S}"
      kill -0 "${pid}" 2>/dev/null || exit 0
      kill -TERM -"${pid}" 2>/dev/null || kill -TERM "${pid}" 2>/dev/null || true
      sleep 1
      kill -KILL -"${pid}" 2>/dev/null || kill -KILL "${pid}" 2>/dev/null || true
    ) >/dev/null 2>&1 </dev/null &
    watcher=$!
    wait "${pid}" 2>/dev/null; rc=$?
    kill -TERM "${watcher}" 2>/dev/null || true
    wait "${watcher}" 2>/dev/null || true
    [ "${rc}" -gt 128 ] && rc=124
  fi
  # On timeout the partial file is DISCARDED, not parsed: a half-written row of
  # digits would satisfy the ^[0-9]+$ guard downstream and become a real verdict.
  [ "${rc}" -eq 124 ] || cat "${out}" 2>/dev/null
  rm -f "${out}" 2>/dev/null || true
  return "${rc}"
}
```

**Replace** the call at `:114-120` with:

```bash
  local burn24h
  burn24h="$(_lbg_bounded_sqlite "${db}" "
SELECT COALESCE(SUM(
  COALESCE(cc_sum,0)+COALESCE(cr_sum,0)+COALESCE(input_sum,0)+COALESCE(output_sum,0)
),0)
FROM hourly
WHERE hour_key >= strftime('%Y-%m-%d-%H','now','-24 hours');
" 2>/dev/null)"
```

No `if` on the rc is needed: on rc 124 the helper prints nothing, `burn24h` is empty, and the **existing**
guard at `:122-125` already emits `verdict=ok … reason=no_telemetry` and `return 0`. That is the fail-open
the mission asks for, reached through the code path that is already there and already tested — no new branch,
no new state, no new rc. Keep the existing `-cmd '.timeout 2000'`: it is the cheap inner bound for the common
lock case and the comment at `:105-112` records live evidence for why the dot-command form (not
`PRAGMA busy_timeout`) and no `-readonly`.

`set -m` / `set +m` inside a function is safe here — `set -uo pipefail` at `:23` does not include `-e`, and
job control is restored immediately.

---

## §3. Files

| File | Change |
|---|---|
| `plugins/leadv2/scripts/leadv2-burn-governor.sh` | add `_LBG_SQL_TIMEOUT_S` + `_lbg_bounded_sqlite`; route the one sqlite3 call through it |
| `plugins/leadv2/hooks/leadv2-compact-trigger.sh` | `emergency)` `MSG` text only (`:328-329`) |
| 51 × `plugins/leadv2/scripts/tests/test-*.sh` / `zzrepro-test-lpp.sh` | one `export LEADV2_BURN_GOVERNOR=0` line each |

The 51 test files (exact list, `plugins/leadv2/scripts/tests/`):
`test-arm-ladder-vocabulary-drift.sh`, `test-backlog-pump.sh`, `test-broad-status-lanes-blind.sh`,
`test-broad-status-relay-scope.sh`, `test-claim-evidence-gate.sh`, `test-codex-instant-complete.sh`,
`test-codex-worker-liveness.sh`, `test-dispatch-architect-degrades.sh`,
`test-dispatch-architect-prepass-late-artifact.sh`, `test-dispatch-architect-prepass-orphan-timeout.sh`,
`test-dispatch-arm-vocabulary.sh`, `test-dispatch-checkpoint-commit-cutoff.sh`,
`test-dispatch-cwd-root-else-branch.sh`, `test-dispatch-duplicate-caller-race.sh`,
`test-dispatch-ledger-partial-close.sh`, `test-dispatch-ledger-task-id.sh`,
`test-dispatch-outcome-terminal-retry.sh`, `test-dispatch-resume-sentinel.sh`,
`test-dispatch-retry-dead.sh`, `test-fg-dispatch-guard.sh`, `test-foreign-project-root-guard.sh`,
`test-glm-deferred-ladder.sh`, `test-glm-first-recovery.sh`, `test-landed-at-spawn.sh`,
`test-landing-diff-scoping.sh`, `test-lane-placement-pin.sh`, `test-lane-truth-batch-01.sh`,
`test-lane-worktree-isolation.sh`, `test-lane-writes-scoping.sh`,
`test-leadv2-dispatch-outcome-ledger.sh`, `test-leadv2-event-emitter.sh`,
`test-leadv2-router-v2-toggle.sh`, `test-lock-busy-reresolve.sh`, `test-lockout-failure-class.sh`,
`test-phase-precondition.sh`, `test-plan-run-contract.sh`, `test-plugin-reliability-01.sh`,
`test-prepass-repo-parity.sh`, `test-quota-lockout-postspawn.sh`, `test-quota-standdown-duration.sh`,
`test-report-only-gate.sh`, `test-review-codex-base.sh`, `test-router-v2-retired-arm.sh`,
`test-routing-enforcement-p1.sh`, `test-st2-question-protocol.sh`, `test-status-surface.sh`,
`test-statusline-count-truth.sh`, `test-stop-gate.sh`, `test-subsession-absolute-handoff-path.sh`,
`test-worker-env-asserts.sh`, `zzrepro-test-lpp.sh`.

---

## §4. Acceptance

```
acceptance:
  - surface: log_line
    observable: >
      Running `bash plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh` by hand on the
      founder's laptop — the same machine whose 24h burn is currently 1.96B, over the 1.3B hard
      cap — no longer prints a line saying subtest (f) failed to spawn a new dispatch, and no
      "BURN GATE" refusal text appears anywhere in that suite's output. The suite's two
      known-on-main failures, (d) and (e), still appear and are still expected.
    authored_at: 2026-08-23T20:38:56Z
  - surface: log_line
    observable: >
      `bash plugins/leadv2/scripts/tests/test-burn-governor.sh` prints twenty-five PASS lines
      and no FAIL lines, unchanged from before this work.
    authored_at: 2026-08-23T20:38:56Z
  - surface: rendered_line
    observable: >
      When a session crosses the emergency context width, the warning the founder reads names
      the threshold it crossed alongside the session's own size, says in plain words that
      automatic /compact is off by default, and names LEADV2_COMPACT_INTERACTIVE_BLOCK=1 as the
      switch that turns it on. A founder who has never read the hook can tell from that one line
      why nothing was compacted for them and what to set if they want it to be.
    authored_at: 2026-08-23T20:38:56Z
  - surface: log_line
    observable: >
      With the telemetry database made unreadable-but-slow (a fixture db on a stalled path, or
      the db replaced by a FIFO nobody writes to), the governor still prints its single verdict
      line within about five seconds, that line reads ok / no_telemetry, and a dispatch driven
      against that host proceeds instead of hanging. Before this change the same setup hangs
      with no output at all.
    authored_at: 2026-08-23T20:38:56Z
  - surface: file_artifact
    observable: >
      The worktree b22dc98b carries one commit whose message names b22dc98b, and whose changed
      files are exactly the governor script, the compact-trigger hook, and the 51 test files —
      nothing under docs/, no other script, no refactor.
    authored_at: 2026-08-23T20:38:56Z
```

---

## §5. NON-GOALS (out of scope for the implementer)

1. **Findings 4 and 5** (retry-all TOCTOU, `founder_task_id` drop) — inherited from `cmd_glm_deferred`
   (`leadv2-dispatch-code.sh:1097-1108`). Do not touch that block.
2. **The `LEADV2_COMPACT_INTERACTIVE_BLOCK` default.** It stays `0`. Text only.
3. **`run-core-offline.sh`.** Its `env -u LEADV2_*` scrub (`:102-113`) would strip any export added there,
   and its HOME sandbox already makes the full-runner path immune. Leave it alone.
4. **Bounding the governor process itself at C1/C2**, and bounding the two `python3` forks inside it
   (counterexample (a)). Real, out of scope this round — see §6.
5. **Introducing a shared test preamble/helper** to make finding 1 a mechanism instead of 51 lines
   (counterexample (c)). That is a refactor; the mission forbids it.
6. **Any change to the governor's stdout contract, its thresholds, or its always-exit-0 property.**
   Two independent `sed` parsers depend on the exact shape.
7. **`docs/`, `docs/leadv2/`, `docs/handoff/`** — the implementer writes no documentation for this round.

---

## §6. Follow-up worth queueing (do not do it here)

- Bound the governor invocation at `leadv2-dispatch-code.sh:1424` and `:1174` (`_burn_gate` and
  `burn-deferred retry-all`) so a hung `python3` inside the governor cannot hang a dispatch — closes
  counterexample (a), which finding 3 only half-closes.
- A shared `plugins/leadv2/scripts/tests/lib.sh` preamble carrying the ambient-env scrub, so the next
  suite cannot forget `LEADV2_BURN_GOVERNOR=0` — closes counterexample (c).

---

LANE_WRITES: plugins/leadv2/scripts/leadv2-burn-governor.sh, plugins/leadv2/hooks/leadv2-compact-trigger.sh, plugins/leadv2/scripts/tests/test-arm-ladder-vocabulary-drift.sh, plugins/leadv2/scripts/tests/test-backlog-pump.sh, plugins/leadv2/scripts/tests/test-broad-status-lanes-blind.sh, plugins/leadv2/scripts/tests/test-broad-status-relay-scope.sh, plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh, plugins/leadv2/scripts/tests/test-codex-instant-complete.sh, plugins/leadv2/scripts/tests/test-codex-worker-liveness.sh, plugins/leadv2/scripts/tests/test-dispatch-architect-degrades.sh, plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-late-artifact.sh, plugins/leadv2/scripts/tests/test-dispatch-architect-prepass-orphan-timeout.sh, plugins/leadv2/scripts/tests/test-dispatch-arm-vocabulary.sh, plugins/leadv2/scripts/tests/test-dispatch-checkpoint-commit-cutoff.sh, plugins/leadv2/scripts/tests/test-dispatch-cwd-root-else-branch.sh, plugins/leadv2/scripts/tests/test-dispatch-duplicate-caller-race.sh, plugins/leadv2/scripts/tests/test-dispatch-ledger-partial-close.sh, plugins/leadv2/scripts/tests/test-dispatch-ledger-task-id.sh, plugins/leadv2/scripts/tests/test-dispatch-outcome-terminal-retry.sh, plugins/leadv2/scripts/tests/test-dispatch-resume-sentinel.sh, plugins/leadv2/scripts/tests/test-dispatch-retry-dead.sh, plugins/leadv2/scripts/tests/test-fg-dispatch-guard.sh, plugins/leadv2/scripts/tests/test-foreign-project-root-guard.sh, plugins/leadv2/scripts/tests/test-glm-deferred-ladder.sh, plugins/leadv2/scripts/tests/test-glm-first-recovery.sh, plugins/leadv2/scripts/tests/test-landed-at-spawn.sh, plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh, plugins/leadv2/scripts/tests/test-lane-placement-pin.sh, plugins/leadv2/scripts/tests/test-lane-truth-batch-01.sh, plugins/leadv2/scripts/tests/test-lane-worktree-isolation.sh, plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh, plugins/leadv2/scripts/tests/test-leadv2-dispatch-outcome-ledger.sh, plugins/leadv2/scripts/tests/test-leadv2-event-emitter.sh, plugins/leadv2/scripts/tests/test-leadv2-router-v2-toggle.sh, plugins/leadv2/scripts/tests/test-lock-busy-reresolve.sh, plugins/leadv2/scripts/tests/test-lockout-failure-class.sh, plugins/leadv2/scripts/tests/test-phase-precondition.sh, plugins/leadv2/scripts/tests/test-plan-run-contract.sh, plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh, plugins/leadv2/scripts/tests/test-prepass-repo-parity.sh, plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh, plugins/leadv2/scripts/tests/test-quota-standdown-duration.sh, plugins/leadv2/scripts/tests/test-report-only-gate.sh, plugins/leadv2/scripts/tests/test-review-codex-base.sh, plugins/leadv2/scripts/tests/test-router-v2-retired-arm.sh, plugins/leadv2/scripts/tests/test-routing-enforcement-p1.sh, plugins/leadv2/scripts/tests/test-st2-question-protocol.sh, plugins/leadv2/scripts/tests/test-status-surface.sh, plugins/leadv2/scripts/tests/test-statusline-count-truth.sh, plugins/leadv2/scripts/tests/test-stop-gate.sh, plugins/leadv2/scripts/tests/test-subsession-absolute-handoff-path.sh, plugins/leadv2/scripts/tests/test-worker-env-asserts.sh, plugins/leadv2/scripts/tests/zzrepro-test-lpp.sh

DELIVERABLE_COMPLETE
