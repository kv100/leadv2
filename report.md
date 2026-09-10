# PLUGIN-SELF-SUFFICIENT-TENANTS-ONLY-DELTA-01 — report

Row `61dedbec`. Invariant shipped: **the plugin is self-sufficient from its own
tree; a tenant may supply only a declared delta.** One guard extended, no
second mechanism built.

## What changed

| File | Change |
|---|---|
| `plugins/leadv2/scripts/leadv2-one-copy-convert.sh` | ROOTS → `key\|tenant\|canonical\|scope` quadruples; project-root pairs (check-only); DIVERGED + ROTTEN-EXCEPTION gate the check; UNUSED-EXCEPTION advisory; explicit cache/worktrees prune list; per-root visibility lines with the DEAD-ROOT marker; `--apply` and the `--revert` whole-tree fallback now strictly apply-scoped |
| `plugins/leadv2/ref/one-copy-exceptions.txt` | 9 new declarations (3× diverged `ref/leadv2-main-model.yaml`, 6× identical contract copies); header documents the `project/<repo>/<subroot>/<relpath>` key shape |
| `plugins/leadv2/scripts/tests/test-one-copy-tenant-delta.sh` | NEW suite, 13 cases (registered: `# run-all-triggers: leadv2-one-copy-convert one-copy-exceptions`) |
| `plugins/leadv2/scripts/tests/test-one-copy-drift.sh` | T3 now expects exit 1 (DIVERGED gates); `LEADV2_ONE_COPY_PROJECT_ROOTS=0` for hermeticity |
| 4 tracked `.pyc` | `git rm --cached` — caches are not comparison input and not tracked content (`__pycache__/` already ignored) |

## Roots added

- **Project roots** (scope=`check`): `<repo>/.claude/{scripts,agents,ref,config,contracts}`
  for every repo in `cross-repo-paths.yaml` — persona-engine, m3-market
  (`~/MythicalGames/m3-market`), respiro-ios. Repo list is READ from the yaml
  (same registry plugin-sync uses), never hardcoded; a repo without `.claude/<sub>`
  prints a `files=0` root line — skip, never refusal.
- **Plugin roots ref/config/contracts** are covered through those pairs (canonical
  side `plugins/leadv2/<sub>`).
- **Dead root named dead**: `~/.claude/leadv2-shared/scripts` has no readers
  since 2026-09-06 (everything under it is already a symlink). Kept — plugin-sync
  (b) still produces it and `--revert` manifests key on it — but every `--check`
  run prints `[DEAD-ROOT: no readers since 2026-09-06; ...]` on its root line.
  Silently watching the empty room is no longer possible.
- **Deliberately NOT added**: `~/.claude/leadv2-shared/contracts` as a shared
  pair. plugin-sync (b) produces it by design (link-only producer + gated shadow
  refresh) and owns its drift check (`test-plugin-sync-contracts-gate.sh`);
  adding the same root here would fight the producer. Its 5 identical real
  copies are plugin-sync's domain, not undeclared tenant drift.

## The three census shadows → rule

Census re-measured this lane (relative-path match, caches excluded) — worse
than the brief knew: **all three live repos** carry the shadows, m3-market
included, and a fourth file (`leadv2-shadow-proposal.schema.json`) rides along.

| Shadow | Found | Action |
|---|---|---|
| `ref/leadv2-main-model.yaml` | diverged real copy in persona-engine, respiro-ios AND m3-market | declared `project/<repo>/ref/...`; header says: port to a `.claude/leadv2-overrides/` delta or resync by hand, then retire the line |
| `contracts/leadv2-scorecard.schema.json` | identical copy in all 3 repos | declared `project/<repo>/contracts/...`; plain `--apply` candidate (retire line → founder-run `--apply` symlinks it) |
| `contracts/leadv2-shadow-proposal.schema.json` | identical copy in all 3 repos (census addendum) | same treatment |
| `ref/leadv2-routing.yaml` | — | NOT touched (line `414e61122454` owns it) |

No shadow remains undeclared. Repo `.claude/scripts` and `.claude/agents` trees
came out fully linked (628/403/382 and 3/3/3 files) — plugin-sync did its job
there; the guard now proves it continuously.

## Acceptance fixtures (suite `test-one-copy-tenant-delta.sh`, 13/13 green)

- **A1** real copy (identical → `REGRESSION`, diverged → `DIVERGED`) in a tenant
  tree is NAMED, exit 1 — T1/T1b.
- **A2 paired** same file, one exception-list line, nothing else changed →
  `EXPECTED-OVERRIDE`, exit 0 — T2.
- **A3** `__pycache__` (and lane-`worktrees/`) copies → pruned, exit 0 — T3.
- **A4** exception line whose canonical twin is gone → `ROTTEN-EXCEPTION`, exit 1 — T4.
- Edges: tenant-only file = info not violation (T5); symlink out of canonical =
  `BADLINK` (T6); repo without `.claude/` skipped with visible `files=0` (T7);
  declared-identical = advisory only (T8); DEAD-ROOT marker printed (T9);
  UNUSED exception advisory (T10); exception naming a repo absent from the yaml
  is inert (T11).

Sibling suites stay green: `test-one-copy-drift.sh` 8/8, `test-one-copy-drift-hook-postsync.sh` 7/7.

## Live verification (read-only)

Run against a `/tmp/livegate` canonical model (subtrees symlinked to the main
checkout + this lane's script/exceptions — byte-faithful to post-merge main):

- **Green with declarations**: `rc=0`, `tally: linked=2352 regression=0 badlink=0
  expected_override=9 diverged=0 rotten_exceptions=0 unused_exceptions=3`.
- **Paired red without them** (main's old exception list): `rc=1`, naming
  exactly the 9 shadows (3 DIVERGED + 6 REGRESSION).
- The SessionStart hook stays advisory (always exit 0); its filtered report
  carries the extended tally, so a diverged/rotten-only failure can no longer
  render as "0 regression(s)".

## Mutation control (negative control, brief-mandated)

`mutation-control/20260910T121204Z-86715.txt` — mutant: exception-list
consultation removed INSIDE `cmd_check` body
(`/^cmd_check()/,/^}/ s/if is_exception .../if false; then/`). Baseline rc=0 →
mutated rc=1, red line = paired fixture T2 leaking `DIVERGED`. Exactly the
brief's "убрать сверку с файлом исключений внутри тела функции".

## Known notes

- **Worktree artifact**: running `--check` from a lane worktree flags the live
  shared/repo symlinks as BADLINK because `CANONICAL_ROOT` resolves to the
  worktree while the links point into main. Production paths (hook via
  `~/.claude/plugins/local/leadv2` symlink, humans from main) resolve to main
  and are unaffected. Live proofs above used the main-canonical model.
- The 3 legacy `agents/*.md` exception lines now report UNUSED (tenant files
  were converted to symlinks 2026-09-09). Left in place — retiring them is a
  founder-visible call, not one to smuggle into this lane; the advisory makes
  them impossible to miss.

## Falsification set

- `bash -n` on every changed shell file: convert, both suites — SYNTAX-OK.
- No Python files changed (py_compile n/a).
- `tests/run-all.sh --scope changed`: see verdict below.

`tests/run-all.sh --scope changed` → **5 passed, 1 failed (core-offline
umbrella), 0 known-red**. The red is NOT this lane's:

- Inside the same run, ALL three one-copy suites passed (`test-one-copy-drift.sh`
  8/8, `test-one-copy-tenant-delta.sh` 13/13, postsync 7/7).
- The umbrella's failing cases — `P-h(a/b/g) prompt pin line MISSING`,
  `5b no host installs its own EXIT trap`, `NEGATIVE CONTROL 1: mutated
  arbiter still passed`, `(g) live repo not found (set LEADV2_DOD_LIVE_REPO)` —
  are byte-identical in the CONCURRENT lane `414e61122454`'s core-offline run
  (foreign runner confirmed via per-pid lsof cwd, alive 15:20–15:45+ while
  this lane's run spanned 15:12–15:47; the
  core-offline-reds-under-concurrent-runners pattern). Two lanes with
  disjoint diffs producing the same failure set = shared baseline/environment
  red, not a regression from this diff. Follow-up belongs to the baseline-reds
  owner, not this row.

Red/green pair for the behavior change (the brief's mandate):

- RED (mutant, exception consultation removed inside `cmd_check`):
  `MUTATION-CONTROL ok ... red_line=FAIL: T2 ... DIVERGED` (artifact
  `mutation-control/20260910T121204Z-86715.txt`).
- GREEN (restored): `test-one-copy-tenant-delta.sh ── 13 passed, 0 failed ──`,
  `test-one-copy-drift.sh ── 8 passed, 0 failed ──`,
  `test-one-copy-drift-hook-postsync.sh ── 7 passed, 0 failed ──`,
  live gate `rc=0` (2352 linked, 9 EXPECTED-OVERRIDE) vs paired live red
  `rc=1` (exactly the 9 shadows) without the declarations.

