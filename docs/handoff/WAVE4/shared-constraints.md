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

## Prove the check executed before you believe it — two twins

**A mutation that did not apply reads as a control that passed.** A suite's awk/sed anchor stops
matching after the code it targets is reshaped; the mutation writes nothing, the suite stays green,
and the artifact records a control that never happened. Remedy: assert the mutant differs from the
original **byte for byte** before running it, and report the observed `baseline_rc` / `mutated_rc` /
`restored_rc` triple — never a `diff_hash`, never a tool's verdict.

**A shell that did not execute reads as a column that passed.** `test-lead-session-identity.sh` ran
every identity case through `bash -c` (deliberately — two forks give two pids under either shell), so
its "zsh column" was a bash run in a zsh wrapper: coverage of the zsh path was zero, while that path
returned the very `direct` collapse the lane existed to remove. Six passes under zsh and ten under
bash were the same run counted twice. Remedy: an explicit assertion on the value the other shell
returns — pinning a documented fail-open turns accidental green into a signal in both directions
(fix the fail-open and the case reddens, asking for a deliberate update; break the good path down to
the fallback and the two shells stop disagreeing, which the case shows).

The general rule both twins share: **green means "the check passed" only after you have proven the
check ran.** Before trusting a control, make the mutant differ; before trusting a column, make the
interpreter speak.

## The instrument was fine — that is why its silence was believed

Five forms of the same failure were measured in a single night. In none of them was the tool broken;
in every one, a working tool was pointed at something that could not contain the answer, and its
empty output was read as a fact about the world.

1. **Not that tree.** A deliverable was declared missing by a `find` run inside the lane worktree,
   while dispatch directories live in the MAIN repo. Check both, with the address named.
2. **Not that directory.** `git status | grep -vE 'docs/handoff/dispatch-'` filtered away exactly
   the directory the worker writes into; nine "produced nothing" reports were blind. And
   `git status -uall` never shows gitignored files at all, so a deliverable can be invisible to git
   entirely — use `find`.
3. **Not that arm.** Liveness belongs to the arm, not the lane: a codex arm writes no
   `handle=PID=`, so a PID probe reports death for a healthy worker. `codex-task.sh status` is
   workspace-scoped and answers "no jobs" from the wrong directory.
4. **Not that syntax.** `trace_path` with a bare function name returns `[]` when several nodes share
   the name — ten real callers, an empty answer, no error.
5. **Not that artifact.** A watcher waited for `^status:` in `e2e-gate.log`; the gate writes its
   verdict to `e2e-gate.md`. The filter could not have seen the outcome it was watching for under
   any sequence of events — not "missed it", *could not*.

The shared remedy is one question, asked before the answer is believed: **if the thing I am looking
for existed right now, would this command show it to me?** An empty result answers that question
only if the answer is yes. Otherwise the result is `unknown`, and `unknown` is not `no`.

A sixth, adjacent form is worth keeping beside these because it inverts the direction: a refusal can
be right. `REFUSE placement: lane_is_live verdict=starting:221` was the single refusal in a day of
false ones that meant exactly what it said. So a refusal gets verified the same way a death does —
by processes and files — and never dismissed by habit.

## Built, correct, and addressed by a form that barely exists

Three mechanisms were measured in one shift. None is broken. Each is nearly unreachable.

| mechanism | state | reach |
|---|---|---|
| falsifiability gate (`leadv2-review-run.sh:1269`) | unconditional, checker present | **2.6%** of dispatches carry its decision line |
| lead→worker channel (`leadv2-tell.sh` + PostToolUse hook) | built, atomic, acked once | **1.2%** of handoff directories are addressable |
| editing a brief after dispatch | writes fine, rc=0 | **0%** of workers — the mission is snapshotted at spawn |

We spent a night believing we lacked instruments. We had them; the addresses did not fit. The
product writes by founder-id, observers address by dispatch-sig, and a third format — bare hex —
appears almost nowhere. Adding one more accepted form to each caller produces a fourth
representation and repeats the cause: **there must be one address resolver, and every caller must
use it.**

Two corollaries, both about output that is not bound to behaviour:

- **A tool that prints its diagnosis where nobody reads it.** `leadv2-broad-status.sh` announces
  `26 foreign lane row(s) not dispatched by this repo dropped` on stderr while the rendered board
  says nothing — so the board reports "no lanes" when it means "no lanes of mine".
- **A tool that prints a hint it will not accept.** `leadv2-tell.sh` refuses an id, then offers a
  "Known tasks:" list built from the same directory, every entry of which its own validator
  rejects. A hint that leads away is worse than no hint.

And the reader-side rule that governs all of it: **a new state exists only as far as the last
reader in the chain distinguishes it.** Teaching a writer to emit `unknown` changes nothing while a
consumer still treats "not pass" as "fail". Enumerate the readers before changing the writer, and
prove the distinction by mutating at the reader — not by reading the list.

## Derive the probe's ability to answer, not the answer

"Derive a zero a second way" is not enough, and half a night was spent proving it: **a zero derived
twice by the same blind probe is false twice.** The rule that survives is one step earlier —

> Before believing a zero, show the probe can return non-zero at all, on a case known to be alive.

The case that forced the correction had four layers of blindness stacked in one check, over a branch
with no defects in it: a mutation applied by `perl` that turned out inert; a condition established
with `touch`, which git does not see while `--scope changed` asks git precisely that; `run-all.sh`'s
`root_escape` guard aborting the run before selection because on macOS `/tmp` is a symlink to
`/private/tmp`

```text
rc=2  run-all: FATAL root_escape expected=/tmp/… resolved=/private/tmp/…
```

and, on top, the whole thing reading as an honest negative result about the code under test. Moving
the same tree to `/private/tmp` gave `rc=0` and 109 suites selected. Nothing in the output said
"path defect"; it said "not selected", which is a sentence about the code.

Two operational consequences:

- **Temporary trees for acceptance go in `/private/tmp`, never `/tmp`.** Any check that creates a
  worktree, a fixture repo, or an `mktemp` sandbox and then runs `run-all.sh` inherits this.
- **When an acceptance says "not selected", check the path before the code.** The abort and the
  substantive answer are indistinguishable at the call site, and only one of them is about your work.

A sharper form of the same trap, worth stating separately because the two cases differ in what
they cost. In one, the path defect hid a working mechanism — unpleasant, and correctable the moment
anyone looks. In the other it took an acceptance that was **guaranteed red today** and made it green,
leaving the text of the check untouched: the falsifiable check we had just congratulated ourselves
for writing quietly stopped being falsifiable. So:

> A trap of this kind is dangerous not because it hides a defect, but because it removes the
> check's ability to show one — and nothing in the check's wording changes when that happens.

This is why the precheck belongs before the result and not beside it. An acceptance that cannot go
red is indistinguishable, at every surface we read, from an acceptance that went green honestly.
The only thing that separates them is having watched the probe answer non-zero on a case known to
be alive.

# A convention that was found, not invented

Our recurring family defect is a mechanism that is built, correct, and addressed by a form that
barely exists — the falsifiability gate reaching 2.6% of rounds, the tell channel 1.2% of
directories, a brief edited after dispatch reaching 0% of workers. Every instance had the same
shape: a caller needed to name something, did not use the existing name, and minted a fourth
representation of it.

`GATE-UNKNOWN-MUST-NOT-KILL-A-ROUND-01` is the counter-example, and it is worth keeping precisely
because it is rare. The lane had to give "the gate reached no verdict" a distinct exit code in
`leadv2-phase8-close.sh`. The sibling path `leadv2-dispatch-product-close.sh` had already solved the
same problem for its own timeout branch — `rc=124` → `status: unknown`, `_dl_note parked
e2e_timeout`, **`exit 5`**. The lane adopted **that same 5** rather than picking a free number.

The rule this instance supports:

> Before you mint a representation, look for the one a sibling path already uses. Conventions in
> this codebase are almost always found, not invented — and the cost of inventing is not paid by
> you, it is paid by the next reader who has to learn that two paths say the same thing two ways.

Two corollaries the same round produced, both about the limit of a fix at the writer:

- **A new state exists only as far as the last reader distinguishes it.** `close-state.md`, the
  marker this lane added, has zero readers anywhere in the plugin. It is a note for a human or the
  next round — legitimate, but never acceptance evidence.
- **Prove the consequence as state, not as wording.** The suite proved a log line and a marker file.
  What actually makes the round resumable is ordering: `exit 5` fires before
  `leadv2-phase8-assert.sh`, the writer of `phase8-passed.flag`, so no "finished" sentinel exists.
  Assert the ordering; drop the message assertion and the claim must still stand.

## Borrowed justification

A round needed a reason and cited a real document. `run-core-offline.sh` justified seven
`|||SERIAL` markers by membership in `_CORE_OFFLINE_OWNED_SUITES`. The list exists, the membership
is accurate, the citation is honest — and the list does not say what the reason needed it to say.
It is read in exactly one place and sets the **severity** of a hermeticity violation (owned = FAIL,
otherwise WARN). It says what happens *if* a suite dirties the tree; it never says one does.

> Before citing a declaration as a reason, ask whether it asserts the proposition you need — not
> whether it is about the same subject.

The real reason was a conjunction: *dirties the shared tree* **and** *its violations are fatal*.
The list supplied only the second half, and nobody noticed the first half had never been
established. Measuring it moved four of the seven suites into the parallel pool.

This figure is unlike the rest of our catalogue: it has nothing to do with zeros, silence, or
missing output. Everything speaks, everything is true, and the conclusion is still wrong.

## Described is a hypothesis; measured is evidence

Two root causes died in one hour, both mine, both stated confidently to a peer before being
checked: "the digest generator reads one file and writes another" (it reads and writes the same
file; its zero was a correct count under its own grammar) and "`leadv2-lanes-resume.sh` writes the
journal" (it only reads it; the writer was a `UserPromptSubmit` hook doing `os.replace` over a
symlink). Each survived being repeated twice and died on the first read of the code.

In the same hour, a behavioural result held without correction: seven suites run alone in an
isolated tree, `git status` before and after, a probe first shown able to answer DIRTY.

> A description of a cause is a hypothesis until it has been read back against the code — including
> when you wrote the description yourself. A measurement of behaviour is evidence immediately.

We spent the night applying this to other agents' reports and never once to our own.

## Before believing a control, show it changed the thing its result is blamed on

The zero rule has a twin, and it bit twice in one lane.

> Before believing a control, show that it changed exactly the thing its result is attributed to.

**A control that never writes cannot fail.** A suite's declared negative control reported GREEN
having performed no write at all: `capture_ask` dedupes on the first 60 characters of a prompt, and
the control prompt shared them with the case above it. The mutation applied, the mutant was
byte-different, the suite ran — and the subject of the check simply never occurred. This is the
cousin of "the mutation did not apply", one step further along: not the mutation missing, but the
*event under test* missing, with green meaning "there was nothing to check".

**A control that proves a different proposition.** Removing a suite's row from `EXTRA_SUITE_MAP`
left it still selected, which read as "the row is unnecessary". It was selected because the suite
file itself had changed — run-all selects changed tests directly. The honest form is to change
**only the carrier** (the hook) with the suite already committed:

```text
hook-only change:  with the map row selected=1,  without it selected=0
```

The first version proved that an edited test runs. The second proves that CI selects this suite when
the code it covers changes — which is the claim being made.

Both failures share a shape with `borrowed justification`: something true was demonstrated, and it
was not the thing that needed demonstrating.

## An empty field is honest ignorance; a stale field is false knowledge

A merge queue named the head of every branch. One of them went stale within the hour, and merging by
it would have silently dropped five commits — discovered not at merge time but later, by someone
following a reference to a record that was not there. The fix was not to refresh the field but to
decide which fields may exist at all:

> For anything still changing, record no value. A missing field makes you look; a wrong field does
> not.

Two branches in that queue therefore carry no head on purpose, with the omission itself written down
so a later reader does not helpfully fill it in from a listing. The value is read at the moment it is
used, from the thing itself.

This is the third shape of one idea in a single shift, and the three are worth seeing together:

| surface | the state | what we turned it into |
|---|---|---|
| a probe | `unknown` | "no" |
| the e2e gate | "I could not tell" | "it failed" |
| a written record | "this is still moving" | a specific stale value |

We convert ignorance into an assertion because an assertion is easier to carry forward. Each time,
the conversion is invisible at the point of use: nothing about a stale head, a zero, or a `fail`
looks different from the real thing.

**And the matching rule about scale.** When the merge queue's one stale head was found, the response
was not to fix that line: it was to re-verify all eight heads the document named (all eight held).
A defect found in a record is evidence about the record's *class*, not about the line — the same way
a mutation that reddens three cases through one branch is one witness, not three. Fixing the
instance and leaving the class is how the same defect returns wearing a different name.

**Where this file goes after the queue moves.** This branch is not a change waiting to merge; it is
an accumulator that cannot stabilise, because doctrine has nowhere else to land while `main` is
reachable through one blocked channel. Its head rotted twice in an afternoon for that reason alone.
Once the queue clears, doctrine goes to `main` directly and never rides a branch that is itself
waiting in line — otherwise the next quiet week reproduces the same unstable record by habit.
