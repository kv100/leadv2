# Architect prepass — PLUGIN-SYNC-CLAUDE-SCRIPTS-01

Mechanism-closed design for making `leadv2-plugin-sync.sh` section (c) keep every repo's
`.claude/scripts/` per-file-symlink-managed instead of silently materializing real copies.
**Design only — no implementation here.**

---

## 0. Measured state (2026-08-23, this machine) — three mission claims are wrong

All numbers below are `find`/`cmp` output taken this session against the live trees.
Canonical = `~/Projects/leadv2/plugins/leadv2/scripts` (205 top-level `.sh`, 20 `.py`,
1 `.mjs`, 2 `.json`, `lv2`, 1 `.tmpl`; 690 files total incl. `tests/` 247 and `lib/` 23).

| repo | `.claude/scripts` | symlinks | real files | real `leadv2-*` | of those: identical to canonical | diverging | **no canonical counterpart (repo-native)** | canonical files absent entirely |
|---|---|---|---|---|---|---|---|---|
| persona-engine | real dir, mixed | 227 | 62 | 28 | 4 | **1** (`leadv2-lane-detail.sh`) | **23** | 5 |
| respiro-ios | real dir, mixed | 173 | 69 | 50 | 21 | **22** | 7 | 22 |
| m3-market | **exists** at `~/MythicalGames/m3-market/.claude/scripts` | 158 | 101 | 61 | not measured | not measured | not measured | not measured |

Corrections to the mission's framing — the design is built against the code and the disk,
not against these claims:

1. **"28 real `leadv2-*` copies of canonical plugin scripts" in persona-engine is false.**
   28 real `leadv2-*` files exist, but **only 5 have a canonical counterpart** (4 byte-identical,
   1 diverging). The other 23 (`leadv2-telegram-bot.py`, `leadv2-rollback.sh`,
   `leadv2-preflight.sh`, `leadv2-cleanup.sh`, `leadv2-route-budget.py`, …) are **repo-native
   scripts that merely start with `leadv2-`**. Consequence for the design: **the filename prefix
   `leadv2-*` must never be the selection criterion.** The only safe criterion is *"a file of the
   same relpath exists in canonical"*. A `leadv2-*`-prefix rule would convert or clobber 23
   persona-engine-owned scripts. The mission's own verification step 2 (`find … -name 'leadv2-*'
   | wc -l` must drop) is therefore **not an acceptable acceptance signal** — that count cannot
   drop below 23 in persona-engine no matter how correct the fix is. Restated acceptance in §5.
2. **m3-market DOES have a `.claude/scripts/`** — 158 symlinks + 101 real files — but at
   `~/MythicalGames/m3-market`, while `cross-repo-paths.yaml` records
   `path: ~/Projects/m3-market`, which **does not exist** (`ls` → *No such file or directory*).
   So m3-market has been silently `WARN + skip`ped by every sync and by `leadv2-drift-guard.sh`
   (which reads the same yaml, `leadv2-drift-guard.sh:71`) for as long as that entry has been
   wrong. **Not fixed by this task**: `cross-repo-paths.yaml` is a shared tree, and the global
   rule requires founder approval before editing it. Flagged for the founder — see §6 D-3.
3. **respiro-ios is ~4× worse than persona-engine** (22 diverging canonical-named files vs 1).
   Any plan sized for "one or two drift reports" is mis-sized; the real run will print ~23 DRIFT
   lines and convert ~25 files. That is the expected, correct outcome — not a failure.

Also measured: **every existing symlink in both repos points into canonical** (0 links point
anywhere else), and **dangling links already exist** (`leadv2-supervise*.sh`,
`leadv2-status-surface.10s.sh` in persona-engine — canonical deleted them in SUPERVISOR-DELETE-01,
the links stayed). Dangling-link handling is therefore a real state, not a hypothetical (§2).

---

## 1. CALLERS / CALLEES of everything this change touches

### 1a. Functions modified

| symbol | file:line | callers | callees |
|---|---|---|---|
| `_sync_project_root()` | `plugins/leadv2/scripts/leadv2-plugin-sync.sh:452-592` | exactly one: the `(c)/(d)` loop at `:782-786` (`while IFS=$'\t' read -r proj_root proj_vendors_scripts; do _sync_project_root …`) | `_rsync_or_dry` (:504), `cp -p` for (c2) (:551) and (d) (:567) and eval-harness (:590), `log/log_warn/log_ok` |
| `_rsync_or_dry()` | `:122-138` | (a) `:607`, (b) `:629`, (c) **`:504` ← removed by this design**, (e) `:676`, (f) `:754`, (g) `:772` | `rsync`, `python3` filter, `mkdir -p` |
| `_resolve_project_roots()` | `:402-443` | `:786` (process substitution feeding the (c)/(d) loop) | `python3` + PyYAML |

**The (c) write path is not one path — it is three independent write paths into
`<repo>/.claude/scripts`, and all three must change or the defect survives:**

1. `:504` — `_rsync_or_dry "project/scripts[…]" "${src}" "${proj_scripts}" --recursive …`
   with `--exclude` per *already-existing* symlink (built at `:499-503`). A canonical file with
   **no pre-existing link** is written as a real file. *This is the mechanism behind all
   identical-copy drift.*
2. `:588-591` — the eval-harness `cp -p`, a second, independent write path guarded only by
   `[[ ! -L "${proj_scripts}/leadv2-eval-harness.sh" ]]`. If the file is a **diverging real
   file**, this `cp` overwrites it silently — exactly the "never silently overwritten" prohibition
   in the mission, on a path nobody named.
3. `:536-557` — (c2), the curated list `cp -p` into `<root>/scripts/` (top-level, a *different*
   directory). Same materialize-a-real-copy defect, different target. Its only protection is the
   same-inode skip at `:548`.

### 1b. Callers of the script itself (blast radius of any exit-code change)

| caller | file:line | how it consumes plugin-sync |
|---|---|---|
| `leadv2-plugin-sync-drift-warn.sh` (PostToolUse:Bash hook) | `plugins/leadv2/hooks/leadv2-plugin-sync-drift-warn.sh:34,43`; registered `hooks/hooks.json:491` | fires *after* any Bash command whose text matches `*leadv2-plugin-sync.sh*`; runs `leadv2-drift-guard.sh` and warns if the copies still diverge. **Ignores plugin-sync's exit code**, always exits 0. |
| `plugins/leadv2/tests/test-drift-direction-gates.sh` | `:19, :176-200, :310` | drives the script in a scratch `$HOME`/canonical fixture; asserts on **stderr text** and `bash -n`. Text of the existing REFUSED/WOULD-MOVE-BACKWARDS lines must not change. |
| `leadv2-fanout.sh:85`, `:450`; `leadv2-drift-guard.sh:231` | message text only | tell the operator to *run* plugin-sync; no invocation. |
| founder / lead, by hand | — | `bash …/leadv2-plugin-sync.sh --write` |

**No caller branches on plugin-sync's exit status.** The script today can only exit non-zero via
`set -e` or the two `exit 3` refusals (`:67`, `:82`) and the `exit 2` unknown-arg (`:101`).
**Design decision D-1: keep exit 0 for drift reports.** A drifting file is a *report*, not a
failure of the sync; the existing `_REFUSED_COUNT` convention (`:114`) already models "refused but
exit 0". Making drift fatal would abort the run before later repos are synced (the exact class of
bug `:548`'s same-inode skip was added to fix).

### 1c. Adjacent mechanisms that read the same perimeter (must stay consistent)

- `leadv2-drift-guard.sh:60-81` builds `COPY_PATHS` from the *same* `cross-repo-paths.yaml` +
  `vendors_scripts` rule and compares content. A symlinked file reads through to canonical, so
  every file this design converts becomes trivially drift-clean. No change needed there.
- `leadv2-one-copy-convert.sh:38-42` already implements exactly the classification this mission
  needs (`linked` / `REGRESSION` = identical real copy / `DIVERGED` / `BADLINK` /
  `EXPECTED-OVERRIDE` / `STALE-EXCEPTION`, `:150-196`) — **but only for two roots**:
  `~/.claude/leadv2-shared/scripts` and `~/.claude/agents-shared`. It also enumerates **the shared
  root, not canonical** (`enumerate_pairs`, `:112-125`), so **it can never create a missing link** —
  failure mode #1 in the mission is structurally invisible to it.
  **D-2: do not extend that script.** The mission's off-limits says "do not change any other
  script's behaviour"; its `--apply` path is welded to a `tar -C ~/.claude leadv2-shared
  agents-shared` backup (`:213`) and a `leadv2-lane-liveness.sh` precondition (`:129-152`) that do
  not generalize to repo roots. **Mirror its vocabulary** (`LINKED/REGRESSION→CONVERT/DIVERGED/
  BADLINK`) inside plugin-sync so the founder reads one taxonomy in two places, and cross-reference
  it in a comment.

---

## 2. STATES AND RETURN CODES

### 2a. Per-file classification — the new `_link_one_file <canonical_file> <dst_file>` helper

It prints exactly one token on stdout and returns 0 in every non-fatal case (rc is *not* the
channel; the token is). Caller `_link_project_scripts` accumulates counters per repo.

| # | state of `dst_file` | token printed | rc | write performed (`--write`) | write performed (dry-run) | what the caller does | **user-visible consequence** |
|---|---|---|---|---|---|---|---|
| S1 | absent | `LINK` | 0 | `ln -s <canonical_abs> dst` (parent `mkdir -p` only for `lib/`, `tests/`) | none, prints `WOULD LINK` | `linked++` | the script the repo was missing now exists and runs; `leadv2-status-collector.sh`'s sibling calls resolve |
| S2 | symlink, `readlink -f dst` == `readlink -f canonical` | `OK` | 0 | none | none | `ok++` | nothing — this is the idempotent steady state (2nd run prints only `OK`) |
| S3 | symlink, resolves elsewhere | `BADLINK` | 0 | **none** | none | `badlink++`, warn with both paths | founder sees a named link pointing outside canonical and decides; nothing is repointed behind their back |
| S4 | symlink, **dangling** (canonical file deleted) | `DANGLING` | 0 | **none** (never delete — off-limits) | none | `dangling++`, warn | founder sees e.g. `leadv2-supervise-loop.sh -> <deleted>` listed as removable; measured to exist today (5+ in persona-engine) |
| S5 | real file, `cmp -s` identical to canonical | `CONVERT` | 0 | atomic: `ln -s canon dst.tmp.$$ && mv -f dst.tmp.$$ dst` | none, prints `WOULD CONVERT` | `converted++` | that file stops being a second inode; a future canonical fix reaches this repo |
| S6 | real file, differs | `DRIFT` | 0 | **none** | none | `drift++`, warn with `git --no-pager diff --no-index --stat` one-liner (fallback: `<n> lines differ` via `diff \| grep -c '^[<>]'` if git absent) | founder gets `path + N files changed, +a −b` per diverging file and decides promote-or-discard; the file keeps running exactly as it is |
| S7 | dst is a **directory** where canonical has a regular file | `TYPECLASH` | 0 | none | none | `typeclash++`, warn | named and skipped; no `rm -rf`, ever |
| S8 | dst exists but is unreadable / `ln` fails (EACCES, read-only fs) | `ERROR` | 0 (token carries it) | none | none | `error++`, warn with errno text | one file named as un-syncable; **the remaining repos still sync** (see D-1) |
| S9 | canonical file itself vanished between enumeration and act | `SKIP` | 0 | none | none | `skip++` | nothing |

`set -euo pipefail` hazard: `cmp -s` returns 1 on difference and `git diff --no-index` returns 1
when files differ. Both **must** be written as `if cmp -s a b; then … fi` / `… || true`, never as a
bare statement — a bare `cmp` aborts the whole sync mid-repo under `set -e`. This is the same trap
`:548` documents for `cp`.

### 2b. Per-repo and whole-run outcomes

| state | where | rc / exit | consequence in plain words |
|---|---|---|---|
| repo root absent on disk (m3-market today) | `:455-458` | `return 0`, `WARN` | that repo is not synced at all and the run still says "Sync complete" — measured true for m3-market since the yaml entry was written |
| `.claude/scripts` **absent** | new guard | skip, `log` | **never created.** Applies to any repo, honouring "m3-market has no `.claude/scripts` — do not create one" even if the yaml path is later corrected |
| `.claude/scripts` is a whole-dir symlink | `:480-481` | skip, unchanged | reading through it already reflects canonical |
| `vendors_scripts: false` | `:483-484` | skip (c) + (c2), unchanged | opted-out repos keep a symlink-only architecture |
| canonical `scripts/` absent | `:487` guard | skip | nothing written |
| any file class S3/S4/S6/S7/S8 present | new counters | **exit still 0** (D-1) | founder reads the per-repo tally line and the named files; automation is unaffected |
| whole run | `:801-805` | 0 | summary gains one line per repo: `(c) <repo>: linked=N converted=N ok=N drift=N badlink=N dangling=N typeclash=N error=N` |

**Terminal-outcome trace for the failure this task exists to fix.** Before: S1 was not a state —
a canonical file with no pre-existing link fell into rsync's default write path, so
`leadv2-lanes-snapshot.sh` was simply absent in persona-engine; `leadv2-status-collector.sh:115`
(`bash "$_SC_DIR/leadv2-lanes-snapshot.sh" --json`, resolving siblings from
`_SC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`) exited non-zero, the collector died, and
**every founder-status beat printed "НЕ ВИЖУ ЛИНИИ" while lanes were actually running** — the board
looked empty when it was not. After: S1 creates the link on the first `--write` run, and the beat
renders the lane table.

---

## 3. CONFIGURATION BOUNDARIES

Every input the mechanism reads, at each boundary. **Bold = behaviour that must change.**

### 3a. `~/.claude/leadv2-shared/cross-repo-paths.yaml` (read at `:411-443`)

| boundary | current behaviour | required behaviour |
|---|---|---|
| absent | `log_warn` + skip (c)/(d) entirely, exit 0 (`:411-414`) | unchanged |
| present, `repos:` empty/missing | `repos = {}` → zero lines → loop body never runs → **"Sync complete" with nothing synced, exit 0** | **emit `WARN: (c)/(d): resolved 0 project roots from <config> — nothing synced`**; still exit 0 |
| **malformed YAML** | `yaml.safe_load` raises → the `python3` in the **process substitution** at `:786` dies; a failing process substitution does **not** trip `set -e`/`pipefail` in the parent → loop reads nothing → **all repos silently skipped, exit 0, log says "Sync complete"** | **materialize the roots into a variable first (`roots="$(_resolve_project_roots)" \|\| roots=""`), and if the resolver failed or produced no lines while the config file exists, `log_warn` loudly with the parser's stderr.** Same one-line WARN as above. Silent total no-op is the worst possible failure of a sync tool |
| entry `path:` empty | filtered by `if expanded:` (`:439`) | unchanged |
| entry `path:` points at a non-existent dir (**m3-market, live today**) | `log_warn` + `return 0` (`:455-458`) | unchanged behaviour, but the WARN must appear in the founder report — it is why m3-market has 61 real `leadv2-*` files nobody is syncing |
| `vendors_scripts` absent / `true` / `false` / `"false"`/`no`/`off`/`0` | `vendors_scripts_enabled` (`:422-431`) handles bool + quoted-string spellings | unchanged |
| **very large repo list** (over-cap) | linear iteration; no cap | unchanged — cost is O(repos × canonical files); see §3d |

### 3b. CLI flags / env

| input | absent | empty | minimum | maximum / over-cap | malformed |
|---|---|---|---|---|---|
| `--write` | dry run (default, `:91`) | n/a | n/a | repeated → last-wins, logged `:110` | n/a |
| `--dry-run` | dry run anyway | n/a | n/a | with `--write`, last flag wins (`:97-99`) | n/a |
| `--project-root <p>` | yaml iteration | `--project-root ""` → `PROJECT_ROOT_OVERRIDE=""` → **falls through to yaml, silently ignoring the operator's intent** | 1 root | n/a | **`--project-root` as the LAST arg → `shift` then `"$1"` under `set -u` → `$1: unbound variable`, abort.** Both should become `printf 'Unknown/invalid arg' ; exit 2` like `:101`. Small, in-mechanism, fix it here |
| `LEADV2_PROJECT_ROOT` | yaml (`:407-410`) | empty → yaml | — | — | non-existent path → per-repo WARN+skip |
| `LEADV2_CANONICAL_ROOT` | `~/Projects/leadv2` (`:78`) | → default | — | — | not a dir → `exit 3` (`:80-83`) |
| `SYNC_HYGIENE_FILTERS` | `--exclude=__pycache__/ *.pyc .DS_Store` (`:191`) | — | — | — | the new link pass must apply the **same** name filter, or it will link `.pyc`/`.DS_Store` |

### 3c. Canonical `plugins/leadv2/scripts/` as an input — the enumeration set

Today's rsync (`--recursive`, hygiene filters only) copies **the entire tree** into every repo:
690 files including `node_modules/` (17 MB, measured present in *both* repos), `docs/`, `tests/`
(247 files), `lib/` (23), `__pycache__/`, **and two junk directories created by a mis-quoted
heredoc: `plugins/leadv2/scripts/import json,sys/` and `import json,sys,collections/`**.

**D-4 — enumeration rule (closed, deterministic):** the link pass walks canonical with a
**top-level-subdirectory allowlist of `lib/` and `tests/`**, plus every top-level regular file, and
skips any name matching the hygiene filter. Everything else (`node_modules/`, `docs/`,
`__pycache__/`, `.mypy_cache/`, the two `import json,sys*` dirs, and any future junk dir) is
pruned by construction — an allowlist cannot be out-run by new debris the way a denylist can.

| boundary | behaviour |
|---|---|
| canonical top-level file that is **not** `leadv2-*` (e.g. `lv2`, `ZZ-pre-review-run.sh`, `glm-coder.sh`) | **in scope, linked.** The criterion is "exists in canonical", never the prefix (§0.1). Note this links the currently-untracked WIP `ZZ-pre-review-run.sh` into both repos; if that file should not exist, delete it in canonical — do not special-case it in the sync |
| canonical file added after the last sync | S1 on the next run — the whole point |
| canonical file **deleted** | existing repo link becomes S4 `DANGLING`: reported, never deleted (off-limits) |
| canonical subdir file (`lib/x.py`, `tests/y.sh`) | linked, parent `mkdir -p` on demand. Both repos already carry 147/46 `tests/` links, so this is the existing coverage expressed as links |
| canonical `docs/`, `node_modules/` | **narrowing vs today**: no longer copied. Existing copies in repos are left untouched (no deletes). Stated as a non-goal, §7 |
| empty canonical scripts dir | `:487` guard → nothing written |

### 3d. Scale boundary

Per repo: ~470 in-scope canonical files × (1 `readlink -f` + at most 1 `cmp`) ≈ sub-second on SSD;
`cmp -s` runs only for real files (≤101 in the worst repo). Three repos → well under 5 s. No cap
needed, and **no silent truncation anywhere** — every in-scope file yields exactly one token, and
the tally line's counters must sum to the enumerated count (assert this in the test, §5).
Contrast with today's `_rsync_or_dry` dry-run, which pipes through `head -20` (`:133`) and so
**silently hides everything past the 20th change** — the reason a founder inspecting a dry run
today cannot see the real plan. The new dry-run prints every line, unbounded.

---

## 4. THE CHANGE — exact edits

All in `plugins/leadv2/scripts/leadv2-plugin-sync.sh` unless stated.

| # | location | change |
|---|---|---|
| C1 | new helper, placed next to `_rsync_or_dry` (~`:139`) | `_link_one_file <canonical_file> <dst_file>` — the S1–S9 classifier of §2a. Pure; prints one token; honours `DRY_RUN`; `ln -s` with an **absolute** canonical target (comparison is by `readlink -f`, so pre-existing relative links still classify as S2/OK) |
| C2 | new helper below it | `_link_project_scripts <root> <dst_dir>` — enumerate canonical per D-4, call `_link_one_file` per relpath, accumulate the 9 counters, emit `WOULD LINK/WOULD CONVERT/DRIFT/BADLINK/DANGLING/TYPECLASH` lines (dry-run) or the `LINK/CONVERT/…` equivalents (write), then one tally line |
| C3 | `:486-505` | **delete the `_rsync_or_dry` call and its `_symlink_excludes` scan; call `_link_project_scripts` instead.** rsync no longer writes into any repo `.claude/scripts` — the guarantee the mission asks for is structural, not a flag |
| C4 | new guard before C3 | `[[ -d "${proj_scripts}" ]] \|\| { log "(c): ${proj_scripts} absent — not creating it"; }` → skip. Never `mkdir` a repo's `.claude/scripts` |
| C5 | `:579-591` | **delete the eval-harness `cp -p` block.** It is write path #2 into the same directory and it silently overwrites a *diverging* real file. `leadv2-eval-harness.sh` is an ordinary canonical file and is covered by C2 |
| C6 | `:538-555` | (c2): replace the `cp -p` body with `_link_one_file "${cf_src}" "${proj_scripts_toplevel}/${cf}"`. Same taxonomy, same protection, and it subsumes the same-inode special case at `:548`. The curated list, the `compgen` gate and the "never a wildcard" rule at `:509-535` stay exactly as they are |
| C7 | `:782-786` | materialize `_resolve_project_roots` output into a variable, warn on "0 roots resolved" / resolver failure (§3a) |
| C8 | `:100` | `--project-root` arg validation: missing or empty value → `exit 2` (§3b) |
| C9 | `:801-805` | summary: after "Targets touched", print the accumulated per-repo tally lines and, if any repo had `drift>0`, a final `ACTION REQUIRED: N diverging file(s) across M repo(s) — promote or discard; nothing was overwritten` |
| C10 | `plugins/leadv2/scripts/tests/test-plugin-sync-claude-scripts-linking.sh` **(to-create)** | see §5 |

Explicitly **unchanged**: `_direction_safety_excludes`, `_sync_direction_of`, `_quarantine_copy`,
`_dst_file_dirty`, the write gates, and targets (a), (b), (d), (e), (f), (g). The (c) link pass
does not need the backward/dirty gates: it **never overwrites content**. S5 replaces a file with a
link to byte-identical content; S6 writes nothing at all. That is a strictly stronger guarantee
than gates 1 and 2 provide.

---

## 5. Test design (C10) — scratch fixture, real `$HOME` never touched

Follow the containment pattern of `plugins/leadv2/tests/test-drift-direction-gates.sh:10` — a
temp canonical root via `LEADV2_CANONICAL_ROOT`, a temp repo root via `--project-root`, `TMPDIR`
cleanup on `EXIT`. Cases:

1. **missing link created** — canonical `leadv2-alpha.sh`, repo has nothing → dry run says
   `WOULD LINK` and creates nothing; `--write` → `test -L` and `readlink -f` == canonical.
2. **identical copy converted** — repo has a byte-identical real file → dry run `WOULD CONVERT`,
   file still real; `--write` → symlink, content unchanged.
3. **diverging copy preserved + reported** — repo file differs → **both** runs leave it a real
   file with its original bytes, and stderr contains its path plus a diffstat.
4. **repo-native untouched** — `leadv2-native-only.sh` with no canonical counterpart → not
   mentioned as an action, still a real file, bytes unchanged (guards the §0.1 regression).
5. **idempotency** — run `--write` twice; the second run's tally has `linked=0 converted=0` and
   `ok` equal to the enumerated count.
6. **`.claude/scripts` absent → not created** (m3-market invariant).
7. **dangling link preserved** — link to a canonical file that does not exist → reported, still
   present after the run.
8. **counter completeness** — tally counters sum to the number of enumerated canonical files.
9. `bash -n` on the modified script.

Also re-run the existing suite; `plugins/leadv2/tests/test-drift-direction-gates.sh` must still
pass unchanged (it asserts on (b)/(f) gate text this design does not touch).

---

## 6. COUNTEREXAMPLE — what still violates the invariant after every finding here is fixed

The invariant is *"one inode: a fix committed in `~/Projects/leadv2` is the fix every runtime
runs."* After this task it holds for `<repo>/.claude/scripts` and `<root>/scripts`, and it still
does **not** hold, for four reasons I can name and one I cannot rule out.

**D-3 (the big one, proven live this session).** Target (b) at `:620-632` rsyncs canonical into
`~/.claude/leadv2-shared/scripts` — a **real-copy** tree by construction, with the identical
"no pre-existing link → write a real file" mechanism. This session's own SessionStart hook printed
`[one-copy] REGRESSION: ~/.claude/leadv2-shared/scripts/leadv2-answer.sh is a real file, identical
to canonical` and the same for `leadv2-status-watch.sh`, `leadv2-resume.sh`, `leadv2-deploy-merge.sh`,
`leadv2-task-judge.sh`, `leadv2-queue-archiver.sh`, `leadv2-lane-child-suffixes.sh`,
`leadv2-status-projects.sh` (8+ named, output truncated at 2 KB). Every repo's `.claude/leadv2/`
is a *directory* symlink into that shared tree, so a stale second inode there is exactly as
load-bearing as one in `.claude/scripts` — and `leadv2-one-copy-convert.sh --apply` converts it
while the very next plugin-sync run re-materializes it. **This task does not fix that**, and
fixing it means giving (b) and (f) the same link pass. Recommend a follow-up:
`PLUGIN-SYNC-SHARED-TREE-LINKING-01`.

Three more, in decreasing severity:
- **Nothing enforces the link outside a sync run.** A `cp` (by a human, an agent, or a future
  script) re-creates a second inode at any moment, and it is only noticed the next time
  `leadv2-one-copy-drift.sh` or plugin-sync runs — and that hook's scope (`ROOTS`,
  `leadv2-one-copy-convert.sh:38-42`) does not include repo `.claude/scripts` at all, so for the
  trees this task fixes there is **no detector between syncs**. Cheapest closure: add the three
  repo roots to that hook's check-only path (deliberately out of scope here — off-limits forbids
  changing another script's behaviour).
- **m3-market is outside the perimeter entirely** (§0.2): 61 real `leadv2-*` files at a path no
  sync and no drift-guard has ever visited, because `cross-repo-paths.yaml` points at a directory
  that does not exist. This design cannot fix it without a founder-approved shared-tree edit.
- **The plugin cache (a) is a real copy on purpose** (hooks load from it; global CLAUDE.md records
  that `claude plugin update` no-ops for directory-source marketplaces). Unchanged by this task
  and correctly so, but it remains a genuine second inode for hook code.

What I checked and found *clean*: every existing symlink in persona-engine and respiro-ios resolves
into canonical (0 exceptions), so there is no third-party link target to worry about; and
`leadv2-drift-guard.sh`'s perimeter is derived from the same yaml + `vendors_scripts` rule, so it
cannot disagree with the sync about which repos are in scope.

---

## 7. Non-goals (the implementer must NOT do these)

- No deletions, anywhere, in any repo — including dangling links, `_backup-pre-sync/`,
  `*.quarantine-*` files, `node_modules/`, and stale `docs/` copies. Report only.
- No change to targets (a), (b), (d), (e), (f), (g).
- No edit to `leadv2-one-copy-convert.sh`, `leadv2-one-copy-drift.sh`, `leadv2-drift-guard.sh`,
  `hooks.json`, or any hook.
- No edit to `~/.claude/leadv2-shared/cross-repo-paths.yaml` (shared tree; founder approval
  required) — the m3-market path defect is *reported*, not fixed.
- Do not create `.claude/scripts` in any repo that lacks one.
- Do not remove the two junk canonical dirs (`import json,sys*`); the allowlist makes them
  harmless. Cleaning them is a separate one-line commit.
- Do not use a `leadv2-*` filename filter as the selection criterion (§0.1).
- No new env vars.
- No exit-code change (D-1).

---

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >-
      A founder running the sync with --dry-run against persona-engine and respiro-ios reads a
      complete, untruncated plan naming, for each repo, every file that would be newly linked,
      every real copy that would be replaced by a link, and every diverging file that would be
      left alone with the size of its difference beside it — and after that dry run the two repos
      are byte-for-byte unchanged.
    authored_at: 2026-08-23T03:05:00Z
  - surface: file_artifact
    observable: >-
      After the real run, the canonical scripts that were previously missing from
      persona-engine's and respiro-ios's .claude/scripts directories are present there and point
      at the single copy in ~/Projects/leadv2; every repo-native script that merely starts with
      "leadv2-" is still an ordinary file with its original contents; and no file anywhere was
      deleted.
    authored_at: 2026-08-23T03:05:00Z
  - surface: rendered_line
    observable: >-
      A founder-status beat run in persona-engine after the sync shows the lanes table with its
      rows, instead of "НЕ ВИЖУ ЛИНИИ".
    authored_at: 2026-08-23T03:05:00Z
  - surface: log_line
    observable: >-
      Running the real sync a second time immediately after the first produces a run in which
      nothing is reported as newly linked or converted — the founder sees only "already correct"
      counts and the same list of diverging files as before.
    authored_at: 2026-08-23T03:05:00Z
  - surface: log_line
    observable: >-
      The founder is handed a named list of the diverging files left behind (about one in
      persona-engine and about twenty-two in respiro-ios), each with how much it differs from
      canonical, and an explicit statement that none of them was overwritten.
    authored_at: 2026-08-23T03:05:00Z
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-plugin-sync.sh, plugins/leadv2/scripts/tests/test-plugin-sync-claude-scripts-linking.sh

DELIVERABLE_COMPLETE
