# Mission B — unified lane trace: mechanism-closed implementation design

Role: architect (prepass). **No implementation performed.** Every fact below was read from
the tree or measured on this machine; probe artifacts are inline.

---

## 0. Where the mission's framing and the code disagree

Three points where the mission's wording does not survive contact with the tree. Design is
against the code.

### 0.1 "at most one env test per span — no subshell, no external command, no file open"

Literally unachievable as stated, because the *helper itself* must be loaded before any span
call can exist, and loading is a file open. Probe:

```
$ grep -hoE '(source|\.) +"?\$\{?SCRIPT_DIR\}?/[a-z0-9./-]+' leadv2-dispatch-code.sh ... | sort | uniq -c
   2 source "${SCRIPT_DIR}/leadv2-active-registry.sh
   1 source "${SCRIPT_DIR}/leadv2-tasks-lib.sh
   1 source "${SCRIPT_DIR}/leadv2-portable-lock.sh
   1 source "${SCRIPT_DIR}/leadv2-lane-child-suffixes.sh
   1 source "${SCRIPT_DIR}/leadv2-helpers.sh
```

Resolution — **strictly cheaper than what the mission asked for**: one env test per
*process* (not per span), and when off the lib file is never opened at all. See §3.1. Off-path
per-span cost becomes a no-op shell function call: no fork, no file open, no `[[ ]]`.

### 0.2 "MONOTONIC clock (not `date`)" — no fork-free monotonic clock exists on this platform

| source | fork-free? | monotonic? | available here | probe |
|---|---|---|---|---|
| `EPOCHREALTIME` | yes | **no** (wall, NTP-steppable) | bash 5.3 only | `bash -c 'echo $EPOCHREALTIME'` → `1787452247.539477`; `/bin/bash -c ...` → `UNSET` (bash 3.2.57) |
| `/proc/uptime` | yes | yes | **no** | `cat /proc/uptime` → `No such file or directory` |
| `perl -MTime::HiRes CLOCK_MONOTONIC` | no (~9 ms) | **yes** | yes | `perl -MTime::HiRes=clock_gettime,CLOCK_MONOTONIC -e '...'` → `361614730288000` |
| `python3 time.monotonic_ns()` | no (~30 ms) | **yes** | yes | `python3 -c 'import time;print(time.monotonic_ns())'` → `361619401817875` |
| `date +%s%N` | no | **no** | yes | `/bin/date +%s%N` → `1787452247548737000` |

Measured fork cost (20 iterations, this machine, 2026-08-23):
```
perl   CLOCK_MONOTONIC x20 -> 0.179s total  =>  ~9 ms/call
python3 monotonic_ns   x20 -> 0.599s total  =>  ~30 ms/call
```

**Decision D1:** monotonic source is `perl -MTime::HiRes` (primary), `python3 time.monotonic_ns`
(fallback if perl missing). Two forks per span (~18 ms). Never `date`. Never `EPOCHREALTIME` as
the timing source. The record carries `clock_source` so no reader has to guess.

**Decision D2 — instrument-cost floor.** 18 ms of instrument per span is 0.012% of a 146 s
provider median but **~14% of one `leadv2-dispatch-code.sh --help`** (measured: 5 runs → 0.645s
=> ~129 ms/run). Therefore every record carries `instrument_ns` (measured cost of the two
boundary forks) so the reader can subtract it, and §6 states which spans are too cheap to
trust. This is honest instrumentation, not a hidden tax.

### 0.3 "one file per trace" — concurrent lanes are the normal case, not the edge

Mission §3 says "one file per trace … one writer per process". Those are two different
partitionings. A lane spawns children (`glm-coder.sh`, `codex-task.sh`, review fanout) that
inherit `LEADV2_TRACE_ID` and therefore share the *trace*, so "one file per trace" means N
processes appending to one file. That is exactly why the mission also demands O_APPEND
single-line writes. Design honours both: **one file per trace, many writers, each record a
single `write(2)` under O_APPEND, each record ≤ PIPE_BUF-sized by construction (§3.4).**

---

## 1. CALLERS / CALLEES

### 1.1 The nine instrumentation targets — verified present, with size and existing trap load

```
leadv2-dispatch-code.sh   5580 lines   EXIT traps: 2   exits: 96   exec: 1
leadv2-router.sh          1125 lines   EXIT traps: 1   exits: 12   exec: 0
leadv2-review-run.sh      1314 lines   EXIT traps: 0   exits: 10   exec: 0
leadv2-status-collector.sh 233 lines   EXIT traps: 1   exits:  2   exec: 0
leadv2-lanes-snapshot.sh  1389 lines   EXIT traps: 0   exits:  4   exec: 2
leadv2-backlog-pump.sh     984 lines   EXIT traps: 1   exits:  2   exec: 0
glm-coder.sh              1773 lines   EXIT traps: 0   exits: 32   exec: 2
kimi-coder.sh             1804 lines   EXIT traps: 0   exits: 35   exec: 2
codex-task.sh             1862 lines   EXIT traps: 2   exits: 22   exec: 1
```

**The 96 `exit` statements in `leadv2-dispatch-code.sh` are the single most important
discovery in this design.** No wrapper of the form `main "$@"; rc=$?; trace_end` can close
the lane span, because 96 code paths leave the process without ever returning to that line.
Only an `EXIT` trap catches them all. And `leadv2-dispatch-code.sh` **already has one**:

```
leadv2-dispatch-code.sh:2487  cleanup_pending_dispatch() {
leadv2-dispatch-code.sh:2494  trap cleanup_pending_dispatch EXIT
leadv2-dispatch-code.sh:2495  trap 'exit 130' INT TERM
```

A naive `trap lv2_trace_end EXIT` **silently replaces** it — bash keeps exactly one EXIT
handler. `cleanup_pending_dispatch` would stop running, `ACTIVE_DISPATCH_TOKEN` would never be
released, and every aborted dispatch would leak a pending-dispatch entry into the active
registry. In plain words: **adding a trace would leave phantom lanes in the founder's status
board forever.** This is the defect this design exists to prevent; see §3.5 (trap chaining) and
§5 (counterexample).

### 1.2 Existing EXIT traps that a naive instrumentation would destroy

| file:line | existing handler | what breaks if clobbered (plain words) |
|---|---|---|
| `leadv2-dispatch-code.sh:2494` | `cleanup_pending_dispatch` | aborted dispatch never releases its token → phantom lane rows in status, forever |
| `leadv2-dispatch-code.sh:2495` | `trap 'exit 130' INT TERM` | Ctrl-C stops reporting 130; supervisors misread a cancel as a crash |
| `leadv2-router.sh:95` | `rm -f "$PY_HELPER"` | a temp python helper leaks per routing decision |
| `leadv2-status-collector.sh:47` | `rm -rf "$_SC_TMPDIR"; exit $_ec` | temp dir leaks **and the collector's exit code is lost** — the status timer starts reporting success on failure |
| `leadv2-status-collector.sh:28` | `trap 'exit 0' ERR` | probe contract "never crash the timer" is voided |
| `leadv2-backlog-pump.sh:544` | `_release_pump_lock` (installed **inside** a function) | pump lock is never released → backlog pump wedges permanently |
| `codex-task.sh:471` | `rm -rf "$_codex_watch_lockdir"` (inside a function) | quota-watch lockdir leaks |
| `codex-task.sh:1255` | `rm -f "$_JOB_REG_DIR/$_JOB_REG_ID"` (inside a function) | codex job registry entry leaks → zombie job rows |

Two of these (`leadv2-backlog-pump.sh:544`, `codex-task.sh:471`/`:1255`) install their trap
**at runtime from inside a function**, i.e. *after* any top-level arming would have happened.
Bash traps are process-global, so those late installs would clobber an early trace trap
regardless of source order. **Consequence: in `leadv2-backlog-pump.sh` and `codex-task.sh` the
EXIT-trap strategy is unusable. Those two get explicit begin/end bracketing instead** (§3.6),
which is what the mission wants anyway for `codex-task.sh` ("span = the provider call itself").

### 1.3 Callers of each instrumented script — who supplies `LEADV2_TRACE_ID`

Established by grep over `plugins/leadv2` (`*.sh`, `*.py`, `*.md`):

| target | callers found | trace-id source |
|---|---|---|
| `leadv2-router.sh` | `leadv2-dispatch-code.sh`, `leadv2-llm-judge.sh`, `claude-subsession.sh`, `lib/leadv2-glm-policy-resolve.py`, `commands/leadv2.md`, 2 tests | inherited env when called from dispatch; **self-derived when called from `leadv2.md` (a slash command, no lane)** |
| `leadv2-review-run.sh` | `leadv2-dispatch-code.sh`, `leadv2-review-findings.sh`, `leadv2-helpers.sh`, `leadv2-plan-run.sh`, 2 hooks (`leadv2-workflow-bypass-guard.sh`, `leadv2-workflow-sentinel-touch.sh`), `ZZ-pre-review-run.sh` (untracked) | inherited; hooks run in a **fresh Claude-Code hook process with no lane env** → self-derive from `--task` |
| `leadv2-status-collector.sh` | `leadv2-status-render.sh`, `leadv2-broad-status.sh`, `leadv2-lane-detail.sh` | **no lane at all** — these are timer/pulse paths. Trace id = `ambient` (§2.3) |
| `leadv2-lanes-snapshot.sh` | `leadv2-status-collector.sh`, `leadv2-lanes-resume.sh`, `leadv2-plugin-sync.sh`, `leadv2-broad-status.sh`, 3 tests, `docs/supervisor-role.md` | same — ambient |
| `leadv2-backlog-pump.sh` | `leadv2-pulse-beat.sh`, `leadv2-fanout.sh`, `leadv2-tasks-lib.sh`, 2 tests | ambient (pump runs before a lane exists) |
| `glm-coder.sh` | `codex-task.sh`, `leadv2-review-run.sh`, 3 hooks (`leadv2-link-tree-heal.sh`, `leadv2-no-opus-code-edit.sh`, `leadv2-block-fg-dispatch.sh`), 2 tests | inherited from dispatch/review |
| `kimi-coder.sh` | `leadv2-dispatch-code.sh`, `codex-task.sh`, `leadv2-lane-outcome.sh`, `leadv2-status-surface.sh`, `leadv2-kimi-session-runner.sh`, 3 tests | inherited |
| `codex-task.sh` | 2 hooks (`leadv2-codex-first-nudge.sh`, `leadv2-block-codex.sh`), 3 tests, 3 docs | inherited when dispatched; **hook path has no lane** |

**The independent-copy miss the mission warns about, named explicitly:** `glm-coder.sh` and
`kimi-coder.sh` are *not* only reached from `leadv2-dispatch-code.sh`. `codex-task.sh` calls
both of them, and `leadv2-review-run.sh` calls `glm-coder.sh`. A provider span therefore
appears under a **review** parent as often as under a **dispatch** parent, and a trace that
assumes `provider ⇒ lane` will mis-attribute review cost to lane cost. The record's `ppid` +
`parent_span` fields (§3.4) exist precisely to keep those two paths separable.

**Second independent path:** three hooks (`leadv2-workflow-bypass-guard.sh`,
`leadv2-workflow-sentinel-touch.sh`, `leadv2-codex-first-nudge.sh`) invoke instrumented scripts
from a Claude-Code hook process. Hooks do **not** inherit a lane's exported env. Those
invocations self-derive or fall to `ambient`; they are not a lane and must not be summed into
one.

### 1.4 Functions the new lib calls (callees)

| callee | file:line | why |
|---|---|---|
| `leadv2-state-path.sh --no-link <name>` | `plugins/leadv2/scripts/leadv2-state-path.sh` (arg parsing at `:63-67`) | resolve sink dir. `--no-link` is mandatory — the default path **mutates the caller's worktree** by creating `docs/leadv2/<name>` symlinks and migrating real files (documented at `:40-57`). A trace must never mutate a worktree. |
| `perl -MTime::HiRes` / `python3 -c` | external | monotonic clock (D1) |

Precedent for `--no-link`: `leadv2-dispatch-code.sh:633` already calls it that way.

`STATE_PATH_BIN` override precedent: `leadv2-dispatch-code.sh:542`
`STATE_PATH_BIN="${LEADV2_STATE_PATH_BIN:-${SCRIPT_DIR}/leadv2-state-path.sh}"` — the lib
follows the same convention so tests can sandbox it.

---

## 2. STATES AND RETURN CODES

### 2.1 State table of the trace mechanism

| # | state | condition | behaviour | user-visible consequence |
|---|---|---|---|---|
| S0 | disabled | `LEADV2_TRACE` unset or ≠ `1` | lib never sourced; span calls are no-op stubs | nothing changes anywhere; zero files created |
| S1 | enabled, id inherited | `LEADV2_TRACE=1`, `LEADV2_TRACE_ID` non-empty | spans append to `<trace-dir>/<trace_id>.ndjson` | one file joins lane + children |
| S2 | enabled, id derivable | `LEADV2_TRACE=1`, no id, but a `--task`/sig8 is in argv | derive `dispatch-<sig8>`, **export** it | children join the same file |
| S3 | enabled, no id derivable | `LEADV2_TRACE=1`, hook/timer path | id = `ambient-<YYYYMMDD>`; records get `"ambient":true` | timer noise lands in one dated file, never mixed into a lane total |
| S4 | enabled, sink unresolvable | `leadv2-state-path.sh` rc≠0 (e.g. its `exit 3`, `LINK_ROOT="/"`, non-writable parent) | trace disables itself for this process, one stderr line, **rc of the host script unchanged** | founder sees `[trace] disabled: sink unresolvable`; the lane runs exactly as before |
| S5 | enabled, clock unavailable | no `perl` and no `python3` | as S4 | same |
| S6 | enabled, sink write fails | disk full / EACCES on append | span dropped, counter `dropped` incremented, one stderr line at process end | a gap in the NDJSON; the lane still completes |
| S7 | enabled, process killed (SIGKILL / `exec`) | see §2.3 | begin record present, end record absent | reader shows the span as `unterminated`, never as duration 0 |

### 2.2 Return codes of the mechanism, and what each caller does with them

**The mechanism returns nothing that any caller branches on.** That is the core invariant, and
it is a design constraint, not an accident: mission off-limits says *"Do not change any
existing control flow, exit code, or output format."*

| rc surface | value | caller reaction | traced to terminal outcome |
|---|---|---|---|
| `lv2_trace_begin` | always `0` | none — called as a statement | n/a |
| `lv2_trace_end` | always `0` | none | n/a |
| `lv2_trace_arm_exit` | always `0` | none | n/a |
| host script exit code | **unchanged** | preserved bit-for-bit by the chained EXIT trap (§3.5) which saves `$?` first and re-exits with it | a dispatch that returned 2 still returns 2; the router's exit-2 refusal contract (`codex-task.sh:1387` `_codex_quota_gate`, refuses with exit 2) is untouched |
| `leadv2-state-path.sh` rc 3 | consumed internally | trace self-disables (S4) | founder's lane is unaffected — **this is the "over-cap input must not take down more than its own operation" rule applied to the instrument itself** |

Every trace function is written to end with `return 0` and every internal command is
`|| true`-guarded, because five of the nine targets run under `set -e`-family options
(`leadv2-lanes-snapshot.sh:60` `set -euo pipefail`), where a non-zero return from an
instrumentation line would abort the host script mid-lane. In plain words, without that rule
**turning the trace on would kill lanes**, which is the exact opposite of an instrument.

### 2.3 Terminal outcomes traced to the end — the three ways a span never closes

1. **`exec` replaces the process.** Verified sites: `leadv2-dispatch-code.sh:5578`
   (`reconcile) ... exec bash "${LEDGER_BIN}" reconcile "$@"`), `glm-coder.sh:547`
   (`setsid_wrapper() { exec python3 -c ... }`), plus 2 in `kimi-coder.sh` and 2 in
   `leadv2-lanes-snapshot.sh`. **`exec` does not fire EXIT traps.** The begin record exists,
   the end record never will.
   *User-visible consequence:* the rollup would show the lane's `reconcile` path as running
   forever. **Mitigation:** the reader (§4) classifies a begin without an end as
   `unterminated` and reports the count separately; it never imputes a duration. A silent
   0 ms would be a lie about the exact code path the audit most wants to measure.
2. **SIGKILL / process-group kill.** `glm-coder.sh` documents `kill -TERM -$child_pid`
   watchdog kills at `:535-545`. Same outcome as (1), same handling.
3. **`trap 'exit 130' INT TERM`** at `leadv2-dispatch-code.sh:2495` — this one *does* reach
   EXIT, so a Ctrl-C'd lane closes its span with `exit_code:130`. Good: cancelled lanes stay
   visible and distinguishable from crashed ones.

---

## 3. DESIGN

### 3.1 New file: `plugins/leadv2/scripts/lib/leadv2-trace.sh`

Placement follows the existing `plugins/leadv2/scripts/lib/` convention (peer of
`lib/leadv2-glm-policy-resolve.py`).

**Load protocol — one line, added once per instrumented script, right after `SCRIPT_DIR=`:**

```bash
if [[ "${LEADV2_TRACE:-0}" == "1" ]]; then . "${SCRIPT_DIR}/lib/leadv2-trace.sh"
else lv2_trace_begin() { :; }; lv2_trace_end() { :; }; lv2_trace_arm_exit() { :; }; fi
```

Off-path cost, exactly: **one string comparison + three function definitions per process**
(all in-process; no fork, no file open, no `stat`), and **one no-op function call per span**.
Strictly cheaper than the mission's "one env test per span" budget. The lib file is not even
opened when the trace is off.

### 3.2 Public API (3 functions, that is the whole surface)

| function | args | effect | returns |
|---|---|---|---|
| `lv2_trace_begin <span_name>` | short stable name | reads monotonic clock, pushes onto an in-process stack, lazily resolves sink + id on first call | `0` always |
| `lv2_trace_end [<exit_code>]` | defaults to `$?` captured by caller | reads monotonic clock, pops, writes one NDJSON line | `0` always |
| `lv2_trace_arm_exit <span_name>` | short stable name | `lv2_trace_begin` + install a **chained** EXIT trap that closes the span preserving `$?` | `0` always |

### 3.3 Trace id derivation and propagation

- Source of truth is the existing lane id — **no new registry**, per mission §1. Format
  `dispatch-<sig8>`, which is already the handoff directory name
  (`leadv2-dispatch-code.sh:219,222`: `docs/handoff/dispatch-<sig8>/`).
- Resolution order: `$LEADV2_TRACE_ID` → `--task` / `--task-id` value in argv → `ambient-<UTC date>`.
- On resolution the lib does `export LEADV2_TRACE_ID` so children inherit across `bash`,
  `exec`, `nohup`, and `setsid_wrapper` (`glm-coder.sh:547`) boundaries. Export is the only
  propagation mechanism that survives `os.execvp` in that wrapper.
- **Validation before use** (this is a filename component): `[[ "$id" =~ ^[A-Za-z0-9._-]{1,64}$ ]]`
  or the trace self-disables (S4). A `/` or `..` in an inherited env var would otherwise let a
  trace id write outside the sink.

### 3.4 Record schema (one JSON object per line)

| field | type | source | null when |
|---|---|---|---|
| `trace_id` | string | §3.3 | never |
| `span` | string | literal at call site | never |
| `script` | string | `${BASH_SOURCE[0]##*/}` | never |
| `pid` | int | `$$` | never |
| `ppid` | int | `$PPID` | never |
| `parent_span` | string\|null | enclosing stack entry | top-level span |
| `t_start_ns` | int | monotonic (D1) | never |
| `t_end_ns` | int | monotonic (D1) | never |
| `duration_ms` | number | `(t_end_ns - t_start_ns)/1e6` | never |
| `exit_code` | int | `$?` at close | never |
| `child_exec_count` | int\|null | best-effort in-process counter | `null` when the script does not increment it |
| `clock_source` | `"monotonic_perl"`\|`"monotonic_python"` | D1 | never |
| `instrument_ns` | int | measured cost of the two boundary forks (D2) | never |
| `ambient` | bool | S3 | never |
| `wall_iso` | string | `date -u +%FT%TZ` — **extra field, never the timing source** | never |

**Atomicity:** each record is composed fully in a shell variable, then emitted with a single
`printf '%s\n' "$rec" >> "$sink"` where `$sink` is opened O_APPEND by the redirect. Records are
capped at 512 bytes by construction (span names ≤ 40 chars, no free text, no paths), which is
far under `PIPE_BUF`/`getconf` atomic-write size on darwin and Linux, so **two concurrent lanes
cannot interleave a record**. If a composed record exceeds 512 bytes it is dropped with a
counter increment rather than written truncated — a half-record would silently corrupt every
downstream percentile.

### 3.5 The chained EXIT trap (the mechanism's hardest part)

```bash
lv2_trace_arm_exit() {
  lv2_trace_begin "$1"
  local prev; prev="$(trap -p EXIT)"           # e.g.  trap -- 'cleanup_pending_dispatch' EXIT
  prev="${prev#trap -- \'}"; prev="${prev%\' EXIT}"
  _LV2_PREV_EXIT_TRAP="$prev"
  trap '_lv2_rc=$?; lv2_trace_end "$_lv2_rc"; [[ -n "${_LV2_PREV_EXIT_TRAP:-}" ]] && eval "$_LV2_PREV_EXIT_TRAP"; exit "$_lv2_rc"' EXIT
}
```

Three properties this must have, each of which is a test in §7:
1. **`$?` is captured first and re-exited last** — the host's exit code is bit-identical.
2. **The previous handler still runs** — `cleanup_pending_dispatch` is not lost.
3. **Ordering constraint:** `lv2_trace_arm_exit` must be called *after* the host's own
   `trap ... EXIT`. For `leadv2-dispatch-code.sh` that means **after line 2495**, not at the
   top. Placing it earlier silently produces the phantom-lane bug of §1.2.

**Scripts that may NOT use `arm_exit`**, because they install an EXIT trap at runtime from
inside a function and would clobber it regardless of order: `leadv2-backlog-pump.sh:544`,
`codex-task.sh:471`, `codex-task.sh:1255`. These use explicit begin/end (§3.6).

### 3.6 Instrumentation points — span name, file, anchor line, strategy

| # | span name | file | anchor | strategy |
|---|---|---|---|---|
| 1 | `lane` | `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | insert after `:2495` (`trap 'exit 130' INT TERM`) | `lv2_trace_arm_exit lane` — the only strategy that survives 96 `exit`s |
| 2 | `lane.resolve` | same | `cmd_resolve()` at `:4309`, first line of body / `lv2_trace_end` before each `return` | explicit begin/end (nested under `lane`) |
| 3 | `route` | `plugins/leadv2/scripts/leadv2-router.sh` | after `:95` (`trap 'rm -f "$PY_HELPER"' EXIT`) | `lv2_trace_arm_exit route` |
| 4 | `review` | `plugins/leadv2/scripts/leadv2-review-run.sh` | after `:44` (arg init; no pre-existing EXIT trap) | `lv2_trace_arm_exit review` |
| 5 | `status.collect` | `plugins/leadv2/scripts/leadv2-status-collector.sh` | after `:47` (`trap '_ec=$?; rm -rf ...' EXIT`) | `lv2_trace_arm_exit status.collect`. **Must preserve `$?`** — this trap already carries the collector's exit code |
| 6 | `lanes.snapshot` | `plugins/leadv2/scripts/leadv2-lanes-snapshot.sh` | after `:92` (`PROJECT_ROOT=""`) | `lv2_trace_arm_exit lanes.snapshot`. Runs under `set -euo pipefail` (`:60`) → every trace line must be `|| true` safe |
| 7 | `pump` | `plugins/leadv2/scripts/leadv2-backlog-pump.sh` | `:965` (`MODE="${1:-check}"`) begin; end at each `case` arm terminus (`:~975-984`) | explicit begin/end — **cannot** use `arm_exit` (runtime trap at `:544`) |
| 8 | `provider.glm` | `plugins/leadv2/scripts/glm-coder.sh` | around `cmd_run` / `cmd_bg` invocation inside `main()` `:1737-1742` | explicit begin/end. Not whole-script: mission says span = the provider call |
| 9 | `provider.kimi` | `plugins/leadv2/scripts/kimi-coder.sh` | around `cmd_run` / `cmd_bg` inside `main()` `:1767-1772` | explicit begin/end |
| 10 | `provider.codex` | `plugins/leadv2/scripts/codex-task.sh` | around `_run_with_fallback` (def `:1700`; call site in the tail block near `:1387+`) | explicit begin/end — **cannot** use `arm_exit` (runtime traps at `:471`, `:1255`) |

Ten spans across nine files. `lane.resolve` is the one span beyond the mission's literal list;
it is inside a file already on the list and is what makes the lane total decomposable at all —
without it `lane` is an opaque bar and the audit's original question stays unanswered.

### 3.7 Sink

```
sink_dir  = $(bash leadv2-state-path.sh --no-link traces)      # ~/.claude/leadv2-state/<slug>/traces
sink_file = ${sink_dir}/${trace_id}.ndjson
```

`--no-link` is mandatory (§1.4). Resolved **once per process**, cached in a variable — not once
per span. `traces` is a new name and is deliberately **not** added to the `STANDARD` set at
`leadv2-state-path.sh:244`, because that set drives worktree symlink creation and a trace must
have zero worktree side effects. `leadv2-state-path.sh` is therefore **read-only in this
mission — not modified.**

---

## 4. THE READER: `plugins/leadv2/scripts/leadv2-trace-report.sh`

```
leadv2-trace-report.sh [<trace-dir-or-file>]
```
Default target: `$(leadv2-state-path.sh --no-link traces)`. Python3 core (same idiom as
`leadv2-status-collector.sh`'s embedded python). Output, plain text:

1. per span name: `count  p50_ms  p95_ms  max_ms  unterminated  instrument_ms_total`
2. per trace_id: total wall span of the `lane` span, and the sum of child spans
3. a footer naming spans whose `p50_ms < 10 × instrument_ms` — **"measurement below
   instrument noise floor; do not draw conclusions"** (D2)
4. `--json` for machine use

Percentiles are nearest-rank on the sorted `duration_ms` list; with `count < 5` it prints the
raw values instead of a fabricated p95. A p95 from three samples is not a p95.

---

## 5. CONFIGURATION BOUNDARIES

Every input the mechanism reads, at every boundary. Rule applied throughout: **a malformed
input disables the trace, never the lane.**

### `LEADV2_TRACE` (env)
| boundary | value | behaviour |
|---|---|---|
| absent | unset | S0, off. Lib not sourced. Zero files. |
| empty | `""` | S0, off (`${LEADV2_TRACE:-0}` → `""` ≠ `1`) |
| minimum/on | `1` | S1–S3 |
| other | `0`, `true`, `yes`, `TRUE` | **off.** Only the exact string `1` enables. Documented; a `true` that silently means off is worse than a `true` that loudly means off, so the reader prints `[trace] LEADV2_TRACE="true" is not "1" — trace is OFF` once, to stderr, from the reader script only (never from a lane). |
| over-cap | 4 KB of junk | off; single `==` comparison, no cost |

### `LEADV2_TRACE_ID` (env)
| boundary | value | behaviour |
|---|---|---|
| absent | unset | derive from argv, else `ambient-<date>` |
| empty | `""` | same as absent |
| minimum | `a` | accepted (1 char, passes charset) |
| maximum | 64 chars | accepted |
| over-cap | 65+ chars | **rejected → trace self-disables (S4).** Truncating would silently merge two traces into one file and corrupt every percentile — worse than no data |
| malformed | `../../etc/x`, `a/b`, `$(rm -rf /)`, embedded newline | rejected by the charset regex → S4. This is the path-traversal / injection boundary; it is closed before any filename is built |

### `LEADV2_TRACE_DIR` (env, optional test override)
| boundary | behaviour |
|---|---|
| absent | resolve via `leadv2-state-path.sh --no-link traces` |
| empty | same as absent |
| set, non-existent | `mkdir -p` once; failure → S4 |
| set, not writable | S4, one stderr line, lane unaffected |
| set to `/` | rejected → S4 (mirrors `leadv2-state-path.sh:98-103`'s own `LINK_ROOT="/"` refusal, which exits 3) |

### Sink file
| boundary | behaviour |
|---|---|
| absent | created on first append by the `>>` redirect |
| empty (0 bytes) | valid — reader reports zero spans |
| exists, another writer mid-append | fine: O_APPEND + sub-PIPE_BUF single write |
| exists, malformed line (partial write from a `kill -9` mid-write on some filesystem) | **reader skips the line and counts it as `malformed_lines: N`** in the footer. It never aborts — a report that dies on one bad line is a report the founder stops running |
| over-cap: file > 100 MB | reader streams line-by-line (never `read()` whole); writer does not rotate. Documented: `rm` the file. Auto-rotation is out of scope (§8) |
| directory missing at write time (someone `rm -rf`'d the state dir mid-lane) | append fails → S6, span dropped, counter incremented, lane unaffected |

### Clock binary
| boundary | behaviour |
|---|---|
| `perl` present | `clock_source: monotonic_perl` (~9 ms/read, measured) |
| `perl` absent, `python3` present | `clock_source: monotonic_python` (~30 ms/read, measured) |
| both absent | S5 → trace self-disables, one stderr line |
| present but returns garbage (non-numeric) | numeric guard `[[ "$v" =~ ^[0-9]+$ ]]`; failure → S5 |

### `leadv2-state-path.sh`
| boundary | behaviour |
|---|---|
| present, rc 0 | normal |
| its `exit 3` (no repo + `LINK_ROOT=/`, or unwritable parent — `:98-110`) | S4 |
| absent / not executable | S4 |
| slow | called once per process, not per span |

---

## 6. COUNTEREXAMPLE

*After every item in this mission is implemented as specified, what can still violate the
invariant the mechanism exists to protect — "the trace attributes lane wall-clock truthfully,
and costs nothing when off"?*

Four things, and they are not hypothetical. **First**, the trace covers ten spans in nine
files, but a lane's wall-clock also passes through `claude-subsession.sh`,
`leadv2-fanout.sh`, `leadv2-plan-run.sh`, `leadv2-worktree-cleanup.sh`, and the review fanout's
subagent processes — none instrumented this round, by the mission's own §5 "no more". So
`lane` minus the sum of children will be a large unattributed residual, and a reader who takes
that residual for "overhead" will be wrong; it is mostly un-instrumented work. The reader
therefore labels it `unattributed_ms`, never `overhead_ms`. **Second**, `exec` and SIGKILL
(six verified `exec` sites, plus `glm-coder.sh`'s documented `kill -TERM -$pgid` watchdog)
produce spans that never close; the count of these is reported, but the *duration* of that
work is permanently unmeasurable with an in-process instrument — and `reconcile`
(`leadv2-dispatch-code.sh:5578`, `exec bash`) is exactly such a path. **Third**, the
instrument's own ~18 ms/span is 14% of a `--help`-class run (measured 129 ms), so any span
under ~200 ms is noise, and `status.collect` and `route` may well be in that class — the p50/p95
for them will be dominated by instrument cost, which is why `instrument_ns` is a per-record
field and why the reader prints an explicit noise-floor footer rather than letting the founder
read a clean-looking number that is mostly the ruler. **Fourth and most likely to bite:** the
trace id is a lane id, but the *same* provider launcher is invoked from at least three
independent parents (`leadv2-dispatch-code.sh`, `leadv2-review-run.sh`, `codex-task.sh` — all
verified by grep), so `provider.glm` records under one trace id can mix a lane's coding call
with that lane's review call; `parent_span` + `ppid` make them separable, but only if the
reader groups on them, and a naive `jq` one-liner over `span=="provider.glm"` will silently sum
two different activities. That is the trap I would expect a first week of data to fall into.

What I checked to say this: the caller sets in §1.3 (grep over `plugins/leadv2` for each target
name), the `exec`/`exit` counts in §1.1, the existing EXIT traps in §1.2, and the two timing
measurements in §0.2/D2. What I did **not** check: whether `claude-subsession.sh` re-execs in a
way that drops exported env (which would break trace-id inheritance into subagents) — that is
the first thing the implementer should probe, and if it does drop env, span 8/9/10 will show up
under `ambient` instead of the lane, which would quietly halve the trace's value.

---

## 7. TESTS (mission §7, expanded to cover what §1.2 found)

New: `plugins/leadv2/scripts/tests/test-leadv2-trace.sh`

| # | test | asserts |
|---|---|---|
| T1 | writer schema | every emitted line is valid JSON with all 14 fields; `duration_ms == (t_end_ns-t_start_ns)/1e6` |
| T2 | append under concurrency | 20 concurrent writers × 50 spans → exactly 1000 lines, **zero malformed**, all parseable |
| T3 | **off ⇒ zero files** | `unset LEADV2_TRACE; LEADV2_DISPATCH_SPAWN=0 leadv2-dispatch-code.sh …` → `traces/` dir does not exist / is unchanged (mission §7, literal) |
| T4 | **exit code preserved** | a stub host that `exit 7`s under `arm_exit` still exits 7 |
| T5 | **prior EXIT trap still runs** | stub with `trap 'echo PRIOR' EXIT` + `arm_exit` → `PRIOR` printed **and** span written |
| T6 | `set -euo pipefail` safety | host with `set -euo pipefail` and an unresolvable sink completes normally (exit 0), trace self-disabled |
| T7 | malformed trace id | `LEADV2_TRACE_ID='../../x'` → no file outside sink, trace disabled, host rc unchanged |
| T8 | id inheritance | parent exports id; child `bash` sees it; both append to one file |
| T9 | unterminated span | begin then `kill -9` → reader reports `unterminated: 1`, not `duration 0` |
| T10 | reader on malformed line | append `{garbage` → reader still prints percentiles, footer shows `malformed_lines: 1` |
| T11 | `bash -n` | all 11 touched/created files parse |

---

## 8. EXPLICIT NON-GOALS

- **No optimisation of anything.** The mission is the instrument; the audit's refactor
  decisions come later, from the data.
- No refactor, extraction, or Python rewrite of any existing block (mission off-limits).
- No change to any existing control flow, exit code, stdout, or stderr format.
- Trace stays OFF by default. No default flip, no auto-enable heuristic.
- No modification to `leadv2-state-path.sh` (read-only consumer; `traces` deliberately not in
  its `STANDARD` set, §3.7).
- No log rotation, retention policy, or compaction for trace files.
- No instrumentation of `claude-subsession.sh`, `leadv2-fanout.sh`, `leadv2-plan-run.sh`, or
  the review-fanout subagents this round (mission §5 "no more") — named in §6 as the source of
  `unattributed_ms`.
- No sampling, no trace-id registry, no OpenTelemetry/Jaeger export.
- No real copies of plugin files in project repos (global rule; edits land once in
  `~/Projects/leadv2`).

---

## 9. ACCEPTANCE

```yaml
acceptance:
  authored_at: 2026-08-23T02:32:39Z
  criteria:
    - surface: file_artifact
      observable: >
        After the founder runs one dispatch with the trace switched on, a single
        file named after that lane exists in the state directory, and opening it
        shows one line per traced step -- a line for the lane itself, one for each
        helper it ran, and one for the provider call -- each line carrying how many
        milliseconds that step took and how it finished.
    - surface: file_artifact
      observable: >
        After the founder runs the same dispatch with the trace switched off, the
        traces directory is still absent -- there is no new file anywhere for that run.
    - surface: rendered_line
      observable: >
        Running the report on a directory of collected traces prints, for each named
        step, how many times it ran and its typical and near-worst durations, plus a
        per-lane total; steps whose typical duration is too small to distinguish from
        the measuring cost are called out underneath as not trustworthy.
    - surface: rendered_line
      observable: >
        A lane that the founder cancels with Ctrl-C still shows up in the report as a
        finished-but-cancelled lane with a real duration, not as a missing or
        zero-length one.
    - surface: log_line
      observable: >
        When the trace cannot find somewhere to write, the founder sees one line
        saying the trace turned itself off, and the lane finishes exactly as it would
        have with the trace never switched on -- same result, same reported outcome.
```

**Founder-facing commands** (to appear verbatim in the mission report):

```bash
# enable for one dispatch
LEADV2_TRACE=1 bash plugins/leadv2/scripts/leadv2-dispatch-code.sh <args>

# read the rollup
bash plugins/leadv2/scripts/leadv2-trace-report.sh
```

---

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-trace.sh, plugins/leadv2/scripts/leadv2-trace-report.sh, plugins/leadv2/scripts/tests/test-leadv2-trace.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/leadv2-router.sh, plugins/leadv2/scripts/leadv2-review-run.sh, plugins/leadv2/scripts/leadv2-status-collector.sh, plugins/leadv2/scripts/leadv2-lanes-snapshot.sh, plugins/leadv2/scripts/leadv2-backlog-pump.sh, plugins/leadv2/scripts/glm-coder.sh, plugins/leadv2/scripts/kimi-coder.sh, plugins/leadv2/scripts/codex-task.sh

DELIVERABLE_COMPLETE
