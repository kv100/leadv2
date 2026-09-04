verdict: APPROVE
next_action: review_round_2

# TWO-SLOTS-COLLAPSE-INTO-ONE-ACCOUNT-01 — developer completion report

## Starting point

This lane's worker died mid-task (parent session exit, ~17:54Z) and the lead rescued the
uncommitted diff verbatim as `wip(...): rescue uncommitted lane work after worker death`
(commit 209981be). I read that commit and judged it rather than trusting it, per the resume
note. Verdict: the implementation was substantially complete and largely correct. What I
kept, what I fixed, and what I verified follow.

## What I kept from the rescued commit (unchanged, verified correct)

- `plugins/leadv2/scripts/leadv2-claude-profile-select.sh`: `derive_identity` tuple extended
  with `account_uuid`, `org_uuid`, `cred_digest12` (brief §2d). The same-account detection was
  already extracted into `detect_same_account()` — the brief's stated precondition (§4) was
  already satisfied by the rescued work, not something I had to do.
- `detect_same_account()`: keys on `accountUuid` first, falls back to `<sub>/<email>` only when
  a uuid is unresolved on either side. On a hit it writes the alarm file, sets
  `SAME_ACCOUNT_HIT=1`, and the caller prints `profile=- reason=same_account` + exit 0 instead
  of continuing to probe (brief §2a). The existing warn is email-free (`sub=... account=..tail`
  only, brief §2e).
- Alarm file (`write_alarm`/`clear_alarm`, brief §2b): atomic `mktemp`+`mv` write, `rm -f` clear,
  fields are `kind/labels/account_uuid_tail/sub/detected_at/remedy_dir` — no email, no digest of
  a token.
- `plugins/leadv2/scripts/leadv2-claude-account-check.sh` (new, brief §3): matches the spec's
  exact output shape (`slot=... dir_hash=... account=..tail org=..tail sub=... tier=... cred=...`
  / `VERDICT: TWO_BUCKETS accounts=N creds=N|unavailable(no-keychain)`), exit codes 0/1/2 exactly
  as specified, keychain-less fallback guarded by `command -v "$SECURITY_BIN"` so a missing
  keychain alone never forces exit 2, bash 3.2 parallel-array style matching the selector.
- `plugins/leadv2/hooks/leadv2-claude-account-alarm.sh` (new, brief §2c): SessionStart hook,
  reads both registry slots' `.claude.json` directly (no keychain, no alarm-file dependency —
  correctly independent per the brief), emits the **nested**
  `hookSpecificOutput.additionalContext` shape (a top-level `additionalContext` would be a
  silent no-op, brief was explicit about this and the rescued code got it right).
- Wired into `plugins/leadv2/hooks/hooks.json` using the existing `rc<=2` pass-through +
  `LEADV2_DEGRADE_LOG` wrapper idiom, matching every other SessionStart hook in the file.
- `test-claude-account-check.sh` (new, 5 fixtures: two distinct accounts, collapsed accounts,
  unreadable `.claude.json`, no-keychain fallback, keychain-present digest) and
  `test-claude-profile-select.sh` extended with T14/T14a-e/T21/T21a-c for same-account
  refusal — all present and passing.
- `nc-claude-account-collapse.sh` / `nc-claude-account-check.sh`: modeled on
  `nc-claude-profile-select.sh` exactly as the brief instructed, including the
  `NC-SETUP-FAIL` guard (fails loudly if the target line's shape ever changes instead of
  silently mutating nothing).
- `run-core-offline.sh:424`: `test-claude-account-check.sh` registered in the same shape as the
  existing `:423` row.

## What I fixed

1. **Runtime-state drift (repeated 3x).** The rescued commit touched 9 `docs/leadv2/*`
   symlinks (`.bus-offsets`, `.bus.lock`, `.merge.lock`, `active.yaml`, `active.yaml.lock`,
   `bus.jsonl`, `merge-queue.jsonl`, `open-threads.md`, `questions`) — these are symlinks to a
   shared state directory whose *target* path drifts as a side effect of running any leadv2
   command/test-suite in this repo (multiple other lanes are concurrently active in this
   worktree's git history per the session's active-task list). This violates the DoD gate's
   runtime-state-path constraint. I reverted them from `main` in a standalone commit, and they
   drifted twice more mid-session from concurrent activity outside my control — reverted each
   time immediately before finalizing. `docs/LEAD_V2_STATE.md` drifted once the same way and was
   reverted too. None of these are part of this lane's actual diff (confirmed via
   `git diff --stat main...HEAD`, three dots, run after each revert).
2. **False "branched early" deletions ruled out.** `git diff --stat main..HEAD` (two dots)
   showed ~10 unrelated files being deleted/changed because `main` has advanced far past this
   branch's merge-base. `git diff --diff-filter=D --name-only main...HEAD` (three dots, the
   correct comparison) returned empty — no genuine deletions from this lane. Nothing restored
   was actually needed beyond the symlink drift above.

## Verification (all commands run in this worktree)

### bash -n syntax
All 7 changed/added shell files: `leadv2-claude-profile-select.sh`,
`leadv2-claude-account-check.sh`, `leadv2-claude-account-alarm.sh`,
`test-claude-account-check.sh`, `nc-claude-account-check.sh`,
`nc-claude-account-collapse.sh`, `test-claude-profile-select.sh` — all `OK`.

No `.py` files were changed by this lane (only inline `python3 -c` heredocs inside the shell
scripts, unchanged in interface); `py_compile` N/A.

### Suite baselines (green)

```
=== test-claude-account-check.sh ===
[TEST] Results: PASS=15 FAIL=0
RC=0

=== test-claude-profile-select.sh ===
[TEST] Results: PASS=73 FAIL=0
RC=0
```

### Negative controls — via `leadv2-mutation-control.sh` (not hand-asserted prose)

Per the brief's explicit instruction ("artifacts produced via the existing
plugins/leadv2/scripts/leadv2-mutation-control.sh") I additionally ran the canonical mutation
tool against both NC targets, in a scratch snapshot (never the lane tree), producing real
artifacts under `docs/handoff/dispatch-54e6f32d/mutation-control/`:

**NC1 — `detect_same_account()` in the selector**, mutation
`if (( same )); then` → `if (( same )) && [[ "X" == "Y" ]]; then` (always-false, inside the
function body):
```
suite=plugins/leadv2/scripts/tests/test-claude-profile-select.sh
file=plugins/leadv2/scripts/leadv2-claude-profile-select.sh
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: T14a: same_account warn is email-free (no accountUuid in fixture -> unresolved) -- no match for 'WARN: same_account label=same1 label=same2 sub=team account=unresolved' in:
```
Full mutated run: 65 PASS / 8 FAIL (T14b/c/d and T21a/b/c also went red, as expected — the
whole same-account refusal path lost its signal).

**NC2 — `verdict()` in `leadv2-claude-account-check.sh`**, mutation forces the collapse-guard
comparison to always-true→always-false pairing so it never detects a match (inside the
function body):
```
suite=plugins/leadv2/scripts/tests/test-claude-account-check.sh
file=plugins/leadv2/scripts/leadv2-claude-account-check.sh
baseline_rc=0
mutated_rc=1
red_line=[TEST] FAIL: T2a: collapse verdict names both labels + uuid tail -- no match for '^VERDICT: ONE_BUCKET collapsed=\[personal,work\] account=\.\.red999$' in: slot=personal dir_hash=af35f62b account=..red999 org=.. sub=team tier=default_claude_max_5x cred=fe4b30ab33f0
```
Full mutated run: 13 PASS / 2 FAIL (T2a and its exit-code check).

(Per brief instruction, `diff_hash` is not cited as evidence — it is present in both artifact
files but proves only that a mutation diff was non-empty, not that it was the intended one.)

I additionally kept and ran the repo's own `nc-claude-account-collapse.sh` /
`nc-claude-account-check.sh` scripts (modeled on the precedent `nc-claude-profile-select.sh`,
which itself does inline `sed` + `NC-SETUP-FAIL`, not a `leadv2-mutation-control.sh` call) —
same result, `NC-PASS` on both, and they self-clean their scratch copies (verified no leftover
`.nc-mutated-*` files and suites re-confirmed green immediately after).

### CI selection proof

```
$ LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh --scope changed
[SELECT] .../plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] .../tests/test-status-surface-bash32.sh
[SELECT] .../tests/test-status-surface-single-lead.sh
[SELECT] .../tests/test-status-surface-fast-names.sh
run-all: 4 selected, scope=changed, select_only=1
```
`run-core-offline.sh` is selected (always-on core runner, as the brief predicted — "already
selected, no EXTRA_SUITE_MAP row needed"), and it runs both
`test-claude-profile-select.sh` (line 423) and the new `test-claude-account-check.sh`
(line 424) internally.

## What I deliberately left alone

- The nightly single-profile fallback (`:245-253`→now shifted, `refuse_all_expired`) and the
  expiry predicate — owned by `CLAUDE-PROFILE-DEFAULT-TOKEN-EXPIRED-01`, confirmed untouched by
  diffing `leadv2-claude-profile-select.sh` against `main` line-by-line.
- `leadv2-dispatch-code.sh`, `lib/leadv2-route-arbiter.sh` — not touched, per off-limits.
- `tests/known-red-suites.txt` — not touched.
- No commit to `main`; all work is on this lane branch.
- Quota scoring, `lib/leadv2-claude-profile-pick.py`, the orphan keychain service, SwiftBar
  surfacing — all explicitly out of scope per brief §6, untouched.

## Credential-safety check

Grepped all new/changed output paths (warn lines, alarm file, check script stdout, hook
context string) for token-shaped strings (`sk-ant`, `accessToken`, `refreshToken`) across every
test run above — zero matches (`T1d`, `T5b`, `T11k-leak`, `T11k-leak2`, `T19b` assert this
directly in the suites; also spot-checked manually in the raw mutation-control run output).

DELIVERABLE_COMPLETE
