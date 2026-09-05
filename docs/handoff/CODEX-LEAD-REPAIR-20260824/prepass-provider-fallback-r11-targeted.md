# PREPASS-PROVIDER-FALLBACK-01-R11-TARGETED

One targeted High fix on the existing dispatcher worktree at `b062092`.

Close the fallback supervisor registration gap: no detached provider process
group may become live before the parent can identify and terminate it. Publish
the runner PID atomically before exposure, or launch through a registration
handshake whose child cannot start the provider until the parent has armed its
signal cleanup. SIGTERM at every point in that handshake must kill/reap the
runner and provider group and remove the disposable workspace.

Add an executable barrier fixture that stops immediately before/at registration,
sends SIGTERM, and proves no provider remains. Preserve the 10 existing cases.
Run bash-n, diff-check and focused suite. Commit the two files and leave clean.

acceptance:
  surface: review_gate
  observable: SIGTERM during fallback runner registration leaves no provider process or disposable workspace, and all focused cases pass.
  authored_at: 2026-08-24T21:58:00Z

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-code.sh,plugins/leadv2/scripts/tests/test-dispatch-prepass-provider-fallback.sh
