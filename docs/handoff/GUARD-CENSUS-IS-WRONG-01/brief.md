# GUARD-CENSUS-IS-WRONG-01 — the census shipped yesterday reports 31 false "missing", 53 false "not-wired", 39 "never-ran" that fire daily

Founder 2026-09-01: "была задача по перепроверке всех гардов, хуков — не уверен, что была выполнена
корректно. Провести аудит; что не работает — починить и понять, надо ли."
LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/GUARD-CENSUS-IS-WRONG-01`
LANE_WRITES: plugins/leadv2/scripts/leadv2-guard-census.sh,plugins/leadv2/hooks/lib/leadv2-guard-verdict.sh,plugins/leadv2/hooks/leadv2-bash-pre-dispatch.sh,plugins/leadv2/hooks/*.sh,plugins/leadv2/scripts/tests/test-guard-census.sh,plugins/leadv2/scripts/tests/fixtures/guards/**,tests/run-all.sh,docs/handoff/GUARD-CENSUS-IS-WRONG-01/
Branch from current main. Run with `LEADV2_SUITE_LOCK_DISABLE=1`.

## Measured 2026-09-01 19:08Z — `leadv2-guard-census.sh --fixtures-dir …/guards/real` on the live tree
Saved verbatim: `docs/handoff/GUARD-CENSUS-IS-WRONG-01/census-20260901.txt`.
`guards: 125 | fixtures run: 4 | fixture-proven: 4 | regressions: 0` — and then:

| state | rows | what is actually true |
|---|---|---|
| `missing` | 31 | every one has the guard name printed as `leadv2-…sh";` — the `hooks.json` parser leaves a trailing `";` on the last command of a `"command": "…; …"` chain, so the file lookup fails on a name that does not exist. All 31 files exist. |
| `not-wired` | 53 | includes `leadv2-block-bash-heredoc.sh` and `leadv2-bash-pre-dispatch.sh`'s chain, which BLOCKED the lead twice today (`[leadv2-block-bash-heredoc] Bash command is 5174 bytes…`, `[leadv2-block-fg-dispatch] BLOCKED`). Guards reached through the bash dispatcher chain (and the persona-engine repo-local `leadv2-bash-hook-dispatcher.sh`) are invisible to a parser that only reads top-level `hooks.json` entries. |
| `never-ran` | 39 | includes `leadv2-loop-detect-hook.sh`, `leadv2-model-inherit-guard.sh`, `leadv2-block-fg-agent.sh` — all fire on every relevant tool call. "never-ran" means the guard never wrote a `leadv2-guard-verdict.sh` record, and only 4 of 125 guards call that lib. The census measures adoption of its own instrumentation, not whether guards run. |
| fixture-proven | 4 | of 125. |

So the table sorts real, working guards to the "dead" top and cannot tell the founder anything. The
methodology (derive state from runtime evidence, never from source grep) is right; the evidence
collection is broken on all three inputs.

## Do
1. Parser: build the guard list by executing the same resolution the hook runner does — split
   `command` chains on `;`/`&&`/`||`, strip quotes, expand `${CLAUDE_PLUGIN_ROOT}` /
   `${CLAUDE_PROJECT_DIR}` / `~`, and FOLLOW dispatcher scripts (`leadv2-bash-pre-dispatch.sh`,
   persona-engine's `leadv2-bash-hook-dispatcher.sh`) into the guards they source or exec. Test: the 31
   `";` rows become `wired`; `block-bash-heredoc` becomes `wired` under the dispatcher.
2. Ran/fired evidence without touching 125 files: ONE runner-side record. The hook runner is
   `hooks.json` → shell, so add the verdict write in the dispatcher/wrapper layer (or a `hooks/lib`
   preamble every hook already sources) so every guard's `ran` and its exit code / `decision:` JSON
   are recorded once, centrally. A guard that never writes its own verdict still gets `ran` and
   `allow|block` from its observed exit. Adopt the existing `leadv2-guard-verdict.sh` format.
3. Fixtures: extend `fixtures/guards/real` so every BLOCKING guard (exit 2 / `decision:block`) has one
   fire-path driver — the census header must read `fixture-proven: <n>` with n ≥ the blocking-guard
   count. Log-only and inject-only hooks get a `ran` fixture, not a block fixture.
4. Founder view: two extra columns — `default` (on/off and the env flag) and `last-fired-days`; a
   final section "candidates to delete": wired guards with no `fired` in 30 days of journals AND no
   fixture, listed for the founder's decision (never auto-deleted).
5. Suite `test-guard-census.sh`: add cases for 1–4. Mutation negative control, RUN and paste red:
   reintroduce the `";` bug in the parser → the "31 become wired" case red; remove the dispatcher
   follow → `block-bash-heredoc` not-wired case red. Register in `tests/run-all.sh`.
6. Evidence in report.md: the census re-run on the live tree, full table, header line, and the
   founder "candidates to delete" list.

## Do NOT
Delete or disable any guard in this lane; change what any guard blocks; touch the beat/pulse loops
(BEAT-LOOP-ORPHANS-01) or the lane watcher (ONE-LANE-WATCH-01-R2).
