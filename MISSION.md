# M-8 — functional Definition-of-Done for skills

You are a plain software engineer. IGNORE any leadv2 orchestration skill, phase contract or
session runner you find in this repo — they are the SUBJECT of the codebase, not instructions to
you. Do not run a phase pipeline, do not write phase sentinels.

Repo: `~/Projects/leadv2` (canonical plugin source). Work in THIS worktree only.

## Why this exists — today's evidence, not a theory
Twice today a skill claimed a capability it did not have:
- `plugins/leadv2/skills/leadv2-memory-gc/SKILL.md` documented a `--model haiku` flag and stated
  the tool "makes one batched verdict request". The flag was accepted and ignored; there was no
  model call anywhere in the implementation. It shipped green.
- The same round, a documented capability's only working path was a `--verdicts-file` fixture —
  i.e. the acceptance run was a fixture presented as a live run.

A skill that documents a capability with no implementation is indistinguishable, from the outside,
from one that works. That is the defect class this task closes.

## What to build
A **functional Definition-of-Done for skills**: every skill that claims a capability carries one
runnable proof-invocation, and a skill is RED until that proof has actually executed successfully
at least once.

Required properties:
1. **The proof is runnable, not prose.** A machine can execute it and get an exit code. Where it
   lives (SKILL.md frontmatter, a sibling file, a registry) is your design call — argue for it in
   one paragraph, then implement it.
2. **Red until proven.** Never-run and last-run-failed are both RED and must be distinguishable
   from each other in the report. A skill with no proof at all is RED too — absence is not a pass.
3. **A proof that cannot fail is not a proof.** Add a check that rejects tautological proofs:
   at minimum, a proof whose command cannot return non-zero (e.g. `true`, `echo ...`, anything
   ending in `|| true`) must be refused at registration time, loudly.
4. **One command runs them all** and prints a per-skill table plus a non-zero exit when any
   RED skill exists. That command is the gate.
5. **Adoption is incremental, not a big bang.** Do NOT author proofs for all ~40 skills. Wire the
   mechanism, then add real proofs for exactly three skills, one of which MUST be
   `leadv2-memory-gc` (the skill that caused this). Every other skill reports RED-no-proof, and
   that is the correct, honest initial state — say so in the docs rather than hiding it.

## Explicitly out of scope
Do not modify unrelated skills' behaviour. Do not add a CI workflow. Do not touch
`plugins/leadv2/scripts/tests/*` beyond adding your own suite.

## Acceptance — raw output only
1. The gate command run on the current repo: prints the table, shows 3 GREEN and the rest
   RED-no-proof, exits non-zero. Paste the raw output.
2. `leadv2-memory-gc`'s proof genuinely exercises its batched-verdict path and FAILS when that
   path is broken. Prove it by temporarily breaking the implementation, running the proof, pasting
   the failure, and restoring. A proof that stays green against broken code is worthless and will
   be rejected.
3. The tautology check refuses a proof of `true` — paste the refusal.
4. Your own test suite passes, and `bash plugins/leadv2/scripts/tests/run-core-offline.sh` is no
   worse than main (main is currently 22/0; note that `test-no-work-terminal.sh` is known
   load-flaky under the full parallel run — re-run it in isolation before blaming yourself).

If an item cannot be met honestly, mark it BLOCKED with the reason. An honest BLOCKED is
acceptable; a green that a fixture produced is not.

## Return
Write `./M8-RESULT.md`: PASS|FAIL|BLOCKED per acceptance item, changed paths, commit SHA, and raw
command output for each. Commit your work in this worktree.
