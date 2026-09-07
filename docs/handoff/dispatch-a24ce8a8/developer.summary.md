verdict: APPROVE
next_action: review_round_2

Part A delivered: launch-capability registry (new) + quota-read.py keychain-registry filter and unmetered/unknown account-state classifier.

- `leadv2-launch-registry.py` (new): (kind,role,arm,task_class)->argv, `check(arm,model)`, CLI; opus `pool_default:false` recorded as DATA only.
- `leadv2-quota-read.py`: `_keychain_services` now intersects with the profile registry (fail-open); new `classify_account_state` distinguishes team-401-unmetered from dead-credential-unknown, additive `account_state` field, `status` untouched.
- 2 new suites, both self-register via `# run-all-triggers:`, 23/23 green, 3 negative controls verified red-then-green.
- No `tests/run-all.sh` edit needed — corrects prior assumption in the brief: bash `[[ str == glob ]]` crosses `/`, so `scripts/*.py` already covers `scripts/lib/*.py`.

Full: developer.full.md
