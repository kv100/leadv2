verdict: APPROVE
next_action: deploy

# developer.full.md — CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01 (dispatch-ca26c56e)

## Starting state (per RESUME NOTE)

This lane had already been rescued twice by the lead after worker deaths:
- `243191c6` — rescue of uncommitted lane work
- `bfc51f22` — second rescue
- `1cbfbdfc` — a real fix found and committed on review: registered
  `test-claude-profile-select.sh` in `tests/run-all.sh`'s `EXTRA_SUITE_MAP` so
  `--scope changed` picks it up when `leadv2-claude-profile-select.sh` changes
  (the suite's name lacks the `leadv2-` prefix, so the generic stem match
  never reached it; `run-core-offline.sh` already ran it unconditionally, so
  full/offline runs were never blind — only the fast changed-scope path was).

My job this round was to **judge, not rebuild**: verify the rescued diff is
actually correct and complete against the brief's acceptance criteria, not
assume the commit messages are honest.

## What I verified (no further code changes were needed)

Read the full diff `main...HEAD` for
`plugins/leadv2/scripts/leadv2-claude-profile-select.sh`,
`plugins/leadv2/scripts/tests/{test,nc}-claude-profile-select.sh`, and
`tests/run-all.sh`. Confirmed against context.yaml's acceptance list and the
brief's §3/§5 spec, all present and correct:

- `keychain_service_for_dir()` — pure python3 `sha256(config_dir)[:8]` hash,
  no shasum/sha256sum dependency, bash-3.2 safe.
- `derive_identity()` extended tuple: `<sub>\t<email>\t<expiresAt|->\t
  <refreshTokenExpiresAt|->\t<has_refresh:0|1>\t<cj_ok>\t<cred_ok>` — boolean
  `has_refresh` only, never the token value.
- `credential_health()` extracted as its own function (0=refreshable /
  1=unrefreshable / 2=unreadable), predicate keyed on `refreshToken` presence
  + `refreshTokenExpiresAt` vs now — `expiresAt` (access-token) never
  consulted.
- Default-slot resolution order: `file:$default_dir/.credentials.json` →
  `keychain:<suffixed-service>` → `keychain:"Claude Code-credentials"`
  (legacy last resort), each keychain attempt guarded by
  `command -v "$SECURITY_BIN"`.
- Warns renamed: `default_token_expired`→`default_token_unrefreshable`,
  `token_expired`→`token_unrefreshable`; `default_token_absent` unchanged;
  `reason=all_expired` stdout token byte-identical (verified: grep shows no
  other caller-side change).
- Registry loop uses `credential_health()` instead of a raw `expiresAt`
  compare.
- Test suite re-pointed per the brief's table: T12/T13/T17 corrected, T17c/
  T17d/T17e added (dead-refresh, dead-refresh-window, suffixed-before-legacy
  keychain ordering), T18 unchanged, T11k-style leak assertions present on
  the new T17c/T17d/T17e paths.
- `nc-claude-profile-select.sh` NC2 arm added, mutation lands **inside**
  `credential_health()`'s body (verified by reading the python heredoc that
  builds the mutated scratch copy — it patches the `rexp` line to `exp`
  in-place inside the function, never at file top level). Confirms D6.

## Falsification set run this round (fresh, not reused from commit messages)

All commands run from the worktree root
`/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01`.

**Syntax check, every changed shell file:**
```
bash -n plugins/leadv2/scripts/leadv2-claude-profile-select.sh   -> OK
bash -n plugins/leadv2/scripts/tests/nc-claude-profile-select.sh -> OK
bash -n plugins/leadv2/scripts/tests/test-claude-profile-select.sh -> OK
bash -n tests/run-all.sh -> OK
```
No `.py` files changed (the derived-identity/hash logic lives in python
heredocs inside the `.sh` files, exercised live by the suite below).

**Suite, macOS (this host):**
```
$ bash plugins/leadv2/scripts/tests/test-claude-profile-select.sh
...
[TEST] Results: PASS=80 FAIL=0
```
Exit code 0 (no FAIL lines, `set -e`-free harness reports FAIL=0 with 80/80
passing).

**Negative control, macOS — both arms, mutation only ever inside the function
body:**
```
$ bash plugins/leadv2/scripts/tests/nc-claude-profile-select.sh
--- NC: running suite against mutated selector (...) ---
[TEST] Results: PASS=73 FAIL=7
--- NC: suite exit=1 ---
NC-PASS: suite went red against the broken selector, as required
--- NC2: running suite against mutated selector (...) ---
[TEST] Results: PASS=77 FAIL=3
--- NC2: suite exit=1 ---
NC-PASS: suite went red against the credential_health() expiresAt-regression mutation, as required
```
`nc-claude-profile-select.sh` never mutates the real source file — it sed/
python-patches a scratch copy (`$SCRIPTS_ROOT/.nc*-mutated-...sh`, removed on
EXIT trap) and points `LEADV2_TEST_SELECT_BIN` at it, so there is no
mutate/revert cycle needed on the tracked file: baseline (green, PASS=80
FAIL=0, exit 0, shown above) and both red arms (exit 1 each) together are the
full red/green pair, on the untouched source. Confirmed `git status` before
and after this run shows the source file unmodified.

**Same suite + same NC, Linux container** (`bash:5`, Alpine-based, no
`security` binary — exercises the `command -v "$SECURITY_BIN"` guard path,
i.e. the keychain-less host case the brief calls out in §3):
```
docker run --rm -v "$(pwd)":/repo -w /repo/plugins/leadv2/scripts/tests bash:5 sh -c '
  apk add --no-cache python3 util-linux >/dev/null 2>&1
  bash test-claude-profile-select.sh
'
[TEST] Results: PASS=80 FAIL=0   EXIT=0

docker run ... bash nc-claude-profile-select.sh
[TEST] Results: PASS=73 FAIL=7  --- NC: suite exit=1 --- NC-PASS
[TEST] Results: PASS=77 FAIL=3  --- NC2: suite exit=1 --- NC-PASS
EXIT=0   (wrapper itself exits 0 because both arms went red as required)
```
Note: the stock `bash:5` image is missing `uuidgen`, which five *unrelated*
Integration tests (I1/I2/I2b/I3/I7 — `claude-subsession.sh` child-process
plumbing, no relation to `credential_health()`) depend on; without it the
suite showed PASS=72 FAIL=5. Installed `util-linux` (provides `uuidgen`) and
it went green — an environment-package gap, not a defect in this diff, so I
did not touch the fixtures (RESUME NOTE: "an environment-sensitive failure is
a finding, not a test bug").

**`--scope changed` actually selects the suite** (RESUME NOTE requirement —
proved live, not just by reading the map):
```
$ printf '# nc-scope-probe\n' >> plugins/leadv2/scripts/leadv2-claude-profile-select.sh
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/test-claude-profile-select.sh
run-all: 5 selected, scope=changed, select_only=1
$ git checkout -- plugins/leadv2/scripts/leadv2-claude-profile-select.sh   # revert the harmless probe line
$ git diff --name-only HEAD | grep claude-profile-select   # empty -> REVERTED_CLEAN
```
`LEADV2_RUN_ALL_SELECT_ONLY=1` is an existing non-executing seam in
`tests/run-all.sh` built exactly for this ("Selection proof is intentionally
non-executing"). Confirmed via `git status`/`git diff` before and after that
the probe left no trace.

**`run-core-offline.sh` unconditional inclusion (brief claim, re-verified):**
```
$ grep -n "claude-profile-select" plugins/leadv2/scripts/tests/run-core-offline.sh
423:  "Claude multi-profile selector (CLAUDE-MULTIPROFILE-QUOTA-02)|||bash $TEST_DIR/test-claude-profile-select.sh"
```

**No deletions, no runtime-state touched, no known-red-suites.txt change:**
```
$ git diff --diff-filter=D --name-only main...HEAD   # empty
$ git diff --name-only main...HEAD | grep known-red-suites   # empty (count 0)
$ git status --short   # only docs/leadv2/* and docs/LEAD_V2_STATE.md modified —
                        # these are shared runtime-state files touched by the
                        # live concurrent system, not by this diff; off_limits
                        # per context.yaml, left untouched by me.
```

**Credential-leak scan on the diff itself:**
```
$ git diff main...HEAD -- <the 3 selector/test files> | grep -iE "sk-ant-oat|accessToken.*:.*\"[A-Za-z0-9_-]{20,}"
+  printf '{"claudeAiOauth":{"accessToken":"sk-ant-should-never-be-read", ...
```
That one hit is a test fixture literal (proves the leak-scan assertions
themselves — same pattern as the existing `sk-ant-r` doubles), not a real
credential. No other hits.

## What I kept vs. what I rewrote

Kept the entire rescued implementation verbatim — read it function by
function against the brief's §3 spec and context.yaml's acceptance list and
found no defect, no missing case, no weakened assertion, and the NC mutation
correctly placed inside the function body (D6). I made **zero code changes**
this round; the only actions taken were verification (test runs, docker
run, syntax checks) and one harmless probe-and-revert to prove the
`--scope changed` selection claim, which left no diff.

## What I deliberately left alone

Everything the brief and lane-scope addendum marked off-limits:
`leadv2-dispatch-code.sh`, `leadv2-ratelimit-probe.sh` and the
`rate_limit_anthropic` write path, `leadv2-route-arbiter.sh`,
`claude-subsession.sh` (read-only reference, unchanged), `docs/leadv2/**`,
`docs/LEAD_V2_STATE.md`, `tests/known-red-suites.txt`, and `main`.

## Commit state

All relevant work is already committed on this lane branch (`1cbfbdfc` is
HEAD, includes the run-all.sh registration fix; the selector/test/NC files
were committed in the earlier rescue commits `243191c6`/`bfc51f22`). Nothing
new to commit — working tree is clean apart from shared runtime-state files
(`docs/leadv2/*`, `docs/LEAD_V2_STATE.md`) that are off-limits and touched by
the live concurrent orchestrator process, not by me.

DELIVERABLE_COMPLETE
