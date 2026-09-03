# CI-SUITES-ARE-MACOS-ONLY-01 — the first CI run was red because nine suites only work on macOS

## READ THIS FIRST
- **Pulse mode does NOT apply to you.** One turn-chain, no notification will reach you. Never end a
  turn waiting for anything.
- **Never background a command whose result you need.** Foreground, `timeout 1800`.
- **Commit after every step.**
- Suite path is `tests/run-all.sh` at the repo **ROOT**. Do NOT open with a full suite run.

**Class:** Standard. **Repo:** leadv2 plugin.

## The measurement

`.github/workflows/test-suites.yml` ran for the first time ever on 2026-09-02 (run `33694115147`)
and failed. It is **not** a regression. From the run log:

```
tests/test-status-surface-fast-names.sh: line 142: /cache/labels.map: No such file or directory
FAIL - warm cache (title='⏳ leadv2 (нет кэша)')
ci-gate: scope=changed run_all_rc=1 known_red=14 unexpected=13
```

The path is `/cache/...` — an absolute path from the filesystem root. The suite builds it from
`FIX="$(mktemp -d -t leadv2-fast-names)"`. On BSD/macOS `-t` takes the string as a prefix and works.
On GNU coreutils `-t` is the deprecated no-argument form, so `leadv2-fast-names` is read as the
TEMPLATE, it contains no `XXX`, mktemp fails, `FIX` is empty, and every derived path becomes
`/cache`, `/ledgers`, `/handoff` **at the root of the filesystem**. The suite then fails on every
assertion that touches a fixture.

Census: 10 occurrences across 9 files.

```
tests/test-status-surface-bash32.sh          plugins/leadv2/scripts/tests/test-lane-close-loop.sh
tests/test-status-surface-single-lead.sh     plugins/leadv2/scripts/tests/test-status-surface.sh
tests/test-status-surface-fast-names.sh      plugins/leadv2/scripts/tests/test-close-chain.sh
tests/test-status-surface-batch01.sh         plugins/leadv2/scripts/tests/test-backlog-pump.sh
                                             plugins/leadv2/scripts/tests/test-skill-proof-gate.sh
```

## Why this matters more than its size

A CI that is red from birth teaches everyone to ignore it within a week, and required status checks
cannot be turned on until it is green — so the whole `CI-RUNS-THE-SUITES-01` feature is inert until
this is fixed. There is also a second-order hazard: on a Linux box where the runner can write to
`/`, these suites create directories at the filesystem root.

## Deliver

1. **A portable temp-dir form everywhere.** `mktemp -d "${TMPDIR:-/tmp}/<name>.XXXXXX"` works on both
   platforms. Apply it to all 10 sites.
2. **A failed `mktemp` must stop the suite, not corrupt paths.** Every one of these sites assigns
   into a variable and carries on. Add the check where the value is created — an empty or unset
   temp root is a hard error, never a path prefix. If a shared helper is the right home for that,
   say so and put it there instead of repeating a guard nine times.
3. **A guard so the BSD form cannot come back.** A grep-based check in the suite tree that fails on
   `mktemp -t` / `mktemp -d -t` without an `XXX` template. Wire it where it will actually run.
4. **Do not "fix" the 14 known-red suites.** They are allow-listed on purpose. Your job is the 13
   `unexpected` ones caused by this defect — report what remains unexpected after the fix, with
   names, and do not silence anything by adding it to the allow-list.

## Prove it
- Run one of the affected suites under a Linux-like `mktemp` before the fix → the `/cache` failure
  reproduces. Paste it. (`docker run --rm -v $PWD:/w -w /w bash:5 …` or a stub `mktemp` earlier in
  `PATH` that mimics GNU behaviour — say which you used.)
- Same suite after the fix, both on this macOS box and under the Linux-like path → green. Paste both.
- **Negative control:** restore `mktemp -d -t name` in one site inside a mktemp FULL copy whose
  baseline is proven green → the Linux-like run goes red again. Paste baseline and mutant runs.
- The new guard fires on a reintroduced BSD form and is silent on the fixed tree. Paste both.
- `tests/run-all.sh --scope changed` from the LANE ROOT at the END, FOREGROUND, `timeout 1800`.

## Constraints
LANE_WRITES: `tests/`, `plugins/leadv2/scripts/tests/`, `plugins/leadv2/scripts/lib/`, this task's
handoff dir. Never commit `docs/leadv2/`, `LEAD_V2_STATE.md`, `phases.d/`, `critic.*`.
**Do not touch `.github/workflows/`** — the workflow itself is correct; the suites are what is broken.

## Done when
All 10 sites are portable, a failed `mktemp` is a hard error, a guard prevents the regression, the
Linux-like run of the affected suites is green, and the negative control turns it red again.
