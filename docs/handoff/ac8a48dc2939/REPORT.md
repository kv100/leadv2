# PREPASS-MECHANISM-CLOSURE-01 — census falsification

## Stop condition

Discovery falsified the authoritative design's stated baseline: it requires
`test-account-truth-active-is-metered.sh` to move from `14/14` to `18/18`, but
the committed base `c5393455` exits non-zero at `13/14` before this round makes
any change.

The failing assertion is in the existing derivation-contract test.  It creates
`d` as an absolute temporary-directory path, then requires
`account_key_for_config_dir(d) != sha256_8(d)`.  That cannot hold: the reader
intentionally computes `sha256_8(realpath(expanduser(d)))`; for an existing,
absolute, non-symlink temporary path, `realpath(d) == d`.

This is a test-census contradiction, not evidence that the proposed cache or
daemon mechanism is wrong.  Fixing the test would require widening the design
to alter a pre-existing baseline assertion that Change D describes as green;
the scoped design explicitly directs the implementer to stop rather than
silently implement around a falsified census.

## Reproduction artifact

```
$ timeout 180 bash plugins/leadv2/scripts/tests/test-account-truth-active-is-metered.sh
...
Traceback (most recent call last):
  File "<stdin>", line 10, in <module>
AssertionError: raw string hashed (tilde/relative forms would fork keys)
[TEST] FAIL: 2 derivation: normalization contract broken
...
pass=13 fail=1
```

```
$ python3 - plugins/leadv2/scripts/leadv2-quota-read.py /private/tmp/ac8a48dc2939-census
d=/private/tmp/ac8a48dc2939-census/cfgdir
realpath=/private/tmp/ac8a48dc2939-census/cfgdir
account_key=ad387661
raw_hash=ad387661
equal=True
```

## Required decision

Authorize a corrected design that explicitly permits repairing assertion 2
(for example, compare an unexpanded tilde or relative spelling against its
normalized path), then reissue the cache/daemon implementation scope against
that green baseline.  No production code, cache behavior, credential, or
runtime-state path was changed in this halted round.
