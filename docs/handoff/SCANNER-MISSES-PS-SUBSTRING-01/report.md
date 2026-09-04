# SCANNER-MISSES-PS-SUBSTRING-01 — report

The liveness suite's static check T3 locked two *idioms* (`pgrep -f`,
`ps | grep`) while a third spelling of the same disease — `ps -axo` +
`if worktree not in line` in `lib/leadv2-lane-state.sh` reconcile() — ran
live and undetected. This lane extends the check from two idioms to the
**class**: "a liveness decision made by enumerating the process table and
selecting rows by TEXT membership instead of by a numeric pid taken from a
record".

## What changed

One file: `plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh`.

- T1–T4 and their negative controls: untouched (T3's old two-idiom scanner
  is preserved verbatim inside `_scan_process_name_pattern`).
- NEW `_scan_text_matched_process_table()` — the class scanner:
  - **Enumeration** (opens a 15-line window): any `pgrep` (any flags — pgrep
    always selects by name pattern); `ps` whose own argument tokens contain a
    table-wide flag (`-e`, `-A`, `-a`, `-ax`, `-axo`, `-eo`, `-ef`, `-Ao`,
    `aux`, `ax` — regex `(?<![a-zA-Z])-[a-zA-Z]*[eEaA][a-zA-Z]*\b`); `/proc`
    *listing* (`listdir/scandir/iterdir('/proc…')`, `/proc/[0-9]*` glob).
    Comment lines are skipped. The `ps` argument span stops at the first
    `|`, `;`, `&` so a downstream `sed -e` can never impersonate a ps flag.
  - **Text row-select** inside the window (closes the case): `not in X`,
    `if/elif/while … X in Y`, any `grep`, `.find(`, bash `=~`,
    `case X in`, `== *"…"*` glob-contains.
  - Per-pid lookups are NOT enumeration by design: `ps -p <pid> -o …`,
    `ps -o lstart= -p`, and reading `/proc/<pid>/stat` for a recorded pid
    never open a window.
- NEW checks: T5 (class scan over the two canonical liveness libs —
  currently and deliberately RED on the live violator, see below),
  T5-NC (substring form caught in a copy), T5-NCb (old `pgrep -f` control
  still bites under the class scanner), T5-NCc (old `ps | grep` control
  still bites), T5-FP (sanctioned per-pid forms stay green).

Two regex bugs found while building the scanner are worth recording: a
word-boundary `\b-` can never match after a quote (`'-axo'` — `'` and `-`
are both non-word), and `ps\s+` misses the Python form `['ps','-axo'…]`.
Both are encoded as comments in the suite.

## Acceptance evidence

### 1. Negative control on the new requirement (the exact missed form)

Insertion into `wl_cmdline_match()` body of a scratch copy of the CLEAN
`lib/leadv2-watch-lifecycle.sh` (baseline scans green):

```
T5-NC: baseline_rc=0 (watch-lifecycle.sh unmutated) mutated_rc=1
[TEST] PASS: T5-NC: scanner caught the injected ps -axo + not-in row-select and named file:line -- .../lib/.nc-substr-leadv2-watch-lifecycle.sh:71: liveness by process-table enumeration + TEXT row-select (ps table-wide enumeration; text select: ...)
```

Baseline/mutated rc pair: `baseline_rc=0`, `mutated_rc=1` (logged by the
suite, raw run output below).

### 2. Backward compatibility — old controls still bite

```
T3-NC:  baseline_rc=0 mutated_rc=1  (pgrep -f, old scanner)      PASS — named .nc-pattern-leadv2-lane-state.sh:36
T5-NCb: baseline_rc=0 mutated_rc=1  (pgrep -f, new class scanner) PASS — named .nc-pgrepf-leadv2-watch-lifecycle.sh:71
T5-NCc: baseline_rc=0 mutated_rc=1  (ps | grep, class scanner)    PASS — named .nc-pipegrep-leadv2-watch-lifecycle.sh:71
```

### 3. The live violator — T5 is deliberately RED

The suite now fails on exactly one check, against the real product defect
this lane was dispatched to expose:

```
[TEST] FAIL: T5: text-matched process-table liveness decision(s) found ...:
.../plugins/leadv2/scripts/lib/leadv2-lane-state.sh:133: liveness by process-table enumeration + TEXT row-select (ps table-wide enumeration; text select: if worktree not in line: continue)
=== test-liveness-tristate-01.sh: 13 passed, 1 failed ===
```

`lane-mission.md` forbids fixing `lib/` in this lane ("их чинит другая
линия"), so the red stands until the reconcile() fix lands, then T5 goes
green with no suite edit. Silently allow-listing the known violator to
force a green run was rejected — that is the exact "зелёная против живого
нарушителя" disease this lane exists to kill.

### 4. Ten consecutive runs (rule of 2026-09-04)

```
run1 rc=1
run2 rc=1
run3 rc=1
run4 rc=1
run5 rc=1
run6 rc=1
run7 rc=1
run8 rc=1
run9 rc=1
run10 rc=1
```

All ten identical: 13 passed / 1 failed, the single failure being the
deterministic T5 finding above. Static scan ⇒ zero flake.

### 5. Full suite raw output (final run)

```
=== test-liveness-tristate-01.sh: 13 passed, 1 failed ===
FAIL: T5: ... lib/leadv2-lane-state.sh:133: ... (text select: if worktree not in line: continue)
```

All 14 checks: T0, T1, T1-NC, T2, T2-NC, T3, T3-NC, T4, T4-NC pass;
T5 fails (live violator); T5-NC, T5-NCb, T5-NCc, T5-FP pass.

## Repo-wide findings census (NOT fixed here — report only)

Scanner run over all runtime `.sh`/`.py` under `plugins/` and `.claude/`
(tests excluded; comment lines skipped):

| # | file:line | form | class |
|---|-----------|------|-------|
| 1 | `plugins/leadv2/scripts/lib/leadv2-lane-state.sh:133` | `ps -axo pid=,lstart=,command=` → `:136 if worktree not in line` | **THE live violator this lane was dispatched on** — any argv mentioning the worktree path (grep, `git -C`, another session's tree walk) becomes a `session_id: recovered` registry row that resurrects closed lanes |
| 2 | `plugins/leadv2/scripts/leadv2-fanout.sh:1244` | `pgrep -f "/leadv2 ${tid}"` | known idiom (documented in the suite header since 2026-09-03) |
| 3 | `plugins/leadv2/scripts/leadv2-lane-watch-v2.sh:518` | `pgrep -f "$SELF_BASENAME --loop $session"` | same class |
| 4 | `plugins/leadv2/scripts/leadv2-lane-watch-v2.sh:634` | `pgrep -f "$SELF_BASENAME --loop"` | same class |
| 5 | `plugins/leadv2/scripts/leadv2-spawn-rate.sh:119` | `ps -Ao comm=,etimes= \| grep -E 'leadv2-(…)'` | known idiom (suite header) |

### Inspected and NOT violations (per-pid / non-liveness)

- `lib/leadv2-lane-state.sh:34,55` — `ps -o lstart= -p <pid>`: row selected
  by numeric pid from the record; exactly the sanctioned form.
- `lib/leadv2-watch-lifecycle.sh:70-78 wl_cmdline_match` — `ps -p "$1" -o
  command=` + `== *"needle"*`: per-pid corroboration, green by design
  (locked by T5-FP).
- `leadv2-helpers.sh:1702-1703` — reads `/proc/<pid>/stat` for a recorded
  pid (start-time corroboration): per-pid, not a table listing.
- `claude-subsession.sh:708` — `find … -newer /proc/1`: mtime trick, no
  process-table row selection.
- `leadv2-dispatch-product-close.sh:958,996` — comment lines saying the code
  must NEVER use `pgrep -f`; comment-skipping keeps them green.

## False positives — named, not silently suppressed

1. **Window attribution can name a numeric-validation `=~`.** In the T5-NC
   scratch copy the window's first TEXT hit is `[[ "$1 =~ ^[0-9]+$ ]]` — a
   numeric pid check, not a text select. The scanner still flags the correct
   enumeration line (71) and the control passes on file:line; the
   *attribution string* may name the nearest `=~` rather than the injected
   `not in`. Accepted: attribution is diagnostic prose; the flag target is
   correct. Not suppressed.
2. **Any `grep` within 15 lines after a table-wide `ps`.** E.g. a future
   `ps -axo … > log` followed by an unrelated `grep` on other data would be
   flagged. In the current census this fires only on genuine members
   (spawn-rate:119 flags itself). Acceptable for a liveness-lib scanner whose
   scope is two files curated for this concern; each T5 failure message
   demands the finding be justified against the census before acting.

No check was weakened to obtain green output.

## Self-check

- `bash -n plugins/leadv2/scripts/tests/test-liveness-tristate-01.sh` — OK.
- No Python files changed (scanner is an embedded heredoc; `bash -n` plus
  10 executed runs cover it — the runs above are the compile check).
- Changed-scope runner `tests/run-all.sh --scope changed`: result appended
  below after completion (runs >10 min core-offline; see run output).

## Changed-scope runner output

(appended when the detached run-all completes)
