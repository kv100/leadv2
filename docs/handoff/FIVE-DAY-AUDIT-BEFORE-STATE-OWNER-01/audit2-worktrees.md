# Five-day sweep — audit 2 of 3: committed work that never reached `main`

Method: every worktree under `~/Projects/leadv2/.claude/worktrees/`, commits ahead of `main`,
with lane-anchor and merge-bookkeeping commits discounted as "not work", then each remaining
body checked against `main` by commit message and content.

**145 worktrees examined · 115 carried zero real work** (62 with no commits ahead, 53 whose only
ahead-commits were anchors or merges) · **90 unmerged real commits across 30 worktrees.**

## Worth merging (11)

| worktree | commits | what it is | state in main |
|---|---|---|---|
| FABLE-THINK-TIER-01 | 15 | think-role LLM calls routed through Fable 5.1 with Opus-5 fallback; R1–R9 review-fix cycle, kill-switch on every channel | only the R2–R8 planning briefs landed; R9's fix/test/report commits absent |
| WORKER-DOD-GATE-01 | 13 | mechanical Definition-of-Done gate before model review + mutation-control artifact provenance | only round briefs in main |
| WORKER-MCP-ALL-ARMS-01 | 8 | both code-intel MCPs wired into freepool/kimi/codex arms + cross-arm suite | only briefs in main |
| HOOKS-PARITY-ACROSS-REPOS-01 | 5 | hook-fork-guard wired as SessionStart in all 4 repos, m3-market root-scan miss fixed | not in main (lane still live) |
| GLM-EFFICIENCY-01 | 4 | flash cost 0.4→0.33 (founder-approved) + effort wiring | only briefs in main |
| 0ac989a9 | 3 | BOARD-BLIND-TO-DETACHED-WORKERS-01: detached-worker liveness leg + prune veto | not in main |
| 0e7cd03d | 3 | PPC-G1: e2e harness sandbox-escape / hang fixes | not in main |
| DRIFT-GUARDS-TO-CANON-01 | 2 | lifts the plugin-scripts drift guards out of persona-engine into canonical | not in main |
| 05d28614 | 2 | PPC-G8: e2e-suite deadline enforcement, two call sites | not in main |
| WATCHER-LEAK-01 | 1 | step 3: reap sweep for provably-dead sessions (L7–L9) | main has steps 1–2 only |
| SUITE-LOCK-IS-MACHINE-WIDE-01 | 1 | round 3: bounded loud wait, non-inheritable lock fd, negative control | main has the earlier round only |
| ca7c1056 | 1 | PPC-G11: GLM_POLICY_RESOLVER stub fix | not in main |

## Needs review before a verdict (4)

| worktree | commits | why it is not a clean yes |
|---|---|---|
| 6409fada | 3 | PPC-G3: dispatch must `cd` into `E2E_REPO`. A *different* PPC-G3 fix is already in main — check whether this one is subsumed. |
| OPS-42 | 2 | dispatch-ledger fixture isolation; the author's own note says "no mission work". Low content value. |
| PHASE-BOOTSTRAP-ADMIT-02 | 1 | generic salvage of a lane killed before commit; distinct value unclear. |
| ANTI-SILENCE-BEAT-ABORT-03 | 1 | errexit leak killing the beat mid-abort; a later lane `-04` merged instead and probably supersedes it. |

## Decided not to merge (15) — reason recorded

Already landed in `main`, verified by identical commit message or hash: `7c9da953` (PPC-G2),
`PLUGIN-PAPERCUTS-01`, `ONE-LANE-WATCH-01-R2`, `27434c7a` (FP-07), `CLOSE-GATE-A2-ID-SCHEME-MISMATCH-01`,
`DISPATCH-PHASE-DEADLOCK-01`, `LANE-LIVENESS-THREE-STATES-02`, `PHASE-BOOTSTRAP-PROVE-05`,
`PROMISE-GUARD-UNKNOWN-KIND-01` (merged 2026-09-03).
Superseded by a later real fix: `LANE-FINISHED-IS-NOT-DEAD-01`.
Carry no code, only a note: `CHEAP-ARMS-ARE-SWITCHED-OFF-01`, `COMPLEXITY-ESTIMATOR-ON-02`.
Bookkeeping only, not feature work: `N7F-C3-BOUND-ID`, `288db6a6` (redundant with `0ac989a9`).
