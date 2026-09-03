# Architect prepass — Mission A (retire 3 statically-unwired scripts)

TASK_ID: dispatch-6f1dded5-architect · authored 2026-08-23T02:31:33Z · repo `~/Projects/leadv2`

No `context.yaml` exists for this task (`docs/handoff/dispatch-6f1dded5-architect/` contains only
`architect.stream.jsonl` + `sessions.map`), so there are no `decisions[]`/`off_limits[]` to honour
beyond the mission's own Off-limits block. MD-02 noted.

---

## 0. VERDICT UP FRONT — the mission's premise is false for 2 of the 3 targets

The mission asserts "all three files still exist, still have **zero production callers**" and
instructs: *"If ANY live caller turns up, STOP and report it — do not delete."* Live callers turned
up. Design against the code, not the framing:

| Target | Mission's claim | What the tree says |
|---|---|---|
| `leadv2-wiki-query.sh` | unwired, zero callers | **WIRED** — `~/.claude/settings.json:269` `UserPromptSubmit` hook, `timeout: 15`, user-level ⇒ fires on **every prompt in every project** |
| `leadv2-cache-warm.sh` | only ref is a test | **Required to exist** by persona-engine's repo-native `leadv2-preflight.sh` at 4 sites (`:40`, `:73`, `:187`, `:205`) — `test -x` + `bash -n` |
| `leadv2-wiki-index.sh` | unwired, zero callers | **Confirmed unwired** — no hook, no settings entry, no curated list, no caller |

And, orthogonal to all three: **both consumer repos symlink these files into this working tree.**
`git rm` here deletes the target inode of 6 live symlinks.

The mission's search scope (`hooks.json`, docs, marketplace manifests, `leadv2-plugin-sync.sh`) is
the reason it missed this: the wiring is in `~/.claude/settings.json`, not in the plugin manifest,
and the file-existence dependency is in a *repo-native* script in another repo. The audit finding
(`codex-findings.md §Q5`) is correct as stated — these are unwired **from `plugins/leadv2/hooks/hooks.json`** — but hooks.json is not the only wiring surface in this system.

**Recommendation: split the mission.** Delete `leadv2-wiki-index.sh` now (173 LOC, genuinely dead).
`leadv2-wiki-query.sh` and `leadv2-cache-warm.sh` require an unwire-then-delete sequence that
touches files outside this repo (`~/.claude/settings.json`, persona-engine's `leadv2-preflight.sh`)
— i.e. founder-owned surfaces, not a plugin-repo lane. Full sequencing in §5.

---

## 1. CALLERS / CALLEES

### 1.1 `plugins/leadv2/scripts/leadv2-wiki-query.sh` (172 LOC, last touched `29372e6` 2026-07-29)

**Callers (all copies, all paths):**

| Site | Kind | Live? |
|---|---|---|
| `~/.claude/settings.json:269` → `~/.claude/scripts/leadv2-wiki-query.sh`, `UserPromptSubmit`, `timeout:15` | user-level hook, applies to all 3 repos | **LIVE, every prompt** |
| `~/Projects/persona-engine/.claude/scripts/leadv2-wiki-query.sh` | symlink → this repo's file | live path, no invoker found |
| `~/Projects/respiro-ios/.claude/scripts/leadv2-wiki-query.sh` | symlink → this repo's file | live path, no invoker found |
| `~/.claude/leadv2-shared/scripts/leadv2-wiki-query.sh` | **real file**, byte-identical to canonical (one-copy drift, flagged by this session's SessionStart hook) | reachable via each repo's `.claude/leadv2/` dir-symlink |
| `~/.claude/plugins/local/leadv2/plugins/leadv2/scripts/leadv2-wiki-query.sh` | plugin **cache** copy (mtime Jul 29) | separate inode by design |
| `~/Projects/respiro-ios/.claude/settings.json.bak-20260818T115857:166` | backup file | dead |
| `~/Projects/respiro-ios/.claude/scripts-vendor-backup-20260728T090301Z/` | vendor backup | dead |
| `plugins/leadv2/hooks/hooks.json` | **absent** (verified: `grep -n wiki hooks.json` → 0 hits; `UserPromptSubmit` manifest starts at `:92`) | n/a |

**Note the inode split that matters:** `~/.claude/scripts/leadv2-wiki-query.sh` is a **real file**
(`-rwxr-xr-x`, 5769 B, Jul 29 04:04), *not* a symlink into this repo. So `git rm` here does **not**
break the live hook — it orphans it. The hook keeps firing against a copy with no upstream source.
That is worse than either alternative: the script survives with no version control and no owner.

**Callees:** `python3` (inline heredoc, `:73`), `sqlite3` via the DB at `~/.claude/leadv2-wiki/wiki.db`,
`lv2_mktemp_file` from `plugins/leadv2/scripts/leadv2-temp.sh` (`:35`), `/tmp/leadv2-wiki-query.log` (`:126`).

### 1.2 `plugins/leadv2/scripts/leadv2-cache-warm.sh` (193 LOC, last touched `0e02a4f` 2026-07-21)

| Site | Kind | Live? |
|---|---|---|
| `~/Projects/persona-engine/.claude/scripts/leadv2-preflight.sh:40,73` — `test -x "$PROJECT_ROOT/.claude/scripts/leadv2-cache-warm.sh"` | repo-native preflight, "Scripts executable" + "R6 scripts executable" blocks | **LIVE — existence dependency** |
| same file `:187` (`R6 scripts executable`), `:205` (`R6 scripts bash -n`) | same | **LIVE** |
| `plugins/leadv2/scripts/tests/test-hook-token-mode-isolation.sh:11` | `CACHE_WARM=` assignment | in-repo test |
| same test `:57` | `bash -n "$CACHE_WARM"` inside a 6-way `&&` chain feeding `pass "hook/cache scripts parse"` | in-repo test |
| same test `:175-182` | executes it, asserts `status: skipped_unsupported` + `next_spawn_cache_hit_expected: false` | in-repo test |
| persona-engine + respiro-ios `.claude/scripts/leadv2-cache-warm.sh` | symlinks → this repo's file | live path |
| `~/.claude/leadv2-shared/scripts/leadv2-cache-warm.sh` | real file, identical (drift) | reachable |
| `~/.claude/scripts/leadv2-cache-warm.sh` | real file, 7051 B Jul 21 (drift) | no invoker found |
| `~/Projects/persona-engine/.claude/ref/leadv2-main-model.yaml:40`, `.claude/ref/leadv2-cache-prefix-audit.md:47,60`, `docs/leadv2-context.md:232,241`, `docs/leadv2-opus-mode.md:57,83` | prose/config comments naming the path | doc references, several in stale worktrees |
| `plugins/leadv2/skills/leadv2-build/SKILL.md:103`, `docs/audits/LEADV2-PLUGIN-AUDIT-2026-07-22.md:119` | prose, no path | harmless, leave |

**The mission named 1 of the 3 in-repo test sites.** Lines 11 and 57 are not in the mission text.
Deleting only the `175-182` block leaves `CACHE_WARM` assigned at `:11` and `bash -n`'d at `:57`,
which makes `pass "hook/cache scripts parse"` fail — a green suite turns red on the *next* run, not
this one, because `set -euo pipefail` + `bash -n` on a missing file returns non-zero into the `if`,
taking the `fail` branch, and the file's final `(( FAIL == 0 ))` exits 1.

**Callees:** `curl` to the Anthropic messages API (guarded), `jq`, `/tmp/leadv2-cache/` prefix files.
Guard at `:46` — `[[ "${LEADV2_LEGACY_API_CACHE_WARM:-0}" != "1" ]]` → early no-op exit.

### 1.3 `plugins/leadv2/scripts/leadv2-wiki-index.sh` (173 LOC, last touched `29372e6` 2026-07-29)

**No caller of any kind.** Verified: no `hooks.json` entry, no `settings.json` entry in
`~/.claude/settings.json` or either project's, no curated list in `leadv2-plugin-sync.sh`
(that file contains zero occurrences of `wiki` or `cache-warm`), not in persona-engine's preflight
lists. Only the symlink pair + the two drifted real copies + vendor backups. Its own header comment
at `:9` claims "used by PostToolUse:Write hook" — that hook does not exist. **This one is safe to delete.**

**Callees:** `sqlite3` (`:24`, `:49`), inline `python3` (`:61`), `~/.claude/leadv2-wiki/wiki.db`.

---

## 2. STATES AND RETURN CODES

### 2.1 `leadv2-wiki-query.sh` as invoked by the live `UserPromptSubmit` hook

| State | rc | What the caller (Claude Code hook runner) does | User-visible consequence |
|---|---|---|---|
| `LEADV2_WIKI_INJECT != 1` (**current: `0` in all 3 settings files** — `~/.claude/settings.json:9`, persona-engine `:69`, respiro-ios `:15`) | 0, prints `{}` | empty JSON ⇒ nothing injected | nothing; ~10 ms per prompt |
| flag `=1`, DB absent (`:29`) | 0, `{}` | nothing injected | nothing |
| flag `=1`, DB present, 0 hits | 0, `{}` | nothing injected | nothing |
| flag `=1`, hits > 0 | 0, JSON with context | prompt gains wiki excerpts | extra context in the prompt |
| **file deleted at `~/.claude/scripts/`** | 127 (`command not found`) | Claude Code surfaces a hook failure line | **every prompt in every project prints a hook-not-found error, forever** |
| file deleted **only in this repo** (the proposed `git rm`) | unchanged (0) | hook still runs the drifted real copy | nothing user-visible — and that is the trap: the change looks safe and silently strands an untracked script on a live path |
| script exceeds `timeout: 15` | hook killed | prompt proceeds | ≤15 s stall on that prompt |

### 2.2 `leadv2-cache-warm.sh` as invoked by persona-engine `leadv2-preflight.sh`

| State | `test -x` rc | `bash -n` rc | Preflight behaviour | User-visible consequence |
|---|---|---|---|---|
| file present (today) | 0 | 0 | `✓ leadv2-cache-warm.sh` ×4 | preflight green |
| **symlink dangling after `git rm` here** | 1 | 1 (`No such file or directory`) | `check` marks FAIL ×4 | **`leadv2-preflight.sh` in persona-engine reports 4 failures and a non-zero summary — the founder running preflight before a dispatch sees a red environment and cannot tell whether the environment is broken or merely stale** |

### 2.3 `leadv2-cache-warm.sh` as invoked by `test-hook-token-mode-isolation.sh`

| State | rc | Test behaviour | Consequence |
|---|---|---|---|
| present, `LEADV2_LEGACY_API_CACHE_WARM` unset | 0, stdout contains `status: skipped_unsupported` | `pass` ×2 | suite green |
| deleted, test untouched (`:11`,`:57`,`:175`) | `:57` `bash -n` → 1; `:177` `$(…)` → 127 under `set -e` | script aborts at `:177` **before** printing the `Results: PASS=… FAIL=…` line | **the test file exits non-zero with no results line — the suite runner sees a failure with no diagnosis** |
| deleted, only `:175-182` removed (mission's instruction as written) | `:57` → 1 | `fail "hook/cache scripts parse"`, `FAIL=1`, final `(( FAIL == 0 ))` → exit 1 | **one named test failure in a 209-file suite** |
| deleted, all 3 sites removed (this design) | n/a | 5-way `bash -n` chain, behavioural block gone | suite green |

### 2.4 `leadv2-wiki-index.sh`

No caller ⇒ no rc reaches anything. Deleting it changes no observable state. The only downstream
artifact is `~/.claude/leadv2-wiki/wiki.db`, which becomes unwritable-by-anything; it is already
unread because `LEADV2_WIKI_INJECT=0` everywhere. **Out of scope:** do not delete the DB.

---

## 3. CONFIGURATION BOUNDARIES

### 3.1 `LEADV2_WIKI_INJECT` (read at `leadv2-wiki-query.sh:22`)

| Input | Behaviour | Assessment |
|---|---|---|
| absent | `${LEADV2_WIKI_INJECT:-0}` → `0` → no-op exit 0 | correct fail-closed |
| empty string | `""` != `"1"` → no-op | correct |
| `0` (**current, all 3 settings files**) | no-op | correct |
| `1` | full FTS5 path runs | the only active mode |
| `true` / `yes` / `01` / ` 1 ` | != `"1"` → **silently no-op** | fail-closed but silent; a founder setting `true` would get no injection and no warning. Not a defect worth fixing in a deletion mission |
| any value, DB missing | no-op (`:29`) | correct |

Blast radius if malformed: **bounded to this hook.** Bad value ⇒ no injection ⇒ prompt proceeds
normally. It cannot take down more than its own operation. ✅

### 3.2 `LEADV2_LEGACY_API_CACHE_WARM` (read at `leadv2-cache-warm.sh:46`)

| Input | Behaviour |
|---|---|
| absent / empty / `0` | early exit, prints `status: skipped_unsupported`, zero network, rc 0 |
| `1` | `log_warn` + experimental Anthropic API call with `ANTHROPIC_API_KEY` |
| anything else | no-op |

Set nowhere in any `settings.json` (grep across `~/.claude/settings.json` and both project settings:
zero hits). The `=1` branch is unreachable in normal operation. Blast radius: bounded. ✅

### 3.3 Inputs to the deletion itself

| Input | absent | empty | min | over-cap | malformed |
|---|---|---|---|---|---|
| `docs/handoff/SCRIPT-SIZE-AUDIT-20260821/removed-scripts.md` | **absent today** — directory has `brief.md`, `codex-findings.md`, `cost-estimate.yaml`, `mission-a-unwired.md`, `mission-b-trace.md`. Implementer must create it (marked `(to-create)`) | n/a | one row | n/a | free-form md; no parser reads it, so malformation costs only readability |
| `plugins/leadv2/scripts/tests/` | 209 `.sh` files present | n/a | n/a | full-suite run is minutes, not seconds — budget for it | a pre-existing red test must be recorded as **pre-existing**, not attributed to this change. Capture a baseline run *before* the deletion |
| the 6 consumer symlinks | they exist and are unconditional | n/a | n/a | n/a | after `git rm` they dangle — `ls -la` shows the target in red, `test -x` returns 1 |

---

## 4. COUNTEREXAMPLE

*After every finding in this mission is fixed, what can still violate the invariant "no script is
deleted while something still runs it"?*

Two things, and neither is closed by any census this mission can run inside `~/Projects/leadv2`.
**First, the one-copy drift.** `~/.claude/scripts/` and `~/.claude/leadv2-shared/scripts/` hold
real, byte-identical, untracked copies of all three scripts (verified with `diff -q`: `identical`
for each; verified with `[ -L ]`: not symlinks). The live `UserPromptSubmit` hook resolves to the
`~/.claude/scripts/` copy, so **a `git rm` in this repo removes the versioned original and leaves
the actually-executed file in place, untracked**. Every future census of this repo will then
correctly report "no such script" while the script keeps running on every prompt — the deletion
makes the system *less* auditable, not more. The mission's `git revert` escape hatch does not help,
because the thing still running was never in git's view. Second, **`grep` over paths cannot see
dynamic dispatch**: a caller that builds a script name (`"$SCRIPTS/leadv2-${kind}-query.sh"`) or a
`settings.json` that is generated at session start is invisible to a literal-name census. I did not
find such a construction for these three names, but I checked by reading only the sites that a
literal grep surfaced, so absence here is weaker evidence than presence was. The honest boundary:
`leadv2-wiki-index.sh` I am confident is dead (no hook manifest, no settings entry, no curated list,
no test, header claims a hook that does not exist); for the other two I found live callers, so the
question of what *else* might call them is moot — they should not be deleted in this lane at all.

---

## 5. DESIGN — what to change, exactly

### 5.1 Scope decision

| Target | Action this lane | Rationale |
|---|---|---|
| `leadv2-wiki-index.sh` | **DELETE** (`git rm`) | zero callers, verified 4 ways |
| `leadv2-cache-warm.sh` | **DO NOT DELETE** — report to founder | persona-engine preflight requires its existence ×4; unwiring that is a persona-engine repo-native change, outside this repo's scope and outside the mission's Off-limits allowance |
| `leadv2-wiki-query.sh` | **DO NOT DELETE** — report to founder | live user-level `UserPromptSubmit` hook; deleting the tracked copy strands the untracked one |

This is the mission's own step-1 instruction (`If ANY live caller turns up, STOP and report it`)
applied literally. Net LOC removed this lane: **173, not 538.**

### 5.2 Changes for `leadv2-wiki-index.sh`

1. `git rm plugins/leadv2/scripts/leadv2-wiki-index.sh`
2. Create `docs/handoff/SCRIPT-SIZE-AUDIT-20260821/removed-scripts.md` with one row:
   path · LOC (173) · last commit (`29372e6`, 2026-07-29, *fix(wiki): derive PROJECT_ROOT from git
   instead of hardcoding persona-engine*) · verbatim census commands + output · revert instruction.
3. Same file, a **"Deferred — live callers found"** section recording the two blocked targets with
   their caller table from §1, so the next lane does not re-derive it.
4. Repair the two dangling consumer symlinks:
   `~/Projects/persona-engine/.claude/scripts/leadv2-wiki-index.sh` and
   `~/Projects/respiro-ios/.claude/scripts/leadv2-wiki-index.sh` → `rm` the symlink in each repo.
   These are symlinks in *other* repos; per the Writable-scope rule the implementer must **not**
   write them. Emit instead:
   `LEAD_ACTION: rm two dangling symlinks — <persona-engine>/.claude/scripts/leadv2-wiki-index.sh, <respiro-ios>/.claude/scripts/leadv2-wiki-index.sh`
5. Same for the two untracked real copies (`~/.claude/scripts/leadv2-wiki-index.sh`,
   `~/.claude/leadv2-shared/scripts/leadv2-wiki-index.sh`) — `LEAD_ACTION`, not a direct write.
   These are shared trees; global CLAUDE.md forbids editing them without explicit founder say-so.
6. `bash -n` on nothing (no surviving file is edited for this target).

### 5.3 Changes to the test file — **only if** the founder later approves deleting `leadv2-cache-warm.sh`

Not part of this lane. Recorded here so the follow-up lane does not miss two of three sites:
`tests/test-hook-token-mode-isolation.sh` (last commit `f15c8ee`) needs **three** edits, not one —
drop `:11` (`CACHE_WARM=`), drop `&& bash -n "$CACHE_WARM"` from the chain at `:57` (leaving a
5-way chain and its `pass "hook/cache scripts parse"` intact — the file also covers anchor,
user-prompt-context, mode-isolation, tool-counter and hardbans-reinject, so **keep the file**), and
drop the `:175-182` block including its comment. Mission step 3's "if that test also covers
unrelated behaviour, keep the file" resolves to: keep it.

### 5.4 Sequencing for the two blocked targets (founder decision required)

`leadv2-wiki-query.sh`: (a) remove the `UserPromptSubmit` block at `~/.claude/settings.json:256-265`;
(b) `rm ~/.claude/scripts/leadv2-wiki-query.sh` and the `leadv2-shared` copy; (c) restart affected
sessions; (d) *then* `git rm` here. Steps (a)–(c) are outside this repo.
`leadv2-cache-warm.sh`: (a) remove the 4 list entries in persona-engine's repo-native
`leadv2-preflight.sh`; (b) drop the 3 test sites here; (c) then `git rm`. Step (a) is a
persona-engine change.

### 5.5 Non-goals (explicit)

- No touching `~/.claude/leadv2-wiki/wiki.db`.
- No touching `leadv2-plugin-sync.sh` — verified it contains **zero** occurrences of `wiki` or
  `cache-warm`; mission step 4 is a no-op.
- No touching `plugins/leadv2/skills/leadv2-build/SKILL.md:103` or
  `docs/audits/LEADV2-PLUGIN-AUDIT-2026-07-22.md:119` — prose, no path dependency.
- No touching the semantic-recall / eval-harness / memory-backup mechanisms.
- No fixing the one-copy drift generally — it is a systemic issue (this session's SessionStart hook
  reported ~dozens of regressed files) and belongs in its own task, not in a 173-line deletion.
- No refactor of `test-hook-token-mode-isolation.sh` beyond the surgical removals in §5.3.
- No copies of plugin files created in any project repo.

### 5.6 Risks and mitigations

| Risk | Mitigation |
|---|---|
| Test suite has pre-existing failures, misattributed to this change | Run the full suite **before** the `git rm` and record the baseline pass/fail counts verbatim; report both runs |
| Dangling symlinks in 2 other repos after deletion | Enumerate them in the deliverable as `LEAD_ACTION:`; never write them from this lane |
| Implementer follows the mission verbatim and deletes all 3 | This design is the authority on scope; the mission's own step-1 STOP clause backs it |
| Untracked `~/.claude` copies survive and silently keep running | Named explicitly in `removed-scripts.md` so a future census reads the truth |

---

## 6. Census commands run (verbatim, for the implementer to reproduce)

```
grep -rn --exclude-dir=.git -E "leadv2-(cache-warm|wiki-index|wiki-query)" .
grep -rn -E "cache-warm|wiki" plugins/leadv2/scripts/leadv2-plugin-sync.sh          # 0 hits
grep -n -E "cache-warm|wiki" plugins/leadv2/hooks/hooks.json                        # 0 hits
grep -rn --exclude-dir=.git -E "cache-warm|wiki-index|wiki-query|CACHE_WARM" ~/Projects/persona-engine/.claude ~/Projects/respiro-ios/.claude
grep -rn -E "cache-warm|wiki-index|wiki-query" ~/.claude/leadv2-shared ~/.claude/agents-shared
grep -n -E "wiki-query|wiki-index|cache-warm" ~/.claude/settings.json <repo>/.claude/settings.json   # ~/.claude/settings.json:269
grep -rn "LEADV2_WIKI_INJECT\|LEADV2_LEGACY_API_CACHE_WARM" ~/.claude/settings.json ~/Projects/*/.claude/settings.json
[ -L <path> ] existence/symlink probe over the 3 names × {leadv2-shared, ~/.claude/scripts, persona-engine, respiro-ios}
diff -q ~/.claude/leadv2-shared/scripts/<f> plugins/leadv2/scripts/<f>              # identical ×3
git log -1 --format='%h %ad %s' --date=short -- plugins/leadv2/scripts/<f>
```

---

acceptance:
  - surface: file_artifact
    observable: "`docs/handoff/SCRIPT-SIZE-AUDIT-20260821/removed-scripts.md` opens to a table whose first row reads `plugins/leadv2/scripts/leadv2-wiki-index.sh | 173 | 29372e6 | 2026-07-29`, and a section headed 'Deferred — live callers found' naming leadv2-wiki-query.sh and leadv2-cache-warm.sh with the settings.json line and the preflight line that call them."
    authored_at: 2026-08-23T02:31:33Z
  - surface: file_artifact
    observable: "Opening `plugins/leadv2/scripts/` in a file browser shows no entry named `leadv2-wiki-index.sh`, while `leadv2-wiki-query.sh` and `leadv2-cache-warm.sh` are both still present."
    authored_at: 2026-08-23T02:31:33Z
  - surface: rendered_line
    observable: "The mission report's test section shows two full-suite runs — one taken before the deletion and one after — with identical pass and fail counts, so a reader can see the deletion changed no test outcome."
    authored_at: 2026-08-23T02:31:33Z
  - surface: log_line
    observable: "The mission report carries a line beginning `LEAD_ACTION:` naming the four residual copies of leadv2-wiki-index.sh outside this repo (two symlinks in persona-engine and respiro-ios, two real files under ~/.claude) that the lead must clear."
    authored_at: 2026-08-23T02:31:33Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-wiki-index.sh

DELIVERABLE_COMPLETE
