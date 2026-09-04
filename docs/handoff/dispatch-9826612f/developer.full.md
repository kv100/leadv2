verdict: APPROVE
next_action: review_round_2

# CODEX-LEAD-FULL-01 — implementation report

## What was implemented

All of §5's file list from the scoped design, under `plugins/leadv2/codex-lead/`
(worktree `.claude/worktrees/9826612f`, commits `a1e2034`, `2119dbc`):

- `lv2guard.sh` — bash reimplementation of the CATASTROPHIC-tier deny-floor.
  Fails **closed** (rc 97) on missing/unreadable/zero-rule patterns files or
  missing `python3` (inverting the canonical hook's fail-open behavior, per
  design §0.3 — intentional, documented). Does **not** honor
  `LEADV2_DENY_FLOOR=0` (CB-8). Loads the canonical 9-rule
  `leadv2-deny-patterns.yaml` (unmodified, read-only) plus
  `deny-extra.yaml`'s 3 codex-lead-only rules. Supports argv form and `-c`
  form; the `# deny-floor: allow` inline token is only honored in `-c` form
  (CB-6). Normalizes `$HOME` → `~` before matching (CB-7/R-2). Caps the
  matched string at 64 KiB without ever refusing a long command (CB-3).
- `deny-extra.yaml` — `worktree_prune_active_lanes` (predicate, reads the
  control-plane `active.yaml` via `leadv2-state-path.sh --no-link
  active.yaml`; malformed YAML refuses **only** this rule, per CB-4 blast
  radius; empty/absent registry allows), `codex_exec_direct` (regex refusal
  naming `codex-task.sh`), `heredoc_oversize` (advisory only, never refuses,
  threshold via `LEADV2_CODEX_HEREDOC_WARN_BYTES`, default 2048, non-numeric
  falls back to default).
- `leadv2-codex-status.sh` — one-line status. Reads
  `leadv2-quota-live.sh json` only (never `~/.claude/burn/quota-fragment.sh`,
  per §1b's drift-avoidance decision). Live-probed field shapes against the
  running quota-live.sh (see Evidence below) — `.anthropic.accounts[0]`,
  `.glm.<binding_window>`, `.codex.windows[0]` all matched what the design's
  `UNVERIFIED:` note flagged as needing a live check. A failed bucket
  degrades to `?`, never `0%`. Lane count/active task come from
  `leadv2-status-surface.sh --oneline`; its absence/timeout degrades to
  `lanes ?` rather than failing the whole line. Always exits 0 except on a
  bad flag (rc 2).
- `install.sh` — idempotent: `unchanged`/`updated(+.bak)` per prompt file and
  per AGENTS-pilot ref copy; `[mcp_servers.repowise]` block wrapped in
  `# BEGIN/END leadv2-codex-lead repowise` sentinels, added/updated only
  inside those sentinels; a **pre-existing hand-written**
  `[mcp_servers.repowise]` block with no sentinels (verified live in
  `~/.codex/config.toml:2666` — see Evidence) is left untouched, printing the
  designed "already configured by hand" message. TOML parse-checked
  (stdlib `tomllib`) before touching, rolled back if a write would produce
  invalid TOML. Never writes `AGENTS.md` — prints `ACTION REQUIRED` when the
  `@import` line is missing. Target repo missing → rc 3; unwritable/invalid
  `config.toml` → rc 4.
- 5 prompts (`leadv2.md`, `leadv2-status.md`, `leadv2-dispatch.md`,
  `leadv2-review.md`, `leadv2-close.md`) — Russian founder-facing text per
  the existing shim's convention, English rc tables restating (not
  redefining) the verified dispatch/review tables.
- `shim/{rm,git,codex}` — off-by-default PATH-prepend wrappers; re-exec the
  real binary through `lv2guard.sh`. Fixed a bug found during testing: the
  first draft used `command -v -p <bin>`, which restricts lookup to a
  POSIX-default `PATH` that does **not** include `codex` (a non-standard
  CLI location) — switched to stripping the shim dir out of the live `$PATH`
  instead, verified working for `git` (see Evidence).
- `tests/test-lv2guard.sh` (36 cases: every deny/allow/predicate/advisory
  case in the design's §6 fixture list, plus `bash -n` over every shipped
  file) and `tests/test-codex-install.sh` (18 cases: two-run idempotency,
  hand-written-block preservation, missing-target-repo rc, `bash -n`) — both
  green. Raw output below.
- `codex-lead-AGENTS-pilot.md` +50 lines (74 → 124, within the 150 cap) and
  `codex-lead-pilot-runbook.md` — install one-liner in §Install, M-2 reworded
  "deny floor" checklist row.

## Discovery notes vs. the design's own census (per PREPASS-MECHANISM-CLOSURE-01)

None found the design's own §0 census to be wrong. I independently re-verified
the two load-bearing facts it depends on and both held:

1. `~/.codex/config.toml` really does have an un-sentineled hand-written
   `[mcp_servers.repowise]` block today (line 2666) — exactly the scenario
   CB-9/§2d's "left untouched" branch exists for. Confirmed by grep before
   writing `install.sh`, and by a fixture-reproduction of the same shape in
   `test-codex-install.sh`.
2. `~/Projects/persona-engine/AGENTS.md` already has the
   `@import .claude/ref/90-codex-lead-pilot.md` line (line 92, from the prior
   CODEX-LEAD-PILOT-PREP-01 task), and its ref file is byte-identical to
   this repo's `codex-lead-AGENTS-pilot.md` as of the base of this branch —
   so `install.sh`'s ref-copy logic had a real "already synced" case to
   exercise, not just a fixture-only one.

No caller/return-code claim in the design was found to diverge from the live
scripts; `leadv2-quota-live.sh`'s JSON shape (`.anthropic.accounts[0].<window>`,
`.glm.<binding_window>`, `.codex.windows[0]`) matched the design's own
`UNVERIFIED:` placeholder exactly once probed live (see Evidence).

## Non-goals honored

No edit to `leadv2-deny-floor.sh`, `leadv2-deny-patterns.yaml`, `hooks.json`,
or anything under `plugins/leadv2/scripts/`. No new Claude-side hook. No
change to dispatch/review rc semantics (prompts restate the verified tables,
they don't redefine them). No MCP tooling beyond what `install.sh` already
ensures. No writes to `docs/leadv2/` or `docs/handoff/` from any shipped
script (this deliverable file itself is written by me, not by the shipped
tooling).

## Evidence

Live quota-live.sh JSON shape (2026-08-24, this repo, `json` mode):
```
$ bash plugins/leadv2/scripts/leadv2-quota-live.sh json | python3 -c "import json,sys;d=json.load(sys.stdin);print(list(d['anthropic']['accounts'][0].keys())[:6])"
['entry_suffix','service','subscription_type','tier','http','account_label', ...]
# .accounts[0].seven_day.pct / .five_hour.pct / .binding_window == "seven_day" (confirmed)
# .glm.weekly.pct / .glm.five_hour.pct / .glm.binding_window == "weekly" (confirmed)
# .codex.windows[0].used_percent / .reset_iso (confirmed)
```
Rendered status line (live, this machine):
```
$ bash plugins/leadv2/codex-lead/leadv2-codex-status.sh
cc 68%/4d12h · cx 3%/6d14h · glm 1%/6d16h | lanes 9 | task persona-engine/dispatch-43ae4318
```

Hand-written repowise block, live, pre-existing (not created by this task):
```
$ grep -n "mcp_servers.repowise" ~/.codex/config.toml
2666:[mcp_servers.repowise]
```

Test suite raw output (both green):
```
$ bash plugins/leadv2/codex-lead/tests/test-lv2guard.sh
... (36 PASS lines, incl. every §6 fixture case) ...
===================================================
PASS: 36  FAIL: 0
===================================================

$ bash plugins/leadv2/codex-lead/tests/test-codex-install.sh
... (18 PASS lines) ...
===================================================
PASS: 18  FAIL: 0
===================================================
```

Falsification set (per mission's "before you finish" contract):
```
$ for f in plugins/leadv2/codex-lead/lv2guard.sh plugins/leadv2/codex-lead/install.sh \
    plugins/leadv2/codex-lead/leadv2-codex-status.sh \
    plugins/leadv2/codex-lead/tests/test-lv2guard.sh \
    plugins/leadv2/codex-lead/tests/test-codex-install.sh \
    plugins/leadv2/codex-lead/shim/rm plugins/leadv2/codex-lead/shim/git \
    plugins/leadv2/codex-lead/shim/codex; do bash -n "$f" && echo "OK: $f"; done
OK: plugins/leadv2/codex-lead/lv2guard.sh
OK: plugins/leadv2/codex-lead/install.sh
OK: plugins/leadv2/codex-lead/leadv2-codex-status.sh
OK: plugins/leadv2/codex-lead/tests/test-lv2guard.sh
OK: plugins/leadv2/codex-lead/tests/test-codex-install.sh
OK: plugins/leadv2/codex-lead/shim/rm
OK: plugins/leadv2/codex-lead/shim/git
OK: plugins/leadv2/codex-lead/shim/codex
```
No Python files were added or changed; no `py_compile` targets exist for
this diff.

## Left alone / not done

- Did not run `install.sh` against the real `~/.codex` (only against fixture
  `HOME`s in the test suite) — deliberately, to avoid mutating the founder's
  real Codex config from an unreviewed diff. The founder or a follow-up task
  should run `bash plugins/leadv2/codex-lead/install.sh` for real once this
  diff is reviewed.
- Did not open a live Codex CLI session to exercise the prompts end-to-end
  (no Codex session available in this subagent's environment) — the prompts
  are reviewed for content/rc-table accuracy against the verified scripts,
  not executed live.
- `git diff --cached --stat` / `git log` for this branch show exactly the 16
  files listed in §5 plus the two doc edits — no drive-by changes.

DELIVERABLE_COMPLETE
