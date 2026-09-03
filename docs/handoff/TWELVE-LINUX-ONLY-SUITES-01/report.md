# TWELVE-LINUX-ONLY-SUITES-01 — report

Twelve core-offline suites that were green on macOS and red on Linux CI
(run 33706523661, commit 815627a7). All twelve now pass on Linux (verified
in an ubuntu:24.04 container replicating the CI package set) and still pass
on macOS. Nothing was added to `tests/known-red-suites.txt`; no assertion
was weakened.

## Root-cause groups (7, not 12)

**A. BSD-first `stat -f %m ... || stat -c %Y ...` mtime idiom (9 suites).**
On GNU coreutils `stat -f` means "report on the filesystem": it exits 1 but
prints a multi-line filesystem dump **to stdout**, which `$( )` captures
*before* the `|| stat -c` fallback appends the real epoch. The polluted value
then either dies in arithmetic (`File: unbound variable` under `set -u`) or
fails `^[0-9]+$` guards → `read-error:worktree-stat-failed`. Fixed by an OS
switch: `[[ "$(uname -s)" == "Darwin" ]] && stat -f %m f || stat -c %Y f`.
Sites: `leadv2-phase8-assert.sh:72` (Phase-8 task schema),
`leadv2-worktree-protected.sh` (sweeper lane-safety), `glm-coder.sh` /
`freepool-coder.sh` perms+mtime (T14), `leadv2-status-surface.sh:223` +
`test-plugin-sync-contracts-gate.sh:89,100` (sync contracts), plus the same
idiom fixed repo-wide in `codex-task.sh`, `codex-guard.sh`, `kimi-coder.sh`,
`leadv2-event.sh`, `leadv2-fork-session.sh`, `leadv2-lane-status-line.sh`,
`leadv2-lane-watch.sh`, `leadv2-limits-refresh.sh`, `leadv2-portable-lock.sh`,
`leadv2-state-purge.sh`, `leadv2-freepool-model-select.sh`,
`leadv2-guard-census.sh` (`stat -f %Sm` branch made OS-conditional),
`leadv2-backlog-pump.sh`, `leadv2-archive-old-tasks.sh`,
`leadv2-dispatch-code.sh`, `leadv2-dispatch-product-close.sh`,
`leadv2-tmux-status.sh`, `leadv2-auto-clear-after-close.sh` and three test
files — all the same single transform.

**B. `mktemp -t name` without XXXX (status surface single-lead + census).**
GNU mktemp refuses templates with fewer than 3 trailing X. `leadv2-status-surface.5s.sh:331`
grew a `.XXXXXX` suffix; every downstream assertion was failing on this one line.

**C. `date -r <epoch>` is BSD-only (plugin reliability).**
GNU `date -r` takes a *file*. `test-plugin-reliability-01.sh:359` now branches:
`date -d "@$ts"` on Linux.

**D. git ≥ 2.43: clone of a bare repo with unborn HEAD (Phase-8 merge proof).**
After `git push` to a fresh bare repo, later clones print "remote HEAD refers
to nonexistent ref, unable to checkout" and produce an **empty working tree**;
the next `git commit -aqm` then dies under `set -e`. Fixture fix: `git --git-dir="$ORIGIN"
symbolic-ref HEAD refs/heads/main` after the first push (3 scenarios in
`test-deploy-merge-blocker-gate.sh`).

**E. PATH masking removes `bash`/`sleep` on merged-usr Linux (builder selfcheck).**
Ubuntu 24.04 symlinks /bin → /usr/bin, so masking the dir that holds `timeout`
also removes `bash` (test invoked bare `bash`) and `sleep` (needed by the
wrapper's no-timeout fallback). Fixed by resolving bash before masking and
shadowing `sleep` in a temp dir prepended to the masked PATH.

**F. `> /dev/stdout` re-open truncates the outer log (e2e gate arch-01 + lane root).**
`leadv2-dispatch-product-close.sh:2672` logged the e2e run to `/dev/stdout`
inside a `> e2e-gate.log` group; on Linux the inner `>` re-opens (and
truncates) the same regular file, erasing the `e2e-root:` line the tests
assert. Now the timeout wrapper writes to a temp file that is `cat`ed back
into the real log; rc preserved.

**G. Burn-governor dispatch tests were not hermetic (burn governor).**
Tests 14–18 run dispatch past the burn gate; the route arbiter then consults
the **live** quota endpoints. On a developer mac these resolve; on CI every
window is unknown → `all_arms_capped` → rc=4 instead of 0. The tests now stub
`LEADV2_ROUTE_ARBITER_QUOTA_LIVE` / `LEADV2_QUOTA_LIVE` / `LEADV2_ROUTE_ARBITER_FREEPOOL_GATE`
with an all-ok fixture; expected verdicts unchanged.

**H. `claude` CLI unavailable on Linux (plugin manifest/components).**
The only validation seam is `claude plugin validate`. On ubuntu-latest the
CLI does not exist, so `validate_plugin` failed. It now SKIPs cleanly with a
stated reason (the `test-status-surface-bash32.sh` pattern): prints
`[CORE-OFFLINE] SKIP: ... claude CLI unavailable on this platform` and exits 0
on Linux; on any machine with the CLI the real validation still runs,
unchanged. Not allow-listed.

## Negative controls (mutation → red, revert → green)

Each fix was reverted to its broken form in an ubuntu:24.04 container; the
affected suite went red, then green again after revert:

| Group | Mutation | Suite | mutated rc |
|---|---|---|---|
| A | restore `stat -f \|\| stat -c` both sites | test-worktree-lane-safety.sh | 1 |
| B | `mktemp -t leadv2-ss-err` (no XXXX) | test-status-surface-single-lead.sh | 1 |
| C | `date -r "${old_ts}"` | test-plugin-reliability-01.sh | 1 |
| D | drop `symbolic-ref HEAD` | test-deploy-merge-blocker-gate.sh | 1 |
| E | drop the `sleep` shadow | test-builder-selfcheck-gate.sh | 1 |
| F | restore `/dev/stdout` logfile | test-e2e-gate-arch-01.sh | 1 |
| G | drop quota-live seam stubs | test-burn-governor.sh | 1 |

(H's red side is the CI run itself: "claude CLI unavailable; manifest
validation cannot run" → FAILED at commit 815627a7.)

## Verification — Linux (ubuntu:24.04 container, CI-equivalent packages: jq shellcheck sqlite3 git python3 python3-yaml curl rsync), exit codes

    worktree-lane-safety   rc=0
    phase8-schema          rc=0
    phase8-merge           rc=0
    t14-worker-mcp         rc=0
    builder-selfcheck      rc=0
    burn-governor          rc=0
    e2e-arch               rc=0
    e2e-lane-root          rc=0
    plugin-reliability     rc=0
    sync-contracts         rc=0
    single-lead            rc=0

## Verification — macOS (this machine), exit codes

    test-worktree-lane-safety.sh            rc=0
    test-leadv2-phase8-assert-a2-schema.sh  rc=0
    test-deploy-merge-blocker-gate.sh       rc=0
    test-t14-worker-mcp.sh                  rc=0
    test-builder-selfcheck-gate.sh          rc=0
    test-burn-governor.sh                   rc=0
    test-e2e-gate-arch-01.sh                rc=0
    test-e2e-gate-lane-root.sh              rc=0
    test-plugin-reliability-01.sh           rc=0
    test-plugin-sync-contracts-gate.sh      rc=0
    test-status-surface-single-lead.sh      rc=0

`bash -n` clean on every changed .sh; no Python files changed. The
authoritative proof remains the CI run on the merge of this lane: a local
macOS pass is exactly what created this situation.
