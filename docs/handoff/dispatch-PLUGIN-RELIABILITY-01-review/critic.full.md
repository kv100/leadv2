# Verify: "D3/D5 tests are pure grep-on-source; no test exercises the two reap call sites"

Severity as filed: High / correctness. Mission: attempt refutation; default is_real=false absent
concrete confirmation. Evidence source: `docs/handoff/PR01-review/build-r2.diff` (774 lines).

## 1. Are D3/D5 grep-on-source?

Yes. In the added test file `plugins/leadv2/scripts/tests/test-plugin-reliability-01.sh`:

- D3 block (diff lines ~677-695):
  - `if grep -q '\-\-no-block' "$src" && ! grep -q 'prepass.*--timeout 1800' "$src"; then`
  - `if grep -q 'prepass_parked task=' "$src"; then`

  Both assert only that a string appears in `leadv2-dispatch-code.sh`. No prepass-park path is run,
  so a `--no-block` that is present but unreachable, misplaced, or shadowed still passes.

- D5 block (diff lines ~753-758):
  - `if grep -q 'router_v2_reorder_failed' "$src"; then`

  The file's own header concedes it: `#   D5 — router_v2 reorder failure journal (source-grep, trivial)`.
  That concession contradicts the banner a few lines above: `# No grep-on-source tests (the lying-green disease).`

The neighbouring D2/D4 asserts have the same shape (`grep -q 'agents_worktree_fallback' .../claude-subsession.sh`;
`grep -B15 'empty_status_pid_gone' "$src" | grep -q '! -f.*meta'`), so the pattern is not isolated to D3/D5.

## 2. Do any tests exercise the two reap call sites?

No. The suite obtains the functions by textual extraction:

```
awk '
  /^_pc_reap_worker\(\)/   { in_func=1 }
  ...
eval "$( ... )"
```

Only `_pc_process_alive` and `_pc_reap_worker` are pulled into the test shell, plus a stub `emit`.
Every D1 assertion then calls the function directly with a directory the test itself built:

```
local run_dir="${TMP_ROOT}/reap-test"
_pc_reap_worker "$run_dir" ""
_pc_reap_worker "$run_dir" "$parent_pid"
_pc_reap_worker "$run_dir" "999999"
```

The two production call sites (diff lines 355 and 363) live inside the wait/timeout logic of
`leadv2-dispatch-product-close.sh`, which is neither extracted, nor sourced, nor invoked:

```
_pc_reap_worker "${HANDLE}" "$(_pc_meta_value ".../${AUTHOR}-runs/${HANDLE}/meta.yaml" pid ...)"
```

`${HANDLE}` is a bare handle string, not the `<run_dir>` the signature
(`_pc_reap_worker() { # <run_dir> [meta_pid]`) requires — contrast the correct third call site at
diff line 323, `_pc_reap_worker "${run_dir}" "${pid}"`. Because the tests always pass a well-formed
`run_dir`, the argument-mismatch defect is invisible to them: `${run_dir}/pgid` and
`${run_dir}/.lockref` resolve to nothing, reaping degrades to the `meta_pid`-only path, and the
suite still reports green.

## 3. Refutation attempts and why they fail

- *"D1 behavioral tests cover the reap path, so call-site coverage is redundant."* — They cover the
  function body, not its callers. The filed defect is entirely in the caller's argument, a class of
  bug that function-level tests structurally cannot see.
- *"grep-on-source is acceptable for a trivial journal-line assertion."* — Arguable as policy, but
  it does not refute the factual claim, and the file's own banner asserts the opposite policy. The
  self-contradiction is itself a defect in the deliverable.
- *"Perhaps another suite covers the call sites."* — Nothing in build-r2.diff adds such coverage;
  the diff's own summary table credits D1 with "call sites pass `run_dir`", a claim no test verifies.

## Conclusion

Both halves of the finding are confirmed directly from the diff text. The finding stands.

VERIFY_VERDICT: upheld

DELIVERABLE_COMPLETE
