status: fail
reason: suite_not_falsifiable
suite: plugins/leadv2/scripts/tests/test-state-path-fails-closed.sh

The review gate refuses this round: the suite above cannot go red.
Its exit code did not change under failure injection (assertion tools
broken, empty working directory, stripped environment), so it cannot
distinguish correct from incorrect behaviour and carries no evidence.
A printed `FAIL:` line that leaves `$?` at 0 is NOT an assertion: make
the suite exit non-zero on failure (exit 1, or let the failing command
propagate — no `|| true` around the checked command), then re-run review.

leadv2-suite-falsifiable: suite=/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/518b42814626/plugins/leadv2/scripts/tests/test-state-path-fails-closed.sh
baseline: rc=0
probe[assertion_tools_broken]: rc=0 shim_invocations=1
probe[empty_cwd]: rc=0
probe[stripped_env]: rc=0
verdict: NOT FALSIFIABLE — /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/518b42814626/plugins/leadv2/scripts/tests/test-state-path-fails-closed.sh
  exit code 0 under every failure injection (assertion tools broken:
  1 sabotaged-tool call(s); empty working directory; stripped environment).
  A suite that stays exit 0 no matter what breaks cannot distinguish
  correct from incorrect behaviour, so it carries no evidence.
  A printed "FAIL:" line that leaves $? at 0 is NOT an assertion: make the
  suite exit non-zero on failure (exit 1, or let the failing command
  propagate — no "|| true" around the checked command).
