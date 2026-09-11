# getmany-followup-bot: plugin parity — report (lane 627824083b9b)

Founder ask 2026-09-10: «хочу чтобы там плагин работал так же хорошо как у нас. И там работал и кодекс и глм».
Three jobs delivered: agent rebase, drift-guard hooks, live dispatch proof (spawned worker + codex run).

## 1. Three agents rebased (canonical frontmatter + repo specifics)

Files: `~/Projects/getmany-followup-bot/.claude/agents/{architect,critic,security-auditor}.md` (commit `42d453c`).

- Frontmatter taken from canonical whole: description, full repowise+graph MCP tool lists, `model: claude-sonnet-5`, `effort: high` (security-auditor: canonical has no effort), canonical skills + capabilities. One repo-specific skill kept: `postgres-rls` on security-auditor (Postgres migrations are this repo's stack).
- Canonical common sections added to all three: code-intel routing (CODE-INTEL-BOTH-01) as "When invoked" step 1 + closing section, index-first non-negotiable rule, pre-finalize contradiction scan (architect, critic), nested-helpers spawn gates (architect), YAGNI expertise bullet (critic).
- Repo-specific halves preserved: `docs/PRD.md` + `docs/projects/followup-system/ARCHITECTURE.md` + ADR flow, integrations (Pipedrive REST, Snov.io/Grinfi Postgres, Anthropic prompt cache, Gmail OAuth, Grinfi API, Telegram), feature folders, zod contracts, `pnpm typecheck`/vitest, `db/migrations/` numbering, graph project id, send-time re-check + audit_log checklist.
- Removed as persona-engine remnants (UNVERIFIED→verified below): Supabase RLS / Paddle webhook / SUPABASE_SERVICE_KEY / PADDLE_WEBHOOK_SECRET — no such stack in this repo:
  ```
  $ grep -rli 'paddle' --include='*.ts' src db → (empty; only old docs/handoff audit copies)
  $ grep -rn 'GRINFI_API_KEY' src/lib/env.ts → (empty; only GRINFI_SEAT_ID optional at :105)
  $ grep -rn 'webhook|app.post' src/index.ts → (empty; no inbound webhooks)
  ```
  Secret list replaced with the repo's real env names (from `.env.example`): ANTHROPIC_API_KEY, PIPEDRIVE_API_TOKEN, GOOGLE_CLIENT_SECRET, GOOGLE_SA_DWD_KEY_B64, GRINFI_API_KEY, SLACK_BOT_TOKEN, POSTGRES_PASSWORD, FOLLOWUP_APP_PASSWORD.

Frontmatter/spec parity probe:
```
== architect: canonical-model=model:claude-sonnet-5 ours-model=model:claude-sonnet-5 repowise-tools=2/2 graph-tools=1/1
== critic:    canonical-model=model:claude-sonnet-5 ours-model=model:claude-sonnet-5 repowise-tools=2/2 graph-tools=1/1
== security-auditor: canonical-model=model:claude-sonnet-5 ours-model=model:claude-sonnet-5 repowise-tools=2/2 graph-tools=1/1
repo specifics: docs/PRD.md→architect, pnpm typecheck→critic, getmany-followup-bot+db/migrations→security-auditor/architect
```

One-copy guard after the rebase (acceptance: still diverged=0):
```
[one-copy] tally: linked=2679 regression=0 badlink=0 expected_override=13 diverged=0 rotten_exceptions=0 unused_exceptions=3 ... rc=0
```

## 2. Plugin drift guards installed

- `.claude/hooks/plugin-scripts-drift-session-warn.sh` → symlink to canonical `~/Projects/leadv2/plugins/leadv2/hooks/…`, registered in `.claude/settings.json` SessionStart (timeout 10), same wiring as persona-engine (its settings.json:121).
- `.claude/hooks/plugin-scripts-drift-guard.sh` → symlink, NOT registered on any event — same as persona-engine: it has no event registration there either; it is the sourced sibling (`source "${SCRIPT_DIR}/plugin-scripts-drift-guard.sh"`, session-warn:27) providing `plugin_script_classify`.
- `leadv2-pulse-json.sh` NOT installed: this repo has `LEADV2_PULSE_MODE=0` in settings.json env — pulse is not armed, a pulse writer would be dead weight.
- `leadv2-supervisor-mode-reinject.sh` NOT installed per brief (supervisor retired 2026-08-17).

Falsification — hook actually fires (harness-faithful run: SessionStart JSON on stdin, CLAUDE_PROJECT_DIR set), clean tree:
```
$ printf '{"session_id":…,"source":"startup","hookEventName":"SessionStart"}' | CLAUDE_PROJECT_DIR=… bash .claude/hooks/plugin-scripts-drift-session-warn.sh
{}rc=0
```
Controlled drift (temporarily vendored copy of ask-lead.sh, then symlink restored — git clean after):
```
{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "PLUGIN-SCRIPTS-REGRESSION: 1 real plugin-owned .claude/scripts/ file(s) exist where symlinks belong. …\n  - REGRESSION .claude/scripts/ask-lead.sh"}}
```
Incident during this probe, fixed same turn: my restore initially left a real file (typechange ` T`); re-restored as symlink, `cmp` identical to canonical, `git status .claude/scripts` clean.

## 3. Live dispatch from that repo (worker_spawned ✅; worker later killed — honest incident)

Real dispatch (spawn) from `~/Projects/getmany-followup-bot`, mission = real stale-docs fix (`.env.example` GRINFI_API_KEY comment lies about env.ts):
```
[leadv2-dispatch-code] route_resolved by=arbiter role=worker arm=freepool model=freepool-default tier=standard effort=medium task=1fb0c568 reason=cheapest_capable … util_glm=28 util_codex=47 util_claude=65 … complexity_policy=capability_fit fit_mode=on
[leadv2-dispatch-code] worker_spawned by=router model=freepool task=1fb0c568 attempt=1fb0c568-1789057059-78484 handle=260910-191755-627824083b9b-50fb
[leadv2-dispatch-code] model_select_telemetry task=1fb0c568 role=worker class=light work_kind=docs arm=freepool … terminal=win cause=worker_spawned
```
Worker fate (honest): the freepool account stalled — its stream shows only `init` + 3 `api_retry` events in ~40 min (`error:"unknown"`, backoff to 2.4s, max_retries=300). Worse, MY spawn leaked lane env into the child: worker journal `cwd` = MY leadv2 worktree (`LEADV2_WRITE_ROOT`/`LEADV2_LANE_WORK_ROOT` inherited from this session), not getmany. I killed the whole chain (product-close 5833, supervise, run_child ×3, the `claude -p` 86576); `pgrep -f freepool-runs/260910-191755` → NONE. Residue: the confirmed ledger row for task 1fb0c568 stands by design (one task = one model; recovery path is `--resume-lane 1fb0c568`); the active.yaml row names my session pid and self-cleans when this session exits. getmany tree: clean at commit 42d453c, zero worker writes (it never woke). Lesson: dispatching from inside a lane session must scrub `LEADV2_WRITE_ROOT`/`LEADV2_LANE_WORK_ROOT` (`env -u …`) or the worker lands in the caller's worktree.

## 4. Codex run (legal, policy-routed)

Build-door analysis (measured, not assumed): with `fit_mode=on`, glm (capability 4, cost 1) ties codex-terra (capability 4, cost 4) on fit and beats it on price for every build dispatch while glm is uncapped — founder order GLM-DOES-ANY-WORK-01. The LEGAL codex lane in this repo is the REVIEW door: `glm_policy: review_arm_order: [codex, opus, sonnet]`, `review_arm_exclusions: [kimi, glm]` (founder 2026-09-03: glm OUT of review) — the close pipeline resolves its review with `--job review --base-arm codex` (leadv2-dispatch-product-close.sh:644). No arm pinned, no exclusion-list edits.

Measured прогон — the review-pool resolver exactly as product-close calls it (leadv2-dispatch-product-close.sh:644-648: `--job review --base-arm codex --review-pool --author <arm> --signals <json>`), against THAT repo's own `.claude/ref/leadv2-routing.yaml`:
```
$ python3 …/lib/leadv2-glm-policy-resolve.py --routing-yaml .claude/ref/leadv2-routing.yaml \
    --job review --base-arm codex --review-pool --author freepool --signals '{"protected_path":false,"lanes":[]}'
arm=codex
rule=none
reason=base_arm_default
tier=standard
codex_quota_blocked=0
reviewer=codex
pool=codex:ok:47,opus:unknown:quota_checked,sonnet:unknown:quota_checked
refusal=
```
→ the arbiter TAKES codex for review work in that repo, quota not blocked (util 47). Not run: a live codex review body — it was to ride the worker's close, and the worker stalled before producing a diff (see §3). No config, no pin, no exclusion-list edit was made anywhere.

## 5. persona-engine untouched

```
$ git -C ~/Projects/persona-engine status --porcelain
 M docs/leadv2/open-threads.md        # mtime 19:26:50 — its own live sessions (8 in intake)
 M docs/leadv2/soak-watchlist.md      # mtime 18:25:35
 M docs/tasks.yaml                    # mtime 19:23:02
```
All three are runtime-state files written by persona-engine's own running sessions; my only calls there were read-only (ls/grep/cat/git status). One-copy `--check` (which covers persona-engine) is green — see §1.

## 6. Self-check

- `bash -n` on both new hook symlinks (through the symlink): `SYNTAX-OK`.
- `settings.json`: `JSON-VALID` after edit.
- No shell/python files changed in leadv2 (lane diff is docs/handoff/w-getmany-parity/report.md only) → no `bash -n`/`py_compile` targets there; falsification for the getmany side is in §2 (SYNTAX-OK / JSON-VALID).

## 7. Changed-scope runner (after lane commit f97914af)

Lane diff is docs-only (report.md); docs map to no suite:
```
$ tests/run-all.sh --scope changed   (rc=0)
[CORE-OFFLINE] scope=changed running 0 of 95 suites (base=main@491a7c1ab0, 0 changed files, 0 unmapped)
[CORE-OFFLINE] suites passed=0 failed=0 missing=0 verdict=nothing_to_run reason=no_relevant_changed_files
run-all: 4 passed, 0 failed, scope=changed
```
4 = always-on tail, green. Range is NOT degenerate: base 491a7c1a → HEAD contains the lane anchor + report.md; docs simply select nothing.
