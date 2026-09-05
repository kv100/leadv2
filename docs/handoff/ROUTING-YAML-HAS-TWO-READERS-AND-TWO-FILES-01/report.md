# ROUTING-YAML-HAS-TWO-READERS-AND-TWO-FILES-01

The row's premise is too small in both directions. It is not two readers — it is
**13 product read sites in 4 resolution disciplines**. And it is not two versions
of one file — it is **two different documents sharing one filename**, with
**zero** top-level keys in common.

Everything below is either *measured* (a command was run, output quoted) or
*read-in-code* (a line was read, cited `file:line`). Nothing is inferred.

## 1. Three files, two documents (measured)

```
f760bea7a8a1  ino=501881138  ~/Projects/leadv2/plugins/leadv2/config/leadv2-routing.yaml
f760bea7a8a1  ino=501881138  ~/.claude/plugins/local/leadv2/plugins/leadv2/config/leadv2-routing.yaml
928851db19bc  ino=501546025  ~/Projects/leadv2/.claude/ref/leadv2-routing.yaml
1b967ac5004d  ino=295957741  ~/Projects/persona-engine/.claude/ref/leadv2-routing.yaml
```

The plugin cache and the canonical checkout are the **same inode today**, but the
code treats them as two separate candidates and searches them in order
(`glm-policy-resolve.py:247,250`), so that is a property of this install, not a
guarantee.

Parsed with the readers' own extraction shapes:

| file | arms | dispatch_ladder | capability_matrix | glm_policy | phases | stop_rules / downgrade_chain / floor_rules |
|---|---|---|---|---|---|---|
| plugin canonical | 7 | 9 | 9 | **absent** | 0 | no |
| leadv2 `.claude/ref/` | 7 | 9 | 9 | **absent** | 0 | no |
| persona-engine `.claude/ref/` | **0** | **0** | **0** | present | 8 | yes |

* **Document A — router registry**: top-level `router_v2` + `router`.
* **Document B — legacy per-phase table**: `phases`, `stop_rules`,
  `downgrade_chain`, `floor_rules`.

They overlap in **no** top-level key. So "the tenant file overrides the plugin
file" is false as a sentence about this system: for any given key exactly one of
the two documents ever carries it.

**Tier and document do not line up.** The tenant path holds document B in
persona-engine and document **A** in leadv2's own repo.

## 2. The three consuming repos do not see the same thing (measured)

| repo | tenant file | document |
|---|---|---|
| persona-engine | present, 282 lines | **B** |
| m3-market | **absent** | — |
| respiro-ios | **absent** (only `scripts-vendor-backup-2026-07-28*` copies, dead) | — |

So the tenant tier exists in exactly one of the three consuming repos. In the
other two, tenant-only readers run on their own defaults and the fallback
readers reach the plugin copy.

## 3. The census — 13 read sites, 4 disciplines (read-in-code)

**A. tenant path only, no fallback of any kind**

| site | key it wants | in a repo with no tenant file |
|---|---|---|
| `leadv2-router.sh:33` | phases/steps | warns, caller uses class fallback (`:134`) |
| `leadv2-cost-estimate.sh:22` | cost table | `routing = {}` (`:108`) |
| `codex-task.sh:150` | codex quota gate | gate skipped silently (fail-open by design) |
| `leadv2-router-v2.sh:70` | `router_v2.arms` + `phases.glm_policy` | `die` rc=2 (`:118`) |

**B. plugin copy only**

| site | key | seam |
|---|---|---|
| `lib/leadv2-route-arbiter.sh:52` | `router_v2.capability_matrix` | `LEADV2_ROUTE_ARBITER_ROUTING_YAML` |
| `leadv2-quota-read.py:372` | `router_v2.active_account` | `LEADV2_ROUTING_CONFIG` |

**C. file-level fallback** — `leadv2-dispatch-code.sh:567→575`: the plugin copy is
used only when the tenant **file** does not exist.

**D. key-level fallback** — the file exists, the key does not, and the reader
silently goes to a different file:

| site | falls back to |
|---|---|
| `leadv2-dispatch-code.sh:2336` (`router.dispatch_ladder`) | plugin copy |
| `lib/leadv2-review-signals.sh:82` (protected path patterns) | **canonical root**, not this install |
| `lib/leadv2-glm-policy-resolve.py:247,250` | tenant → plugin-local → canonical |
| `leadv2-dispatch-product-close.sh:412-417` | tenant → plugin → canonical |

`leadv2-review-run.sh:144,1129` and `leadv2-plan-run.sh:200` pass the tenant path
*into* the C/D readers, so the path they select is not necessarily the file the
value comes from.

## 4. Two documented statements that are false (measured)

1. The plugin file's own header said the repo-local table "is copied there by
   plugin sync when v2 is enabled". **No such sync exists**: the only writers of
   `.claude/ref/leadv2-routing.yaml` anywhere in the repo are two test fixtures
   (`tests/test-kimi-dispatch-spill.sh:23`,
   `tests/test-kimi-admission-guard.sh:26`). The one tenant copy that exists was
   made by hand (RECOVER-WAVE1-TEN-01, 2026-09-05). Corrected in place.
2. `leadv2-router-v2.sh:127` says it pulls `router_v2.arms` and
   `phases.glm_policy` "out of the SAME routing.yaml". **No file on this machine
   carries both** — arms live in document A, `glm_policy` in document B. In
   leadv2 the filter gets `arms=7, glm_policy={}` (policy bans silently empty);
   in persona-engine it would get `arms=0` and `die`.
   **Latent, not live**: every live call site uses `resolve --chain`
   (`leadv2-dispatch-code.sh:8191`), and that branch never reads the yaml at all.
   Filed, not fixed here.

One thing that looked like a defect and is not: `codex_quota_gate` sits at
`/phases/glm_policy/codex_quota_gate` in persona-engine's file, while
`codex-task.sh` reads it **top-level** — but it has a regex fallback
(`^\s*<key>_threshold_pct:\s*(\d+)`) and therefore still resolves 80 / 95.

## 5. What was done (step 1)

A 45–49 line block prepended to **all three** files naming, per decision, which
file is authoritative:

* `router_v2.capability_matrix` → the plugin copy **only**; a matrix written into
  a tenant file is inert.
* `router.dispatch_ladder` → tenant if it carries the key, else plugin.
* `router_v2.active_account` → plugin only.
* protected path patterns → tenant if present, else **canonical root**.
* per-phase model / stop rules / downgrade chain / floors / codex quota gate →
  document B only, and its four readers have no fallback.

**Additive, and proven additive.** `routing-readers-probe.sh` runs all four
extraction shapes any reader uses (`yaml.safe_load`, quota-read's line scanner,
codex-task's regex, review-signals' regex) against all three files, before and
after: `diff` is **empty**, including the sha of each parsed document.

## 6. Decision for step 3: rename exactly one file, not unify

**Not one owner.** Unifying means merging two documents that never overlapped,
and then either imposing document B on the two repos that never had a tenant file
or deleting persona-engine's `phases` / `stop_rules` / `downgrade_chain` /
`floor_rules`. That is a behaviour change in three repos to fix a naming problem.

**Not a rename by tier.** Tier and document do not line up (§1) — renaming "the
tenant file" would rename document A in leadv2 and document B in persona-engine
under one label, i.e. reproduce the exact confusion at a new name.

**Rename by document, which is one file.** persona-engine's tenant file is the
only document-B file in existence. Rename it (proposed:
`.claude/ref/leadv2-phase-policy.yaml`) and afterwards **every file named
`leadv2-routing.yaml` on this machine is document A** — the ambiguity that cost a
full lane on 2026-09-05 cannot recur, and no reader of document A changes at all.

Measured cost of that rename: **4 readers** (§3 discipline A) take the tenant path
with no fallback and want document B. Each must read the new name, keep reading
the old one with a loud deprecation line, and fail loudly — never
"config not found, take default" — if neither exists. `leadv2-router-v2.sh` is the
awkward one: it wants a key from each document (§4.2), so the rename forces that
contradiction into the open rather than leaving it latent.

**Not started.** Step 1 is committed; the rename is a separate change.

## 7. What I could and could not verify across the three repos

* **Verified by reading the files and running the readers' own parsers**: which
  document each repo has, which keys it carries, what each extraction shape
  returns (§1, §2, and the before/after diff in §5).
* **Verified by grep**: no repo-native reader of this filename in m3-market;
  in respiro-ios only `scripts-vendor-backup-20260728*` copies (dead since the
  2026-07-28 vendor cutover) plus one test; in persona-engine only
  `.claude/worktrees/*/.claude/scripts/leadv2-preflight.sh`, i.e. lane worktrees,
  not the live checkout.
* **Not verified**: that a dispatch actually runs to completion in m3-market or
  respiro-ios after this change. Nothing was executed in those two repos — the
  change is comment-only and the parser diff is empty, which is the strongest
  evidence available without dispatching real work there.
