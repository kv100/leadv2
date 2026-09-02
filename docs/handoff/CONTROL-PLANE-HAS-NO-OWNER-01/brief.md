# CONTROL-PLANE-HAS-NO-OWNER-01 — extract the control plane; do NOT rewrite the plugin

**Class:** Heavy. **Repo:** leadv2 plugin. **Filed:** 2026-09-02 by the persona-engine lead, in answer to
the founder's question "не та же ли это болезнь, что у продукта — может, переписать плагин на Python?"

## The answer, from the day's evidence

Eight distinct failures were diagnosed on 2026-09-02. Classified by what actually caused them:

| failure | cause class |
|---|---|
| dispatched worker ends its turn waiting for its own background job (6 lanes) | prompt contract |
| nested agent with `isolation:"worktree"` writes outside the lane | prompt contract |
| `lane-watch-v2` registers ITSELF as the lane's worker pid → dispatch refused forever | **state ownership** |
| dispatch ledger has no reopen; `write-terminal` + `state=dead` still refuses | **state ownership** |
| review gate reports `arm_rc=opus=1` with no cause and an empty stderr file | missing capture |
| `run-core-offline.sh` blocks 600s on a lock whose holder pid is dead | idiom (same bug in any language) |
| negative controls vacuous (mutant copy without `lib/`) | test design |
| `.claude/scripts` real copies drifted from canonical (5 files in another repo, 202 in this one) | **packaging** |

Zero belong to bash-the-language. One belongs to packaging, and that is the only place a Python package
would help by construction (an installed package cannot drift file-by-file the way a symlink farm does).
Three belong to one root cause: **the control plane has no owner.**

The registry (`~/.claude/leadv2-state/leadv2/active.yaml`), the dispatch ledger
(`~/.claude/cache/dispatch-ledger/leadv2.jsonl`), the phase records, the lane locks and the liveness
verdicts are plain yaml/jsonl mutated by dozens of scripts with no schema, no validation on write, and no
transaction. So an observer can write itself into a worker's row; a terminal state can exist and still
refuse; a row deleted by one process reappears from another. Every fix is local, so the next fix is too.

A rewrite in Python carries this architecture across unchanged and adds a year of regressions on top of
245 scripts. Rejected on those grounds — not on sentiment about bash.

## What to build instead

One typed control-plane component (Python is a fine choice for it, that is an implementation detail) that
OWNS four things and is the only writer to them:
1. **Lane registry** — who is working a lane, with `pid_role` (worker | watcher | close | lead) so an
   observer can never be read as worker evidence.
2. **Dispatch ledger** — states with legal transitions, including a reopen path; a refusal must name the
   command that clears it.
3. **Liveness** — one verdict function with its inputs recorded, so a `starting:N` verdict can be explained.
4. **Locks** — a holder pid, and a lock whose holder is dead is free.

Everything else stays bash and calls this component. The interface is a CLI plus a JSON mode, so existing
callers change one line each, not their structure.

Acceptance, in this order:
- a schema + validation on every write, and a suite that proves an invalid write is REFUSED (negative
  control: remove the validation → suite red);
- the four failures above become impossible by construction, each with a regression test that reproduces
  the 2026-09-02 scenario;
- every current writer of those files is migrated (census first: which scripts write which state — that
  count is the real size of this task and must be measured before estimating);
- no behaviour change visible to the lead beyond the refusals gaining a remedy line.

## Measurement to run first (before any code)
`grep -rl` over `plugins/leadv2/scripts` for writes to `active.yaml`, the ledger, `phases.d/`, and lock
paths; report the number of distinct writer scripts per store. If it is under ~10 per store, this is weeks.
If it is 40+, the migration is the whole task and the founder should see that number before approving.

## Explicitly out of scope
- Rewriting the plugin, or porting scripts that do not touch control-plane state.
- The self-learning layer.

## Measurement done, 2026-09-02 — the migration IS the task
Count of scripts under `plugins/leadv2/scripts` that touch each store (mentions / likely writers, by grep):

| store | mentions | likely writers |
|---|---|---|
| `active.yaml` (lane registry) | 126 | **73** |
| dispatch ledger | 55 | 13 |
| lock files | 72 | 21 |
| `phases.d/` | 11 | 3 |

73 likely writers to the lane registry is the answer to "how big is this": the component itself is small,
the migration is the whole project. Sequence accordingly — write the owner, migrate the ledger (13) and
phases (3) first as the cheap proof, then the locks (21), and only then the registry (73) in batches with a
guard that fails any direct write from a non-owner script. Do NOT start with the registry.
