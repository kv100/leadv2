# BEAT-LOOP-ORPHANS-01 — fix-round 2 report

Branch: `worktree-BEAT-LOOP-ORPHANS-01`, commits `cc80a42` (r1 salvage) → `38be66c` (r2) → final.
All work in `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/BEAT-LOOP-ORPHANS-01`.

## Review verdict → fix map

| # | Round-1 finding | Fix | Where |
|---|---|---|---|
| 1 | `*/docs/handoff/*\|*-runs/*` path rule never matches a real worker transcript → unpinned workers classified `lead` and armed loops | Rule DELETED. Classifier now decides from the transcript itself (see below) | `plugins/leadv2/hooks/lib/leadv2-hook-session-kind.sh` |
| 2 | E7 enshrined `~/.claude/projects/-Users-x/abc.jsonl -> lead` | E7 now asserts `unknown` (fail closed); suite 19 → 30 cases | `tests/test-beat-loop-orphans.sh` |
| 3 | task-judge / codex-session-runner (and others) spawn `claude -p` with no env pin | Census below; every claude spawn site now pins `LEADV2_SUBSESSION_ROLE`; grep gate F2 locks zero unpinned sites | see census |
| 4 | beat-loop `:170` owner-check unguarded; missing lib → rc 127 kills the founder beat on iteration 1 | Guarded `command -v leadv2_loop_owner_check` like the pulse-watch sibling; new F1: lib absent → beat still runs + journals `owner_check=unavailable reason=classifier_lib_missing` | `leadv2-single-lead-beat-loop.sh` |
| 5 | No report.md | This file | `docs/handoff/BEAT-LOOP-ORPHANS-01/report.md` |

## 1. New classifier (transcript-content rule)

Evidence order in `leadv2_hook_session_kind` (also mirrors its result into
`LEADV2_SESSION_KIND_OUT` / `LEADV2_SESSION_KIND_REASON` in the caller's shell):

0. `LEADV2_SESSION_KIND` pin (lead|worker|unknown)
1. `LEADV2_WORKER_ARM=1` (glm/freepool/kimi coders)
2. `LEADV2_SUBSESSION_ROLE` non-empty ≠ lead (now exported at EVERY spawn site)
3. the transcript's own content:
   a. munged-cwd path contains `-claude-worktrees-` (live-probed: every lane
      worker's transcript dir is
      `~/.claude/projects/<munged-cwd-with--claude-worktrees->/<sid>.jsonl`)
   b. lane-mission marker (`LANE ROOT:` / `WORKTREE PIN:` / `LANE_WRITES:` /
      `LEADV2_LANE_OUTCOME`) within the first 20 lines of the jsonl
   (either → `worker`)
4. neither signal and no pin → **`unknown`, and `unknown` FAILS CLOSED for
   loops**: beat-loop / lane-pulse-watch / dispatch-code `_arm_*` do NOT arm;
   they journal one `event=loop_armed_by_unknown_session kind=unknown
   reason=<why>` line. The single-shot beat HOOK keeps its documented
   fail-open (it spawns no loop).

## 2. `claude -p` spawn-site census (grep gate F2 enforces it)

Census command (also live in the suite's `spawn_gate`):

```
grep -rnE '(claude|CLAUDE_BIN|FREEPOOL_CLAUDE_BIN|KIMI_CLAUDE_BIN|GLM_CLAUDE_BIN)[^|;&>]*[" -]-p( |")|spawn_args=\(-p|claude_args=\(|claude -p|claude --print' \
  plugins/leadv2/scripts plugins/leadv2/hooks --include='*.sh' | grep -v '/tests/'
```

| Spawn site | Pin |
|---|---|
| `glm-coder.sh:370,1154` (`spawn_args=(-p …)`) | `LEADV2_WORKER_ARM=1` :103 |
| `freepool-coder.sh:421,1197` | `LEADV2_WORKER_ARM=1` :101 |
| `kimi-coder.sh:313,1054` | `LEADV2_WORKER_ARM=1` :126 |
| `claude-subsession.sh` (delegates to session-runner) | `LEADV2_SUBSESSION_ROLE=worker` :8 |
| `leadv2-task-judge.sh:214,216` | **NEW** inline `LEADV2_SUBSESSION_ROLE=…judge` |
| `leadv2-session-runner.sh:414/439` (`claude_args=(-p …)`) | **NEW** `export LEADV2_SUBSESSION_ROLE=${…:-runner}` :144 |
| `leadv2-lane-shape.sh:324` (frame-check) | **NEW** inline `LEADV2_SUBSESSION_ROLE=…frame-check` |
| `leadv2-codex-session-runner.sh` | spawns `codex exec`, not `claude -p` — no claude hooks fire in a codex process; out of claude census |
| `leadv2-context-diet-probe.sh` | spawns via `claude-subsession.sh` → covered above |
| `leadv2-lanes.sh:124` | python string list of runner names, not a spawn — allowlisted in the gate |

Gate: `F2 spawn grep gate: zero unpinned claude -p sites in the live tree` — PASS.

## 3. Live proof (real run, pasted)

Fixture worktree `…/leadv2/.claude/worktrees/BLO-PROOF-FIXTURE`; real GLM run
(quota gate live-check: `5h=51% weekly=66% — Lane may start`):

```
$ glm-coder.sh bg "Reply with exactly DONE and nothing else." --cwd …/BLO-PROOF-FIXTURE
260902-000806-BLO-PROOF-FIXTURE-3d52
$ … status → status: complete   (finished after 34s)
```

Before/after orphan counts (`pgrep -fl 'single-lead-beat-loop|lane-pulse-watch|backlog-pump' | grep worktrees`):

```
BEFORE: 53   (all pre-fix legacy loops from other lanes)
AFTER:  52   (one legacy loop hit its lifetime cap mid-run)
loops for BLO-PROOF-FIXTURE: 0   ← the fixture run armed NOTHING
```

The child session's hooks demonstrably fired (its result.md quotes the
task-anchor) and its transcript landed at the exact path the new signal
matches — yet no loop was armed and `docs/leadv2/loop-arm-journal.log` has no
fixture rows:

```
~/.claude/projects/-Users-kostiantyn-vlasenko-Projects-leadv2--claude-worktrees-BLO-PROOF-FIXTURE/602e812f-….jsonl
```

## 4. Mutation negative controls (RUN, red as required)

- **NC1** predicate always `lead` → A1 breaks (worker arms) — PASS (red)
- **NC2** owner-pid check neutered → B1 breaks (loop outlives dead owner) — PASS (red)
- **NC3** (new) worktree-path signal dropped → A2 breaks (worktree session no longer `worker`) — PASS (red)
- **NC4** (new) `LEADV2_SUBSESSION_ROLE` pin stripped at task-judge on a tree COPY → F2 gate red on `leadv2-task-judge.sh` — PASS (red). All mutations applied to skeleton copies only; live tree never mutated.

## 5. Suite

`LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-beat-loop-orphans.sh` →
**30 passed, 0 failed** (two consecutive full runs; a third mid-development run
showed D0 flaking at MAX_S=3 under suite load — lifetime margin raised to 6s).

## 6. Decision surfaced (async question q-79937ee6)

Fail-closed `unknown` means a founder lead session with NO pin (repo-root
transcript, founder-typed first message) also classifies `unknown` and stops
arming the autonomous beat loop — starvation is loud (journal
`reason=no_worker_evidence`) but real. Wiring: a lead that wants the
autonomous loop pins itself with `LEADV2_SESSION_KIND=lead` (pin is evidence
rule 0 and is exercised by A4/E4). Question `q-79937ee6` asked whether to
prefer the literal fail-closed (a, default) or a root-guard lead inference (b);
the lane proceeded on the default per contract. Note: thread q-1ba6ae9f had
earlier accepted fail-open for unknown — this round supersedes it per the
round-2 review verdict; journaling keeps the decision visible either way.

## 7. Self-falsification

`bash -n` clean on all 9 changed shell files; no Python files changed.
`tests/run-all.sh --scope changed` output: see lane journal appendix below.
