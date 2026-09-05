# Retro-review: leadv2 62ccd9f / 341b80a / a38a5bd

## 62ccd9f (backlog-pump cd_out) — PASS
`_lv2bp_canonical_root`: `cand=""`/`common_dir=""`/`cd_out=""` fixed the `set -u` unbound-var risk. `_tree_mid_conflict` rc contract (0=conflict,1=clean,2=probe-fail) correctly consumed in `cmd_check` (`leadv2-backlog-pump.sh:790-802`); `tree_state_rc=$?` captures the right exit code in the `else` branch. New test `test_tree_state_probe_failure` runs the real function against a real non-git fixture, not a string stub. Ran full suite pre/post on parent commit in a scratch clone: 13→14 passed, same 7 pre-existing unrelated failures both sides (`ceiling_refuses_7th`, `duplicate_signature_refused`, etc.) — commit introduces zero regressions.

## 341b80a (route-arbiter physical path) — FAIL
`readlink`-loop portable across macOS/GNU, correctly avoids `readlink -f`. **But: zero test coverage added** for the actual bug (symlink resolution under per-file installs) in any of the three touched files — `test-route-arbiter.sh` untouched, no `test-quota-live*.sh`/`test-freepool-gate*.sh` exist at all. A fix explicitly framed as "rc=65 fail-open everywhere" ships with no regression test proving fail-open is now closed. Also: identical 13-line helper copy-pasted 3× (`leadv2-route-arbiter.sh`, `leadv2-quota-live.sh`, `leadv2-freepool-gate.sh`) instead of one shared lib function — Medium, drift risk.

## a38a5bd (FP-01/FP-02) — FAIL
yaml valid (`python3 -c yaml.safe_load` OK). `_rank_candidates` role fallback is defensive (empty/missing role_rank → flat `model_rank`, never errors) — confirmed via test suite, 25/25 pass. **But FP-01's "explicit FREEPOOL_ROLE wins" branch is dead code**: grepped every caller (`leadv2-dispatch-code.sh:4471,4496`, `freepool-coder.sh`) — nobody ever exports `FREEPOOL_ROLE` before invoking `freepool-coder.sh`, so role selection lives entirely on the regex fallback in `freepool_role_for_mission` (`freepool-coder.sh:136-155`). That regex **misses real review missions**: `"you are the critic agent, find bugs"` and `"adversarial critique of the diff"` both fail to match (`review|reviewer|audit|auditor|arbiter` excludes `critic`/`critique`, the actual agent name per this repo's CLAUDE.md) and silently default to `implement`, sending review work to the wrong-tier model. Also over-matches: `"implement the code-review dashboard feature"` → misclassified as `review`. No test exercises `freepool_role_for_mission` at all — only the downstream selector with `FREEPOOL_ROLE` pre-set by hand.

**Verdict: BLOCK 341b80a and a38a5bd; APPROVE 62ccd9f.**

DELIVERABLE_COMPLETE
