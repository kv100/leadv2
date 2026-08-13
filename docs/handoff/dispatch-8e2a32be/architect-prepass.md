# CODEX-QUOTA-GATE r2 + REVIEW-POOL-EMPTIES-UNDER-QUOTA-01 — implementation design

Lane: `.claude/worktrees/83c44855`, resume from `fb1c7da` (WIP: quota parser +
post-spawn test + dispatch-code/product-close edits). **Continue, do not restart.**

---

## 1. Why the pool was empty at runtime — evidence, not theory

The founder's premise ("opus is declared in config yet was not reached") is correct but
the failure is one layer earlier: **the resolver never parsed any routing yaml, and
therefore never ran the pool code at all.**

### 1.1 The observed line

`docs/leadv2/tasks/dispatch-83c44855/journal.md:23`

```
2026-08-06T16:47:54Z [decision] review_gate task=83c44855 status=unreviewed
  reason=all_arms_unavailable author=sonnet pool= refusal=all_review_arms_unavailable tried=
```

### 1.2 The chain

1. `resolve_review_pool_call()` (`leadv2-dispatch-product-close.sh:244`) computes
   `routing_yaml="${LEADV2_ROUTING_YAML:-${ROOT}/.claude/ref/leadv2-routing.yaml}"`.
2. **That file does not exist — not in the lane worktree, not in the repo root:**

   ```
   $ ls .claude/ref/leadv2-routing.yaml                       -> No such file or directory
   $ ls .claude/worktrees/83c44855/.claude/ref/leadv2-routing.yaml -> No such file or directory
   ```

   The only routing yaml on disk is `plugins/leadv2/config/leadv2-routing.yaml`
   (canonical) — the very file that declares `claude-opus` and `fable`. The resolver
   has **no fallback** to it: `resolve_review_pool_call` builds one path and stops,
   unlike the sibling lookup it performs three lines earlier for the resolver *binary*
   (co-located → canonical). Asymmetry is the defect.
3. `leadv2-glm-policy-resolve.py:573-577` — `Path(args.routing_yaml).read_text()` raises,
   the handler calls `_emit_fallback(job, "no_routing_yaml")` and `return 0`.
   `_emit_fallback` prints only `arm=/rule=/reason=/tier=/codex_quota_blocked=` and
   **returns before line 608**, so the `if args.review_pool:` block — the only place
   `reviewer=`, `pool=`, `refusal=` are ever printed — never executes. Exit code is 0,
   so bash's `|| printf ... resolver_error_failclosed` guard does not fire either.
4. Reproduced verbatim just now:

   ```
   $ python3 plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py \
       --routing-yaml /nonexistent.yaml --job review --base-arm codex \
       --review-pool --author sonnet --signals '{}'
   arm=sonnet
   rule=none
   reason=no_routing_yaml
   tier=
   codex_quota_blocked=1
   ```

   No `reviewer=`, no `pool=`, no `refusal=`.
5. `…product-close.sh:1489-1491` `sed -n 's/^pool=//p'` finds nothing → `reviewer=""`,
   `pool=""`, `refusal=""`. Line 1505 `refusal="${refusal:-all_review_arms_unavailable}"`
   **manufactures** the refusal string. So `all_review_arms_unavailable` in the journal
   is a bash default, not a resolver verdict — the pool was never computed.

### 1.3 Corollaries this proves

- **`DEFAULT_REVIEW_ARM_ORDER = ["codex","glm","kimi","opus","sonnet"]`
  (`resolve.py:69`) already contains opus.** Had the pool run, the entries list would
  have been non-empty for *any* author — at minimum `sonnet:author:`. `pool=` being
  empty is itself the proof that `resolve_review_pool()` never ran. Config declaring
  opus was never the problem.
- **The `--quota-live`/lockout observation has a separate root cause.** `grep -c lockout
  leadv2-glm-policy-resolve.py` → **0**. The resolver reads live-percentage probes
  (`live_codex_weekly_pct` etc.) and has no knowledge of the lockout store whatsoever,
  which is why a live probe returned `arm=codex codex_quota_blocked=0` with
  `quota-lockout-codex.json` sitting on disk. Two independent bugs; both must be fixed.
- **`tried:` empty was truthful but unreadable.** Zero arms were attempted, so nothing
  was recorded — indistinguishable at the surface from "recording is broken".

---

## 2. Design

Four changes, additive and backward compatible.

### D1 — Routing-yaml lookup becomes ordered, and the resolver self-heals

`resolve_review_pool_call()` resolves the yaml through the same co-located-then-canonical
convention already used for the resolver binary:

| # | candidate | note |
|---|---|---|
| 1 | `$LEADV2_ROUTING_YAML` | test/tenant override, unchanged |
| 2 | `${ROOT}/.claude/ref/leadv2-routing.yaml` | tenant override, unchanged precedence |
| 3 | `${SCRIPT_DIR}/../config/leadv2-routing.yaml` | plugin-local canonical |
| 4 | `${LEADV2_CANONICAL_ROOT:-$HOME/Projects/leadv2}/plugins/leadv2/config/leadv2-routing.yaml` | canonical |

First existing file wins. Same fallback added inside `_main` when `--routing-yaml` is
unreadable, so any other caller is fixed too. Emit
`emit decision "review_routing_yaml task=… source=<tenant|plugin|canonical|none>"`.

### D2 — `--review-pool` output is unconditional

`_main` gains `_emit_pool_lines(reviewer, entries, refusal)` and **every** return path
prints `reviewer=`/`pool=`/`refusal=` when `--review-pool` was requested — including
`no_routing_yaml`, `resolver_error`, and the top-level `except` at `:620`. On those
degraded paths the pool is the D3 floor (below), with entry suffix `:floor:degraded`
and `refusal=` left empty (a reviewer exists). The class of bug "resolver bailed early,
gate read silence as unavailability" becomes structurally impossible.

### D3 — The floor: derived escalation, never enumerated

Founder intent (Sonnet→Opus, Opus→Fable) is expressed as **data in the routing yaml**,
not a pair list in code. Each Anthropic-account arm gains a `review_rank:` integer:

| arm | provider | review_rank |
|---|---|---|
| haiku | anthropic | 1 |
| sonnet | anthropic | 2 |
| opus | anthropic | 3 |
| fable | anthropic | 4 |

Floor function, on the author-excluded candidate set `C = {a : a ≠ author}`:

```
floor(author) = argmin{ rank(a) : a ∈ C, rank(a) > rank(author) }      # escalate up
             or argmax{ rank(a) : a ∈ C }                              # author at top -> highest other
```

`rank(author)` for an author absent from the table is treated as `-∞`, which selects the
**lowest-ranked non-author arm** — still a valid, non-empty answer.

**Non-emptiness proof (requirement 1).** The rank table is loaded from the yaml and
asserted to have ≥ 2 entries at load (`pool_floor_table_degenerate` is a hard resolver
error, not a silent pass). For any author value `x` — including an arm this task has
never seen, including the empty string — `C = table \ {x}` has ≥ 1 element because
removing one element from a ≥2-element set leaves ≥1. Both branches of `floor` select
from `C`, so `floor` is total and never returns the author. Quota/lockout filtering is
applied to the *preferred* pool only and is skipped for the floor arm, so no filter can
empty the result. ∎

Ordering rule: the preferred pool (codex → glm → opus → sonnet, quota- and
lockout-filtered, author-excluded) is tried first exactly as today. The floor is
appended **only if the filtered pool is empty**, marked `<arm>:floor:<pct|degraded>`.

**Deliberate consequence, flagged:** the floor arm is admitted even when the Anthropic
reading is over the 95 % review threshold. Requirement 1 ("the pool is never empty") is
unconditional and outranks the ceiling; ceilings themselves are unchanged (constraint
honoured). The gate reports `reason: floor_reviewer` so this is visible, never silent.
If the founder wants the ceiling to win instead, that is a one-line policy flip at the
floor-append site.

**No arm is hardcoded.** Code contains no arm literal on this path: the order comes from
`review_arm_order` / `dispatch_ladder`, the ranks from `review_rank:`, the provider
mapping from `dispatch_ladder[].provider`. Adding an arm to the yaml adds it to the
ladder with zero code change. (`DEFAULT_REVIEW_ARM_ORDER` at `:69` stays only as the
no-yaml-parsed emergency default and is superseded whenever a yaml is found — with D1 it
effectively never applies again.)

### D4 — Resolver reads the on-disk lockout store

New `_lockout_blocked(provider, now)` in the resolver:

- dir: `${LEADV2_QUOTA_LOCKOUT_DIR:-${LEADV2_DISPATCH_CACHE_DIR:-$HOME/.claude/cache}/dispatch-ledger}`
- file: `quota-lockout-<provider>.json`, honouring the existing schema written by
  `leadv2-dispatch-code.sh record-quota-lockout` (the field carrying the return time).
- `now` injectable via `LEADV2_QUOTA_NOW_EPOCH` for deterministic tests.
- arm→provider derived from `dispatch_ladder[].provider`; unknown arm ⇒ provider == arm.
- Effects: a live lockout yields pool entry `<arm>:blocked:lockout`, and for codex it
  also forces `codex_quota_blocked=1` in the non-pool output block. Expired or malformed
  file ⇒ not blocked (fail-open — a corrupt cache file must not remove an arm).
- The floor arm bypasses this, per D3.

### D5 — `unreviewed` becomes loud, `pool:`/`tried:` always populated

In `…product-close.sh`:

- `PC_TRIED=()`; every arm the gate actually invokes is appended **before** the spawn, so
  a crash mid-review still leaves it recorded.
- Both terminal branches (zero-reviewer at `:1503`, and pool-exhausted further down)
  write the same shape:

  ```
  status: unreviewed
  reason: all_arms_unavailable
  author: <author>
  pool: <resolver entries, or "-" only when the resolver produced none>
  tried: <csv, or "-" when genuinely zero arms were attempted>
  refusal: <resolver refusal | bash-manufactured token>
  ```

  `-` replaces the blank so "nothing attempted" and "not recorded" are distinguishable.
  The `refusal:` field is new and carries the resolver's own token verbatim — the exact
  signal whose absence made this incident opaque.
- After D1+D3, `all_arms_unavailable` should be unreachable; the branch stays as an
  assertion and now always reports a non-empty `tried:`/`pool:` when it does fire.
- Merge path: `exit 9` + `_dl_note dead` are already in place; the design adds no new
  exit codes. `_stamp_review_terminal unreviewed` unchanged.

---

## 3. Tests (each must FAIL against pre-fix code)

New suite `plugins/leadv2/scripts/tests/test-review-pool-never-empty.sh`, hermetic
(`LEADV2_QUOTA_LOCKOUT_DIR`, `LEADV2_ROUTING_YAML`, `LEADV2_QUOTA_NOW_EPOCH` all pointed
at a temp dir — the live `~/.claude/cache/dispatch-ledger/quota-lockout-codex.json` is
never touched):

| # | case | pre-fix result |
|---|---|---|
| T1 | author=sonnet, codex+glm locked ⇒ `reviewer=opus`, review runs | FAIL (`all_arms_unavailable`) |
| T2 | author=opus, codex+glm locked ⇒ `reviewer=fable` | FAIL (fable not in order at all) |
| T3 | codex lockout on disk ⇒ `codex_quota_blocked=1`, codex absent from pool | FAIL (`=0`, resolver has 0 refs to lockout) |
| T4 | routing yaml unreadable + `--review-pool` ⇒ `pool=` non-empty, `reviewer` non-empty | FAIL (no pool lines emitted at all) |
| T5 | author = an arm not in the rank table ⇒ pool non-empty, reviewer ≠ author | FAIL |
| T6 | if `all_arms_unavailable` still reachable, `tried:` is non-empty (`-` counts) | FAIL (blank) |
| T7 | author-exclusion holds across T1/T2/T5 — reviewer never equals author | passes today, regression guard |

Round-1 suite `test-quota-lockout-postspawn.sh` (already in `fb1c7da`) keeps its five
cases: post-spawn lockout, provider-named return time, unparsable fallback, non-quota
failure writes no lockout, next dispatch skips the locked arm.

---

## 4. Risks

| risk | mitigation |
|---|---|
| Floor arm admitted over the 95 % Anthropic ceiling | explicit `reason: floor_reviewer` + pool entry `:floor:`; ceilings themselves untouched; one-line flip if founder rules otherwise |
| Adding `review_rank:` to the yaml breaks other yaml consumers | key is additive; `extract_glm_policy_block` is regex-per-key, ignores unknown keys; verify with a full-suite run |
| Canonical-yaml fallback masks a genuinely missing tenant override | `review_routing_yaml … source=` decision line names which file won |
| Lockout file parsed with a different schema than dispatch-code writes | read the writer in `fb1c7da` first; malformed ⇒ fail-open (not blocked) |
| Two parallel gates read the lockout dir while dispatch-code writes it | read-only here, last-write-wins per provider already; no lock needed |
| `_emit_fallback` output shape change breaks non-pool callers | pool lines emitted **only** under `--review-pool`; v1 byte-equivalence preserved |

## 5. Out of scope

Quota ceilings; the hand-written live codex lockout; re-enabling kimi as a review arm;
build-ladder ordering; `dispatch: false` semantics for fable on the **build** path (fable
becomes a *reviewer*, it is not being added as a build arm); merge-path rewrite beyond
the gate's own output; the `.claude/scripts/tests/` de-duplication thread.

## 6. Constraint checklist

1. Env vars — `LEADV2_*` throughout (`LEADV2_QUOTA_LOCKOUT_DIR`, `LEADV2_ROUTING_YAML`,
   `LEADV2_CANONICAL_ROOT`, `LEADV2_QUOTA_NOW_EPOCH` new). No `LEAD_V2_*` drift.
   `GLM_POLICY_QUOTA_LIVE` is pre-existing and left alone.
2. Paths — all listed paths verified present except
   `tests/test-review-pool-never-empty.sh` **(to-create)**.
   `.claude/ref/leadv2-routing.yaml` is confirmed **absent** — that is the finding, not a
   path error.
3. No `claude -p` invocation introduced by this design.
4. Concurrency — lockout dir is read-only here; gate output files are per-task.
5. Config contradiction — `review_rank:` is a new key with no other consumer (grepped).

---

acceptance:
  - surface: file_artifact
    observable: "docs/handoff/dispatch-<task>-review/review-gate.md for a sonnet-authored lane run while codex and glm are both locked out shows a review verdict from opus — not the line `reason: all_arms_unavailable`."
    authored_at: 2026-08-06T17:25:00Z
  - surface: log_line
    observable: "The task journal's review_gate decision line shows a non-empty pool: list naming every arm and why each was skipped, and a tried: list naming the arm actually invoked — neither field is blank."
    authored_at: 2026-08-06T17:25:00Z
  - surface: log_line
    observable: "With a codex lockout file present in the test lockout dir, the resolver's printed codex_quota_blocked reads 1 and codex does not appear as an offered reviewer."
    authored_at: 2026-08-06T17:25:00Z
  - surface: file_artifact
    observable: "An opus-authored lane under the same double lockout produces a review-gate.md naming fable as the reviewer, and no gate output anywhere names the author as its own reviewer."
    authored_at: 2026-08-06T17:25:00Z

LANE_WRITES: plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py, plugins/leadv2/scripts/lib/leadv2-quota-error-parse.py, plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/config/leadv2-routing.yaml, plugins/leadv2/scripts/tests/test-review-pool-never-empty.sh, plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh

DELIVERABLE_COMPLETE
