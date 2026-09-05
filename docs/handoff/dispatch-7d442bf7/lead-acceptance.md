# GATE-UNKNOWN-MUST-NOT-KILL-A-ROUND-01 — lead acceptance

branch: worktree-GATE-UNKNOWN-MUST-NOT-KILL-A-ROUND-01
head:   1450b5eb  (worker 10fcfa8d + lead 1b3ce2fd, 1450b5eb)
scope:  4 files, +264/-7 (worker) +25 (lead) · deletions 0 (`--diff-filter=D main...HEAD` empty) · forbidden paths 0

## What the round was actually about

The writer already said `unknown`. `leadv2-phase8-e2e-gate.sh` wrote
`status: unknown / reason: e2e_timeout` on a timeout **and then `exit 1`**, and
`leadv2-phase8-close.sh` collapsed every non-zero into `log_error "E2E gate failed"`.
So the distinction existed in a file and died at the reader. The fix is at the reader.

## Negative controls — observed rc triples, never a diff hash

| # | site | mutation (inside the body) | baseline / mutated / restored | red assertions |
|---|---|---|---|---|
| NC1 | writer `leadv2-phase8-e2e-gate.sh` | `exit 5` → `exit 1` | 0 / 1 / 0 | 2, **one cause** (T1 + T4 both trace to the removed branch) |
| NC2 | reader `leadv2-phase8-close.sh` | `-eq 5` → `-eq 6` | 0 / 1 / 0 | 1 — T2, the named one |
| NC3 | reader ordering | move `ASSERT_SCRIPT=` above the gate block | 0 / 1 / 0 | 1 — T5, the named one |

NC2's first attempt was **invalid and discarded**: perl interpolated `$e2e_rc` to empty,
giving `if [[  -eq 999 ]]` — a parse break proves the file stopped running, not that the
consequence broke. Redone as a semantic mutation; mutant byte-differs asserted before running.

## Two lead-added things the round was missing

1. **zsh blindness.** The suite resolved its own dir through `${BASH_SOURCE[0]}`, absent under
   zsh, so every zsh run hit non-existent paths. The round reported "10/10 zsh green"; measured
   **1×5**. Third suite blinded this way in one shift. Fixed with the merged
   `lib/leadv2-lane-state.sh` resolution order → bash 0×10, zsh 0×5.
2. **The claim was asserted as wording, not as state.** T1–T4 proved a log line and a marker
   file. Resumability is neither: it holds because `exit 5` fires **before**
   `leadv2-phase8-assert.sh`, the writer of `phase8-passed.flag` — the artifact every reader
   keys on to call a round finished. T5 asserts that ordering on the shipped file; NC3 is its
   control. Drop T2's message assertion and the claim still stands on T5.

## Reader census — proven by mutation, and its two honest limits

- `leadv2-phase8-close.sh` — **was** the conflating reader. Fixed; proven by NC2/NC3, not by
  reading a list.
- `leadv2-dispatch-product-close.sh` — the sibling path already distinguished (`rc=124` →
  `status: unknown`, `_dl_note parked e2e_timeout`, `_stamp_review_terminal blocked`,
  **`exit 5`**). The lane adopts the **same exit code**, so this is convergence on an existing
  convention, not a fourth representation of the same idea. Worth stating: our recurring family
  defect is the opposite.
- **`close-state.md` has zero readers** anywhere in the plugin (`grep -rn close-state
  plugins/leadv2` outside the writer is empty). The new marker is a note for a human or the next
  round; it is not a mechanism. Nothing downstream switches on `5` vs `1` either — the callers
  that matter key on sentinels, not on close's rc.
- **`leadv2-lane-outcome.sh` never reads the gate verdict at all.** It classifies on
  max_turns/subtype, the worker's final prose (`lib/leadv2-parked-detect.sh` is a *wording*
  probe), and whether the tree has work — then `died-with-work → continue`, `parked → continue`.
  A timed-out round survives as resumable **because it has commits**, not because the gate said
  unknown. So "every consumer distinguishes unknown from fail" is true of the two consumers that
  read the verdict, and vacuous for the one the lead actually looks at.

## Scope deviation, reported not hidden

Declared file was `leadv2-dispatch-product-close.sh`; the lane edited
`leadv2-phase8-e2e-gate.sh` + `leadv2-phase8-close.sh`. Justified — the conflation lives in
phase8, and product-close was already correct — but it is a deviation and is stated here.

Verdict: **acceptance proven.** Ready for merge by e9.
