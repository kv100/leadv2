# w-resume-cwd — the resume command carried `cd "-"` on every completed transcript

## Defect (live, 2026-09-10)

`leadv2-interactive-session-switch.sh:116` took the cwd from `tail -n 1` of the
transcript.  The last line of a COMPLETED session is a `type=cost-state` record
with no `cwd` key structurally — the extraction fell back to `-`, and the resume
command the operator copies by hand silently sent them to the PREVIOUS
directory.

Live transcript `678952be-029b-486b-aa58-20f3b162000e.jsonl` (m3-market),
measured this lane:

```
lines: 19904
cwd-bearing lines: 14255
last-line type=cost-state keys=['hasUnknownModelCost', 'modelUsage', 'sessionId', 'startTime', 'totalAPIDuration', 'totalAPIDurationWithoutRetries', 'totalCostUSD', 'totalDuration', 'totalLinesAdded', 'totalLinesRemoved', 'totalToolDuration', 'type'] cwd=None
"cwd":"/Users/kostiantyn.vlasenko/MythicalGames/m3-market"   <- the value that was always there
```

Founder's live capture (before, 2026-09-10):

```
DRY-RUN resume: cd "-" && CLAUDE_CONFIG_DIR=".../.claude-work" claude --resume 678952be-...
```

## Fix

`leadv2-interactive-session-switch.sh` — only the cwd extraction and its
refusal:

- Backward chunked scan (64 KiB from EOF, never loading the whole transcript):
  the first record carrying a non-empty string `cwd` wins.
- No `cwd` anywhere → LOUD refusal `REFUSED reason=transcript_no_cwd` (rc=5,
  own journal word), never a guessed directory.
- Nothing else touched: detector, account-switch, transplant, journal format,
  existing fixtures unchanged.

Suite (`tests/test-interactive-session-switch.sh`): case 7 (cost-state tail →
resume carries the REAL cwd) and case 8 (no cwd anywhere → loud refusal, never
`cd "-"`).

## Live resume command, before and after

Before (founder's live capture, and the deterministic re-run below):

```
DRY-RUN resume: cd "-" && CLAUDE_CONFIG_DIR=".../.claude-work" claude --resume 678952be-...
```

After (fixed bytes, same live transcript, `--screen-text` banner, `--dry-run`,
rc=0, captured this lane):

```
interactive-switch: DRY-RUN resume: cd "/Users/kostiantyn.vlasenko/MythicalGames/m3-market" && CLAUDE_CONFIG_DIR="/Users/kostiantyn.vlasenko/.claude-work" claude --resume 678952be-029b-486b-aa58-20f3b162000e
```

Deterministic before/after of the extraction itself on the live file (exact
`HEAD~1` shipped bytes vs exact fixed bytes, same transcript):

```
before (HEAD~1 bytes): CWD=-
after  (HEAD bytes):    CWD=/Users/kostiantyn.vlasenko/MythicalGames/m3-market
```

A full-command BEFORE re-run is no longer reachable today: the live selector
now returns `selector_reason=single_profile` (the `work` slot is burning
again, so there is no free account to point at) — that stage is
account-state-dependent.  The cwd segment is decided before any of it, and is
the deterministic pair above.

## Mutation matrix (mutation → what reddened)

Each new guard has its own case; each mutation reddens EXACTLY its case and
none of the six existing ones.  Both runs backed by leadv2-mutation-control.sh
artifacts (worker mode, scratch copy, red proven):

| mutation | reddened | stayed green | raw |
|---|---|---|---|
| M7: scan consults only the file's LAST line (the shipped defect's scan half) | case 7 (3 checks) | cases 1–6, 8 — PASS=45 FAIL=3 | `mutation-control/20260910T160908Z-7206.txt` |
| M8: not-found substitutes `"-"` instead of refusing (the shipped defect's fallback half) | case 8 (6 checks) | cases 1–6, 7 — PASS=42 FAIL=6 | `mutation-control/20260910T160937Z-18642.txt` |

Raw FAIL lines:

```
M7:
[TEST] FAIL: case7 rc=0 (switched + transplanted past a cost-state tail) -- rc=5 want=0
[TEST] FAIL: case7 resume command carries the REAL cwd from above the cost-state tail -- no fixed match for 'resume: cd "/tmp/proj7" && CLAUDE_CONFIG_DIR=".../slot-b" claude --resume 99999999-8888-7777-6666-555555555555'
[TEST] FAIL: case7 transcript transplanted into slot b -- missing: .../slot-b/projects/-tmp-proj/99999999-8888-7777-6666-555555555555.jsonl
[TEST] summary: PASS=45 FAIL=3
M8:
[TEST] FAIL: case8 rc=5 (refused) -- rc=0 want=5
[TEST] FAIL: case8 names transcript_no_cwd (no guessed directory) -- no match for 'REFUSED reason=transcript_no_cwd' in: interactive-switch: detector: verdict=limit source=screen label=a pct=- attempt=1/300
[TEST] FAIL: case8 never emits a dash cwd -- found cd "-" in: interactive-switch: detector: verdict=limit source=screen label=a pct=- attempt=1/300
[TEST] FAIL: case8 account-switch NEVER invoked -- unexpectedly exists: .../handoff-c8-8/account-switch.log
[TEST] FAIL: case8 account untouched (guard fires before the switch) -- unexpectedly exists: .../cache/identity-max_a_test/probe-cooldown-until
[TEST] FAIL: case8 journal names the cwd guard -- no match for 'REFUSED reason=transcript_no_cwd' in: 2026-09-10T15:58:26Z [limit-detect] verdict=limit source=screen label=a pct=- attempt=1/300
[TEST] summary: PASS=42 FAIL=6
```

Note M8's red output is itself the shipped defect replayed verbatim: detector
runs, account-switch runs, marker armed, `cd "-"` emitted — exactly the
quiet-lie behaviour the founder saw live.

## Falsification set (raw)

```
$ bash -n plugins/leadv2/scripts/leadv2-interactive-session-switch.sh \
  && bash -n plugins/leadv2/scripts/tests/test-interactive-session-switch.sh
SYNTAX-OK

$ bash plugins/leadv2/scripts/tests/test-interactive-session-switch.sh | tail -1
[TEST] summary: PASS=48 FAIL=0          (prior 38 + 10 new; prior 38 unchanged)

$ bash tests/run-all.sh --scope changed
[CORE-OFFLINE] scope=changed running 2 of 95 suites (base=main@446609cbec, 2 changed files, 0 unmapped)
run-all: 5 passed, 0 failed, scope=changed   (rc=0)
```

Two foreign `run-all.sh` runners were live in other worktrees during the
changed-scope run (known concurrent core-offline flake vector) — no nested
lock/codex/glm reds occurred.  Post-mutation restores verified clean:
`git status --porcelain` empty after each, suite 48/0.
