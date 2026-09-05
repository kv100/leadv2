# ARBITER-REMEMBERS-FAILURES-01 — report

Both edits landed in one lane, in the one file they share, plus its config and tests.
Three commits, named files only, nothing pushed.

| | |
|---|---|
| `ee68e4e0` | the two arbiter edits + `leadv2-routing.yaml` + the existing suite's fixture fix |
| `bd2a99d1` | `test-route-arbiter-failure-memory.sh` (12 cases) + the negative-control harness and its log |
| `b8857fd9` | the two `tests/mutations/catalog.yaml` rows |

Write set respected exactly. Nothing outside it was touched; the one boundary I hit is
recorded under **Where I stopped** below.

---

## Edit A — the arbiter remembers which arms failed this task

### What counts as a failure

**A failure is: the spawn happened and no work came back.** Everything else is somebody
else's breakage and must never retire an arm.

Excluded, and each for its own reason:

- **Every `refused:*` cause** — `writeset_pending`, `writeset_overlap`, `writeset_conflict`
  (the registry window), `duplicate_task_signature`, `all_arms_capped`,
  `plan_source_absent`, `undiffable_write_set`, `unscoped_lane_work`,
  `lane_root_not_a_worktree`. These are refusals *before* the spawn: the lane's shape or
  the gate's state. Counting them would ban a healthy arm for a defect it never saw.
- **The quality rejections** — `e2e_regression`, `review_verdict_fail`, `review_dod_fail`.
  Here work *did* come back and was judged bad. That is a different question from "this arm
  cannot produce here", and folding the two together would retire an arm for writing code a
  reviewer disliked twice.
- **`parked:*`** — parked is not dead.
- **Infrastructure** — `all_arms_unavailable`, `router_v2_unavailable_rc_1`.

The implementation is an **allow-list**, not a deny-list, and that direction is
load-bearing: an unrecognized terminal shape is never counted, so a new cause added
upstream tomorrow cannot silently start banning arms. The list lives in
`router_v2.failure_memory.arm_failure_causes` with the same list hardcoded as the script's
default, so a config drift cannot quietly disable the memory either.

### Where the counter is stored — no sixth store, and no single journal was enough

I checked both journals the mission named. **Neither carries the fact on its own**, which
is why this looked like it needed a new store and does not:

| journal | rows | carries | missing |
|---|---|---|---|
| `~/.claude/leadv2-state/leadv2/dispatch-ledger.jsonl` | 1360 | `task_sig`, `terminal`, `cause`, `ts` | **no arm** |
| `~/.claude/cache/leadv2-events/leadv2.jsonl` | 7397 | `worker_spawned` rows with `arm` + `task` + `ts`; `arm_refused` rows naming the arm directly | terminal causes: its 4771 `worker_terminal` rows carry **no arm** and only ever hold the pre-spawn refusals (`skipped:plan_source_absent`, `refused:writeset_*`, `refused:all_arms_*`) — never `no_work:*` or `dead:*` |

So the join: **a ledger failure at time T for signature S is attributed to the arm of the
last `worker_spawned` for S at or before T.** One lane per signature is already enforced by
the `duplicate_task_signature` guard, so that attribution is unambiguous by construction.

Measured against the live journals on 2026-09-05, before writing any code:

```
failure ledger rows attributed to an arm: 113   unattributable (no surviving spawn): 71
task signatures where ONE arm failed >= 2 times: 12
  b413968c {codex:3}   18ab6b98 {sonnet:3, glm:2, codex:1}   16fbe872 {codex:3, sonnet:1}
  e9d256b4 {freepool:2} b5db546a {sonnet:2}  0f9e4d16 {codex:2}  faee3fc5 {codex:3}
  a605eb2a {codex:4}    7a8f236f {codex:2}   57a94876 {sonnet:2} 3dd21396 {sonnet:2}
  6436a2e2 {glm-flash:3}
```

The 71 unattributable failures predate the events file's rotation window. They do not
count. That is the conservative direction: the memory under-reports rather than banning on
a guess.

### The key

`d['task']` — and it is **already** the mission-content signature. `leadv2-dispatch-code.sh`
builds the arbiter descriptor with `"task": sys.argv[7]` where argv[7] is `${sig8}`
(around line 8038), the same `sig8` the `duplicate_task_signature` guard keys on. So the
mission's guess was right and no caller change, no new descriptor field and no env seam was
needed.

The three fallback descriptors (`_bf_desc` bench-fallback, `_e76_desc` exit76,
`_adv_desc` advisory) and the reviewer descriptor in `leadv2-dispatch-product-close.sh` do
**not** carry `task`. Those journal `failure_memory=absent_key` and route exactly as before,
rather than reading another task's memory or pretending the answer was zero.

### Empty memory is not zero

Five distinct statuses, all printed on the decision line:

| status | meaning |
|---|---|
| `absent_key` | this caller passed no signature — nothing to look up |
| `unavailable` | a journal could not be read — **unknown**, never zero. Nothing is banned (banning on no evidence is its own failure mode) but the line says so |
| `no_history` | journals read fine, this signature has no attributed failures |
| `ok` | journals read fine and this signature has failures |
| `exhausted` | every capable cell is a repeat offender; the ban yields rather than deadlocking, and says it yielded |

`threshold: 2` — the founder's rule. 1 would retire an arm on a single flake and the
arbiter cannot tell a flake from a pattern.

### The honest part: this rule does **not** fire on the incident that motivated it

`GUARDS-SELF-DISABLE-ON-THE-EMPTY-WRITE-SET-01` is signature `b5abfcfd`. Its two glm spawns
are in the events journal (19:58:36 and 23:41:08 on 2026-09-04), but **every one of its 24
ledger rows is a `refused:*`** — two `undiffable_write_set` and twenty-two
`writeset_pending`. Under the rule the mission itself specified, those are pre-spawn
refusals and are not glm's fault, so glm is not retired for that task.

I did not widen the allow-list to make the motivating case light up. Adding
`refused:undiffable_write_set` would have banned a healthy arm for a write-set defect —
precisely the failure mode the mission warned about — and would have retired glm on the
first `writeset_pending` burst of any future lane. The rule fires on the 12 *other*
signatures listed above, which are the same disease with a terminal that actually names it.

**What this leaves open:** if a worker really does come up and die without writing a line,
and nothing downstream terminalizes it as `no_work`/`dead`, the failure is invisible to
every journal and therefore to this memory. Making that visible means teaching the
terminalizer, in `leadv2-dispatch-code.sh` — outside this write set. Named here, not done.

---

## Edit B — "I don't know" stops meaning "busy"

`util()` has returned `pct=100.0` **with** `unknown=True` for a failed probe all along, and
`unk` has carried the flag since — but the flag reached the selection **nowhere**. The
arbiter knew it did not know, printed `util_<arm>=unknown_capped`, and then routed as if the
arm were full.

### How an unknown arm is ranked, and why

**Chosen: keep it in the candidate set, demoted behind every measured arm.** Implemented as
`UNKNOWN_PROBE_PENALTY = 50.0` on effective cost — the sort's dominant key, the same
mechanism the freepool capability floor already uses. 50 clears the entire real cost range
(max real cost: opus 9), so any arm with a live reading outranks any arm whose probe failed;
and it sits below the freepool floor (+100), so an unmeasured arm still loses to nothing
except a deliberately floored one.

The two alternatives, and why not:

- **"Skip it"** is today's bug verbatim — it is exactly what `capped()` was doing.
- **"Take it with a warning", i.e. rank it as free** would spend a genuinely burnt provider
  on the strength of a *failed reading*. An unknown arm might be at 5% or at 99%; ranking it
  last among the measured is the only position that is right in both worlds.

`capped()` now returns `False` for an unknown provider. `over_ceiling()` is untouched, so
freepool (whose `unknown` is never set — its own gate already encodes down-vs-busy
correctly) is unaffected, and a *measured* over-ceiling arm still caps exactly as before.

### The instrument failure is journaled separately

`probe_outage=<arms>` is now a token of its own on every decision line and both refusal
lines, and is in the decision record. It can no longer be absorbed into `all_arms_capped`.

### The stale comment next door

`leadv2-routing.yaml` claimed codex and claude had "no ceiling reader at all" and that the
numbers were "declared policy, NOT enforced behaviour". Untrue since the arbiter landed:
`over_ceiling()` enforces all three rows per role (`review_pct` when `role=reviewer`,
`work_pct` otherwise). Corrected, with the live proof (claude at 96% → `all_arms_capped`)
and with `leadv2-glm-quota-gate.sh` named as the *second*, glm-only enforcement point rather
than the only one. The replacement also documents the two exemptions that now sit on top:
`wait_applied=` and `probe_outage=`. Comment only — no code change.

---

## The five requirements

### 1. The real function is under assertion

Every case in `test-route-arbiter-failure-memory.sh` calls the real `route_arbiter()` from
`plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` against the real
`config/leadv2-routing.yaml`. Only the layer **below** is faked: the quota-live probe (a
stub echoing a JSON fixture, the seam the suite already used) and the two outcome journals —
which are **real files on disk in the real formats**, not a stubbed reader. Nothing replaces
`read_failure_memory`, `capped`, `ecost` or `route_arbiter`.

Twelve cases, `pass=12 fail=0`:

```
empty history is no_history and still resolves (baseline arm=glm-flash)
arm that failed twice on this task is not chosen again (glm-flash -> glm)
banned arm is absent from the candidate chain, not only from arm=
a single failure does not retire the arm (threshold is 2)
pre-spawn refusals (write-set / registry window / capped gate) never ban an arm
unreadable journal reports unavailable, never a clean zero
descriptor without a task signature is absent_key, routed as before
the ban is scoped to the failing task signature, not global
all-arms-banned yields instead of deadlocking (failure_memory=exhausted)
a failed probe does not read as a capped arm (probe_outage named, work still routed)
three measured over-ceiling arms still refuse all_arms_capped
an unmeasured arm is demoted behind every measured one (won: glm-flash)
```

The chain case matters on its own: `leadv2-dispatch-code.sh` iterates `chain=` from index 0,
so an arm removed from `arm=` but left in the chain would still be spawned on the next
fallback step.

### 2. Negative controls — run, by regex, inside a function body

Both mutations are applied to a **copy** of the tree, never to the shared canonical file:
live lanes read that file and a two-second mutation would reach them.

| control | mutation | result |
|---|---|---|
| `ARBITER-FAILURE-MEMORY-STOPS-COUNTING` | in `read_failure_memory()`: `counts[arm]=counts.get(arm,0)+1` → `pass` | **4 red** — the ban, its absence from `chain=`, threshold=2, all-banned-yields. Every edit-B case stays green. |
| `ARBITER-UNKNOWN-IS-CAPPED-AGAIN` | in `capped()`: delete `if unk.get(provider): return False` | **1 red** — exactly the probe-outage case. Every edit-A case stays green. |

Each control reddens **only its own edit's cases**. A control that reddens everything proves
nothing; these are specific.

Run twice, two ways:

- `mutation-control/run.sh` → `mutation-control/negative-controls.log`, which prints the
  mutated function body (proof the edit landed *inside* it) and the full per-case verdicts.
- The repo's own runner, `leadv2-mutation-control.sh`, twice → `MUTATION-CONTROL ok` on
  both, artifacts `20260905T014916Z-72733.txt` and `20260905T014933Z-74628.txt`.
  **Caveat worth knowing:** on the second run that tool's `red_line=` field quoted a *PASS*
  line. Its verdict comes from the suite's exit status and is correct; the quoted line is
  not. Read `negative-controls.log` for which cases actually went red.

The mutation is inserted by regex, never by line number — a line-number insert lands at top
level, reddens every suite for the wrong reason, and reads like a pass.

### 3. Catalog rows

Two entries in `tests/mutations/catalog.yaml` (`arbiter-failure-memory-stops-counting`,
`arbiter-unknown-is-capped-again`), each with `file`, `suite`, `anchor`, `patch`,
`expected: killed`, and a note on which cases it kills.

> Correction, made the same day from the next lane: the running total I wrote
> here ("repo kill rate 8/8 → 10/10") was inherited from the catalog header,
> which was itself stale — the file already held eleven entries while the header
> said eight. The honest statement is that these two entries are killed, and
> that the catalog's total is now derived by counting rather than carried
> (commit `9703e25c`). Counted on 2026-09-05: 15 entries, all `expected: killed`.

### 4. CI selection, proven by changing the PRODUCTION file

The suite self-registers `# run-all-triggers: leadv2-route-arbiter leadv2-routing.yaml`.
With the runner's own state file advanced to HEAD so only working-tree dirt counts:

```
CONTROL — arbiter clean:              4 selected, none of them mine
PROOF   — dirty ONLY lib/leadv2-route-arbiter.sh (the suite untouched):
          15 selected, including
          plugins/leadv2/scripts/tests/test-route-arbiter-failure-memory.sh
```

The dirt was a comment appended to the production file and was reverted immediately
(`git checkout --`, tree clean). A dirty suite selecting itself would have proved nothing —
that is why the trigger was exercised from the production side.

### 5. Two live arbiter runs, before and after

Real `leadv2-quota-live.sh`, real freepool gate, real journals, real `routing.yaml`. BEFORE
is the arbiter as it stood at `ee68e4e0^`.

**Edit A — signature `6436a2e2`, which really did give glm-flash three `no_work:empty_diff`
terminals on 2026-09-04:**

```
BEFORE  arm=glm-flash  model=glm-5.3-flash  chain=glm-flash,glm,sonnet,freepool
        (no failure_memory token — the old arbiter has no memory)
AFTER   arm=glm        model=glm-5.3        chain=glm,sonnet,freepool
        failure_memory=ok  failure_banned=glm-flash:3
```

The arm that had already failed three times is gone from `arm=` **and** from the chain. That
task's `parked / e2e_timeout` row was correctly not counted.

A second live pair on `a605eb2a` (codex ×4) leaves the pick unchanged — codex is at 92%,
already over its 90 ceiling — but the AFTER line now carries `failure_banned=codex:4`, so
the arm is retired by record as well as by quota.

**Edit B — the same live probe payload with anthropic's account `status` stripped, the shape
a 401 produces (glm/codex pushed over ceiling so the old arbiter had a real reason to look
for a third arm):**

```
BEFORE  arm=freepool  chain=freepool
        util_claude=unknown_capped   (no outage token)
AFTER   arm=sonnet    chain=sonnet,freepool
        util_claude=unknown_capped  probe_outage=claude
```

This is the consequence in a sharper form than the recorded refusal: with the freepool arm
healthy today, the conflation did not refuse — it silently handed Standard production build
work to the **deliberately floored last-resort arm** while sonnet sat one field away,
excluded only because nobody could read its meter. On 2026-09-04, with freepool also down,
the same conflation produced `all_arms_capped` and killed six lanes. Suite case (b1) covers
that second shape; case (b2) proves three genuinely measured over-ceiling arms still refuse.

---

## Suite state

| suite | before | after |
|---|---|---|
| `test-route-arbiter.sh` | `pass=10 fail=1` on main (`fallback` red before me) | `pass=10 fail=1`, same single pre-existing red |
| `test-route-arbiter-failure-memory.sh` | did not exist | `pass=12 fail=0` |

I had to repair one fixture in the existing suite, and the repair is a finding in itself.
Its `quota()` helper emitted an anthropic account with **no `status` key**, so `util()` took
the no-ok-account branch and ran claude as *unmeasured* on every call. Case (b), "all capped
refuses all_arms_capped", was therefore asserting the refusal on a fixture with only two
measured arms — it was testing the unknown-is-capped conflation, not the invariant. The
helper now emits `status: ok`, and case (b) additionally asserts `probe_outage=` is absent,
so it can never again pass for that reason.

---

## Where I stopped

- **The `codex_worker_died` event kind names an arm but carries no `task` field**, so it
  cannot be keyed to a signature and is not counted. Fixing it means editing the emitter in
  `leadv2-dispatch-code.sh` — outside the write set.
- **A worker that dies without any terminalizer writing a `no_work`/`dead` ledger row is
  invisible to this memory** (see the `b5abfcfd` note above). Same file, same boundary.
- One tooling note, not a code change: writing into `~/Projects/leadv2` from a session whose
  cwd is `persona-engine` trips `guard-worktree-scope.sh` on the `Write` tool (though not on
  `Bash`, which edited and committed the same files freely). I used the guard's own
  documented cross-worktree override (`touch /tmp/pe-worktree-scope-override`, single-use).
  The inconsistency between the two tools is worth a look by whoever owns that hook.
- `docs/handoff/*/*` is gitignored; the control artifacts were force-added, matching what
  every prior handoff's `mutation-control/` did.
