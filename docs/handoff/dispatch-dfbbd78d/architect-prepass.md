# Mission B round 2 — architect prepass (mechanism-closed design)

Task: `dispatch-dfbbd78d-architect` · role: architect · authored 2026-08-23.
Scope: design the test suite for the round-1 trace instrument, plus the minimal
product fixes the tests will expose. **No implementation here.**

---

## 0. Two places where discovery contradicts the mission's framing

The mission is the reason to look; it is not the boundary of what is true. Two of its
stated premises are false on the tree, and both change what the implementer must do.

### 0.1 `.claude/worktrees/f72c8c9c` is NOT the lane worktree. It is a stale scaffold.

The mission says "Continue in the EXISTING lane worktree `.claude/worktrees/f72c8c9c`."
That directory is not a registered git worktree, and round 1's work is not in it.

```
$ git worktree list
/Users/kostiantyn.vlasenko/Projects/leadv2                            61b2fd3 [lane/dispatch-f72c8c9c]
/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/273da7e9 a726c16 [worktree-273da7e9]
...   (f72c8c9c is NOT in this list)
```

The **main checkout is itself on branch `lane/dispatch-f72c8c9c` at 61b2fd3** — that is
where round 1 landed. The `f72c8c9c` directory contains only:

```
$ find .claude/worktrees/f72c8c9c -maxdepth 4 -not -path '*/docs/*'
.claude/worktrees/f72c8c9c/plugins/leadv2/scripts/lib      <- only leadv2-trace.sh
.claude/worktrees/f72c8c9c/.claude/scripts/lv2
$ ls .claude/worktrees/f72c8c9c/plugins/leadv2/scripts/
lib
```

No `tests/`, no `run-core-offline.sh`, no `leadv2-trace-report.sh`. And the one file it
does hold is a **stale, different** copy of the instrument:

| path | bytes | lines |
|---|---|---|
| `.claude/worktrees/f72c8c9c/plugins/leadv2/scripts/lib/leadv2-trace.sh` | 6215 | 162 |
| `plugins/leadv2/scripts/lib/leadv2-trace.sh` (main, = HEAD) | 7206 | 198 |

The stale copy has a *different API surface* (`_LV2_TRACE_DISABLED`, `LEADV2_TRACE_DIR`
honoured, `_LV2_TRACE_STACK` as a string, no drain loop). A worker that obeys the mission
literally would author its whole suite against a file that is not the shipped instrument,
pass every assertion, and prove nothing.

**Design decision D0: work in the main checkout `~/Projects/leadv2` (already on
`lane/dispatch-f72c8c9c`). Do not `cd` into `.claude/worktrees/f72c8c9c`, do not read
from it, and do not delete it** (deleting is out of scope and the mission forbids
`clean`). If any tooling insists on a lane root, it is the repo root.

### 0.2 "All nine declared seams are instrumented" is true of the call sites and false of the behaviour

Four of the nine seams can never write a span. See Defect A (§4.1). The mission's item 3
("OFF costs nothing") is therefore only half the load-bearing question — the other half is
that ON currently costs nothing either, for four seams.

---

## 1. CALLERS / CALLEES — every seam, with file:line

### 1.1 The mechanism under test

`plugins/leadv2/scripts/lib/leadv2-trace.sh` (198 lines, HEAD 61b2fd3).

Public API → internal callees:

| function | line | calls |
|---|---|---|
| `lv2_trace_begin` | 116 | `_lv2_trace_init` (118), `_lv2_trace_now_ns` (121) |
| `lv2_trace_end` | 127 | `_lv2_trace_now_ns` (140, 142), `awk` (146), `basename` (149), `date` (157), `printf >> sink` (163) |
| `lv2_trace_arm_exit` | 179 | `lv2_trace_begin` (181), `trap -p EXIT` (183), installs EXIT trap (196) |
| `_lv2_trace_init` | 107 | `_lv2_trace_resolve_id` (110), `_lv2_trace_resolve_clock` (110), `_lv2_trace_resolve_sink` (110) |
| `_lv2_trace_resolve_id` | 25 | `date -u +%Y%m%d` (42) on the ambient path, `_lv2_trace_id_valid` (47) |
| `_lv2_trace_resolve_clock` | 56 | `command -v perl` (57), `command -v python3` (61) |
| `_lv2_trace_now_ns` | 69 | `perl` (73) **or** `python3` (75) — one fork+exec per call |
| `_lv2_trace_resolve_sink` | 86 | `"$bin" --no-link traces` (94), `mkdir -p` (99) |

External command budget per closed span (ON path): 2 × clock (`perl`/`python3`) + `awk` +
`basename` + `date` = **5 forks per span**, plus 1 `leadv2-state-path.sh` + 1 `mkdir` +
2 `command -v` once per process. The report must state this; it is the honest ON cost and
the mission asks the OFF cost be proven against it.

### 1.2 The nine call sites (callers of the API), all verified by grep at HEAD

| # | file:line | span | form | `SCRIPT_DIR` defined in that file? |
|---|---|---|---|---|
| 1 | `leadv2-dispatch-code.sh:2498` | `lane` | `lv2_trace_arm_exit "lane" "$@"` | yes (`:412`) |
| 2 | `leadv2-dispatch-code.sh:4316` | `lane.resolve` | `lv2_trace_begin` (nested inside `lane`) | yes |
| 3 | `leadv2-review-run.sh:69` | `review` | `lv2_trace_arm_exit "review"` | yes (`:30`) |
| 4 | `leadv2-router.sh:98` | `route` | `lv2_trace_arm_exit "route" --task-id "$TASK_ID"` | yes |
| 5 | `leadv2-lanes-snapshot.sh:95` | `lanes.snapshot` | `lv2_trace_arm_exit ... \|\| true` | yes |
| 6 | `leadv2-backlog-pump.sh:968/985/990` | `pump` | explicit `begin`/`end` pair, no arm | yes |
| 7 | `leadv2-status-collector.sh:50` | `status.collect` | `lv2_trace_arm_exit` | **no** |
| 8 | `codex-task.sh:1703/1749` | `provider.codex` | `begin`/`end` pair | **no** (uses `_CODEX_SCRIPT_DIR`) |
| 9 | `glm-coder.sh:1743-1758`, `kimi-coder.sh:1771-1786` | `provider.glm` / `provider.kimi` | `begin`/`end`, **two branch copies each** | **no** (`_GLM_SCRIPT_DIR` / `_KIMI_SCRIPT_DIR`) |

**The independent copy nobody named:** `glm-coder.sh` and `kimi-coder.sh` each open the
`provider.*` span in **two separate branches** (1743 and 1753; 1771 and 1781). A fix or a
test that touches only the first branch covers half the path. Same shape in both files —
they are siblings, and a fix to one that is not applied to the other is the classic miss.

The load-protocol stanza is byte-identical at all nine files (verified at
`leadv2-review-run.sh:31-32`, `glm-coder.sh:60-61`, `codex-task.sh:119-120`,
`leadv2-dispatch-code.sh:413-414`):

```bash
if [[ "${LEADV2_TRACE:-0}" == "1" ]]; then . "${<DIR>}/lib/leadv2-trace.sh"
else lv2_trace_begin() { :; }; lv2_trace_end() { :; }; lv2_trace_arm_exit() { :; }; fi
```

### 1.3 Callers of the reader

`plugins/leadv2/scripts/leadv2-trace-report.sh` has **zero callers** in the tree
(`grep -rn trace-report --include='*.sh'` → only itself). It is an operator CLI. Its only
callee is `python3` with a heredoc, and `leadv2-state-path.sh --no-link traces` when no
target argument is given (`:24`).

---

## 2. STATES AND RETURN CODES

Every public entry point returns 0 unconditionally by design (`lib:9-10`). The interesting
axis is therefore not the rc but **what got written and whether the host survived**.

### 2.1 Writer states

| # | state | reached when | what is written | rc | what the caller does with it | user-visible consequence |
|---|---|---|---|---|---|---|
| W1 | unsourced (OFF) | `LEADV2_TRACE` unset/≠1 | nothing; `:` stub runs | 0 | continues | no trace file exists; lane behaves exactly as before |
| W2 | ready | id+clock+sink all resolve | one NDJSON line per closed span | 0 | continues | `leadv2-trace-report.sh` shows rows for that span |
| W3 | id rejected | id fails `^[A-Za-z0-9._-]{1,64}$` (`:19`) | nothing; `[trace] disabled: ...` on **stderr** | 0 | continues | **the lane's stderr/log gains a `[trace] disabled` line; no spans for the whole process** |
| W4 | no clock | neither `perl` nor `python3` on PATH (`:65`) | nothing; stderr note | 0 | continues | same as W3 |
| W5 | sink unresolvable | `leadv2-state-path.sh` missing/not executable (`:89`) **or** returns empty **or** dir not writable (`:99-100`) | nothing; stderr note | 0 | continues | **this is where seams 7/8/9 land today — see Defect A. Silently no `provider.*` / `status.collect` rows ever appear in any report** |
| W6 | clock dies mid-span, in `begin` | `_lv2_trace_now_ns` fails at `:121` | nothing; **no push** | 0 | continues | that span is simply absent from the report |
| W7 | clock dies mid-span, in `end` | `_lv2_trace_now_ns` fails at `:140` | nothing; **the stack is NOT popped** | 0 | continues | benign for an explicit `begin`/`end` pair; **fatal under `arm_exit` — see Defect B: the host script never exits** |
| W8 | record over 512 B | `${#rec} > 512` (`:159`) | nothing; `[trace] dropped: record exceeds 512 bytes` | 0 | continues | one span silently missing; the operator sees a `dropped` line on stderr |
| W9 | append fails | sink deleted/read-only after resolve (`:163`) | nothing; `[trace] dropped: append failed` | 0 | continues | spans stop appearing part-way through a lane; totals under-report |
| W10 | `end` with empty stack | `lv2_trace_end` called unpaired (`:131`) | nothing | 0 | continues | no row; no error — an unbalanced instrumentation bug is invisible |
| W11 | ambient id | no `--task`/`--task-id` and no `LEADV2_TRACE_ID` (`:41-43`) | rows with `"ambient":true`, sink `ambient-YYYYMMDD.ndjson` | 0 | continues | every un-tasked run of every script that day shares one file; the report's per-trace "lane total" row for `ambient-*` is a mixture, not one lane |

### 2.2 Reader states and rcs

| # | state | rc | what a human sees |
|---|---|---|---|
| R1 | target dir with ≥1 `*.ndjson` | 0 | the span table + per-trace lane totals |
| R2 | no target arg and `leadv2-state-path.sh` unresolvable → `TARGET` empty | **1** (`:29`) | `[trace-report] no trace data found at '<unresolved>'` on stderr, no table |
| R3 | target path does not exist | **1** | same message with the path |
| R4 | dir exists, zero `.ndjson` | **0** with `set -e` surviving (python prints empty tables) | header rows and nothing under them — "the report ran and found nothing", distinguishable from R2/R3 |
| R5 | a line is not JSON, or `duration_ms` non-numeric | 0 | `malformed_lines: N (skipped, not fatal)` footer |
| R6 | file unreadable (`OSError`, `:39-40`) | 0 | that file is **silently skipped** — no counter, no footer. A permissions problem reads as "no data" |
| R7 | `n < 5` samples for a span | 0 | `p50`/`p95` are both the **max**, with a ` (raw)` suffix — see §3.4; the arithmetic is deliberately not a percentile |
| R8 | python3 absent | **127**, `set -euo pipefail` propagates | shell reports `python3: command not found`; no report |

Terminal tracing: **no rc from the writer ever reaches a retry loop or a gate.** All nine
seams either ignore it or `\|\| true`. The writer cannot fail a lane — except through
Defect B, which is not an rc at all but a hang.

---

## 3. CONFIGURATION BOUNDARIES

Every input the mechanism reads, with behaviour at absent / empty / minimum / over-cap /
malformed.

### 3.1 `LEADV2_TRACE` (env, the master switch)

| case | value | behaviour |
|---|---|---|
| absent | unset | OFF via `:-0` default. Stubs defined. |
| empty | `""` | OFF (`"" != "1"`). |
| minimum ON | `1` | sourced. |
| over-cap / other | `2`, `true`, `yes`, `on` | **OFF.** Only the literal `1` enables. An operator who exports `LEADV2_TRACE=true` gets silence with no diagnostic. Test must pin this so it is a documented contract, not an accident. |
| malformed | `1 ` (trailing space) | OFF. |

### 3.2 `LEADV2_TRACE_ID` (env) / `--task` / `--task-id` (argv)

| case | behaviour |
|---|---|
| absent (both) | ambient id `ambient-$(date -u +%Y%m%d)` → W11 |
| empty string | treated as absent → ambient |
| minimum | 1 char, e.g. `a` → accepted |
| maximum | 64 chars → accepted; **65 chars → W3, trace disabled process-wide** |
| malformed | `../../etc/passwd`, `a b`, `a/b`, UTF-8 → W3. The charset check is the path-traversal guard for the sink filename; **it must stay a whitelist.** A test must assert the traversal case explicitly, not just "some bad string". |
| argv form | `--task=X` and `--task X` both parsed (`:31-36`); `--task-id=X` / `--task-id X` likewise |
| conflict | env wins over argv (`:26` short-circuits) |

**Blast radius check (mission's rule: an over-cap input must not take down more than its own
operation).** A 65-char task id disables the trace for the whole process, which is correct
— it does not touch the lane. PASS. But note it prints to **stderr**, which several lanes
capture into the worker log the review gate reads. That is noise, not a defect.

### 3.3 `LEADV2_STATE_PATH_BIN` / `SCRIPT_DIR` (sink resolution, `lib:87-88`)

```bash
local bin="${LEADV2_STATE_PATH_BIN:-${SCRIPT_DIR:-.}/leadv2-state-path.sh}"
[[ -x "$bin" ]] || bin="$(command -v leadv2-state-path.sh 2>/dev/null || true)"
```

| case | behaviour |
|---|---|
| `LEADV2_STATE_PATH_BIN` set and executable | used |
| set but not executable | falls through to `command -v` → almost always empty → W5 |
| absent, `SCRIPT_DIR` set (seams 1-6) | correct path, works |
| **absent, `SCRIPT_DIR` unset (seams 7,8,9)** | `./leadv2-state-path.sh` **relative to CWD** → not executable in any real run → `command -v` → not on PATH → **W5, permanent silence.** Defect A. |
| resolves but returns empty | W5 |
| dir not creatable / not writable | W5 |

Verified absence of `SCRIPT_DIR`:

```
$ for f in glm-coder.sh kimi-coder.sh codex-task.sh leadv2-status-collector.sh \
           leadv2-router.sh leadv2-lanes-snapshot.sh leadv2-backlog-pump.sh; do ... done
glm-coder.sh                 SCRIPT_DIR=0 LEADV2_STATE_PATH_BIN=0
kimi-coder.sh                SCRIPT_DIR=0 LEADV2_STATE_PATH_BIN=0
codex-task.sh                SCRIPT_DIR=0 LEADV2_STATE_PATH_BIN=0
leadv2-status-collector.sh   SCRIPT_DIR=0 LEADV2_STATE_PATH_BIN=0
leadv2-router.sh             SCRIPT_DIR=1 ...
leadv2-lanes-snapshot.sh     SCRIPT_DIR=1 ...
leadv2-backlog-pump.sh       SCRIPT_DIR=1 ...
$ grep -rn "export LEADV2_STATE_PATH_BIN" --include='*.sh' .
tests/test-landed-at-spawn.sh:99 ...        (tests only — no production export)
```

Also note: `SCRIPT_DIR` is a **global name the host may already own**. In
`leadv2-dispatch-code.sh` it is the dispatcher's own script dir, which happens to be right.
The instrument is reading a host-owned variable by convention, not by contract — that is
why it silently breaks in the four files that spell it differently.

### 3.4 The trace sink dir (`leadv2-state-path.sh --no-link traces`)

Probe — the key exists and resolves (there is **no** allow-list of keys to add to):

```
$ ./leadv2-state-path.sh --no-link traces
/Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/traces
rc=0
```

Sandbox lever for the tests: `LEADV2_STATE_ROOT` (full root override, `leadv2-state-path.sh:78`)
or `LEADV2_STATE_BASE` (`:127`). `leadv2-state-path.sh:185-188` **aborts** if
`LEADV2_STATE_ROOT` is set while `LINK_ROOT` resolves to a real repo checkout — with
`--no-link` that guard does not fire (`NO_LINK -eq 0` is required), so `--no-link traces`
under `LEADV2_STATE_ROOT` is the safe sandbox. Note the writer does **not** honour a
`LEADV2_TRACE_DIR` (the stale f72c8c9c copy did; the shipped one does not) — tests must
sandbox via `LEADV2_STATE_ROOT`, never by inventing a var.

| case | behaviour |
|---|---|
| absent dir | `mkdir -p` creates it |
| empty dir | fine; reader → R4 |
| read-only dir | W5 (writer), R1 (reader, unaffected) |
| dir is a file | `mkdir -p` fails → W5 |
| enormous file | reader streams line-by-line — bounded memory. OK. |

### 3.5 The NDJSON record (the reader's input)

| case | reader behaviour |
|---|---|
| absent field `duration_ms` | `malformed += 1`, line skipped (`:69-71`) |
| `duration_ms` present but a string | same |
| absent `span` | bucketed under `"?"` |
| absent `trace_id` | bucketed under `"?"` |
| empty line | skipped, **not** counted malformed (`:57-58`) |
| truncated/interleaved line | `json.loads` fails → counted malformed. **This is the only signal test group 2 has, and it is the right one.** |
| 1 sample | `percentile` returns `sorted[-1]` for both p50 and p95 (`:83-84`), `raw_sample: true` |
| even sample count, n ≥ 5 | `idx = round(pct/100*n) - 1`. n=6, p50 → `round(3.0)-1 = 2` → the **3rd smallest** (a lower-median convention, not an interpolated median). n=6, p95 → `round(5.7)-1 = 5` → the max. Pin these two numbers in a fixture; they are the arithmetic the mission asks to nail down. |
| 512-byte cap | `${#rec} > 512` is a **character** count in bash, not bytes. With a pure-ASCII id and span (enforced for the id by §3.2, not enforced for the span name) they coincide. A span name is a literal in the source at all nine sites, so this is not reachable today — note it, do not fix it. |

---

## 4. Product defects the tests will expose (fix minimally; nothing else)

### 4.1 Defect A — four of the nine seams can never write a span

**Mechanism:** `lib:87`, `${SCRIPT_DIR:-.}`, against §3.3's table. `glm-coder.sh`,
`kimi-coder.sh`, `codex-task.sh`, `leadv2-status-collector.sh` define no `SCRIPT_DIR`, so
the sink resolves relative to CWD, fails, and the trace self-disables for the entire
process. `provider.glm`, `provider.kimi`, `provider.codex` and `status.collect` never
appear in any report. The operator sees a report that looks complete — every row it shows
is true — and concludes the provider call is not where the wall-clock goes.

**Minimal fix (do NOT change the record shape, do NOT touch the nine call sites' semantics):**
resolve the bin from the library's own location, which is always correct:

```bash
local bin="${LEADV2_STATE_PATH_BIN:-}"
[[ -n "$bin" && -x "$bin" ]] || bin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/leadv2-state-path.sh"
[[ -x "$bin" ]] || bin="$(command -v leadv2-state-path.sh 2>/dev/null || true)"
```

`${BASH_SOURCE[0]}` inside `lib/leadv2-trace.sh` is the lib path in every sourcing context,
so `../leadv2-state-path.sh` is the sibling script. This is a change to
`lib/leadv2-trace.sh` only — it does not touch the instrumented call sites, so it stays
inside the mission's off-limits.

**Note for the implementer:** verify this against the mission's own claim before fixing.
If a probe shows the four seams *do* write (e.g. because a parent exports something not
found by the greps above), the design is wrong and the test should pin the working
behaviour instead. Red-first: the test must fail on HEAD and pass after.

### 4.2 Defect B — a clock failure at exit hangs the host script forever

**Mechanism:** the EXIT trap installed at `lib:196`:

```bash
while [[ ${#LV2_TRACE_STACK[@]} -gt 0 ]]; do lv2_trace_end "$_lv2_rc"; done
```

`lv2_trace_end` returns **without popping** when `_lv2_trace_now_ns` fails at `lib:140`
(`instr_start="$(_lv2_trace_now_ns)" || return 0`). The loop condition is unchanged, so it
spins forever. Trigger: `perl` present at `_lv2_trace_resolve_clock` time but failing later
— PATH change, a fork/ENOMEM under load, a `perl` that exits non-zero, an interpreter
upgraded mid-run.

**User-visible consequence:** an instrumented lane (`leadv2-dispatch-code.sh`,
`leadv2-review-run.sh`, `leadv2-router.sh`, `leadv2-lanes-snapshot.sh`,
`leadv2-status-collector.sh` — five of the nine, every `arm_exit` site) **never exits.**
The lane is not dead and not alive; product-close waits on a worker that will never
return, and the founder sees a lane stuck in its phase with no error line anywhere.

This directly violates the library's own stated invariant (`lib:9-10`: "a trace failure
must never change a host script's control flow"). It is severe out of proportion to its
likelihood, and it is the honest answer to §5.

**Minimal fix:** make the pop unconditional — pop the stack **before** any operation that
can fail, so `lv2_trace_end` is always a strict pop:

```bash
  local span="${LV2_TRACE_STACK[$((n-1))]}"
  local t0="${LV2_TRACE_STACK_T[$((n-1))]}"
  unset 'LV2_TRACE_STACK[...]' 'LV2_TRACE_STACK_T[...]'    # already here, at :134
  ...
  instr_start="$(_lv2_trace_now_ns)" || return 0            # :140 — now pops-then-returns
```

The `unset` at `:134` already precedes `:140`, so the fix is smaller than it looks: the
hazard is only that a **future** early return could be inserted above `:134`, plus the loop
has no bound. Belt and braces, and the minimal change is the bound:

```bash
trap '_lv2_rc=$?; _lv2_n=${#LV2_TRACE_STACK[@]}; while [[ ${#LV2_TRACE_STACK[@]} -gt 0 && $_lv2_n -gt 0 ]]; do lv2_trace_end "$_lv2_rc"; _lv2_n=$((_lv2_n-1)); done; ...' EXIT
```

A decrementing counter makes the loop terminate in at most `depth` iterations regardless of
what `lv2_trace_end` does. **Implementer: pick exactly one of the two fixes, prove it with
the red-first test in group 5, and do not do both.** Preference: the bounded loop — it
holds even if a later edit re-introduces an early return above the pop.

---

## 5. COUNTEREXAMPLE — what still violates the invariant after every finding is fixed?

The invariant the instrument exists to protect: *turning the trace on must not change what
the lane does, and turning it off must cost nothing.* After Defects A and B are fixed and
all five test groups are green, this can still violate it:

**`lv2_trace_arm_exit` steals the EXIT trap slot from any host that installs its own trap
AFTER the arm call.** The library documents the ordering requirement in a comment
(`lib:175-178`) and nowhere enforces it. Bash has exactly one EXIT-trap slot; the
instrument captures the *previous* trap at arm time (`:183`) and re-runs it, but a host
`trap ... EXIT` executed on any line after the arm silently **discards** the trace trap and,
with it, nothing important — the real hazard is the mirror case: a host that installs its
trap later loses nothing, but a host that installs its trap *conditionally* (inside an `if`,
after a lock is taken) will have its lock-release trap replaced or ordered wrong depending
on which branch ran. `leadv2-dispatch-code.sh` arms at `:2498` out of 4000+ lines — every
`trap ... EXIT` below that line is a live instance of this. A test cannot catch it
generically; only a lint can (`grep -n 'trap .* EXIT'` per instrumented file, asserting no
occurrence after the arm line). **That lint is in scope as test group 5b** — it is three
lines and it closes the only class of ON-path behaviour change I cannot otherwise bound.

Second, smaller, and not fixable here: the ON path costs **5 forks per span** (§1.1). For
`lane.resolve`, whose real duration is single-digit milliseconds, the instrument is a
measurable fraction of what it measures. The reader already tells the truth about this via
its `noise_floor` footer (`trace-report:112-117`, "measurement below instrument noise
floor"), which is the correct mitigation — a *report* that refuses to draw a conclusion
beats a *writer* that pretends to be free. Nothing to fix; the test must assert the footer
fires, so the honesty is pinned rather than incidental.

Third: nothing protects against two lanes with the **same** `LEADV2_TRACE_ID` writing to
one sink. That is by design (a lane's children share the id — that is the whole point) and
the reader's per-`trace_id` total is defined as the sum. Not a defect.

What I checked and found clean: the OFF path (§6 group 3 proves it), the id charset guard
against sink-path traversal (§3.2), record-size cap, reader behaviour on malformed input,
and the sandbox lever (`LEADV2_STATE_ROOT` with `--no-link` does not trip
`leadv2-state-path.sh:185`).

---

## 6. THE DESIGN — test suite structure

One new file: `plugins/leadv2/scripts/tests/test-leadv2-trace.sh`, following the sibling
convention (self-contained bash, own `mktemp -d` sandbox, `PASS`/`FAIL` counters, non-zero
exit on any failure, no writes outside `$TMPDIR` and no `docs/leadv2` mutation — the suite
runner's hermetic gate at `run-core-offline.sh:210-222` fails a lane-owned suite that
dirties `docs/leadv2`).

Sandbox preamble for every group: `export LEADV2_STATE_ROOT="$TMP/state"` and never
`HOME`-mutate; the trace sink then resolves under `$TMP/state/.../traces`.

### Group 1 — writer schema and monotonicity (mission item 1)

1.1 Source the lib directly with `LEADV2_TRACE=1`, `LEADV2_TRACE_ID=t-schema`,
`LEADV2_STATE_PATH_BIN` pointed at the real `leadv2-state-path.sh`. `lv2_trace_begin s1`,
sleep, `lv2_trace_end 0`. Assert exactly one line in the sink; parse with `python3 -c`;
assert **every** required key present: `trace_id, span, script, pid, ppid, t_start_ns,
t_end_ns, duration_ms, exit_code, child_exec_count`.
  - `child_exec_count` is emitted as literal `null` (`lib:154`). Assert **the key exists**,
    and that its value is `null`. The mission forbids changing the record shape to make a
    test easier, so the test pins today's honest "not measured", it does not demand a number.
1.2 Assert `exit_code` round-trips a non-zero: `lv2_trace_end 7` → `"exit_code":7`.
1.3 Assert nesting: `begin a; begin b; end; end` → two records, inner has
`"parent_span":"a"`, outer has `"parent_span":null`.
1.4 **Monotonicity.** PATH-shim a fake `date` that prints a date one year in the past, and
run under `faketime`-free conditions (no `faketime` dependency — the shim is enough because
`date` is the *only* wall-clock read, at `lib:157` and `:42`). Assert `duration_ms > 0`,
`t_end_ns > t_start_ns`, `clock_source` is `monotonic_perl` or `monotonic_python`, and
`wall_iso` shows the stubbed (wrong) date — proving the wall clock feeds only the cosmetic
field and cannot corrupt the timing. Say this in the report in exactly those words.
1.5 Boundary cases from §3.2: 64-char id accepted (file created), 65-char id → no file
created **and** `[trace] disabled` on stderr, `../../evil` id → no file named anything
outside the sink dir.

### Group 2 — append under concurrency (mission item 2)

Spawn N=24 background subshells, each sourcing the lib with the same
`LEADV2_TRACE_ID=t-concurrent`, each writing 25 spans with a randomized micro-delay. `wait`.
Then assert:
- line count == 24 × 25 == 600;
- **every** line parses standalone as JSON (a `python3` loop that fails on the first
  `json.JSONDecodeError`, reporting the offending line number and its first 80 chars);
- no line contains an embedded `}{` or a second `"trace_id"` (the interleaving signature);
- the multiset of `(pid, span_index)` pairs is exactly the 600 expected — no record lost,
  none duplicated.

Note in the report: this tests the property, it does not prove it universally. 600 records
under ~24-way contention on APFS is evidence, not a proof of `O_APPEND` atomicity.

### Group 3 — OFF costs nothing (mission item 3, load-bearing)

Three independent proofs, all three reported:

3.1 **Behavioural.** With `LEADV2_TRACE` unset, run
`leadv2-dispatch-code.sh` on the resolve-only path (`LEADV2_DISPATCH_SPAWN=0`) under a
sandboxed `LEADV2_STATE_ROOT`. Then `find "$LEADV2_STATE_ROOT" -name '*.ndjson'` → assert
**zero** results, and `find "$LEADV2_STATE_ROOT" -type d -name traces` → assert the dir was
never created either. Report the literal `find` output (empty).

3.2 **Static.** Assert at all nine files that the `else` arm of the load stanza is exactly
`lv2_trace_begin() { :; }; lv2_trace_end() { :; }; lv2_trace_arm_exit() { :; }` — i.e. the
OFF-path body of every trace call is the `:` builtin. Grep for the literal line; assert the
count is 9 and that no file has a load stanza whose else-arm differs. This is the "inspect
the emitted code path" the mission asks for, and it is the part that generalises: a `:`
builtin is by definition no subshell, no exec, no file open.

3.3 **Dynamic exec count.** Prepend a PATH dir holding wrapper `perl`, `python3`, `awk`,
`basename`, `date` scripts that each append one line to `$TMP/execs.log` before exec'ing the
real binary. Run the same resolve-only dispatch with `LEADV2_TRACE` unset; then run it with
`LEADV2_TRACE=1`. Assert the **delta** attributable to the trace is 0 in the OFF run — more
precisely, assert `grep -c . $TMP/execs.log` for the OFF run equals the count for a run with
the load stanza's `if` forced false, and that the ON run's count is strictly greater.
Report both numbers. This is the "count `execve`-equivalents" the mission asks for, done
portably (no `strace`/`dtruss`, which needs root on macOS).

### Group 4 — reader (mission item 4)

Fixtures committed under `plugins/leadv2/scripts/tests/fixtures/trace/`:
- `single/t-one.ndjson` — one `lane` record. Assert `count=1`, `p50 == p95 == max`, and the
  ` (raw)` marker present (§3.5 row "1 sample").
- `even/t-even.ndjson` — six `step` records with durations `1,2,3,4,5,100`. Assert
  `p50_ms == 3` and `p95_ms == 100` — the exact lower-median / max-at-p95 arithmetic derived
  in §3.5. Pinning these two integers is the point of the group.
- `lane-total/t-lane.ndjson` — one `lane` record of 1000 ms and three child spans summing
  to 400 ms. Assert the per-trace row shows `lane_ms=1000`, `child_span_ms_sum=400`,
  `unattributed=600`.
- `malformed/t-bad.ndjson` — a truncated line, an empty line, a valid line. Assert
  `malformed_lines: 1` (empty lines are not malformed, §3.5) and rc 0.
- Reader rc cases: nonexistent path → rc 1 and the `[trace-report] no trace data found`
  line (R3); empty dir → rc 0 with empty tables (R4). Assert both rcs explicitly.
- Assert the noise-floor footer fires for a fixture whose `p50_ms` is below 10× its
  `instrument_ms_avg` (§5, third paragraph).
- `--json` mode: assert the output parses as JSON and carries `spans`, `traces`,
  `malformed_lines`.

### Group 5 — the two defects, red-first

5a. Defect B: source the lib, `lv2_trace_arm_exit "hang"`, then PATH-shim `perl` **and**
`python3` to `exit 1`, then exit the script. Run the whole thing under
`timeout 10 bash ...`. **Red on HEAD** (timeout, rc 124); green after the fix (exits with
its own rc). This test is the entire justification for the §4.2 fix — it must be shown red
before the fix and green after, with both outputs pasted.

5b. The EXIT-trap ordering lint from §5: for each of the five `arm_exit` files, assert no
`trap ... EXIT` appears at a line number greater than the `lv2_trace_arm_exit` line.

5c. Defect A: run `leadv2-status-collector.sh` (the cheapest of the four broken seams) with
`LEADV2_TRACE=1` from a CWD that is **not** the scripts dir, and assert a `status.collect`
record appears. Red on HEAD, green after the §4.1 fix.

### Group 6 — suite wiring (mission item 5)

Append to `SUITE_DEFS` in `plugins/leadv2/scripts/tests/run-core-offline.sh` (the array at
`:259-320`), in the established `"name|||cmd"` form, at the end of the list:

```
  "lane trace instrument (Mission B: writer/concurrency/off-path/reader)|||bash $TEST_DIR/test-leadv2-trace.sh"
```

**No `|||SERIAL` marker.** The suite is hermetic (own `mktemp -d`, own
`LEADV2_STATE_ROOT`, no `docs/leadv2` writes, no global lock), so it shards freely. Adding
`SERIAL` unnecessarily costs the whole suite wall-clock and the shard partition is a pure
function of array order (`:356`), so appending at the end is the minimal-churn position.

---

## 7. The known-foreign failures, and the third one

The mission states two failures are foreign: `deferred-GLM ladder (V3-GLM-LADDER-01)`
(`run-core-offline.sh:312`) and `fanout classifier/runner guard` (`:276`), the latter
because `leadv2-fanout.sh:52` sources a file absent from the harness's private HOME.

The mission asserts a third failure exists and is ours. I could not run the suite in this
prepass (a full `run-core-offline.sh` is minutes of wall-clock and outside a planner's
budget), so I will not name it from a guess. **Implementer: run the suite first, before
writing a line of test code, and capture the failure list.** My prior, from the discovery
above, is that it is either (a) a `bash -n`/`syntax_all` (`:260`) consequence of round 1's
edits, or (b) `all plugin shell syntax` tripping over the stale
`.claude/worktrees/f72c8c9c/.../leadv2-trace.sh` — note `syntax_all` walks
`find "$PLUGIN_ROOT" -type f -name '*.sh'`, and if `$PLUGIN_ROOT` ever encompasses the
worktree scaffold, that stale file is in the walk. Verify; do not assume.

---

## 8. Non-goals — explicitly out of scope

- Instrumenting any new seam. Nine is the set.
- Changing the NDJSON record shape, including making `child_exec_count` a real number.
- Any optimisation of the ON path (the 5 forks/span stay).
- Deleting, repairing, or re-registering `.claude/worktrees/f72c8c9c`.
- Merging, rebasing, stashing, or `git clean`. The 11 unrelated dirty files in `docs/` stay
  untouched.
- Fixing either of the two known-foreign suite failures.
- Adding a `LEADV2_TRACE_DIR` env var (the stale copy had one; the shipped design routes
  through `leadv2-state-path.sh` deliberately — do not reintroduce it).
- Any change to `leadv2-trace-report.sh`'s percentile convention. Group 4 **pins** the
  current arithmetic; it does not correct it.

---

## 9. Constraint checklist

1. **Env var naming** — every var used (`LEADV2_TRACE`, `LEADV2_TRACE_ID`,
   `LEADV2_STATE_PATH_BIN`, `LEADV2_STATE_ROOT`, `LEADV2_STATE_BASE`,
   `LEADV2_DISPATCH_SPAWN`, `LEADV2_SUITE_SHARDS`) carries the `LEADV2_` prefix and was read
   from the tree, not invented. No new env var is introduced by this design.
2. **File paths** — every path in §6 exists on disk except
   `plugins/leadv2/scripts/tests/test-leadv2-trace.sh` **(to-create)** and
   `plugins/leadv2/scripts/tests/fixtures/trace/*` **(to-create)**; `tests/fixtures/`
   itself exists.
3. **`claude -p`** — this design invokes none. N/A.
4. **Concurrent access** — group 2 writes 24 concurrent processes into one sink file; that
   contention *is* the test. Group 3's exec-log shim is written by concurrent wrappers, so
   it must use `>>` with one `printf` per exec, same single-line-append property. Every
   group must use its own `mktemp -d` because `run-core-offline.sh` shards suites in
   parallel — two shards must never share a sink path.
5. **Config contradiction** — `LEADV2_STATE_ROOT` is documented at
   `leadv2-state-path.sh:177` as sandbox-only and never set in production; using it in tests
   is consistent with the four sibling suites that already do. No contradiction.

---

## acceptance

```yaml
acceptance:
  - surface: log_line
    observable: >
      Running the core-offline suite prints a result line for a suite named
      "lane trace instrument", and that line reports it passed; the run's final
      failure count is exactly two, and both named failures are the deferred-GLM
      ladder and the fanout classifier guard.
    authored_at: 2026-08-23T11:35:00Z
  - surface: file_artifact
    observable: >
      After a dispatch runs on the resolve-only path with tracing switched off, a
      person listing the whole state directory finds no trace file and no traces
      folder at all — the folder was never created.
    authored_at: 2026-08-23T11:35:00Z
  - surface: rendered_line
    observable: >
      The trace report, pointed at the six-sample fixture, shows a p50 of 3 and a
      p95 of 100 for that span, and for the single-sample fixture shows the same
      number in the p50, p95 and max columns with a "(raw)" note beside it.
    authored_at: 2026-08-23T11:35:00Z
  - surface: log_line
    observable: >
      A script that armed the trace and then lost its clock finishes and returns
      to the shell prompt instead of hanging; before the fix the same script has
      to be killed by the ten-second timeout.
    authored_at: 2026-08-23T11:35:00Z
  - surface: rendered_line
    observable: >
      The trace report for a lane that ran a provider call lists a row for that
      provider's span; today that row is absent no matter how many lanes ran.
    authored_at: 2026-08-23T11:35:00Z
```

LANE_WRITES: plugins/leadv2/scripts/tests/test-leadv2-trace.sh, plugins/leadv2/scripts/tests/fixtures/trace/*, plugins/leadv2/scripts/tests/run-core-offline.sh, plugins/leadv2/scripts/lib/leadv2-trace.sh

DELIVERABLE_COMPLETE
