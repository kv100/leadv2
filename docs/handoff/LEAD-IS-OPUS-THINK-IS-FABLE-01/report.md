# LEAD-IS-OPUS-THINK-IS-FABLE-01 — follow-up evidence

Date: 2026-09-03
Lane: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEAD-IS-OPUS-THINK-IS-FABLE-01`

The rescue commit `09f7d8da` was preserved verbatim. This follow-up changes only
the existing think-tier suite's missing safety-pin census allowlist entry and
adds this report. `git diff main..HEAD --diff-filter=D` was empty, so there was
no early-branch deletion to restore.

## Item 2 — fresh adoption and the Sonnet fallback

The checker deliberately fails closed when a freshly adopted repo has no local
`main-model.yaml`/guardrail skill yet. The direct probe was:

```text
root=/private/tmp/lead-is-opus-fresh-probe; mkdir -p "$root/project/.claude/ref"
LEADV2_QUOTA_LIVE=/nonexistent PROJECT_ROOT="$root/project" \
  bash plugins/leadv2/scripts/leadv2-main-model-check.sh 2>&1
printf 'CHECK_RC=%s\n' "$?"
```

Raw output:

```text
[leadv2-main-model-check] INFO: main-model.yaml not found — defaulting to sonnet
sonnet
CHECK_RC=0
```

Answer: this is the safe adoption boundary, not a contradiction of the plugin
default. Until the repo-local model declaration and the guardrail skill are
present, Opus has not been proven safe, so the checker returns Sonnet with rc=0.
After adoption has materialized those files, the Opus guardrail path can be
evaluated on the next session.

## Item 3 — existing-repo backfill census

The read-only probe covered every named repo and both settings locations:

```text
environment-platform .claude/settings.json:main=opus,think=fable
m3 .claude/settings.json:main=<unset>,think=<unset> .claude/settings.local.json:main=opus,think=fable
mondia-portal .claude/settings.json:main=opus,think=fable
mp-frontend .claude/settings.json:main=opus,think=fable
mythical-aii .claude/settings.json:main=opus,think=fable
pf3-backend .claude/settings.json:main=opus,think=fable
pf3-local-dev .claude/settings.json:main=opus,think=fable
pf3-smart-contracts .claude/settings.json:main=opus,think=fable
getmany-followup-bot .claude/settings.json:main=opus,think=fable local_ref_main=fable
m3-market .claude/settings.json:main=opus,think=fable .claude/settings.local.json:main=<unset>,think=<unset> local_ref_main=opus
BACKFILL_PROBE_RC=0
```

The m3 result confirms the env override is in `.claude/settings.local.json`; its
tracked `.claude/settings.json` was not touched. The env blocks are already
backfilled to `main=opus, think=fable`. The one remaining stale declaration is
`getmany-followup-bot/.claude/ref/leadv2-main-model.yaml: main_model: fable`;
`m3-market` already has `main_model: opus`. No MythicalGames checkout was
edited or committed.

Because the pinned-lane rule conflicts with mutating the external getmany
checkout, the reversible async question was recorded as `q-235854d4` with
default option `a` (keep the pin and report the manual follow-up). No external
write was performed.

## Item 4 — should Fable also be a hard-task worker arm?

No. Fable belongs on the thinking axis: architect, synthesis, judge, and other
reasoning roles. Hard-task workers are typing arms; task difficulty should raise
the thinking effort and planning/review quality, while the implementation worker
keeps its developer/GLM/Kimi/Codex role. Adding Fable as a general worker arm
would blur the thinking-versus-typing boundary, duplicate the Anthropic review
pool, and make it possible for a think-only model to become an edit worker.

## Item 6 — two-way negative controls

The focused suite contains both directions. The first run was red because its
census missed the unrelated hard-safety pin `CLAUDE_SAFETY_MODEL="opus"` in
`leadv2-session-route.sh`; the allowlist entry was added, and the same suite was
rerun.

Red output before the fix (raw failing portion):

```text
FAIL: tree-wide census: unclassified 'opus' literal(s): /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEAD-IS-OPUS-THINK-IS-FABLE-01/plugins/leadv2/scripts/leadv2-session-route.sh:73:CLAUDE_SAFETY_MODEL="opus"
PASS=57 FAIL=1
SUITE_RC=1
```

Green output after the fix (raw control lines and result):

```text
PASS: repo-install.sh: LEADV2_MAIN_MODEL has its own default (opus), independent of LV2_THINK_MODEL —  "LEADV2_MAIN_MODEL": os.environ.get("LV2_MAIN_MODEL", "opus"),
PASS: repo-install.sh: LEADV2_THINK_MODEL still resolves via the think resolver (fable), independent of the main axis —  "LEADV2_THINK_MODEL": os.environ.get("LV2_THINK_MODEL", "fable"),
PASS: negative control A: pre-fix collapsed main-axis line correctly RED under the split check; the real file's line above is GREEN (revert proven)
PASS: negative control B: a main-derived think-axis line correctly RED under the split check; the real file's line above is GREEN (revert proven)
PASS: mutation A (full model id pin) matches census_re
PASS: mutation B (unguarded 'fallback'-labeled opus pin) correctly rejected
PASS: resolver-gated fallback (guard present) correctly exempted
PASS=59 FAIL=0
SUITE_RC=0
```

## macOS and Linux evidence

macOS command and exit:

```text
LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-fable-think-tier.sh
PASS=59 FAIL=0
SUITE_RC=0
```

Linux container command and exit:

```text
docker run --rm -v <lane>:/repo -w /repo node:22-bookworm bash -lc \
  'python3 -m pip install PyYAML && bash plugins/leadv2/scripts/tests/test-fable-think-tier.sh'
PASS=59 FAIL=0
SUITE_LINUX_RC=0
```

## Changed-scope selection evidence

The selector was run in non-executing mode against the committed rescue change.
The changed files include both requested carriers:

```text
plugins/leadv2/ref/leadv2-main-model.yaml
plugins/leadv2/scripts/leadv2-repo-install.sh
plugins/leadv2/scripts/tests/test-fable-think-tier.sh
tests/run-all.sh
[SELECT] .../plugins/leadv2/scripts/tests/test-fable-think-tier.sh
run-all: 5 selected, scope=changed, select_only=1
SELECT_RC=0
```

The broad `tests/run-all.sh --scope changed` attempt was not treated as task
green: its raw transcript ended with `suites passed=62 failed=21` and seven
`NOT-KNOWN-RED` unrelated nested suites before the independent status-surface
test stopped producing output. The task-specific macOS/Linux contract and the
changed-scope selector are the bounded proofs above.

## Falsification self-check raw output

```text
bash -n plugins/leadv2/scripts/leadv2-repo-install.sh rc=0
bash -n plugins/leadv2/scripts/tests/test-fable-think-tier.sh rc=0
bash -n tests/run-all.sh rc=0
BASH_SYNTAX_RC=0
python3 -m py_compile: no changed Python files
PY_COMPILE_RC=0
```

The required changed-scope runner command was also executed in selector-only
mode so it could prove registration without re-running unrelated core suites:

```text
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEAD-IS-OPUS-THINK-IS-FABLE-01/plugins/leadv2/scripts/tests/run-core-offline.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEAD-IS-OPUS-THINK-IS-FABLE-01/tests/test-status-surface-bash32.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEAD-IS-OPUS-THINK-IS-FABLE-01/tests/test-status-surface-single-lead.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEAD-IS-OPUS-THINK-IS-FABLE-01/tests/test-status-surface-fast-names.sh
[SELECT] /Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/LEAD-IS-OPUS-THINK-IS-FABLE-01/plugins/leadv2/scripts/tests/test-fable-think-tier.sh
run-all: 5 selected, scope=changed, select_only=1
SELECT_RC=0
```
