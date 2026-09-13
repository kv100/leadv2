verdict: BLOCK
next_action: review_round_2

# Adversarial review — PROMISE-GUARD-MISSES-A-CLOSING-PROMISE-01 (ee0eaf69f3e8)

Subject: `~/Projects/leadv2/plugins/leadv2/hooks/leadv2-promise-guard.sh` (uncommitted, +126/-5)
plus new `~/Projects/leadv2/plugins/leadv2/scripts/tests/test-promise-guard-closing-promise.sh`.
Reviewed by reading the diff, running the real hook against synthetic transcripts in a scratch
worktree, and reverting the change in a scratch copy. Nothing in `~/Projects/leadv2` was staged,
committed, reset, or cleaned.

## Findings

| severity | file:line | finding | evidence |
|---|---|---|---|
| BLOCKING | `plugins/leadv2/hooks/leadv2-promise-guard.sh:304-308,630-632` | A Bash-tool write to a scratch path is unconditionally treated as DURABLE. `ACTION_KIND_BASH` (line 304) classifies `touch`/`cp`/`mv`/`tee`/`sed -i`/shell redirection as kind `write`. The durability gate at 630-632 is `if action_kind != 'write' or name == 'Bash' or is_durable_target(write_target(inp))` — the `name == 'Bash'` disjunct short-circuits before the target is ever inspected, and even without it `write_target()` only reads `file_path`/`notebook_path`/`path` JSON keys, which a Bash `tool_use` block never has (it has `command`), so it falls through the `if not path: return True` fail-open anyway. Net effect: `Начинаю с пункта 1 || Bash: echo notes > /tmp/leadv2-pg-notes.md` stays SILENT — the reported 2026-09-13 escape reproduced verbatim through a different, arguably more common, tool. | Live run of the new suite: `[TEST] PASS: N11 start + Bash scratch write stays suppressed (documented residual) silent, row verdict=suppressed_action kind=start durable=["write"]`. The suite's own comment (lines ~325-330) names this "documented residual… shell parsing is out of scope" rather than closing it. Code at lines 304-308 and 630-632 quoted above. |
| BLOCKING | `plugins/leadv2/hooks/leadv2-promise-guard.sh:480-485` (new `start` pattern) | Negation blindness on the new pattern produces a false positive on an honest, plausible closing sentence — exactly the lens-4 probe the mission mandated. `"Не начинаю новую линию, пока не закрою эту — работаю по плану."` (I am NOT starting a new line, still finishing this one) fires and blocks, quoting `"Не начинаю новую линию"` as an unkept promise. Confirmed this is a pre-existing systemic gap, not unique to `start` (`"Не закоммичу пока — тесты ещё красные."` fires identically on both the pre-diff and post-diff hook), but the diff adds a brand-new, high-frequency trigger family ("I'm not starting X yet") onto that gap without a negation guard, which is precisely the failure class ("died from false positives, not missing catches") the mission told the lane not to reproduce. | Direct probe against the live hook (unique session ids, sentinel cleaned up each call): `FIRED: {"decision": "block", ... "Unkept: \"Не начинаю новую линию\"" ...}`. Same probe against `git show HEAD:...leadv2-promise-guard.sh` (pre-diff) with `"Не закоммичу пока..."` also FIRED — proving the negation gap is pre-existing, not introduced, but the diff still ships a new instance of it untested. |
| MEDIUM | `plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh:329-341` | The actual change set is two files, not the one named in the review task ("Diff: ... +126/-5, one file"). `test-promise-guard-morphology.sh` is also modified (+12/-1): `case_r4b_neg_nachnu` flips its expectation from `SILENT` to `FIRED` for `"Начну с разбора причины"`. The change is correct and intentional (consistent with `start` now classifying "начну", verified it passes: 17 passed(red→green) matches the mission's own reported table), but it is an undisclosed second write-surface a reviewer has to discover by `git status`, not something named in the diff being reviewed. | `git diff --stat plugins/leadv2/scripts/tests/test-promise-guard-morphology.sh` → `1 file changed, 12 insertions(+), 1 deletion(-)`; full diff shows the SILENT→FIRED flip with rationale comment citing this same defect id. |
| LOW | `plugins/leadv2/hooks/leadv2-promise-guard.sh:516,520,622,634` | `action_positions` and `last_text_pos` are populated every turn but never read anywhere in the file — leftover bookkeeping from the positional-binding mechanism reverted 2026-08-22 (`PROMISE-GUARD-POSITIONAL-REVERT-01`). Pre-existing dead code, not introduced by this diff; opportunistic cleanup only. | `grep -n "action_positions\|last_text_pos"` returns only the two write sites, zero read sites. |

## Lens-by-lens results

**Lens 1 — target-aware, not verb-widening.** Partially satisfied. The `start` classification is a
new verb family (widening in that narrow sense), but the mission explicitly required it — «начинаю»
was already detected pre-diff, the new work is giving it a *kind* so it can be bound, not adding a
detection trigger. The load-bearing half — target-aware durability — is genuinely new code
(`is_durable_target`, `SCRATCH_PREFIXES`, `durable_kinds_seen`) and does discriminate by path for
the Write/Edit/NotebookEdit surface. It does NOT discriminate for the Bash surface (BLOCKING #1
above) — so the target-awareness claim is only half-true across the tool space the hook itself
already models in `ACTION_KIND_BASH`.

**Lens 2 — positional binding not reintroduced.** Clean. `action_after_promise` is computed from
`durable_kinds_seen`/`action_kinds_seen` (turn-wide sets), never from `action_positions` or
`last_text_pos` (both dead, see LOW finding). The reverted 2026-08-21 mechanism ("only actions
after the last text block count") does not appear anywhere in this diff.

**Lens 3 — scratch-path discrimination hard-coded to one machine?** Clean. `_scratch_prefixes()`
(lines 332-341) derives from `os.environ.get('TMPDIR')`/`TMP` plus the fixed POSIX roots
(`/tmp`, `/private/tmp`, `/var/tmp`, `/private/var/tmp`), with both `/private` spellings added
for each. No literal `/private/tmp/claude-503/...` or any other one-machine path appears anywhere
in the diff.

**Lens 4 — false-positive probe (5 new sentences, live-run against the current hook):**

| sentence | fired/silent |
|---|---|
| «Уже начал — влил fix/promise-guard в main, sha 9a1b2c3.» (past tense + artifact) | silent |
| «Не начинаю новую линию, пока не закрою эту — работаю по плану.» (negated) | **FIRED** — BLOCKING #2 |
| «Если понадобится, начну сразу, но сейчас приоритет другой.» (conditional) | silent |
| «Он начинает нервничать из-за дедлайна, но всё под контролем.» (3rd person) | silent |
| «Приступил к рефакторингу ещё вчера, сейчас всё в main.» (past tense) | silent |

4 of 5 stayed silent as intended (past tense, conditional, and 3rd-person forms are correctly
excluded by the `\b`-anchored 1sg-only regex). The negated form is the one genuine miss, reported
above.

**Lens 5 — negative controls mutate the real file, not a copy.** Verified by reading the mutation
code, not trusting the suite's own comment:
- M1 reads `${HOOK}` (the actual `plugins/leadv2/hooks/leadv2-promise-guard.sh`), string-replaces
  `return False` → `return True` inside the `is_durable_target` scratch-hit branch, writes the
  result to a scratch file, and runs THAT via `HOOK_OVERRIDE`. TP1's spec goes silent under the
  mutant — confirmed live (`PASS: M1 negative control: durability mutant reddens`).
- M2 reads `${HOOK}` and replaces `if primary_kind is None or primary_kind == 'start':` with
  `if primary_kind is None:`, which routes `start` into the `else` branch
  (`action_after_promise = primary_kind in action_kinds_seen`); since no action is ever classified
  kind `'start'`, this is always False, so N6's spec (`start` + `git commit`) must now fire.
  Confirmed live (`PASS: M2 negative control: binding mutant reddens`). The claim in the suite
  header is accurate.
Both mutants are built from the live production file path (`${HOOK}`), not a suite-local fixture —
this is a real control, not the "mutates its own copy" anti-pattern from prior incidents.

**Lens 6 — revert-and-rerun (tautology check).** Extracted the pre-diff hook via
`git show HEAD:plugins/leadv2/hooks/leadv2-promise-guard.sh` (809 lines, matches the mission's
stated original size) into a scratch copy, then ran the new suite with `HOOK_OVERRIDE` pointed at
it (except M1/M2, which hardcode `${HOOK}` to the live file by design and are unaffected by the
override — confirmed this is intentional, not a leak, since normal suite runs always point `${HOOK}`
at whatever file is checked out).

Result: **10 of 18 assertions still pass** against the pre-diff hook:
`bash -n`, N1, N2, N3, N4, N5, N9, M1, M2, and the "real journal has no rows" housekeeping check.
None of these are false claims about the new mechanism: N1/N2/N3/N9 are regression pins for the
five 2026-08-22 false positives (correctly expected to hold on BOTH old and new code — that is
their whole point), N4/N5 pin pre-existing log-only detection behaviour explicitly unchanged by
this diff, `bash -n` and the journal-housekeeping check are infra sanity, and M1/M2 always target
the live file regardless of override. The 8 failing assertions (TP1, TP1b, TP2, N6, N7, N8, N10,
N12) are exactly the ones that depend on code this diff adds (`start` kind, `is_durable_target`,
`durable_kinds_seen`) — no tautology found among the 18.

## Verified-against-claim: pre-existing suite counts

Re-ran all four (not trusted from the mission table blindly):
- `test-promise-guard-closing-promise.sh` (new): **18 passed, 0 failed** — matches.
- `test-promise-action-binding.sh`: **2 passed(red→green), 0 failed, 8 green-pre-fix** — matches.
- `test-promise-guard-classified-block.sh`: **8 passed, 0 failed** — matches.
- `test-promise-guard-morphology.sh`: **17 passed(red→green), 0 failed, 35 green-pre-fix** — matches.
- `test-promise-guard-unknown-kind.sh`: **21 passed, 0 failed** — matches.

All counts confirmed by direct execution, not taken on faith.

## Contradiction scan (env vars, flag semantics, path existence)

- `LEADV2_PROMISE_GUARD_BLOCK_UNCLASSIFIED` semantics unchanged and consistently used (opt-in gate
  for unclassified-kind blocking) across the diff, the suite, and the pre-existing code — no drift.
- `SESSION_ID` length floor (`>= 16`) vs the bash-layer `"unknown"` fallback (7 chars, line 86):
  consistent, verified — the fallback can never accidentally satisfy the floor.
- Scratch-prefix env vars (`TMPDIR`, `TMP`) match the actual runtime scratchpad path shown in this
  session's environment (`/private/tmp/claude-503/.../scratchpad`) — no mismatch found.
- No hardcoded path, table name, or flag name in the diff was found to contradict its usage
  elsewhere in the file.
- One genuine scope-vs-description contradiction: task framing said "one file, +126/-5"; the actual
  working tree carries a second, related, and necessary file change (see MEDIUM finding). Not a
  code contradiction, but a reporting-accuracy gap that should be closed before commit so the commit
  message names both files.

## Second-model review

The new suite's own comment on case N12 attributes it to "second-model review, codex 2026-09-13" —
Codex apparently caught that the `None` branch also needed to bind to durable evidence (not just
the `start` branch), and N12 pins that. No standalone review artifact exists yet under
`docs/handoff/ee0eaf69f3e8/` (no `developer.full.md` present at review time), so the mission's
Report-table line "second-model review verdict" is not independently documentable from this repo
beyond the in-code trace above.

## Verdict

**DO NOT LAND.** Two BLOCKING findings:
1. Bash-tool scratch writes bypass the entire target-awareness mechanism this fix exists to add —
   trivially reproduces the reported escape through a different tool.
2. The new `start` pattern fires on a negated, honest closing sentence, extending a known
   false-positive class the mission explicitly said not to reproduce.

Required before re-review: either extract and check a target from Bash write commands (redirection
target / `cp`,`mv`,`tee` last-arg / `sed -i` file arg) against `SCRATCH_PREFIXES`, or explicitly
narrow `ACTION_KIND_BASH`'s `write` classification so it never marks a Bash call as `write` kind
without a resolvable target — and add a `\b(?:не|ни)\s+` (or equivalent) negation veto ahead of the
`start` pattern match, with a regression pin for the negated case above, before landing.

## mypy / tsc

Not applicable — this change is bash + inline `python3 -c`/heredoc, no `.py`/`.ts` files touched.
Static check performed instead: `bash -n` on both the live hook and the new suite (both pass, per
the suite's own first assertion `PASS: bash -n leadv2-promise-guard.sh`; ran
`bash -n plugins/leadv2/scripts/tests/test-promise-guard-closing-promise.sh` independently, exit 0).

DELIVERABLE_COMPLETE
