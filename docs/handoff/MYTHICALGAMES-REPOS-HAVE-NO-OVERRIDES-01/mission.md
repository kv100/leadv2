# Mission: MYTHICALGAMES-REPOS-HAVE-NO-OVERRIDES-01 — scaffold leadv2 overrides for 8 employer repos

## ABSOLUTE CONSTRAINT — read first, verbatim, binding on every step below

> Never run `git commit`, `git add`, `git push`, or any other write to git history inside ANY
> repository under `~/MythicalGames`. They belong to the founder's employer. leadv2 configuration
> in those repos is LOCAL-ONLY: ignored via `.git/info/exclude` (which is not tracked), never via
> a committed `.gitignore`. Reading those repos is fine. Writing untracked files into them is fine
> ONLY once `.git/info/exclude` covers them. Committing is never fine.

Also binding — `docs/handoff/WAVE4/shared-constraints.md`, referenced throughout this brief: never touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` or `leadv2-claude-profile-select.sh`; never edit `tests/known-red-suites.txt`; never weaken an assertion to go green; never commit to `main` — work on the lane's own worktree branch in `~/Projects/leadv2`; `m3`'s tracked `.claude/settings.json` is separately off-limits (WAVE4 line 10) — the generator creates `.claude/leadv2-overrides/` fresh and must never touch `.claude/settings.json` in any repo.

## Goal

8 real git repos under `~/MythicalGames` are adopted into leadv2 but have no `.claude/leadv2-overrides/` tree, so `/leadv2` has no idea how to build/test/verify anything there. Build a re-runnable generator (lives in `~/Projects/leadv2`, never in a target repo) that detects each repo's stack from real files and writes a minimal, correct override tree as untracked local files, with per-repo hand-tuning layered on top.

## Repo enumeration — 8 real repos, not 28 directories

`~/MythicalGames/*/` has 28 entries; only 8 have `.git` as a **directory** (canonical checkout): `environment-platform`, `m3`, `mondia-portal`, `mp-frontend`, `mythical-aii`, `pf3-backend`, `pf3-local-dev`, `pf3-smart-contracts`. The rest are either a leadv2-state companion dir (`m3-market` — per memory `reference_m3_repo_topology`, m3-market is m3's leadv2 dir, not a repo) or **linked git worktrees** (`.git` is a *file*, not a dir): `m3-promo`, `m3-trait`, `mondia-portal-bbva`, `pf3-digest-*`, `pf3-exclude-buyer`, `pf3-matview-gate`, `pf3-offers-url`, `pf3-preview-perf`, `pf3-trait-catalog`, `wt-*`, and the literal `worktrees/` dir. Linked worktrees share the parent's `.git/info/exclude` via the common git dir — do not generate a second override tree for them. **Disambiguator the generator MUST use:** `test -d "$repo/.git"` (true = canonical repo, process it; false = worktree/companion dir, skip it). Get this wrong and a naive `ls -d */` loop silently produces ~20 duplicate/wrong trees.

## Per-repo stack table (CI-authoritative where CI exists)

| Repo | Language | Pkg mgr | Test cmd (source) | Build / Lint |
|---|---|---|---|---|
| `environment-platform` | IaC (Kustomize/ArgoCD YAML) | n/a | **none** — no CI in repo; needs human-authored check | n/a / n/a |
| `m3` | TS (Next.js/Turborepo, pnpm workspaces) | pnpm 10.34.5 (lockfile) | `pnpm --filter=main exec eslint .` — `.github/workflows/lint.yml`, only real gate (type-check `continue-on-error`). `test-quality-review.yml`/`qa-pr-review.yml` are **disabled** reusable AI-review bots (`workflow_dispatch` only), not test runners; package.json `test`/`test:e2e` exist but are NOT CI-wired | `pnpm build` (pkg.json, Vercel builds itself) / same as test |
| `mondia-portal` | TS (Next.js + Drizzle) | pnpm (lockfile; no `packageManager` field) | **none** — no CI, no `test` script | `pnpm build` (`next build`) / `pnpm lint` |
| `mp-frontend` | TS/JS (Angular) | npm (package-lock.json) | `npm run test` (Jest) — `.circleci/config.yml` `app_test` job, confirmed | `npm run build` (CI persists dist/*) / `npm run lint` (CI `app_lint`, confirmed) |
| `mythical-aii` | n/a — shell/markdown Claude-plugin repo | n/a | **none** — no CI, no app code; best proxy: `bash -n` all `.sh` | n/a / n/a |
| `pf3-backend` | Go 1.25 | go modules (go.mod) | `make ci-unit-tests` — `.circleci/config.yml`, confirmed (BDD: `make ci-bdd-tests`, separate job) | `make build-linux` (Makefile) / `make lint` (`golangci-lint`, Makefile-sourced) |
| `pf3-local-dev` | n/a — Docker Compose wrapper | n/a | **none** — wraps other pf3 services, no app tests | n/a / n/a — safe check: `docker compose config` |
| `pf3-smart-contracts` | Solidity (Foundry) | forge + `.gitmodules` | `forge test -vvv` — `.github/workflows/test.yml`, confirmed (full CI: `forge fmt --check && forge build && forge test -vvv`) | `forge build` / `forge fmt --check` |

4 repos have **no CI-run test command** (`environment-platform`, `mondia-portal`, `mythical-aii`,
`pf3-local-dev`) — a real finding, not a discovery gap. Their `verify.sh` uses the nearest safe
proxy, explicitly labeled a substitute, never presented as "the test suite."

## Override schema — required keys, allowed values, exact reader

All readers are grep/sed/awk (stack.yaml) or python3 (state-paths.yaml, codex-policy.yaml) and
**never crash on a missing file/key** — every key has a coded default. Nothing is schema-required
except the two rows marked REQUIRED below.

| File | Key(s) | Reader (file:line) | Required? | Default if absent |
|---|---|---|---|---|
| `stack.yaml` | any top-level scalar | `_lv2_stack_scalar()` — `leadv2-helpers.sh:401` | no | caller-supplied default |
| `stack.yaml` | `deploy_verify.max_age_hours` (scoped to `deploy_verify:` block) | `_lv2_deploy_verify_scoped_scalar()` — `leadv2-deploy-verify-check.sh:90-96` | no | don't rely on it — set `deploy_verify.required: false` explicitly |
| `stack.yaml` | `hot_paths` | `leadv2-collision-check.sh:58` | no | falls back to PE-specific defaults — set a real (possibly empty) list per repo |
| `stack.yaml` | file presence only | `leadv2-repo-install.sh:403-406` (`ok` / `ABSENT`) | presence checked, content not validated | — |
| `state-paths.yaml` | `dialogue_path,queue_path,lead_state_path,handoff_dir,leadv2_dir,queue_archive_dir,leadv2_tasks_dir,tasks_release_cmd` | `_lv2_load_paths()` — `leadv2-helpers.sh:123-213` | no | `docs/...` under `$LEADV2_PROJECT_ROOT`, computed even if file absent |
| `codex-policy.yaml` | `codex_enabled: true\|false` | `_lv2_codex_enabled()` — `leadv2-helpers.sh` ~208-230 | no | **false** if file missing — opt-in only |
| `deploy.sh` | executable; env `LEAD_V2_TASK_ID`/`LEAD_V2_COMMIT` in, exit 0/non-0 out | `leadv2-deploy-merge.sh:145-151` | **REQUIRED** — hard `BLOCK`+exit 1 if absent | none |
| `deploy-verify.sh` | executable, optional hook, 90s timeout | `leadv2-deploy-merge.sh:160-171` | no — absence only warns (`PRODUCER_GAP`), never blocks | omit (see Out of scope) |
| `verify.sh` | executable; allow-listed Bash the lead session runs in Phase 6/7, no fixed orchestrator caller | allow-listed at `leadv2-session-spawner.sh:78`, `leadv2-session-runner.sh:165` | no forced caller, but must exist or verify has nothing to run | none |

Exact env name is `LEAD_V2_TASK_ID` / `LEAD_V2_COMMIT` (underscore after LEAD, **not**
`LEADV2_TASK_ID`) — verified at `leadv2-deploy-merge.sh:148`. Getting this wrong is silent: the
stub just sees an empty var, no error.

## Generator design

New file (to-create): `~/Projects/leadv2/plugins/leadv2/scripts/leadv2-mythicalgames-overrides-gen.sh`
— canonical, single-source, same convention as every other `leadv2-*.sh` here. Never a copy inside
a MythicalGames repo.

- **Invocation:** no arg = auto-discover (`~/MythicalGames/*/` filtered by `test -d "$d/.git"`);
  `--repo <path>` = single repo; `--force` = overwrite (default: skip-if-exists, log
  `SKIP (exists): <path>`).
- **`detect_stack()`** — one function, repo path in, stack id out (`node-pnpm`|`node-npm`|`go`|
  `foundry`|`docker-compose-only`|`iac-only`|`shell-only`|`unknown`) via the marker files in the
  stack table; lockfile decides the package manager.
- **Emits** into `.claude/leadv2-overrides/`: `stack.yaml` (lang/ci/`deploy_method: none`/
  `deploy_verify: {required: false}`), `state-paths.yaml` (leadv2-init's own template shape,
  `plugins/leadv2/skills/leadv2-init/TEMPLATES.md` — all keys commented, defaults apply),
  `codex-policy.yaml` (`codex_enabled: false`, explicit), `deploy.sh` (NO-OP stub, chmod +x),
  `verify.sh` (stack-specific wrapper running the Test-cmd column, chmod +x). Deliberately
  **omits** `deploy-verify.sh` (Out of scope).
- **Idempotent:** default run never clobbers hand-tuning; `--force` is explicit, logged per file.

## Files allowlist

- WRITE (leadv2 repo, lane's own worktree branch): the generator script; its test suite (below);
  one appended `EXTRA_SUITE_MAP` row in `tests/run-all.sh` (shared file — append at the block's
  end per WAVE4, never reorder; a merge conflict there is expected, lead resolves it).
- WRITE (each of the 8 repos, untracked, only after `.git/info/exclude` covers the path):
  `.claude/leadv2-overrides/{stack.yaml,state-paths.yaml,codex-policy.yaml,deploy.sh,verify.sh}`
  and one appended block in `.git/info/exclude`.
- NEVER write: `.claude/settings.json` in any of the 8 (explicit for `m3`, applied to all out of
  caution); `deploy-verify.sh`; `leadv2-dispatch-code.sh`; `leadv2-claude-profile-select.sh`;
  `tests/known-red-suites.txt`; `main` branch directly.

## `.git/info/exclude` — exact lines, proof

```
# leadv2 local-only config — added by leadv2-mythicalgames-overrides-gen.sh, never committed
.claude/leadv2-overrides/
```

Append (create the file if absent — it is not gitignore, has no tracked counterpart) to
`~/MythicalGames/<repo>/.git/info/exclude`. Proof: `git -C ~/MythicalGames/<repo> status --porcelain`
must be **empty** after the tree is written. Also confirm nothing pre-existing got swept in:
`git -C ~/MythicalGames/<repo> ls-files .claude/leadv2-overrides | wc -l` must print `0` — non-zero
means a file was already tracked and the exclude alone won't hide it; stop and escalate.

## Steps

1. Implement `detect_stack()` + emitters in the generator (leadv2 repo only).
2. Write the negative-control suite against `/tmp` fixtures — RED with the mutation, GREEN
   without, before touching any real repo.
3. Add the `EXTRA_SUITE_MAP` row in `tests/run-all.sh`; prove selection with
   `tests/run-all.sh --scope changed`.
4. Dry-run against one real repo first (`pf3-backend` — richest stack signal), inspect the
   emitted tree by hand, then run (no `--force`) across all 8.
5. Per repo: append the exclude line, run the generator, run Acceptance below.
6. Report per-repo PASS/FAIL — never silently skip a repo that fails Acceptance.

## Acceptance — re-runnable, per repo (`<repo>` = one of the 8 canonical paths)

1. Tree exists: `test -f ~/MythicalGames/<repo>/.claude/leadv2-overrides/stack.yaml && echo OK`
2. Reader parses clean:
   ```bash
   LEADV2_PROJECT_ROOT=~/MythicalGames/<repo> bash -c '
     source ~/Projects/leadv2/plugins/leadv2/scripts/leadv2-helpers.sh
     _lv2_load_paths && echo "paths OK: $LEADV2_HANDOFF_DIR"
     _lv2_codex_enabled && echo "codex: enabled" || echo "codex: disabled (expected)"
     echo "lang: $(_lv2_stack_scalar lang unknown)"'
   ```
   must exit 0, print all three lines, no stderr.
3. Nothing leaked: `git -C ~/MythicalGames/<repo> status --porcelain` → empty output.
4. Verify command runs read-only: execute the repo's Test-cmd from the stack table (or its
   dry-run/`--help` form — none of the 8 need one, all listed commands are read-only); report the
   exit code verbatim. A non-zero exit on a real repo is signal (a broken test), not a mission
   failure — report it, do not paper over it.

## Negative control

Suite (to-create): `~/Projects/leadv2/plugins/leadv2/scripts/tests/test-mythicalgames-overrides-gen.sh`
— builds synthetic fixture repos under `/tmp/leadv2-fixture-repos/<name>/` (real `git init`, only
marker files: `package.json`+`pnpm-lock.yaml`, `go.mod`, `foundry.toml`, etc.) and runs the
generator against fixtures only. **Never touches `~/MythicalGames`.**

Mutation — inside `detect_stack()`'s body, not top level (e.g. flip the pnpm-lockfile branch so it
always reports `node-npm` even when `pnpm-lock.yaml` is present): apply it, run the suite → must
go RED (the pnpm fixture gets an npm-flavored `verify.sh`). Revert → GREEN. Record both exit codes
verbatim in the deliverable, per WAVE4 rule #1.

## Out of scope

- `deploy-verify.sh` for all 8 — deploy is NO-OP, nothing to verify post-deploy. Real Phase-8
  close in these repos is a separate future decision.
- `environment-platform`'s real IaC verify command (kustomize/kyverno) — flagged, not authored;
  needs a human to name the actual overlay path.
- Wiring these repos into full `/leadv2` build-close cycles or Codex dispatch. `codex_enabled:
  false` ships as the default; turning it on per repo is a separate founder decision.
- Any change to a tracked file inside any MythicalGames repo, ever.
- Touching `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`,
  `tests/known-red-suites.txt`, or `m3`'s tracked `.claude/settings.json`.

---

**LEAD ADDENDUM — read `lead-addendum-census.md` in this directory before starting. The census in the table above is short (26 of 27 repos lack overrides, 19 are worktrees), and where the addendum disagrees with this file, the addendum wins.**
