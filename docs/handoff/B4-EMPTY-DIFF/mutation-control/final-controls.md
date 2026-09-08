# B4 final mutation-control evidence

Commands (mutations are inserted inside pc_worker_alive):

```bash
#!/usr/bin/env bash
set -uo pipefail
export PATH="/tmp/b4-tools:$PATH" TMPDIR=/tmp
suite=plugins/leadv2/tests/test-empty-diff-waits-for-a-live-worker.sh
file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
for value in 1 0; do
  printf 'CONTROL forced_pc_worker_alive_rc=%s\n' "$value"
  mutation="/^pc_worker_alive() {/a\\
  return $value # B4 negative control inside the function body
"
  timeout -k 10 300 bash plugins/leadv2/scripts/leadv2-mutation-control.sh "$suite" "$file" "$mutation" docs/handoff/B4-EMPTY-DIFF
  rc=$?
  printf 'control_tool_rc=%s\n' "$rc"
  [[ "$rc" == 0 ]] || exit "$rc"
done
```

Raw foreground output; outer timeout 620 seconds, rc=0:

```text
CONTROL forced_pc_worker_alive_rc=1
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=1
MUTATION-CONTROL ok suite=plugins/leadv2/tests/test-empty-diff-waits-for-a-live-worker.sh file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh red_line=FAIL fable_late terminal value: got=no_work expected=landed diff_hash=a03fa1431af6a5ced8a960dd6abc1c7c5e3d2e796eab382d7e390a35c7683bc2 lane_diff_hash=7c55b362a0a0a4e0ff5103089100cf71d1047b21323958989d18a89564226833
control_tool_rc=0
CONTROL forced_pc_worker_alive_rc=0
leadv2-mutation-control: snapshot=head_plus_declared declared=2 excluded_dirty=1
MUTATION-CONTROL ok suite=plugins/leadv2/tests/test-empty-diff-waits-for-a-live-worker.sh file=plugins/leadv2/scripts/leadv2-dispatch-product-close.sh red_line=FAIL fable_exited terminal value: got=dead expected=no_work diff_hash=3e4b4a2bcacde24278249fde2393d167e9a0f19cdd2b1e2b952711e0c7a26c02 lane_diff_hash=7c55b362a0a0a4e0ff5103089100cf71d1047b21323958989d18a89564226833
control_tool_rc=0
```
