# Wave 4 — shared constraints (binding on every lane)

REPO: all work happens in `~/Projects/leadv2` (the plugin repo). Never in persona-engine.

## Hard prohibitions
- NEVER touch `plugins/leadv2/scripts/leadv2-dispatch-code.sh` (held by the lead session).
- NEVER touch `plugins/leadv2/scripts/leadv2-claude-profile-select.sh` (held by session persona-engine-e1).
- NEVER commit inside any repository under `~/MythicalGames` — they belong to the founder's
  employer. leadv2 config there is local-only via `.git/info/exclude`.
- NEVER write into the git-tracked `.claude/settings.json` of the `m3` repo.
- NEVER commit to `main`. Work on the lane's own worktree branch.
- NEVER edit `tests/known-red-suites.txt`.
- NEVER weaken, delete, or loosen an existing assertion to make a suite green.

## Required on every fix
1. **Negative control, run for real.** Apply the mutation INSIDE the body of the function
   under claim (not at file top level — a top-level insert reddens every suite for the wrong
   reason and reads as a pass). Show the suite RED with the mutation, revert, show it GREEN.
   Record both exit codes verbatim in the report.
2. **Green on macOS AND in a linux container.** Report both exit codes.
3. The test must keep the production function under claim REAL and fake only one level lower.
   A test that stubs the function it claims to cover proves nothing.

## Before handing back
Run `git diff --diff-filter=D --name-only main...HEAD` — **THREE dots**. Anything it lists is a
file this lane actually deletes relative to the merge base; restore it from main unless the
deletion is deliberate and stated in your report.

Do NOT use two dots. `main..HEAD` compares against main's CURRENT tip, so every file added to
main after this lane branched shows up as if this lane deleted it. Measured 2026-09-03: two lanes
were reported as deleting a file neither had touched. Three dots compares against the merge base,
which is the question you actually mean to ask.

## Where suites live, and CI must SELECT yours

- Suites live in `plugins/leadv2/scripts/tests/test-<name>.sh` (a few older ones sit flat in
  `tests/`). New suites go in `plugins/leadv2/scripts/tests/`.
- `tests/run-all.sh` selects suites two ways: by STEM match (a changed `foo.sh` runs
  `test-foo*.sh`), and by explicit rows in `EXTRA_SUITE_MAP` (`tests/run-all.sh:134+`),
  one `"<changed-stem>:<suite-path>"` per line.
- **A green suite CI never runs is worth nothing.** If your suite's stem does not match the
  file you changed, you MUST add the `EXTRA_SUITE_MAP` row, and you MUST prove it with
  `tests/run-all.sh --scope changed` showing your suite in the selected set.
- `EXTRA_SUITE_MAP` is a SHARED file — every Wave-4 lane appends to it. APPEND your row at the
  end of the block, never reorder or reflow existing rows. A conflict there is expected and the
  lead resolves it at merge; a reflowed block is not resolvable and will be rejected.

---

## ADDENDUM — two rules that superseded earlier text (2026-09-04, measured on lane D3)

### Rule 3 replaces "a negative control for this row"

**One negative control per CHANGED FUNCTION. Not one per lane, not one per row.**

Measured on D3: the lane changed two functions and ran one control. The second function reached
main with no assertion behind it at all, and the report read as complete because a control existed.
"There is an NC" is no longer an answer to "is this function covered". The report must name each
function it changed and, beside each, the mutation applied inside THAT function's body with its
`baseline_rc` / `mutated_rc` pair.

A lane that changed three functions and shows one control is INCOMPLETE, whatever its verdict says.

### Rule 4 — editing a plugin script inside a lane does NOT affect the running dispatcher

The plugin **cache** is a separate real file. A change to
`plugins/leadv2/scripts/…` inside a lane worktree is proved by the lane's own suite against the
lane's own copy — and by nothing else. It is not evidence about the dispatcher that is running
right now.

So the report must say this in words: *"verified by suite X against this lane's copy; the live
dispatcher loads the plugin cache and is unaffected until the cache is updated and the session
restarts."* Presenting a green suite as proof that the running system now behaves differently is
the lying-green disease in its plugin-shaped form.

Three Wave-4 lanes edit plugin scripts (PHASE-RECORD, BROAD-STATUS, MUTATION-CONTROL). All three
owe this sentence.

- **Ten consecutive runs, not one.** A suite that passes once is not green; flakiness is exactly
  how a red main hides. Report the suite's exit codes for ten consecutive runs, and if any run
  differs from the others, that disagreement IS the finding.

### A negative control must break the CONSEQUENCE, not print the message

Two lanes produced controls that looked valid and proved nothing, by two different routes:

- `mutated_rc=1` **implied by** the mutation tool printing `ok` — the code was restated from a
  tool's verdict, never observed. That tool has an open row against it for writing the empty hash
  as evidence, so the inference inherits the lie whole.
- `mutated_rc=0` while the mutant printed the expected error text — the suite reddened on a STRING
  in the output, not on anything being broken.

Same root: **the observable symptom was proved instead of the event.** Both reports were honest in
every sentence and neither guaranteed anything.

**The rule:** a negative control must show the CONSEQUENCE broke. Report `baseline_rc`,
`mutated_rc`, `restored_rc` as OBSERVED numbers — never inferred from a tool's verdict, never a
`diff_hash`.

**The falsification, one edit:** remove the assertion on the message text and keep the assertion on
state. The control must stay RED. If it goes green, it was testing output, not behaviour — that is
a coverage hole and it is a finding, not something to omit.
