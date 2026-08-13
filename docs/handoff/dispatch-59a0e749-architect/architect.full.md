# architect — CODEX-QUOTA-GATE r2 + REVIEW-POOL-EMPTIES-UNDER-QUOTA-01

Scoped implementation design. No code written here. Lane `.claude/worktrees/83c44855`,
resume from `fb1c7da`.

## 0. Lane state you are resuming (read before anything else)

`fb1c7da` (WIP) contains:

| file | state |
|---|---|
| `plugins/leadv2/scripts/lib/leadv2-quota-error-parse.py` | new, 211 lines — quota error parser (D1/D2/D3 round-1) |
| `plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh` | new, 287 lines |
| `plugins/leadv2/scripts/leadv2-dispatch-code.sh` | +337/-47 — post-spawn verdict window |
| `plugins/leadv2/scripts/leadv2-dispatch-product-close.sh` | +27 — `_pc_maybe_quota_advance()` + close-gate out-of-window hook in `pc_worker_alive` |

**The worktree also has UNCOMMITTED work on top of `fb1c7da`** (verified via
`git -C .claude/worktrees/83c44855 status --porcelain`):

```
 M plugins/leadv2/config/leadv2-routing.yaml
 M plugins/leadv2/scripts/leadv2-dispatch-product-close.sh
 M plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py
?? plugins/leadv2/scripts/tests/test-review-pool-never-empty.sh
```

That uncommitted product-close.sh already adds `_pc_or_dash()` (`:219`) and threads it +
a `refusal:` field through BOTH `all_arms_unavailable` branches (`:1539-1543`, `:1722-1726`).
**Do not re-derive or overwrite it — commit it first as its own step**, then build on it.
Constraint from the mission: never `git reset --hard`/`clean`/`stash` in this tree.

## 1. Why the pool was empty at runtime — the narrowing, and the one test that closes it

The lead's evidence already exonerates `resolve_review_pool()` (the Python) and the config
declaration: a live probe with real signals returned
`pool=codex:blocked:100,glm:ok:82,kimi:excluded:safety,opus:ok:71,sonnet:author:`.

The live artifact from lane `83c44855` was:

```
status: unreviewed
reason: all_arms_unavailable
author: sonnet
pool:
tried:
```

Match that shape against canonical `leadv2-dispatch-product-close.sh`:

- `:1658` (the **loop-exhausted** branch) prints `tried: %s` from `${_pc_tried_csv}`, which is
  non-empty by construction — `PC_TRIED+=("${reviewer}")` runs *before* the first
  `run_reviewer_arm`. The observed empty `tried:` therefore did **not** come from here.
- `:1480` (the **resolver-returned-nothing** branch) prints `pool: %s` from `${pool}` and a
  **literal, hardcoded `tried: `** — and prints **no `refusal:` line at all**. The live
  artifact has no `refusal:` line. **This is the branch that fired.**

Conclusion, from artifact shape alone: `reviewer` was empty immediately after
`resolver_out="$(resolve_review_pool_call)"`, **and** `pool` was empty too. So the empty
`tried:` is a *print* bug (hardcoded field), and the empty `pool:` is a *real* signal — the
function's stdout carried no `pool=` line whatsoever. That means `resolve_review_pool_call`
did not reach its final `python3` line, or the python3 output never made it to stdout.

### Leading hypothesis H1 — `set -e` abort inside the command substitution

`resolve_review_pool_call` (canonical `:237-…`) runs, before its final `python3`:

1. `emit decision "review_routing_yaml task=${TASK} source=${_ry_source}"` — **no `|| true`**
2. `source "${_signals_lib}"` — no `|| true`
3. `_sig_cap="$(mktemp … || printf …)"`, `leadv2_review_signals … || true`, `sed`, `rm -f … || true`

The script runs under `set -euo pipefail`. Any non-zero from (1) or (2) — a ledger file not
yet created, an `emit` sink unavailable, a `source`d lib returning the rc of its last
statement — aborts the **subshell of `$( )`** at that point. `resolver_out` then contains only
whatever had been echoed so far; `sed -n 's/^reviewer=//p'` finds nothing; `reviewer`, `pool`
and `refusal` are all empty; the `:1480` branch fires and prints exactly the observed artifact.

This also explains the divergence from the lead's probe: the lead invoked the **resolver
directly**, not through `resolve_review_pool_call`, so steps (1)–(2) never ran.

Secondary candidates, same observable, distinguished by the instrumentation in §2:
- **H2** — `python3` itself non-zero *and* the `|| printf 'reviewer=\npool=\nrefusal=resolver_error_failclosed\n'` fallback not reached because the abort happened earlier (H1) or because `python3` is absent on the dispatch PATH.
- **H3** — `emit` writes to **stdout**, so `resolver_out`'s parse is polluted but still parseable; this alone does *not* produce the artifact, so H3 is a hygiene fix, not the root cause.

**The `2>/dev/null` on the `python3` line (`resolve_review_pool_call`, last line) is why this
was invisible all day.** It must go.

### The one test that closes the diagnosis (write it first, it is the evidence)

`test-review-pool-empty-rootcause.sh` — drive `resolve_review_pool_call` in isolation under
`set -euo pipefail` with `emit` stubbed to `return 1`, assert the function's captured stdout
contains **no** `pool=` line. That reproduces the live artifact from a green tree and names H1
with evidence. If it does not reproduce, the instrumentation from §2 turns the next live run
into the answer (`resolver_rc:` + `resolver_stderr:` in review-gate.md) — no third guessing round.

## 2. Design — three layers, land in this order

### Layer A — make the failure legible (lands first; it is the evidence, not a nicety)

**A1. `resolve_review_pool_call` never aborts its own substitution.**
Every pre-python3 statement gets an explicit `|| true`. `emit`'s stdout is redirected to
stderr so it can never pollute the parsed stream (`emit … >&2 || true`).

**A2. Stop swallowing the resolver.**
Replace `python3 … 2>/dev/null || printf …` with a capture:

| element | contract |
|---|---|
| stderr | `2>"${HANDOFF}/review-pool-resolver.err"` |
| rc | captured into `_pc_resolver_rc` |
| on rc!=0 | still print the fail-closed `reviewer=/pool=/refusal=resolver_error_failclosed` line, and additionally `resolver_rc=<n>` |
| ledger | `emit decision "review_pool_resolve task=${TASK} rc=${_pc_resolver_rc} reviewer=<r> pool_n=<n>"` — unconditional, on success too |

**A3. Both terminal branches report what actually happened.** The `:1480` branch and the
`:1658` branch converge on ONE writer (`_pc_write_unreviewed <refusal> <pool> <tried>`) so their
shape can never diverge again. Fields, all always present, `-` for genuinely empty
(`_pc_or_dash`, already in the lane's uncommitted work):

```
status: unreviewed
reason: all_arms_unavailable
author: <arm>
pool: <csv|->
tried: <csv|->
refusal: <named-reason>
resolver_rc: <n>
resolver_stderr: <path|->
merge_blocked: true
```

`tried:` in the `:1480` branch is `-` **only** because zero arms were ever launched — and that
is now distinguishable from the loop branch by the presence of a non-empty `refusal:` plus
`resolver_rc:`. No hardcoded empty field survives.

**A4. Loudness.** `_dl_note dead all_arms_unavailable` + `_stamp_review_terminal unreviewed` +
`exit 9` already exist and stay. Add `merge_blocked: true` to review-gate.md (above) — verified
by grep that **no merge script reads review-gate.md today**
(`leadv2-phase8-e2e-gate.sh` and product-close.sh itself are the only non-test readers), so
this field is the contract a future merge consumer keys on, and the ledger `dead` row plus the
`review:unreviewed` phase stamp remain the live loud signals for the lead. **Out of scope:**
building a new merge-path enforcement script.

### Layer B — the guaranteed floor, derived not enumerated

**Root defect in the arm universe:** `leadv2-glm-policy-resolve.py:69` hardcodes
`DEFAULT_REVIEW_ARM_ORDER = ["codex", "glm", "kimi", "opus", "sonnet"]` — a hand-kept list in
code, and it contains **no `fable`**, so "opus author → fable reviews" is structurally
impossible today regardless of quota. Requirement 2 forbids exactly this shape.

**B1. Derive the arm universe from `leadv2-routing.yaml`.** The review-arms block already
declares each arm with `channel:` + `model:`. The resolver reads that block and builds its
order from **declaration order**, falling back to `DEFAULT_REVIEW_ARM_ORDER` only when the
block is unreadable (fail-safe, not fail-silent — emit `refusal=review_arms_unreadable`).
The Python constant stops being the source of truth.

**B2. Declare the missing arm.** Verify against the live file: the *dispatch* arms block
declares `opus` (`channel: claude-subsession.sh`, `model: opus`) and the *review* block
declares `fable` (`model: fable`) — but the review block's membership must be confirmed to
contain **both** `opus` and `fable`. If `opus` is absent from the review block, add it there.
This is a **declaration in config**, not a hardcode in code — it is what requirement 2 asks for.

**B3. The floor rule — derived from the config, no arm named in code.**
After author-exclusion and quota filtering, if the eligible set is empty:

1. Take `F` = every review arm whose `channel` is `claude-subsession.sh` (the Anthropic-family
   arms — they share one account reading and are reachable whenever the dispatching session
   itself is alive; there is no separate provider that can be "down" for them independently).
2. Order `F` by **declaration index** in the routing yaml (config's own capability ladder).
3. `floor = ` the first arm in `F` strictly **after** the author's index; if the author is the
   last entry, or the author is not in `F` at all, `floor = ` the first arm in `F` that is not
   the author.
4. Emit the floor arm with a distinct pool entry `<arm>:floor:<pct>` and
   `refusal=quota_floor_applied` so the founder can see the ladder fired.

With the declaration order `[haiku, sonnet, opus, fable]` this yields exactly the founder's
stated intent: **sonnet → opus, opus → fable**, and it yields it *by derivation* — change the
config order and the ladder changes with it.

**B4. The guarantee, and its proof obligation.** For any author value `A` — including an arm
this task has never seen — `F \ {A}` is non-empty whenever `|F| ≥ 2`. Assert `|F| ≥ 2` at
resolve time; if the config ever declares fewer than two claude-family review arms, return
`refusal=floor_family_too_small` (a loud, named config error) rather than an empty pool. That
turns "the pool emptied" from a silent runtime outcome into a config-validation failure.

**B5. Author-exclusion is untouched.** The floor is computed from `F \ {A}` by construction; the
existing defense-in-depth `reviewer == AUTHOR` assert in product-close.sh (`:1526-1530`) stays.
The floor may **never** be allowed to relax it.

**B6. Quota interaction.** The floor is a *last resort ordering*, not a quota bypass. The
Anthropic ceiling (95/95, unchanged) still applies: if the floor arm is over its review ceiling
the pool records `<arm>:blocked:<pct>` and the next `F` member is tried. Only when every `F`
member is over ceiling does `all_arms_unavailable` remain reachable — and then `tried:` is
non-empty and `refusal=` names it. **Ceilings are not changed by this task.**

### Layer C — round-1 carry-over (D1/D2/D3, still binding)

`mission-fix-r1.md` items stay in scope and their five tests stay required: post-spawn lockout,
provider-named return time, unparsable fallback, non-quota failure writes no lockout, next
dispatch skips the locked arm. The WIP already carries the parser + one test; finish and commit
them on the same lane. Also carry the WIP's `_pc_maybe_quota_advance` close-gate hook — it is the
out-of-window half of D1 and is currently uncommitted-adjacent work.

## 3. Test matrix — every row must FAIL against pre-fix code

| # | test | pre-fix result | post-fix assertion (file artifact) |
|---|---|---|---|
| T1 | root-cause repro: `emit` returns 1 inside `resolve_review_pool_call` | function stdout has no `pool=` line | `pool=` line present |
| T2 | author=sonnet, codex + glm both locked out | `all_arms_unavailable` | review-gate.md `status:` is not `unreviewed`; reviewer is `opus` |
| T3 | author=opus, codex + glm locked out | opus/fable never reached | reviewer is `fable` |
| T4 | codex lockout file on disk, real signals | (already passes on real path — keep as regression) | pool entry `codex:blocked:<pct>`, `codex_quota_blocked=1` |
| T5 | every arm genuinely refuses at launch | `tried:` empty | `tried:` non-empty CSV of every arm launched |
| T6 | `all_arms_unavailable` shape | no `refusal:`/`resolver_rc:` | both fields present, `merge_blocked: true` present |
| T7 | config declares <2 claude-family review arms | empty pool, silent | `refusal: floor_family_too_small` |
| T8 | author = an arm name never seen before (`"zzz"`) | undefined | floor resolves to first claude-family arm, review runs |
| T9–T13 | the five round-1 quota-lockout tests | fail | pass |

Tests set their own `LEADV2_QUOTA_LOCKOUT_DIR`. **The hand-written live lockout at
`~/.claude/cache/dispatch-ledger/quota-lockout-codex.json` is off-limits** — no test may read,
write, or delete it.

## 4. Risks

| risk | mitigation |
|---|---|
| The uncommitted worktree changes are from a *live* concurrent lane and get clobbered | Commit them as step 0 before any edit; re-`git diff` immediately before every `git add` (global rule) |
| H1 is wrong and the real cause is elsewhere | Layer A lands regardless and makes the next live run self-diagnosing (`resolver_rc:` + `.err` file); no further guessing round is needed |
| Deriving the arm universe from YAML with regex parsing silently mis-parses | Fail-safe to `DEFAULT_REVIEW_ARM_ORDER` **with** a named `refusal=review_arms_unreadable`, never a silent empty |
| Floor lets an arm review its own diff | Floor is computed from `F \ {A}`; the product-close `reviewer == AUTHOR` assert is a second, independent gate (B5) |
| Adding `opus` to the review block changes ordinary (non-floor) routing | `opus` sits after `codex`/`glm`/`kimi` in declaration order, so it is only reached when the cheaper arms are filtered out — the pre-fix ordinary path is unchanged |
| Removing `2>/dev/null` floods the lane log | stderr goes to a **file** (`review-pool-resolver.err`), not the console; only `rc` and a path reach the ledger |
| The `2>/dev/null` removal exposes a pre-existing noisy-but-harmless resolver warning and reads as a new failure | `resolver_rc` is the verdict field, not stderr length; document that non-empty stderr with rc==0 is not a failure |

## 5. Explicitly out of scope

- Changing any quota ceiling (glm 80/90, codex 90/95, claude 95).
- Touching `~/.claude/cache/dispatch-ledger/quota-lockout-codex.json`.
- Building a merge-path enforcement script — Layer A only publishes the `merge_blocked: true`
  contract; no consumer is written.
- `leadv2-status-surface.sh` / `leadv2-state-path.sh` (off-limits per the N-5 note in-file).
- The kimi channel, its probe, and `kimi:excluded:safety` semantics.
- De-duplicating `.claude/scripts/tests/` (a separate open thread).
- Any `git reset --hard` / `git clean` / `git stash` in the shared tree.

## 6. Constraint checklist

1. **Env vars** — all referenced vars use the `LEADV2_*` prefix (`LEADV2_QUOTA_LOCKOUT_DIR`,
   `LEADV2_ROUTING_YAML`, `LEADV2_CANONICAL_ROOT`, `LEADV2_DISPATCH_CACHE_DIR`). One legacy
   exception exists and is **not** renamed by this task: `GLM_POLICY_QUOTA_LIVE` (no prefix),
   read at `resolve_review_pool_call`. Renaming it is a cross-repo change outside this lane —
   flagged, not done.
2. **Paths** — every path in §2/§3 exists on disk except `review-pool-resolver.err` and
   `tests/test-review-pool-empty-rootcause.sh` **(to-create)**;
   `tests/test-review-pool-never-empty.sh` exists untracked in the lane worktree.
3. **`claude -p`** — this design introduces no new `claude -p` invocation. Any that the
   implementation adds must carry `--max-turns`, `--permission-mode bypassPermissions`,
   `--output-format json`.
4. **Concurrent access** — `review-gate.md` is written by the terminal branches **and** by the
   EXIT-trap backstop `_pc_exit_handler` (`:155`). Routing both `all_arms_unavailable` branches
   through the single `_pc_write_unreviewed` writer (A3) keeps one shape; the trap must remain
   last-write-only-if-absent so it cannot overwrite a real verdict. The lane worktree itself is
   shared with concurrent lanes — re-diff before staging.
5. **Config contradictions** — `DEFAULT_REVIEW_ARM_ORDER` (Python) vs the routing-yaml review
   arms block are two competing sources of truth for the same fact. B1 resolves this: YAML wins,
   the constant becomes an unreachable-in-practice fail-safe. **CRITICAL if left unresolved** —
   it is the direct cause of `fable` being unreachable.

## acceptance:

```yaml
acceptance:
  authored_at: 2026-08-06T19:20:00Z
  criteria:
    - surface: file_artifact
      artifact: docs/handoff/<lane>/review-gate.md
      observable: >
        On a lane authored by sonnet while both codex and glm are locked out, the founder
        opens review-gate.md and reads a completed review verdict naming opus as the
        reviewer — not the words "unreviewed" or "all_arms_unavailable".
    - surface: file_artifact
      artifact: docs/handoff/<lane>/review-gate.md
      observable: >
        On a lane authored by opus with codex and glm locked out, the founder reads a
        completed review verdict naming fable as the reviewer.
    - surface: file_artifact
      artifact: docs/handoff/<lane>/review-gate.md
      observable: >
        If "unreviewed" still appears at all, the founder reads on that same page a
        non-empty list of the arms that were actually attempted, a named refusal reason,
        the resolver's exit number, and a line stating the lane is blocked from merging —
        never a blank field.
    - surface: log_line
      artifact: dispatch ledger
      observable: >
        For every lane that reaches the review gate, the founder sees one line recording
        that the reviewer pool was resolved, including the resolver's exit number and how
        many arms it offered — present on successful lanes too, not only failing ones.
    - surface: rendered_line
      artifact: lane status surface
      observable: >
        A lane that could not be reviewed shows "review:unreviewed" in its status row, so
        it is visually distinguishable from a lane that passed review.
```

LANE_WRITES: plugins/leadv2/scripts/leadv2-dispatch-product-close.sh, plugins/leadv2/scripts/lib/leadv2-glm-policy-resolve.py, plugins/leadv2/config/leadv2-routing.yaml, plugins/leadv2/scripts/leadv2-dispatch-code.sh, plugins/leadv2/scripts/lib/leadv2-quota-error-parse.py, plugins/leadv2/scripts/tests/test-review-pool-never-empty.sh, plugins/leadv2/scripts/tests/test-review-pool-empty-rootcause.sh, plugins/leadv2/scripts/tests/test-quota-lockout-postspawn.sh

DELIVERABLE_COMPLETE
