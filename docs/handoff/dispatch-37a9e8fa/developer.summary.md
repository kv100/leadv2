verdict: APPROVE
next_action: review_round_2

Fixed review-r3.md's two High findings: marker-before-verb arm firing on ordinary status
prose (6/10 hand-written clauses false-fired), and the morphology suite testing a stale
regex paraphrase instead of the real hook.

- RU_OTHER_FINITE_VERB vetoes marker+candidate when the rest of the clause carries a
  second, genuinely finite verb — the shape every false positive had, no real promise did.
- Fixed a companion decimal-point sentence-split bug the same fixture exposed.
- test-promise-guard-morphology.sh rewritten to drive the real hook end-to-end (sandboxed
  HOME, synthetic transcript) — same harness as test-promise-action-binding.sh.
- All ten review-r3.md status clauses SILENT, all eleven review-r1.md promises FIRED,
  RED→GREEN mutation control in round4-red/.
- Full: full.md
