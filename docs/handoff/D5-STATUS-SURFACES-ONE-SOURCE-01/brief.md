# D5 — Status Surfaces, One Source (build mission brief)

Repo: `~/Projects/leadv2`. References `docs/handoff/WAVE4/shared-constraints.md` throughout
(cited inline as "WAVE4"). Investigation basis: live grep/read of the plugin tree + two live
`leadv2-lane-liveness.sh` invocations on this machine, 2026-09-03 (see Liveness rule).

## Goal
Every status surface renders from ONE computed lane snapshot instead of independently re-deriving
lane existence and liveness. Root cause: the data is already correctly shared cross-repo
(`~/.claude/leadv2-state/`), but THREE parallel enumeration paths feed one table, and foreign-repo
liveness uses a cheaper, mtime-tainted check the own-repo path doesn't.

## Surface inventory
| Surface | Writer | Reader | Store it derives from | Repo-scoped? |
|---|---|---|---|---|
| `founder-status.md` | `leadv2-broad-status.sh` | founder / session start | collector JSON, 3 sections below | own-repo + only foreign lanes THIS repo dispatched (PULSE-REPO-SCOPED-03 filter) |
| collector `lanes` section | `leadv2-status-collector.sh` | broad-status.sh | `leadv2-lanes-snapshot.sh --json`, `LEADV2_LANES_ALL_REPOS=1` pinned | cross-repo, but foreign liveness = inline pid/log-mtime, never lane-liveness.sh |
| collector `lane_detail` section | same | same | `leadv2-lane-detail.sh --json` → delegates verbatim to lane-liveness.sh | own-repo only |
| collector `dispatched_lanes` section | same | same | raw `active.yaml` rows UNION `.claude/worktrees/*` dirs — added as a fallback because the primary "fails slow or not at all" (STATUS-CHURN-01) | own-repo only |
| `leadv2-lanes-snapshot.sh` | itself | collector + ad hoc CLI | own repo: `active.yaml` + `lane-liveness.sh --all --json`; foreign repos (via status-projects.sh TSV): their `active.yaml` + INLINE pid/log-mtime | cross-repo, non-uniform liveness — the core gap |
| `leadv2-lane-liveness.sh` | itself | lane-detail.sh, lanes-snapshot.sh (own-repo path only) | `active.yaml` + `tombstones.yaml` + PID-identity/sentinel/commit signals | own-repo only, no cross-repo caller — the correct engine, under-used |
| `leadv2-status-projects.sh` | itself, pure compute | lanes-snapshot.sh | globs `~/.claude/leadv2-state/*/` for a live `active.yaml` + resolvable repo root | cross-repo BY DESIGN — this is the repo registry |
| `leadv2-status-surface.sh`(+`.5s.sh`) | itself | timer loop regenerating founder-status.md | own mtime checks, independent of collector | own-repo |
| `leadv2-status.sh` | itself | interactive `/leadv2 status` | own mtime checks | own-repo |
| `leadv2-lane-status-line.sh`(+`-tail.sh`) | itself | Claude Code terminal statusLine | own PID/sentinel 30s-TTL memo | own-repo, different consumer (live paint, not the digest) |
| `leadv2-status-render.sh` / `-status-snapshot.sh` | itself | unverified | likely thin formatters (170 / 67 lines) | unverified — confirm pure-formatter before excluding |
| `docs/leadv2/active.yaml` | `leadv2-dispatch-code.sh` (off-limits) / active-registry | everything above | `~/.claude/leadv2-state/<repo-slug>/active.yaml` | ONE file per repo-slug — raw per-repo data, not the aggregate |
| `leadv2-quota-status.sh` | itself | quota display | provider quota state, not lanes | out of scope for D5 |

## Chosen single source
No new location needed. `~/.claude/leadv2-state/` is already the shared root — confirmed live:
leadv2's own `active.yaml` symlinks to `.../leadv2-state/leadv2/active.yaml`, persona-engine's to
`.../leadv2-state/persona-engine/active.yaml` — same tree, partitioned by repo-slug subdir. The
aggregate is what `leadv2-lanes-snapshot.sh --all-repos --json` ALMOST already produces: repo
discovery via `status-projects.sh`'s TSV (correct), per-repo rows from that repo's `active.yaml`
(correct), verdict from `lane-liveness.sh --all --json` for the OWN repo only — every foreign repo
gets a cheaper inline pid/log-mtime check instead (lanes-snapshot.sh ~335-458, comment: "never
lane-liveness.sh's ... state-path resolution"). That asymmetry is the only real gap. Nothing else
legitimately claims to be the source: `dispatched_lanes`'s raw file union is already documented as
a fallback for when the real path "fails slow or not at all" — keep it as fallback-on-timeout, not
a third parallel primary.

**Where it lives, in 4 lines:** it lives where it already lives — `~/.claude/leadv2-state/<slug>/
active.yaml` per repo, aggregated on demand, never copied into one new shared file, never owned by
one repo. A single physical aggregate file would need write-arbitration across concurrent sessions
in 2+ repos; an on-demand aggregator that only READS N already-authoritative per-repo files has no
write race. `leadv2-lanes-snapshot.sh --json` becomes that aggregator, called by every surface.

## View contract
MUST CONVERT (render only, zero independent lane/liveness computation):
- `leadv2-broad-status.sh` / founder-status.md — read the fixed snapshot; the C3 "foreign lane not
  dispatched by me → dropped" filter (~337-361) becomes "all live foreign lanes render as existence
  rows"; per-lane DETAIL (mission text, worker, stream path) stays own-repo-only via the
  lane_detail join. This reverses part of PULSE-REPO-SCOPED-03 (`test-broad-status-foreign-lanes.sh`
  C3/C4, `test-status-repo-scoped.sh`) — flag as a decision reversal needing explicit sign-off, per
  WAVE4 "never weaken/loosen an existing assertion" — the fix is a stated policy change with a
  rewritten, commented assertion, not a silent loosen.
- `leadv2-status-collector.sh` — fold `_sc_lanes_section` + `_sc_lane_detail_section` into one call
  to the fixed snapshot; keep `_sc_dispatched_lanes_section` gated to run ONLY on snapshot
  timeout/error.
- `leadv2-status-surface.sh`(+`.5s.sh`), `leadv2-status.sh` — stop independent mtime checks, read
  the same collector JSON.
- `leadv2-lane-status-line.sh`(+`-tail.sh`) — per-lane verdict comes from the snapshot; may keep its
  own short TTL memo of the AGGREGATE result for paint-rate, never recompute liveness itself.
MAY STAY:
- `leadv2-lane-liveness.sh`, `leadv2-status-projects.sh` — these ARE the source, not views.
- `leadv2-lane-detail.sh` — becomes the own-repo DETAIL enrichment, joined by task_id; already
  delegates correctly, internals unchanged.
- `leadv2-quota-status.sh` — different domain, untouched.
- `leadv2-status-render.sh` / `-status-snapshot.sh` — read-only formatters; confirm with one grep
  before excluding (unverified in this pass).

## Liveness rule
`verdict(task_id) = leadv2-lane-liveness.sh --project-root <repo_root> --all --json` row for that
task_id, computed ONCE per repo per beat by the aggregator — never per-surface, never from file
mtime. mtime may only gate a cheap pre-filter (skip a repo whose `active.yaml` mtime is unchanged
since the last beat), never stand in for the verdict.

**Live verification on this machine (2026-09-03):** `leadv2-lane-liveness.sh --project-root
~/Projects/leadv2 --all --json` and the same call against `--project-root ~/Projects/persona-engine`
BOTH hung the full 20s timeout at ~0% CPU (blocked, not computing) when invoked standalone —
reproducing "fails slow or not at all" (STATUS-CHURN-01) directly, almost certainly lock contention
with the live lanes this investigation found running. **Consequence:** the aggregator must wrap
every `lane-liveness.sh` call (own-repo AND each foreign repo) in a hard per-call timeout (reuse
the pattern in lanes-snapshot.sh's foreign-read loop, ~line 382) and degrade EXPLICITLY on timeout
(`verdict:"unknown:timeout"`) — never silently drop the row, never guess from a stale cache.

## Files allowlist
Reads: `leadv2-lanes-snapshot.sh`, `leadv2-lane-liveness.sh`, `leadv2-lane-detail.sh`,
`leadv2-status-projects.sh`, `leadv2-status-collector.sh`, `leadv2-broad-status.sh`,
`leadv2-status-surface.sh`(+`.5s.sh`), `leadv2-status.sh`, `leadv2-lane-status-line.sh`(+`-tail.sh`),
`leadv2-status-render.sh`, `leadv2-status-snapshot.sh`, `tests/test-broad-status-*.sh`,
`tests/test-status-repo-scoped.sh`, `tests/test-collector-sees-registered-lane.sh`, `tests/run-all.sh`.
Writes: same script set above (except off-limits below) + new `test-status-single-source.sh` +
one `EXTRA_SUITE_MAP` append in `tests/run-all.sh`.
Off-limits (WAVE4 + task): `leadv2-dispatch-code.sh`, `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh`,
`leadv2-claude-profile-select.sh`, `tests/known-red-suites.txt`, any commit inside `~/MythicalGames`,
m3's tracked `.claude/settings.json`. Do NOT touch `_emit_ready_line` (`leadv2-broad-status.sh` ~136-150)
— that belongs to `BROAD-STATUS-READY-FIRES-ON-A-DAY-OLD-FILE-01`, owned by another lane. **Merge
order:** both fixes land in `leadv2-broad-status.sh`, ~200 lines apart (ready-line ~136-150 vs the
foreign-row filter this brief touches at ~337-361) — no overlap; land the ready-line fix first
(narrower, already in flight) and rebase this lane on top.

## Steps
1. `leadv2-lanes-snapshot.sh` foreign-repo loop (~335-458): replace the inline pid/log-mtime check
   with a timeout-wrapped `leadv2-lane-liveness.sh --project-root <foreign root> --all --json`
   call, degrading to `verdict:"unknown:timeout"` — never zeroing the row.
2. `leadv2-status-collector.sh`: fold `_sc_lane_detail_section`'s own-repo enrichment onto the now-
   uniform snapshot by task_id; gate `_sc_dispatched_lanes_section` to run only when the snapshot
   call itself timed out or errored.
3. `leadv2-broad-status.sh`: change the foreign-row drop (~337-361) to render ALL live foreign rows
   with the existing `<slug>/` prefix (R1-R3 render shapes already correct — do not touch them);
   detail fields stay own-repo-only via the lane_detail join.
4. Point `leadv2-status-surface.sh`(+`.5s.sh`) and `leadv2-status.sh` at the collector JSON instead
   of their own mtime checks.
5. Write `test-status-single-source.sh` (see Negative control); append its
   `leadv2-lanes-snapshot.sh:...` and `leadv2-broad-status.sh:...` rows to `EXTRA_SUITE_MAP`
   (append at the end of the block, per WAVE4); prove selection with `tests/run-all.sh --scope changed`.
6. Update `test-broad-status-foreign-lanes.sh` C3/C4 and `test-status-repo-scoped.sh`'s lane-
   presence assertions to the new policy, as a stated, commented reversal citing this brief —
   never a silent loosen (WAVE4 hard prohibition).

## Acceptance
- Spin up N synthetic lanes split across leadv2's and persona-engine's `active.yaml`; every
  converted surface (founder-status.md, collector JSON, lane-status-line) reports the SAME N —
  assert pairwise equality between surfaces, not plausibility of any single one.
- `kill -9` one lane's worker PID; re-run one beat; every surface agrees `dead` — never mixed.
- A lane registered only in persona-engine's `active.yaml` still appears from a leadv2-repo
  session (and vice versa), carrying the correct `repo:` tag.

## Negative control
Suite: `plugins/leadv2/scripts/tests/test-status-single-source.sh` (new).
Mutation: inside `leadv2-lane-liveness.sh`'s PID-identity corroboration block
(LANE-REGISTRY-SELF-DEADLOCK-01 section, ~176-240) — force the `kill -0`-failure branch to still
set `verdict="alive"` instead of a dead verdict. Apply INSIDE the function body, never at file top
level (WAVE4 rule 1). Expected: suite goes RED — the kill-worker acceptance check fails because
every surface keeps reporting alive for a confirmed-dead PID. Revert, confirm GREEN. Record both
exit codes verbatim in the implementation report, plus the `tests/run-all.sh --scope changed`
output proving the `EXTRA_SUITE_MAP` row selects this suite when `leadv2-lane-liveness.sh` is the
changed file. Green on macOS AND in a linux container (WAVE4 rule 2), both exit codes reported.

## Out of scope
- `BROAD-STATUS-READY-FIRES-ON-A-DAY-OLD-FILE-01` (`_emit_ready_line`'s `at=` stamp) — owned by
  another lane; see Merge order above.
- Anything inside the off-limits files listed above.
- The per-repo product-metric line (posts/comments/replies): PULSE-REPO-SCOPED-03's C1/C2
  (declared-not-hardcoded) is correct and untouched — only its C3/C4 lane-visibility gate changes.
- `leadv2-quota-status.sh` and any provider-quota surface.
- Codex-job liveness (`_lane_codex_status`) — separate process model, not touched here.
- Materializing the aggregate as a stored file — this design is call-based, not storage-based.

---

## LEAD ADDENDUM — one thing this lane may NOT decide, and one it must not simplify

### The foreign-lane filter is a policy question, not an implementation detail

The brief proposes dropping the "dispatched-by-me-only" filter in `leadv2-broad-status.sh` so
lanes in another repo appear. That is the right technical answer — the founder-facing status read
"+0 линии подняты" on an evening when seven lanes were running in the plugin repo, which is the
whole reason this row exists.

But it reverses a stated policy (`PULSE-REPO-SCOPED-03`) and it changes what the founder sees.
**This lane does not flip it unilaterally.** Build the aggregation so foreign lanes are available,
put the display behind a single switch, and leave the switch in its CURRENT position. The lead
has the question and will answer it; when the answer comes, flipping it is a one-line change.

If the answer has not arrived by the time the rest of the lane is done, ship the rest. Do not
block on it, and do not quietly flip it to make the acceptance look better.

### The liveness call can hang — a timeout is part of the fix, not a nicety

The brief measured `leadv2-lane-liveness.sh` taking 20s+ under lock contention. A status surface
that blocks for 20 seconds is a broken status surface, and the natural temptation — keep the
cheap inline pid/log-mtime check for foreign lanes — reintroduces exactly the defect this wave
has been fighting all evening: **mtime is not liveness.** Lanes idle 13 minutes and 26 minutes
were equally dead, and a wide process pattern reports a dead lane as busy.

So: one liveness rule for all lanes, foreign or not, with a per-call timeout and an explicit
`unknown` result when the timeout fires. `unknown` must render as `unknown` — never as alive, and
never as dead. A surface that guesses on timeout is lying in whichever direction it guesses.

The four false answers this rule must survive are enumerated in
`docs/handoff/D4-NO-PATH-LOSES-WORK-01/brief.md` (lead addendum 2), including the zsh
word-splitting trap that made a correct PID check report every lane dead. Read that section
before implementing the liveness call here; D4 owns the rule, this lane consumes it.

### Acceptance stays as written, with one addition

Assert that a timeout produces `unknown` on every surface simultaneously — not alive on one and
dead on another. Surfaces disagreeing under failure is the exact symptom this row exists to kill.
