# architect prepass — RED-FIRST-SELF-INVALIDATES-01

Repo `~/Projects/leadv2`, `main` at `7de23af`. Design only; no implementation here.

---

## §0. The mission's framing is contradicted by the tree — correction first

The mission states:

> Run standalone (`bash plugins/leadv2/scripts/tests/test-parked-worker-resume.sh`) the same
> suite on the same commit gives `pass=9 fail=0`. So the difference is the harness context,
> not the product.

**That is false on the current tree.** Measured just now, standalone, on `7de23af`, in the main
checkout:

```
$ git rev-parse --short HEAD; git rev-parse --short HEAD^
7de23af
b680643
$ bash plugins/leadv2/scripts/tests/test-parked-worker-resume.sh 2>&1 | tail -12
[TEST] FAIL: contract red-first (pre=0 post=0)
[TEST] PASS: clean waiting result with unsatisfied deliverable classifies parked
[TEST] PASS: parked outcome carries continue next
[TEST] PASS: clean success stream replay is parked-shaped
[TEST] PASS: clean success with deliverable does not resume
[TEST] PASS: parked lane launches exactly one resume
[TEST] PASS: second parked exit does not loop
[TEST] PASS: second parked exit journals already_attempted
[TEST] PASS: positive control died-with-work resume remains green
[TEST] RESULT: pass=8 fail=1
```

Standalone is `pass=8 fail=1`, identical to the harness result. The cause is arithmetic, not
context:

```
$ git rev-list --parents -n1 b680643
b6806438… 78bcb9b4… 4d340e20…
$ git log --oneline -S'_LEADV2_FOREGROUND_CONTRACT_MISSION' --reverse -- plugins/leadv2/scripts/leadv2-helpers.sh | head -1
4d340e2 fix: detect workers parked on background jobs
$ git grep -c '_LEADV2_FOREGROUND_CONTRACT_MISSION' HEAD^ -- plugins/leadv2/scripts/leadv2-helpers.sh
HEAD^:plugins/leadv2/scripts/leadv2-helpers.sh:2
```

`test-parked-worker-resume.sh:15` computes its "pre" tree as `HEAD^`. On `main`, `HEAD^` is
`b680643` — the merge commit that **landed the fix**. So the baseline already contains
`_LEADV2_FOREGROUND_CONTRACT_MISSION`, `contract_case` returns 0, `pre=0`, and line 35's
`[[ ${pre} -ne 0 && ${post} -eq 0 ]]` is unsatisfiable. There is no harness-dependent
behaviour to chase.

Design consequence: **do not build a harness-isolation fix.** The defect is the baseline
selector. Everything below designs against that.

The mission's diagnosis of the *disease* — "an assertion about an unrepeatable moment in
history" — is exactly right; only the attributed mechanism was wrong.

---

## §1. CALLERS / CALLEES

### 1a. Who runs the affected suites (upward chain, with file:line)

```
leadv2-phase8-e2e-gate.sh:3,13-14,258
  └─> tests/run-all.sh --scope changed
        ├─ run-all.sh:79-80   add_suite plugins/leadv2/scripts/tests/run-core-offline.sh   [ALWAYS]
        │    └─ run-core-offline.sh:267  "parked worker contract and one-shot resume (WORKER-PARKED-ON-BG-01)|||bash $TEST_DIR/test-parked-worker-resume.sh"
        │    └─ run-core-offline.sh:268  "product-close scopes a single-repo lane worktree|||bash $TEST_DIR/test-lane-diff-single-repo.sh"
        │    └─ run-core-offline.sh:309  "builder selfcheck gate …|||bash $TEST_DIR/test-builder-selfcheck-gate.sh"
        │    └─ run-core-offline.sh:311  "claim-evidence gate …|||bash $TEST_DIR/test-claim-evidence-gate.sh"
        └─ run-all.sh:99-117  stem-match: any changed plugins/leadv2/scripts/<stem> pulls in tests/test-<stem>.sh   [CONDITIONAL]
             └─ this is the ONLY path that runs test-lane-root-not-a-worktree.sh,
                test-lane-writes-scoping.sh, test-landing-diff-scoping.sh,
                test-codex-worktree-trust.sh, test-codex-reap-log-mtime-liveness.sh,
                test-codex-transport-attribution.sh
```

`run-all.sh:148` prints `run-all: N passed, M failed`; non-zero `FAIL` → non-zero exit →
`leadv2-phase8-e2e-gate.sh:13-14` does **not** write the sentinel → the lane is blocked.

**Different-path copy nobody named (the usual miss):** there is a *second, independent*
red-first mechanism in this repo — `plugins/leadv2/scripts/leadv2-red-first-gate.sh`. It
implements the same idea correctly and externally: `probe --base <ref>` builds the pre-fix
tree with `git worktree add --detach <base>`, copies in the working-tree test file, runs
both, and classifies per-label (`leadv2-red-first-gate.sh:20-32`). Its callers:

- `leadv2-phase8-assert.sh:500-523` — A10, blocking unless `LEADV2_RED_FIRST=warn`
- `leadv2-phase8-close.sh:291-300` — R3 headline, read-only
- `plugins/leadv2/scripts/tests/test-red-first-gate.sh:44,179` — its own suite, `--base HEAD`
  against a synthetic fixture repo (correct: the fixture's HEAD *is* pre-fix by construction)

This gate is **not** affected by the defect (its `--base` is caller-supplied and lane-scoped),
and it is the design authority for the vocabulary below. The in-file red-first harnesses are
a hand-rolled duplicate of it. **Non-goal for this lane:** collapsing them into the gate.

### 1b. Callees of the functions being touched

| Function / block | file:line | Calls |
|---|---|---|
| baseline block | `test-parked-worker-resume.sh:13-19` | `git rev-parse HEAD^`, `git archive`, `tar -x` |
| `contract_case()` | `test-parked-worker-resume.sh:23-32` | `awk`, `grep`, reads `${s}/leadv2-helpers.sh`, `${s}/leadv2-dispatch-code.sh` |
| baseline block | `test-lane-root-not-a-worktree.sh:99-102` | `git merge-base origin/main HEAD`, `git archive`, `tar` |
| baseline block | `test-lane-writes-scoping.sh:513-518` | `git archive HEAD`, `tar` |
| baseline block | `test-lane-diff-single-repo.sh:271-274` | `git archive HEAD`, `tar` |
| baseline block | `test-landing-diff-scoping.sh:450-453` | `git archive HEAD`, `tar` |
| baseline block | `test-claim-evidence-gate.sh:74-91` | `merge-base`, **`git grep` content probe ×3**, pinned `559cf15`, `git archive` |
| baseline block | `test-builder-selfcheck-gate.sh:259-271` | `merge-base`, **`git grep` content probe ×1**, pinned `85ae886`, fallback `HEAD`, `git archive` |
| baseline block | `test-codex-worktree-trust.sh:30…` | `git show` of merge-base into a pristine copy |

Nothing outside `plugins/leadv2/scripts/tests/` calls any of these. No product script sources
a test file. Blast radius is confined to the test tree plus the two gate exit codes above.

---

## §2. THE CENSUS — every self-invalidating red-first site

Classification key:
- **BLOCKING** = a vacuous baseline turns into a non-zero suite exit (lane dies).
- **SILENT** = a vacuous baseline is printed but the suite still exits 0 (evidence quietly
  evaporates; nobody notices the guard stopped guarding).
- **IMMUNE** = already carries a content probe + pinned floor.

| # | Suite | Baseline expression | Vacuity → exit | Verdict | Action |
|---|---|---|---|---|---|
| S1 | `test-parked-worker-resume.sh:15` | `git rev-parse HEAD^`, floor `6fa4823` only if `HEAD^` **unresolvable** | `:35` `bad` → `FAIL=1` → `:81` exit 1 | **BLOCKING, live-red today** | Convert to lib; floor `6fa4823` (verified marker-free) |
| S2 | `test-lane-root-not-a-worktree.sh:99` | `merge-base origin/main HEAD`, **no probe, no floor** | `:112` `GREEN_PRE_FIX++` → `:142` exit 1 | **BLOCKING, latent** — trips the day the fix reaches `origin/main` | Convert to lib; pin floor |
| S3 | `test-builder-selfcheck-gate.sh:269` | probe→`85ae886`, but `[[ -n … ]] \|\| LEADV2_TEST_BASELINE_REF="HEAD"` | `:1143` `GREEN_PRE_FIX>0` → exit 1 | **BLOCKING, latent hole** — only when `merge-base` yields empty (no `origin/main`: fresh clone, detached CI, lane worktree without a remote) | Replace the `HEAD` fallback with `RF_BASELINE_UNUSABLE` |
| S4 | `test-lane-writes-scoping.sh:516` | `git archive HEAD` hard-coded | `:537` `GREEN_PRE_FIX++`; `:563` only `FAIL` gates → exit 0 | **SILENT** — vacuous the instant the fix is committed | Convert to lib; pin floor |
| S5 | `test-lane-diff-single-repo.sh:273` | `git archive HEAD` hard-coded | `:286` `RF_GREEN_PRE_FIX++`; `:320` only `POST_FAIL_COUNT` gates → exit 0 | **SILENT** | Convert to lib; pin floor |
| S6 | `test-landing-diff-scoping.sh:452` | `git archive HEAD` hard-coded | `:462`; `:490` only `POST_FAIL_COUNT` gates → exit 0 | **SILENT** | Convert to lib; pin floor |
| S7 | `test-codex-worktree-trust.sh:30` | merge-base copy of one script | `:182` `GREEN_PRE_FIX++`; `:206` only `FAIL` gates → exit 0 | **SILENT** | Convert to lib; pin floor |
| S8 | `test-codex-reap-log-mtime-liveness.sh:20,160` | committed block vs working block | `:159`; `:177` only `FAIL` gates → exit 0 | **SILENT** | Convert to lib; pin floor |
| S9 | `test-codex-transport-attribution.sh:146` | same idiom | `:145`; `:161` only `FAIL` gates → exit 0 | **SILENT** | Convert to lib; pin floor |
| R1 | `test-claim-evidence-gate.sh:74-86` | merge-base **+ 3-marker `git grep` probe** → pinned `559cf15`; final `\|\| "559cf15"` | `:480` exit 1 | **IMMUNE** | Reference implementation. Refactor onto lib, **no semantic change** |
| R2 | `test-red-first-gate.sh:44,179` | `--base HEAD` on a synthetic fixture repo | n/a | **IMMUNE by construction** | No change |
| R3 | `test-e2e-foreign-failure.sh:14-17` | explicitly avoids `git archive HEAD`; uses an env-toggled pre-fix-equivalent | n/a | **IMMUNE by design** | No change |
| R4 | `test-acceptance-shape.sh:9-11` | "the file did not exist pre-fix" | n/a | **DEGENERATE but honest** | No change; census entry only |

Pinned-floor sanity, verified:

```
$ for r in 6fa4823 559cf15 85ae886; do git rev-parse -q --verify ${r}^{commit} >/dev/null && \
    echo "$r ok marker=$(git grep -c '_LEADV2_FOREGROUND_CONTRACT_MISSION' $r -- plugins/leadv2/scripts/leadv2-helpers.sh | wc -l)"; done
6fa4823 ok marker=0
559cf15 ok marker=0
85ae886 ok marker=0
```

`6fa4823` is already written into `test-parked-worker-resume.sh:16` as a floor and is
marker-free — it is simply unreachable, because `HEAD^` always resolves.

**Nine self-invalidating sites. Two blocking today or on the next merge, one blocking on a
remote-less checkout, six silently vacuous. One instance twice is a pattern; this is nine.**

---

## §3. DECISION — option (a), with (b)'s SKIP reserved for the degenerate case

**Chosen: (a) pin the baseline to a commit.** Reasons, in order:

1. **It is already this repo's convention.** `test-claim-evidence-gate.sh:74-86` and
   `test-builder-selfcheck-gate.sh:259-269` independently converged on
   *merge-base → content-probe → pinned floor*. Two suites, two authors, same answer. A
   third mechanism would be a third thing to keep honest.
2. **(b) alone surrenders the guard on `main`.** A self-skipping lane-time-only check means
   the repo's most-run tree — `main`, where `run-core-offline.sh` executes 62 suites — carries
   zero red-first evidence. The mission's own complaint is that the assertion "stops meaning
   anything"; SKIP-on-main makes that permanent by design rather than by accident.
3. **(a) keeps the assertion true on any branch, forever**, which is what the mission asks
   for verbatim.
4. **(b) is still needed, but only where (a) genuinely cannot run.** A pinned SHA can rot:
   `git gc` on a shallow clone, a submodule-style re-root, a file that did not exist at the
   pin. In that one case the honest outcome is neither PASS (a lie) nor FAIL (a false red on
   unrelated work) — it is an explicit, reasoned SKIP. This matches the existing gate's
   `INCONCLUSIVE / "could not run" != red` classification
   (`leadv2-red-first-gate.sh:26`), so it introduces no new vocabulary.

Net: **pinned baseline is the mechanism; SKIP is the failure mode of the mechanism, not an
alternative to it.**

Rejected alternative — "delete the assertion": forbidden by the mission and wrong; S2/S3 are
latent and would rot silently.

Rejected alternative — "make every in-file harness call `leadv2-red-first-gate.sh`": correct
long-term, far past this lane's blast radius (nine suites × a process-spawning gate that
creates git worktrees, inside `run-core-offline.sh`'s locked, hermeticity-checked run). Noted
as follow-up, explicit non-goal here.

---

## §4. THE MECHANISM — `tests/lib/red-first-baseline.sh` (to-create)

One shared resolver so nine copies become one. Sourced, not exec'd (callers need the
variables).

### 4a. Interface contract

| Name | Kind | Meaning |
|---|---|---|
| `RF_PINNED_FLOOR` | in (caller sets, **required**) | SHA known marker-free for this suite's fix |
| `RF_PROBE_PATHSPEC` | in (required) | pathspec passed to `git grep` |
| `RF_PROBE_PATTERN` | in (required) | fixed-string marker that exists post-fix, absent pre-fix |
| `RF_ARCHIVE_PATHS` | in (optional, default `plugins/leadv2/scripts`) | what `git archive` extracts |
| `LEADV2_TEST_BASELINE_REF` | in (env, optional) | operator override; **bypasses probe, honoured verbatim** |
| `rf_resolve_baseline <repo>` | fn | resolves and exports the below; returns rc per §5 |
| `RF_BASELINE_REF` | out | the ref finally chosen (empty when rc≠0) |
| `RF_BASELINE_SOURCE` | out | `env` \| `merge-base` \| `pinned` — for the printed reason |
| `RF_BASELINE_REASON` | out | one human sentence, printed by the caller on rc≠0 |
| `rf_extract_baseline <repo> <destdir>` | fn | `git archive "$RF_BASELINE_REF" $RF_ARCHIVE_PATHS \| tar -x -C <destdir>`; rc 0/4 |
| `rf_skip <name> <reason>` | fn | prints `[TEST] SKIP: <name> — <reason>`, increments `RF_SKIPPED` |

Resolution order inside `rf_resolve_baseline`:

1. `LEADV2_TEST_BASELINE_REF` non-empty → use verbatim, `source=env`, **no probe**
   (an operator pinning a ref for debugging must not be second-guessed).
2. `git merge-base origin/main HEAD` → if non-empty **and** the probe finds no marker there →
   use it, `source=merge-base`. This keeps the honest, always-fresh path live.
3. Otherwise `RF_PINNED_FLOOR` → if resolvable **and** probe-clean → use it, `source=pinned`.
4. Otherwise rc 3, `RF_BASELINE_UNUSABLE`.

The probe is the whole fix: **a baseline that already contains the marker is not a baseline.**

### 4b. Per-suite call shape (S1 shown; S2, S4–S9 identical modulo constants)

`test-parked-worker-resume.sh` lines 13–35 become:

```
RF_PINNED_FLOOR=6fa4823
RF_PROBE_PATHSPEC='plugins/leadv2/scripts/leadv2-helpers.sh plugins/leadv2/scripts/leadv2-dispatch-code.sh'
RF_PROBE_PATTERN='_LEADV2_FOREGROUND_CONTRACT_MISSION'
rf_resolve_baseline "${REPO}"; rf_rc=$?
… rc 0 → extract, run contract_case twice, assert pre!=0 && post==0
… rc 3/4 → rf_skip "contract red-first" "$RF_BASELINE_REASON"   (no PASS, no FAIL)
```

The eight behavioural assertions (lines 37–78) are **not touched**. `PASS`/`FAIL` accounting
is unchanged; a new `RF_SKIPPED` counter is printed on the RESULT line and does **not** affect
the exit code.

### 4c. Suites S4–S9 (the SILENT class)

Two changes each: swap `git archive HEAD` for `rf_resolve_baseline` + `rf_extract_baseline`,
and — because their whole point is red-first evidence — make `GREEN_PRE_FIX > 0` **fail** the
suite, matching S1/S2/S3/R1. This is the one place the design deliberately *tightens* rather
than loosens. Justification: a silently vacuous guard is strictly worse than a loud one, and
once the baseline is pinned, `GREEN_PRE_FIX > 0` can no longer be caused by "the fix is
merged" — it can only mean a genuinely tautological case.

**Risk this creates and its mitigation:** turning six exit-0 suites into exit-1-capable
suites can red a lane that touches an unrelated stem. Mitigation: the implementer must run
each of S4–S9 standalone on the lane *before* committing and report the counts; any suite that
reds under the pinned floor gets its floor corrected, not its gate relaxed. If a floor cannot
be found that makes a case red, that case is a genuine tautology and belongs in the report as
a finding, not silently in `GREEN_PRE_FIX`.

---

## §5. STATES AND RETURN CODES

### 5a. `rf_resolve_baseline` — every state, every rc, and what the caller does

| rc | Symbol | State that produces it | Caller action | User-visible consequence |
|---|---|---|---|---|
| 0 | `RF_OK` | A probe-clean ref was found (env / merge-base / pinned) | extract, run both passes, assert red→green | Suite prints `[TEST] PASS: <name>` or a real `FAIL`. Normal. |
| 3 | `RF_BASELINE_UNUSABLE` | merge-base empty **and** pinned floor missing from the object store, **or** every candidate already contains the marker | `rf_skip` the red-first case only | `[TEST] SKIP: contract red-first — pinned floor 6fa4823 not in this object store (shallow clone?)`. Suite still exits 0 if the eight behavioural assertions pass. **A lane is not blocked, and the log says exactly why the evidence is missing.** |
| 4 | `RF_EXTRACT_FAILED` | ref resolved but `git archive \| tar` produced no `leadv2-helpers.sh` (path did not exist at that ref; disk full; tar absent) | `rf_skip` the red-first case only | `[TEST] SKIP: … — archive of <ref> yielded no plugins/leadv2/scripts`. Same non-blocking outcome as rc 3. |
| 2 | `RF_BAD_USAGE` | caller did not set `RF_PINNED_FLOOR` / `RF_PROBE_PATTERN` | **hard `exit 2`** from the suite | Suite dies with `[TEST] FATAL: red-first lib misused …`. **This one must be loud** — it is a bug in a test, and a silent SKIP here would recreate exactly the disease being cured. |

**Terminal trace, in plain words.** Today: rc-equivalent "vacuous" → `bad()` →
`FAIL=1` → `test-parked-worker-resume.sh:81` exit 1 → `run-core-offline.sh:267` records the
suite failed → `run-all.sh:148` `FAIL≥1` → non-zero exit →
`leadv2-phase8-e2e-gate.sh:13-14` **does not write the sentinel** → *every lane in this repo
is blocked at Phase 8 by a suite that has nothing to do with what that lane changed.* That is
the outage in the mission's second paragraph, stated as a user-visible fact.

After the fix: the same state resolves to rc 3 → `SKIP` → suite exits 0 → sentinel written →
lanes proceed, and the run log carries one line naming the missing evidence.

### 5b. Suite-level exit codes after the change

| Condition | Exit | Consumer effect |
|---|---|---|
| all assertions pass, `RF_SKIPPED=0` | 0 | sentinel written |
| all pass, `RF_SKIPPED>0` | 0 | sentinel written; SKIP line in `run-core-offline` log |
| any behavioural `FAIL` | 1 | lane blocked (correct — real regression) |
| `GREEN_PRE_FIX>0` with a probe-clean pinned baseline | 1 | lane blocked (correct — genuine tautology) |
| lib misused (`RF_BAD_USAGE`) | 2 | lane blocked (correct — broken test) |

---

## §6. CONFIGURATION BOUNDARIES

Every input the mechanism reads, at each boundary.

### `LEADV2_TEST_BASELINE_REF` (env)

| Boundary | Behaviour |
|---|---|
| absent | fall through to merge-base → pinned. Normal path. |
| empty string | treated as absent (`${VAR:-}` + `[[ -n ]]`), **not** as "use empty ref". |
| valid SHA / ref | honoured verbatim, probe skipped, `source=env`. Operator override is deliberate. |
| ref that does not resolve | `git archive` fails → rc 4 → SKIP with the ref named in the reason. **Never** silently falls back — a typo'd override must not masquerade as a pass. |
| over-cap: a 4 KB junk value | `git rev-parse --verify` fails, rc 4, SKIP. Bounded: the value is only ever passed to `git`, never `eval`'d, never interpolated into a shell string unquoted. |
| malformed: contains `;`, `$(…)`, backticks, newline | quoted in every expansion, so `git` rejects it as a bad ref → rc 4 → SKIP. **Explicit requirement for the implementer: no unquoted expansion of this variable anywhere.** |
| **run-core-offline interaction** | `run-core-offline.sh:104-108` scrubs `LEADV2_*` from the child environment (`-u "$v"` for every `LEADV2_*`). So under the full runner this variable is **always absent** and the merge-base→pinned path is the one that runs. The implementer must not design a fix that depends on setting it. |

### `RF_PINNED_FLOOR` (per-suite constant)

| Boundary | Behaviour |
|---|---|
| unset / empty | rc 2, `RF_BAD_USAGE`, suite exits 2 — loud, by design |
| SHA not in object store (shallow clone, gc'd) | rc 3 → SKIP with reason |
| SHA resolves but **contains** the marker (wrong pin) | rc 3 → SKIP with reason `pinned floor already contains <pattern> — the pin is wrong`. Crucially **not** a FAIL: a wrong pin is a defect in the test, and it must not take down every other lane while someone fixes it. |
| SHA resolves, marker-free, but the probed path does not exist at that ref | `git grep` finds nothing → probe-clean → chosen → `rf_extract_baseline` yields no scripts → rc 4 → SKIP. Correct: "the file did not exist yet" is inconclusive, not evidence. |

### `RF_PROBE_PATTERN` / `RF_PROBE_PATHSPEC`

| Boundary | Behaviour |
|---|---|
| pattern unset/empty | rc 2. An empty pattern matches everything and would mark **every** ref dirty, forcing permanent SKIP — a silent global disarm. Must be loud. |
| pattern present in the working tree but nowhere in history | every candidate is probe-clean; merge-base is chosen; the assertion runs and legitimately goes red→green. Fine. |
| pattern **absent from the working tree too** | the fix is not actually in the tree; `post` fails; the suite goes red. Correct and desirable. |
| pathspec naming a nonexistent file | `git grep` returns rc 1 with no output = probe-clean. Combined with the extract check (rc 4) this degrades to SKIP, not a false pass. |
| regex metacharacters in the pattern | use `git grep -qF` (fixed string) throughout. Named explicitly so no suite accidentally gets regex semantics. |

### `origin/main` (implicit input)

| Boundary | Behaviour |
|---|---|
| remote absent (fresh clone, lane worktree with no remote) | `merge-base` empty → pinned floor. **This is exactly the S3 hole**: `test-builder-selfcheck-gate.sh:269` currently falls back to `HEAD` here, which is the worst possible baseline. |
| `origin/main` stale (not fetched) | merge-base points at an older commit — probe-clean, still a valid pre-fix baseline. Harmless. |
| `origin/main` ahead, already contains the fix | probe catches it → pinned floor. **The mission's core defect, closed.** |

### The git object store / worktree

| Boundary | Behaviour |
|---|---|
| suite run from a lane worktree | `git -C "${REPO}"` where `REPO=git rev-parse --show-toplevel`; worktrees share the object store, so pinned SHAs resolve. Verified: `git worktree list` shows 11 worktrees off this repo. |
| `GIT_DIR` / `GIT_WORK_TREE` inherited | scrubbed by `run-core-offline.sh:104` before each suite. Standalone runs may still inherit them; all `git` calls use explicit `-C "${REPO}"`, which is authoritative over `GIT_WORK_TREE` but **not** over `GIT_DIR`. Implementer must `env -u GIT_DIR -u GIT_WORK_TREE git -C …` inside the lib, or the standalone path can read a foreign repo. |
| read-only `TMPDIR` / no space | `mktemp -d` fails → rc 4 → SKIP. |

**Boundary rule applied throughout:** no input to this mechanism may take down more than the
single red-first case it belongs to. The only exception is `RF_BAD_USAGE` (rc 2), which is a
programming error in the test itself, not an environmental input.

---

## §7. COUNTEREXAMPLE — what still violates the invariant after every finding is fixed

The invariant is: *a green red-first assertion means the fix's absence was actually
demonstrated to break something.*

After all nine sites are pinned and probed, **three things can still violate it, and only one
is in scope.**

The first and sharpest: **the probe marker is chosen by the test author, and a marker can be
present without the behaviour being present.** `contract_case` at
`test-parked-worker-resume.sh:23-32` does not exercise the parked-detection code path at all —
it greps `leadv2-dispatch-code.sh` for four literal strings and compares two `grep -n` line
numbers. Pin whatever baseline you like: this asserts that a source file contains certain
text in a certain order. Someone can reorder the `case` arms, keep every marker, keep the line
ordering, and break the mechanism; the assertion stays green on both sides and the pinned
baseline reports a healthy red→green because the *text* moved. **The pinned baseline makes the
assertion permanently evaluable; it does not make it behavioural.** Concretely: after this
lane, S1's red-first case will pass forever for the reason that `6fa4823` lacks a string —
which is a true statement about history and a weak statement about the product. The eight
behavioural assertions in the same file are the real guard; the mission forbids touching them,
correctly, and they are where the value is. This is the honest limit of the chosen design and
belongs in the implementer's report verbatim, not buried.

Second, in scope but only partly closable: **a pinned floor is a promise about a commit that
nobody re-checks.** The probe verifies the *marker* is absent at the floor; it cannot verify
the floor is the *right* pre-fix commit. Pin one commit too early and the case may go red for
an unrelated reason ("could not run" masquerading as evidence); the design mitigates this by
requiring `rf_extract_baseline` to prove the probed files exist at the floor (rc 4 otherwise),
which catches the common "too early, file didn't exist" case but not "too early, different
bug". Mitigation is procedural: the implementer records, per suite, the `git log -S<marker>
--reverse` output that justifies each pin. That evidence goes in the report.

Third, out of scope: the parallel `leadv2-red-first-gate.sh` mechanism and the in-file
harnesses can disagree, and `leadv2-phase8-assert.sh:523` lets `LEADV2_RED_FIRST=warn` demote
the gate's verdict to a warning. Nothing in this lane touches that switch.

What I checked to reach this answer: all nine baseline expressions read at their lines; both
gate consumers (`phase8-assert.sh:500-523`, `phase8-close.sh:291-300`); the full
`run-all.sh` → `run-core-offline.sh` → suite chain; the four pinned SHAs verified marker-free
against the live object store; and the assertion body of S1 read in full.

---

## §8. OUT OF SCOPE (implementer: ignore these)

- The two known-foreign suites: **deferred-GLM ladder (V3-GLM-LADDER-01)** and **fanout
  classifier/runner guard**. Do not open them.
- The eight behavioural assertions in `test-parked-worker-resume.sh:37-78`. Untouched.
- `leadv2-red-first-gate.sh` and `test-red-first-gate.sh` — a separate, correct mechanism.
- Migrating the in-file harnesses onto `leadv2-red-first-gate.sh`. Follow-up, not this lane.
- `leadv2-phase8-assert.sh` A10 semantics and `LEADV2_RED_FIRST=warn`.
- `test-e2e-foreign-failure.sh`, `test-acceptance-shape.sh` — census entries only, no edit.
- Merging to `main`. Commit on the lane branch; the lead lands it.
- Any `git reset --hard` / `clean` / `stash` — the tree is shared with live sessions.

---

## §9. Constraint checklist

1. **Env var naming** — the only env var read is `LEADV2_TEST_BASELINE_REF`, already in use at
   `test-claim-evidence-gate.sh:74`, `test-builder-selfcheck-gate.sh:259`,
   `test-lane-root-not-a-worktree.sh:99`. No new env var introduced. No `LEAD_V2_*` drift.
2. **File paths** — all census paths verified present on disk by `grep -n` at the cited lines.
   `plugins/leadv2/scripts/tests/lib/red-first-baseline.sh` and
   `plugins/leadv2/scripts/tests/test-red-first-baseline-lib.sh` are marked **(to-create)**.
   Note `plugins/leadv2/scripts/lib/` exists; `plugins/leadv2/scripts/tests/lib/` does not yet.
3. **`claude -p` commands** — none in this design. N/A.
4. **Concurrent access** — `run-core-offline.sh:47-60` holds an exclusive flock on
   `/tmp/leadv2-core-offline.lock` for the whole run, so two suites never race. Within a
   suite, each baseline extraction uses its own `mktemp -d`; the shared lib must **not**
   introduce a fixed-path cache under `/tmp` (11 live worktrees off this repo would collide).
   Race surface: none introduced, provided that rule holds.
5. **Config contradiction** — `LEADV2_TEST_BASELINE_REF` semantics ("operator-supplied
   baseline ref, honoured verbatim") match all three existing usages. But note the
   interaction in §6: `run-core-offline.sh:104` scrubs all `LEADV2_*`, so under the full
   runner this override is unreachable. That is not a contradiction, but it **is** a trap: no
   fix may depend on setting it. Flagged, not silently skipped.
6. **Bash 3.2** — the repo standing decision forbids Bash 4+ features. The lib must use no
   associative arrays, no `${var^^}`, no `mapfile`. `run-core-offline.sh:25` states this
   explicitly.

---

## §10. Implementation sequence (additive-first)

1. Create `plugins/leadv2/scripts/tests/lib/red-first-baseline.sh`. Nothing sources it yet —
   zero blast radius.
2. Create `plugins/leadv2/scripts/tests/test-red-first-baseline-lib.sh`: the lib's own
   red-first proof. Its cases are inherently honest — build a synthetic repo where the
   baseline *does* contain the marker and assert `rc=3 SKIP`, not `FAIL`. This is the
   assertion the whole lane exists to make, and it is the mission's verification step 3
   generalised.
3. Convert **S1** only. Run `test-parked-worker-resume.sh` standalone → expect `pass=8 fail=0`
   plus one `SKIP` **or** `pass=9 fail=0` depending on whether `6fa4823` is reachable. Paste
   the real output either way.
4. Run `run-core-offline.sh` → expect exactly two failures (the two known-foreign suites).
   If a third remains, name it in the report rather than chasing it.
5. Convert **S2, S3** (the other blocking sites), re-run both gates.
6. Convert **S4–S9** one at a time, running each standalone after conversion, and tighten
   `GREEN_PRE_FIX` to blocking per §4c. Any suite that reds gets its pin corrected and the
   evidence recorded.
7. Genuine-regression proof (mission step 3): in a scratch copy, remove the
   `_LEADV2_FOREGROUND_CONTRACT_MISSION` line from `leadv2-helpers.sh`, show S1's red-first
   case goes RED (`post` fails, not `pre` passes), restore.
8. Report at `docs/handoff/RED-FIRST-SELF-INVALIDATES-01/report.md` — option chosen and why,
   the full §2 census with per-site disposition, the three pasted verifications, the §7
   counterexample stated plainly, and `git diff --stat`. `DELIVERABLE_COMPLETE` last line.

---

## acceptance:

```yaml
acceptance:
  - surface: log_line
    observable: >
      The run of the full offline suite prints a final tally naming exactly two failed
      suites — the deferred-GLM ladder and the fanout classifier/runner guard — and the
      parked-worker suite is not among them.
    authored_at: 2026-08-23T13:41:00Z
  - surface: log_line
    observable: >
      The parked-worker suite's own result line reports zero failures, and its nine
      assertions are each reported as either passed or explicitly skipped with a printed
      one-sentence reason naming which baseline commit was unusable and why. No assertion
      is reported as failed for the reason that the fix is already present in history.
    authored_at: 2026-08-23T13:41:00Z
  - surface: log_line
    observable: >
      With the parked-detection marker deliberately removed from the working tree in a
      scratch copy, the parked-worker suite reports a failure and names the contract
      assertion — demonstrating that the check still catches a real regression rather than
      skipping past it.
    authored_at: 2026-08-23T13:41:00Z
  - surface: file_artifact
    observable: >
      The report at docs/handoff/RED-FIRST-SELF-INVALIDATES-01/report.md lists every
      red-first site found in the test tree, states for each whether it was already immune,
      converted, or deliberately left alone, and names the baseline commit each converted
      site is now pinned to.
    authored_at: 2026-08-23T13:41:00Z
```

LANE_WRITES: plugins/leadv2/scripts/tests/lib/red-first-baseline.sh, plugins/leadv2/scripts/tests/test-red-first-baseline-lib.sh, plugins/leadv2/scripts/tests/test-parked-worker-resume.sh, plugins/leadv2/scripts/tests/test-lane-root-not-a-worktree.sh, plugins/leadv2/scripts/tests/test-builder-selfcheck-gate.sh, plugins/leadv2/scripts/tests/test-lane-writes-scoping.sh, plugins/leadv2/scripts/tests/test-lane-diff-single-repo.sh, plugins/leadv2/scripts/tests/test-landing-diff-scoping.sh, plugins/leadv2/scripts/tests/test-codex-worktree-trust.sh, plugins/leadv2/scripts/tests/test-codex-reap-log-mtime-liveness.sh, plugins/leadv2/scripts/tests/test-codex-transport-attribution.sh, plugins/leadv2/scripts/tests/test-claim-evidence-gate.sh, plugins/leadv2/scripts/tests/run-core-offline.sh

DELIVERABLE_COMPLETE
