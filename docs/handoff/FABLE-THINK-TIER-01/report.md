# FABLE-THINK-TIER-01 — round 3

## Round 3 evidence

### 1. Escape-mission template fixed (`skills/leadv2-review/ref/architect-escape-mission.md:22`)
Old (broken): `--model "$(leadv2-router.sh think-model)" \  # fable; opus fallback` — bare
script name not on PATH, and the trailing `\  # comment` breaks the line continuation.

New: `--model "$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/leadv2-router.sh" think-model)" \`
with the comment moved to its own line above, matching the `${CLAUDE_PLUGIN_ROOT}/scripts/...`
convention used by every other skill (`docs/phases.md`, `leadv2-close/SKILL.md`, etc. — grepped
and confirmed, none use a bare `leadv2-router.sh` or the `lv2` shim for this call).

Added suite case (`test-fable-think-tier.sh` §2c2): extracts the fenced bash block from the
template with `awk`, runs `bash -n` on it, and resolves the `${CLAUDE_PLUGIN_ROOT}/scripts/*.sh`
path it references, asserting the file exists. Proof it catches the original defect — restored
the pre-fix template text and re-ran:
```
PASS: architect-escape-mission.md: extracted bash block parses (bash -n)
FAIL: architect-escape-mission.md: referenced router script missing or unresolved (got '<none>')
```
(bare `leadv2-router.sh` has no `${CLAUDE_PLUGIN_ROOT}` prefix for the extractor to resolve —
exactly the "not on PATH" defect). Restored the fix afterward; `git diff --stat` on the file
after restore showed the round-3 fix intact.

### 2. Census gate hardened against both proven bypasses (`test-fable-think-tier.sh`)
Reviewer proved two bypass shapes on the round-2 gate:
- (a) `model: 'claude-opus-5'` (full model id) evaded `census_re`, which only matched the bare
  word `opus`.
- (b) any pin line containing the word "fallback" was exempted by `grep -viE "fallback|..."`,
  regardless of whether a real resolver call gated it.

Fix:
- `census_re` now matches the whole **value class**: `opus`, `claude-opus-5`, future
  `claude-opus-4.x`, and `opus[1m]` suffixes — a rename or full-id spelling can't evade it.
- The "fallback" keyword is no longer an exemption by itself. `_lv2_classify_survivor()`
  only exempts a "fallback"-labeled line if a real resolver guard
  (`THINK_MODEL [=!]== 'opus'` or a `think-model` reference) appears in the preceding 25
  lines of the same file — the two legitimate sites (`leadv2-diverge.js:127`,
  `leadv2-po-feedback-loop.js:169`) are conditional retries gated by exactly this pattern
  (`THINK_MODEL !== 'opus'` at diverge.js:119, `THINK_MODEL === 'opus'` at
  po-feedback-loop.js:150 — 8 and 19 lines back respectively, hence the 25-line window).
  "guard prose" (`reserved for`) is still exempt unconditionally, as documented.

Mutation negative controls, run and pasted (all in `test-fable-think-tier.sh` §2c and verified
again live against the real tree):
```
# synthetic-string checks (§2c, always run as part of the suite):
PASS: mutation A (full model id pin) matches census_re
PASS: mutation B (unguarded 'fallback'-labeled opus pin) correctly rejected
PASS: resolver-gated fallback (guard present) correctly exempted

# live re-insertion at a real think-role site (leadv2-diverge.js), then reverted:
FAIL: tree-wide census: unclassified 'opus' literal(s): .../leadv2-diverge.js:128: { label: 'sneak', agentType: 'critic', model: 'claude-opus-5', ... }
FAIL: tree-wide census: think-role spawn line pinning opus: (same line)
PASS=17 FAIL=2   # (green PASS=20/FAIL=0 restored after revert — see full run below)

# old (round-2) census_re + keyword-only filter re-applied to a scratch copy of the suite,
# proving the two mutations WERE real bypasses under the old logic:
FAIL: mutation A (full model id pin) NOT matched by census_re — bypass reopened
FAIL: mutation B (unguarded 'fallback'-labeled opus pin) wrongly exempted — bypass reopened
PASS=4 FAIL=14
```

### 3. SUBAGENT_MODEL_FORCE claim — probed and scoped (not a blanket claim anymore)
Ran `claude -p --model claude-opus-5` with `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=claude-sonnet-5`
set — the top-level `--model` flag was unaffected (`"model":"claude-opus-5"` in the stream),
confirming the var does NOT touch the main-loop model. To find what it DOES affect, disassembled
the installed CC 2.1.257 binary directly (`strings -a ~/.local/share/claude/versions/2.1.257`,
grep for the env var name):
```
strings -a ~/.local/share/claude/versions/2.1.257 | grep -B2 -A2 'ignored: CLAUDE_CODE_SUBAGENT_MODEL_FORCE'
->  Workflow agent model "
->  " ignored: CLAUDE_CODE_SUBAGENT_MODEL_FORCE is set
->  minified source (Workflow-tool internal agent() dispatcher):
      if(I?.model!==void 0 && a.CLAUDE_CODE_SUBAGENT_MODEL_FORCE)
        t(`Workflow agent model "${I.model}" ignored: ...`), I.model=void 0;
```
This confirms the var nulls `opts.model` specifically inside the **Workflow tool's internal
`agent()` dispatcher** (the same code path `docs/model-effort-matrix.md`'s
`model: opts.model || THINK_MODEL` line refers to) — so for Workflow scripts, the original
claim ("overrides every explicit model= pin") holds. It was NOT probed against, and the docs
no longer claim it applies to, non-Workflow spawns (`Agent` tool, `claude-subsession.sh
--model`) — those are separate code paths (a fresh `claude -p` process for the subsession
script; a different internal dispatcher for the `Agent` tool) that this string evidence says
nothing about.

Updated both `docs/model-effort-matrix.md:85` and `docs/phases.md:145` to state the scoped,
evidenced claim with the probe command inline, and to explicitly flag the non-Workflow paths
as unprobed rather than silently included under the old blanket wording.

The round-2 "same Claude Max bucket as Opus" withdrawal (`docs/model-effort-matrix.md:50`,
`config/model-capability.yaml:43`) was already evidence-tagged from round 2 — left unchanged,
still correct on review.

## Falsification (full suite run, post-fix)
```
$ bash -n plugins/leadv2/scripts/tests/test-fable-think-tier.sh
bash -n OK
$ LEADV2_SUITE_LOCK_DISABLE=1 bash plugins/leadv2/scripts/tests/test-fable-think-tier.sh
PASS: resolver default = fable
PASS: resolver LEADV2_THINK_MODEL=opus override wins (negative control)
PASS: resolver falls back to opus when fable marked unavailable
PASS: tree-wide census: zero live think-role 'opus' spawn pins
PASS: mutation A (full model id pin) matches census_re
PASS: mutation B (unguarded 'fallback'-labeled opus pin) correctly rejected
PASS: resolver-gated fallback (guard present) correctly exempted
PASS: leadv2-diverge: THINK_MODEL const present
PASS: leadv2-learn: THINK_MODEL const present
PASS: leadv2-diagnose: THINK_MODEL const present
PASS: leadv2-po-feedback-loop: THINK_MODEL const present
PASS: zero opus-4 literals under plugins/leadv2/{scripts,config,ref,workflows,hooks}
PASS: architect-escape-mission.md: extracted bash block parses (bash -n)
PASS: architect-escape-mission.md: referenced router script exists (.../leadv2-router.sh)
PASS: pool orders fable before opus (codex:blocked:98,glm:blocked:95,kimi:author:,fable:ok:30,opus:ok:30,sonnet:ok:30)
PASS: fable shares the anthropic reading (ok under the 95 ceiling)
PASS: reviewer=fable (first eligible arm after the author/probe exclusions)
PASS: author-exclusion intact: author=opus excluded, reviewer=fable
PASS: dispatch-code.sh: no hardcoded opus prepass default
PASS: dispatch-code.sh prepass default resolves via router think-model
PASS=20 FAIL=0
```
`git diff main..HEAD -- '*.sh' '*.py'` (changed-scope) — only `test-fable-think-tier.sh` has
uncommitted-vs-main shell/python diff beyond the round-1/2 commits already on the branch;
`bash -n` on it passes as shown above; no `.py` files touched this round.

Merged `main` first (ff-able) — brought in `leadv2-guard-census.sh`, `leadv2-suite-falsifiable.sh`
and related test fixtures/suites unrelated to this lane's scope; left untouched. Deleted the
stray `report.md` that round 2 left at the worktree root before merging (main also carries an
unrelated `report.md` from a different task, `PLUGIN-PAPERCUTS-01` — that one is main's file,
not this lane's; left as merged).

DELIVERABLE_COMPLETE
