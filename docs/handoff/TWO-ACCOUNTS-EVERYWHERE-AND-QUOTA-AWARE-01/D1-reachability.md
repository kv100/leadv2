# D1 — Is the selector reachable from every repo? (measured 2026-09-03)

## Verdict: already true everywhere

Every repo the founder listed already has the full symlink chain wired, and the opt-in gate is
already flipped on globally. No fix is required for reachability. D2/D3 (quota-aware scoring,
visible fail-open) are the actual remaining work, as the brief anticipated.

## What "reachable" requires, and where each link lives

1. `<repo>/.claude/scripts/leadv2-dispatch-code.sh` must be the canonical dispatcher (symlink into
   `plugins/leadv2/scripts/`).
2. `leadv2-dispatch-code.sh` must call `claude-subsession.sh` for the Claude/sonnet arm — confirmed
   at `plugins/leadv2/scripts/leadv2-dispatch-code.sh:4995`
   (`SUBSESSION_BIN="${LEADV2_DISPATCH_SUBSESSION_BIN:-${SCRIPT_DIR}/claude-subsession.sh}"`).
3. `<repo>/.claude/scripts/claude-subsession.sh` must be the canonical subsession runner (symlink),
   which calls the selector at `claude-subsession.sh:440-446` inside `leadv2_select_claude_profile()`.
4. That call is gated: `[[ "${LEADV2_CLAUDE_MULTIPROFILE:-}" == "1" ]] || return 0`
   (`claude-subsession.sh:446`). This is an **opt-in env var, not a per-repo config file** — it is
   not set in any repo's `.claude/settings.json`, `.envrc`, or leadv2-overrides anywhere I could
   find (`grep -rn LEADV2_CLAUDE_MULTIPROFILE` across `~/Projects`, `~/MythicalGames`, `~/.claude`
   returns only the plugin source, its tests, and `docs/model-routing.md`).
5. It IS set — globally, for every zsh process on this machine, in `~/.zshenv:6`:
   `export LEADV2_CLAUDE_MULTIPROFILE=1`, commented "leadv2 multi-profile Claude selector
   (founder-approved 2026-08-25)". `.zshenv` is sourced by every zsh invocation (login,
   non-login, interactive, script), so every dispatcher process — regardless of which repo it
   runs in — inherits this env var from its parent shell. Live check: `env | grep
   LEADV2_CLAUDE_MULTIPROFILE` in this session → `LEADV2_CLAUDE_MULTIPROFILE=1`.

## Per-repo table

Checked: `<repo>/.claude/scripts/{leadv2-claude-profile-select.sh, claude-subsession.sh,
leadv2-dispatch-code.sh}` — all must be symlinks into `plugins/leadv2/scripts/` (canonical), not
real copies (a real copy is the drift failure mode called out in this repo's CLAUDE.md).

| repo | location | selector reachable? | evidence |
|---|---|---|---|
| persona-engine | ~/Projects | yes | all 3 files symlinked to leadv2 canonical |
| leadv2 | ~/Projects | yes (is the source) | `leadv2-claude-profile-select.sh` and `claude-subsession.sh` are the real files here (this repo IS canonical); `leadv2-dispatch-code.sh` symlinked from `plugins/leadv2/scripts/` |
| respiro-ios | ~/Projects | yes | all 3 files symlinked to leadv2 canonical |
| getmany-followup-bot | ~/Projects | yes | all 3 files symlinked to leadv2 canonical |
| getmany-crm-reports | ~/Projects | yes | all 3 files symlinked to leadv2 canonical |
| m3 | ~/MythicalGames | yes | all 3 files symlinked to leadv2 canonical |
| m3-market | ~/MythicalGames | yes | all 3 files symlinked to leadv2 canonical |
| pf3-backend | ~/MythicalGames | yes | all 3 files symlinked to leadv2 canonical |
| pf3-local-dev | ~/MythicalGames | yes | all 3 files symlinked to leadv2 canonical |
| pf3-smart-contracts | ~/MythicalGames | yes | all 3 files symlinked to leadv2 canonical |
| mp-frontend | ~/MythicalGames | yes | all 3 files symlinked to leadv2 canonical |
| mondia-portal | ~/MythicalGames | yes | all 3 files symlinked to leadv2 canonical |
| mythical-aii | ~/MythicalGames | yes | all 3 files symlinked to leadv2 canonical |
| environment-platform | ~/MythicalGames | yes | all 3 files symlinked to leadv2 canonical |

Raw evidence (`readlink` on each of the 3 files per repo) captured during this session; every
target resolved to `/Users/kostiantyn.vlasenko/Projects/leadv2/plugins/leadv2/scripts/<file>` with
no real-file drift found in any of the 13 consumer repos.

## Registry and live probe, re-measured this session

`~/.claude/state/leadv2/claude-profiles.tsv` (user-level, never committed) — 2 rows, both live:

```
personal   /Users/kostiantyn.vlasenko/.claude
work       /Users/kostiantyn.vlasenko/.claude-work
```

Live selector run this session (`LEADV2_CLAUDE_MULTIPROFILE=1 bash leadv2-claude-profile-select.sh`):

```
profile=work config_dir=/Users/kostiantyn.vlasenko/.claude-work score=24 source=live reason=worst_window candidates=2 cred=keychain:Claude Code-credentials-5a3c2328 identity=team/kostiantyn.vlasenko@mythical.games
```

`candidates=2` and `source=live` confirm both registry rows resolve to valid, distinct,
non-expired credentials right now — the founder's belief ("все ключи уже есть") is correct; no
login is missing. The 20 most recent `claude-profile.log` files across active dispatches (checked
by mtime) all show `candidates=2`, confirming this is not a one-off — routing is consistently
seeing both accounts across concurrent lanes right now, including this lane's own dispatch record
(`docs/handoff/dispatch-3494b920/claude-profile.log`: `selected=work ... candidates=2`).

## Re-measurement of the known defect (CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01)

The brief's count (198 `default_token_expired` warnings, identity `max/vkk1008k@gmail.com`) is
stale and undercounts. Re-measured this session across all `docs/handoff/*/claude-profile.log`:

```
205 total default_token_expired occurrences (91 distinct log files)
  201 x identity=max/vkk1008k@gmail.com
    4 x identity=max/kostiantyn.vlasenko@mythical.games   (all from today, incl. my own live probe)
```

So: the founder's "logged in again" did **not** clear the defect — it is still live, reproduced
live in this session's own probe (stderr: `WARN: default_token_expired
identity=max/kostiantyn.vlasenko@mythical.games -- fail-open`). This confirms
CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01 is real and current, and is exactly the inherited-default
fallback path described in the brief (`:167-170` of the selector), not either registry row — both
registry rows score fine (`candidates=2`). No credential value was printed or logged anywhere in
this investigation; `identity=` is the script's own by-design non-secret output (email/plan label,
not a token), already present verbatim in the brief's own quote.

## What this means for D2-D4

D1 found no reachability gap to fix. D2 (quota-aware scoring across both accounts' binding
windows) and D3 (loud degraded-router signal) are the whole remaining task, exactly as the brief
anticipated. D2/D3/D4 to follow in subsequent commits on this lane.
