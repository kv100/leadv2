# D3-DERIVE-DIRTY-HAS-NO-COVERAGE-01 — FINISHER. Three things, nothing else.

Your round produced a real result and one honest piece of evidence. Keep both. Do NOT redesign, do
NOT rewrite the suite, do NOT touch anything outside your declared write set.

**What is already accepted and must not be redone:** the red line

```
[TEST] FAIL: C8a: expected dead_with_unlanded_work (never landed), got: landednoneunknown
```

is a genuine failure produced by a genuine mutation. That part of the report is honest and stands.

**What is refused, and why it is refused rather than nitpicked.** The report says:

> `baseline_rc=0`, `mutated_rc=1` (**implied by** `MUTATION-CONTROL ok` — the tool exits 1 for
> `mutant_survived`…)

That is not a measurement. It is a restatement of a tool's verdict. The acceptance asks for the
pair *because* the tool can be wrong: there is an open row, `MUTATION-CONTROL-DIFF-HASH-IS-THE-EMPTY-HASH-01`,
recording that this very tool writes the empty hash as negative-control evidence. An inference
drawn from a lying tool inherits the lie in full, and it reads as proof.

## 1. Measured return codes, not inferred ones

For every control: run the suite, capture the actual exit code, apply the mutation, run again,
capture the actual exit code, revert, run again, confirm green. Report the numbers you observed:

```
function: <name>   mutation: <what you changed inside its body>
baseline_rc=<observed>   mutated_rc=<observed>   restored_rc=<observed>
red line: <the assertion text that failed>
```

**Remove `diff_hash` from the evidence entirely** — not "in addition to" the pair, but instead of
it. It is not evidence and citing it invites the next reader to accept it as such.

## 2. One control per CHANGED FUNCTION, not one per lane

Enumerate every function this branch added or changed (`git diff main...HEAD` — **THREE dots**;
two dots compare against main's current tip and misreport files main gained since you branched).
Give each one its own mutation, applied **inside that function's body** — never a top-level insert,
which reddens every suite for the wrong reason and reads as a pass.

A changed function for which no mutation turns the suite red is a **coverage hole**. Report it as a
finding. Do not quietly omit it, and do not weaken an assertion to manufacture a red.

Lane D3 (this row's sibling) shipped a second function with nothing behind it because one control
was treated as covering the lane. That is the exact defect this requirement exists to prevent.

## 3. Ten consecutive runs, not one

A suite that passes once is not green — intermittency is how a red main hides, and this fleet has
had defects that showed up 2 times in 13. Report ten exit codes. If any run disagrees with the
others, **that disagreement is the finding** and it outranks everything else in the report.

## Also: a commit message must describe its own diff

The previous round's commit said the symlink target was a temp dir. It was
`~/.claude/leadv2-state/leadv2/active.yaml` — the shared state every session reads, not a temp
path. A reader who trusts the message and not the diff makes the wrong call. Describe what you
actually changed.

## Bounds

- Declared write set only. Do NOT touch `tests/run-all.sh` — put the `EXTRA_SUITE_MAP` row in your
  report, ready to paste, and state plainly that CI does **not** select the suite yet.
- Do NOT touch `docs/leadv2/` — it is shared state and another lane owns it.
- Do NOT touch `leadv2-dispatch-code.sh`, `leadv2-claude-profile-select.sh`,
  `lib/leadv2-route-arbiter.sh`.
- Do not commit to `main`; do not add to `tests/known-red-suites.txt`.
- Green under bash AND zsh, failing on disagreement — unquoted `$var` does not word-split in zsh,
  so `for x in $list` iterates once over a glued blob.
- A file counts as saved when it appears in `git ls-files`, checked by eye: `.gitignore` swallows
  handoff paths silently and `git add` exits 0 while doing nothing.
