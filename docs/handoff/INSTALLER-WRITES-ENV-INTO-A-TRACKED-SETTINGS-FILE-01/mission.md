# Mission: installer must never write env config into a tracked settings file

## Goal
`leadv2-repo-install.sh` must stop appending the LEADV2_* env block (17 keys)
into `.claude/settings.json`. Redirect the write to `.claude/settings.local.json`
(git-ignored), add a hard tracked-ness guard immediately before any write, and
report which file it chose. Same env keys, same values — only the destination
and the safety of the write change. Builds on prior art already in this repo:
`docs/handoff/INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01/brief.md`
(measured incident, 2026-09-03) and the related sweep
`MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01`.

## Root cause (file:line)
Repo-wide grep for `settings.json` (plugins/, .claude/scripts/, .claude/hooks/)
finds exactly ONE writer; `settings.local.json` has ZERO writers today.
- `plugins/leadv2/scripts/leadv2-repo-install.sh` — canonical, step "5.
  settings.json env": header `:342`, `env_py()` `:343-390`. Hardcoded target
  `:375 p=pathlib.Path(repo)/".claude/settings.json"` →
  `:385 p.write_text(json.dumps(d,...))`. No `git ls-files --error-unmatch` or
  any tracked-check anywhere before that write. (The file's only `check-ignore`
  hits, `:272-296`, belong to an unrelated phase-gate/.gitignore guard — do not
  conflate the two.)
- `env_py`'s "missing" computation reads ONLY `settings.json`'s `env` — no
  awareness of `settings.local.json`.
- Every adopted repo's `<repo>/.claude/scripts/leadv2-repo-install.sh` is a
  **symlink** to this canonical file (verified for persona-engine and
  `~/MythicalGames/m3`), so one fix here propagates everywhere except leadv2's
  own repo, whose local copy is a real, drifted file (11606B vs canonical
  19840B/432 lines) — pre-existing, unrelated drift, flagged in Out of scope.

## Current damage (probed 2026-09-03)
| Repo | settings.json tracked? | LEADV2_ in tracked file? | Notes |
|---|---|---|---|
| persona-engine | YES | YES, incl. absolute paths (`CLAUDE_PLUGIN_ROOT`, `LEADV2_PROJECT_ROOT` = `/Users/kostiantyn.vlasenko/...`) | Already shipped to every clone. Report only, do not fix here. |
| `~/MythicalGames/m3` (employer repo) | YES | NO (0 keys) | **Live landmine.** `--check` today: `MISSING — 17 key(s)`. Per prior brief.md this already fired for real (`M .claude/settings.json +21 lines`) and was hand-reverted; nothing stops a repeat since the installer still targets settings.json. `.claude/settings.local.json` already exists there (hand-placed) but is invisible to `env_py`. |
| `~/Projects/m3-market` | N/A | N/A | Path does not exist. No git repo literally named `m3-market` exists; `~/MythicalGames/m3-market` is a plain non-git dir (contains unrelated debris, not investigated further). The actual protected repo is `~/MythicalGames/m3`, covered above — this is a naming mismatch in the task ask, flag to founder. |
| leadv2 (own repo) | NO (681B, never `git add`ed) | N/A | Not damaged, incidentally. |
| environment-platform, mondia-portal, mp-frontend, mythical-aii, pf3-backend, pf3-local-dev, pf3-smart-contracts | NO (untracked) | N/A (block present on disk, uncommitted) | Near-miss: one `git add -A` from shipping, same failure mode as persona-engine. Self-heals once the fixed installer next runs there. |
| Other `~/MythicalGames/*` (m3-promo, m3-trait, mondia-portal-bbva, pf3-digest-*, wt-*, worktrees/) | not probed | unknown | No top-level `.git` dir (worktrees/unadopted); out of this lane's budget, fast-follow census only. |

## Files allowlist
- reads: `plugins/leadv2/scripts/leadv2-repo-install.sh`, `docs/handoff/WAVE4/shared-constraints.md`, `docs/handoff/INSTALLER-WRITES-ENV-INTO-A-TRACKED-SETTINGS-FILE-01/brief.md`
- writes: `plugins/leadv2/scripts/leadv2-repo-install.sh`; new `plugins/leadv2/scripts/lib/leadv2-settings-guard.sh` (to-create); new `tests/test-installer-settings-guard.sh` (to-create); `tests/run-all.sh` (register the new suite)
- off_limits: `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh` (shared-constraints.md), `tests/known-red-suites.txt`, `main` branch, anything under `~/MythicalGames/*` (read-only fixtures/probes only — never write or commit there), persona-engine's and m3's already-damaged tracked `settings.json` (report only)

## Steps
1. New sourceable lib `plugins/leadv2/scripts/lib/leadv2-settings-guard.sh`,
   one pure predicate: `leadv2_path_is_tracked(repo, relpath)` — exit 0 if
   `git -C "$repo" ls-files --error-unmatch -- "$relpath"` succeeds (tracked),
   exit 1 otherwise. No globals, no side effects — independently testable and
   sourceable by both the installer and the suite (mirrors the existing
   `GUARD_LIB`/`plugin_script_classify` sourcing idiom already at `:281-283`).
2. In `env_py()`: compute `missing` against the UNION of `settings.json.env`
   and `settings.local.json.env` (both optional). Prevents re-nagging
   already-damaged repos and duplicating onto repos with a hand-placed
   `settings.local.json` (m3).
3. Move the write target to `.claude/settings.local.json`. Read-modify-write:
   parse existing file if present (`{}` if absent), ADD only keys missing from
   the union in step 2, never overwrite a key already there, never touch other
   top-level keys (permissions, hooks, ...). `settings.json` is never opened
   for writing anywhere in this function after the fix.
4. Immediately before that write, call
   `leadv2_path_is_tracked "$REPO" ".claude/settings.local.json"`. If tracked:
   print one loud stderr line naming repo + path, write nothing, exit the
   WHOLE script non-zero (not just this row) — defense-in-depth; should never
   fire given step 3, but must be loud if it ever does.
5. Report the destination: the `row ".claude/settings.json env" ...` output
   line must name whichever file actually received the keys (`settings.local.json`
   in the normal case) so a reader of the install log sees where it landed.
6. `.claude/settings.local.json` ignore state: check
   `git -C "$REPO" check-ignore -q .claude/settings.local.json` first (reuse
   the `gate_ignored`-style idiom at `:284-296`, do not reimplement). Already
   true today for leadv2/persona-engine (global `core.excludesFile`) and m3
   (own tracked `.gitignore:63`). If not ignored: append to
   `.git/info/exclude` ONLY — never a tracked `.gitignore`, never a commit, in
   ANY repo (simpler as a universal rule than branching by owner).
7. Register `tests/test-installer-settings-guard.sh` in `tests/run-all.sh`
   (`EXTRA_SUITE_MAP`-style row) and prove `--scope changed` selects it on a
   diff touching `leadv2-repo-install.sh`.
8. Concurrency: steps 2-4's read-modify-write is not atomic (rare race, two
   sessions on the same repo); low risk, self-correcting via the next
   `--check` — note it in the function header, no lock needed. Commit in this
   lane before handing back (shared-constraints.md).

## Acceptance commands (re-runnable, scratch repo under /tmp)
```
SCRATCH=/tmp/leadv2-installer-guard-test && rm -rf "$SCRATCH" && mkdir -p "$SCRATCH/.claude"
git -C "$SCRATCH" init -q && git -C "$SCRATCH" config user.email t@t && git -C "$SCRATCH" config user.name t

# (a) guard predicate vs a TRACKED settings.json fixture — expect exit=0, file untouched
echo '{"env":{}}' > "$SCRATCH/.claude/settings.json"
git -C "$SCRATCH" add .claude/settings.json && git -C "$SCRATCH" commit -qm fixture
SHA_BEFORE=$(shasum -a 256 "$SCRATCH/.claude/settings.json" | awk '{print $1}')
( . plugins/leadv2/scripts/lib/leadv2-settings-guard.sh && leadv2_path_is_tracked "$SCRATCH" .claude/settings.json ); echo "exit=$?"
SHA_AFTER=$(shasum -a 256 "$SCRATCH/.claude/settings.json" | awk '{print $1}')
[ "$SHA_BEFORE" = "$SHA_AFTER" ] && echo "byte-identical: pass"

# (b) full installer — env lands in settings.local.json, untracked
bash plugins/leadv2/scripts/leadv2-repo-install.sh --quiet "$SCRATCH"
git -C "$SCRATCH" ls-files --error-unmatch .claude/settings.local.json 2>&1; echo "exit=$? (expect 1)"
grep -c LEADV2_ "$SCRATCH/.claude/settings.local.json"   # expect >0

# (c) idempotency — second run, no duplicate keys
K1=$(python3 -c "import json;print(len(json.load(open('$SCRATCH/.claude/settings.local.json'))['env']))")
bash plugins/leadv2/scripts/leadv2-repo-install.sh --quiet "$SCRATCH"
K2=$(python3 -c "import json;print(len(json.load(open('$SCRATCH/.claude/settings.local.json'))['env']))")
[ "$K1" = "$K2" ] && echo "no duplication: pass"
```

## Negative control
Suite: new `tests/test-installer-settings-guard.sh` (`ls tests/` confirms no
existing suite covers this; style sibling: `test-lane-worktree-isolation.sh`).
Mutation: inside the BODY of `leadv2_path_is_tracked()` — replace the `git
ls-files --error-unmatch` line with `return 1` ("always untracked"), never a
top-level insert. Run acceptance (a): exit code must flip 0→1 — assert on the
exit code, not the byte-diff (trivially identical either way, the guard never
writes). RED with the mutation, GREEN after revert; record both exit codes
verbatim (shared-constraints.md).

## Out of scope
- Migrating EXISTING state in persona-engine / m3 / the 7 near-miss repos —
  installer fix only. Damaged repos (persona-engine) need a human-approved
  follow-up PR; the 7 untracked near-misses self-heal on next install run.
- The unprobed `~/MythicalGames/*` entries (m3-promo, m3-trait, wt-*, ...) —
  fast-follow census, not a fix.
- leadv2's own drifted `.claude/scripts/leadv2-repo-install.sh` — separate
  drift-cleanup task; its own `--check` will now report it.
- What `~/MythicalGames/m3-market` actually is — flag to founder, do not dig
  further here.
- Any change to which env keys are installed (the `want` dict contents).
