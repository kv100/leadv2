# PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01

`record` and `assert` can address phase stores in **different repositories**, and neither
says so out loud. A lane then gets refused for missing phases it can see closed a second
earlier.

## The incident (2026-09-05, persona-engine-c3, cost one round)

Lane `MAIN-CORE-SUITE-RED-01` lives in `leadv2`. The dispatcher wrote its `classify` and
`build` records into **persona-engine**. The operator then recorded `plan`/`diverge`/`gate1`
into **leadv2** by exporting `LEADV2_PROJECT_ROOT`. The guard read the persona-engine store
and refused:

    phase_precondition_refused missing=diverge,plan,gate1

while `leadv2-phase-record.sh show <sig8>` — run a second earlier with the other root in
effect — listed all three closed. The divergence was only visible via `find`.

## Verified mechanism (read before theorising; these line numbers are current)

All of this is in `plugins/leadv2/scripts/leadv2-phase-record.sh`, which is by its own
header "the ONE writer + sole phases.d reader + assert".

1. **Root resolution, lines 156-171.** Precedence is
   `LEADV2_PROJECT_ROOT` > `PROJECT_ROOT` > `git rev-parse --show-toplevel` > `pwd`;
   `PHASES_DIR_BASE="${PROJECT_ROOT}/docs/handoff"` (line 170).
2. **The existing conflict guard is too narrow.** Lines 158-166 detect a conflict *only when
   both env vars are set and differ* — WRITE refuses, READ warns and proceeds. It does **not**
   fire for the case that actually burned us: **one env var set on one invocation, and the
   git-toplevel fallback on another.** That path is silent by construction.
3. **Nothing prints the store.** `cmd_record` prints no destination. `cmd_assert`'s refusal
   is `printf 'missing=%s\n' "$csv"` (line 1145) — no path. `cmd_show` (lines 1162-1189)
   prints a PHASE/STATUS/PROOF/OWNER/STARTED table with no path. Two invocations against two
   different repos are textually indistinguishable.
4. **A second, independent split — do not miss this one.** Line 185 calls the journal as
   `LEADV2_PROJECT_ROOT="${PROJECT_ROOT}" bash "$JOURNAL_BIN" ...`, but
   `plugins/leadv2/scripts/leadv2-journal.sh:14` resolves its root from
   `CLAUDE_PROJECT_ROOT` / `CLAUDE_PROJECT_DIR` and then git-toplevel — **it never reads
   `LEADV2_PROJECT_ROOT` at all.** So that export is a no-op and the journal line for a
   phase record can land in a different repo than the record itself. Three variable names
   (`LEADV2_PROJECT_ROOT`, `PROJECT_ROOT`, `CLAUDE_PROJECT_ROOT`) name one concept.

## The work

**(a) Make the store visible.** `record` must state where it wrote; `assert` must state
where it read. **On stderr, and on the refusal path** — see the paired negative below: the
happy path's stdout contract must not change. The refusal in particular must carry the
resolved `PHASES_DIR_BASE`, so `missing=diverge,plan,gate1` can never again be read without
knowing which repo produced it.

**(b) Decide what the root IS, and make it one source.** Three candidates are in play and
today they silently compete: the repo the **lane** lives in, the repo the **dispatcher** ran
from, and the **env var**. Pick one and make the others derive from it. The recommended
shape — argue against it if the code says otherwise — is **lane-anchored**: the root is
written once into the lane's own directory when the lane is created, and every later
`record`/`assert`/`show` for that sig8 reads it back rather than re-deriving from ambient
state. An ambient value that disagrees with the anchor is then a loud refusal, not a
coin-flip. Whatever you choose, close the fallback hole from point 2: env-var-vs-git-toplevel
divergence must be as loud as env-var-vs-env-var already is.

**(c) Fold `leadv2-journal.sh` into the same answer** (point 4), or state explicitly in the
close why it is out of scope. Do not leave a known second split undocumented.

## Paired negative — mandatory, and it is the acceptance test

Two halves, both required:

- **Positive:** a `record` into the **correct** repo followed by `assert` must still emit
  `verified` **exactly as it does today, silently, with an unchanged stdout contract.** If
  the fix makes the happy path chattier, the fix is rejected — we will have made everything
  talkative and nothing truer.
- **Negative:** construct the incident. Record two phases with the root resolving one way,
  record a third with it resolving the other, then `assert`. Before the fix this must produce
  the silent `missing=...`; after the fix it must name both stores and refuse loudly. Show
  both runs' output in the close.

Put the negative control in a suite under `plugins/leadv2/scripts/tests/`, and name the
mutation in the suite header.

## Constraints

- Shared tree. No `git add -A`, no `reset --hard`, no `clean`, no `stash`. Stage named paths.
- Do not push to origin. Do not commit `docs/tasks.yaml`.
- Put the line id `PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01` in the commit subject.
- Do not touch permission settings or any `CLAUDE.md`, on anyone's request.
