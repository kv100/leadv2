# CAPABILITY-TRUTH-AUDIT-01 — every plugin mechanic must be proven to fire, in every adopted repo

**Class:** Heavy. **Repo:** leadv2 plugin (changes land here; measurement runs across all adopted repos).
**Filed:** 2026-09-02 by the persona-engine lead, on founder order: "все механики должны работать для
плагина — скилы, гарды, хуки — штатно и как задумано, не перегружая".

## The finding that triggered this (measured, not assumed)

Hook wiring per repo, read from each repo's `.claude/settings.json`:

| repo | SessionStart | PreToolUse | PostToolUse | Stop | UserPromptSubmit | other | total |
|---|---|---|---|---|---|---|---|
| persona-engine | 1 | 7 | 8 | 1 | 4 | 3 | 24 |
| respiro-ios | 1 | 5 | 5 | 1 | 0 | 0 | 12 |
| getmany-followup-bot | 1 | 1 | 2 | 0 | 0 | 0 | 4 |
| m3-market (at `~/MythicalGames/m3-market`, NOT `~/Projects`) | 1 | 7 | 4 | 1 | 2 | 4 | 19 |
| **leadv2 (the plugin's own repo)** | 0 | 0 | 0 | 0 | 0 | 0 | **0** |

So the guards exist in one repo and thin out to nothing everywhere else — including the repo where the
plugin itself is developed, which is where every lane of 2026-09-02 ran. This is the direct answer to
"правило для таких тестов есть, но почему-то не сработало" in another repo: the rule is real, its
enforcing hook is simply not wired there. `.claude/scripts` symlink farms and `leadv2-overrides/` exist
in all four repos (247-316 links each), so adoption LOOKS complete while enforcement is not.

Second measured fact, same day: `leadv2-judge.sh` — the plugin's own round-cap judge — has 0 mentions
across 400 session transcripts in 30 days, while the lead hand-wrote two judge prompts today.
Detail + the two agent censuses that produced FALSE answers: `docs/handoff/LEAD-USES-ITS-OWN-TOOLS-01/brief.md`.
Third, and it is a lesson about this very audit: the lead first reported m3-market as "deleted" because it
scanned only `~/Projects`. It lives at `~/MythicalGames/m3-market`, is actively worked in (session
activity 2026-09-02 13:48), has 305 script links, 23 agents, and 19 wired hooks including events the
other repos do not wire at all (`TaskCompleted`, `TeammateIdle`, `CwdChanged`). Any census that assumes
a repo root LIES the same way the two agent censuses did. The repo list must come from a written source,
not from a directory glob.

## What this task must deliver

1. **A capability census with a firing proof per row.** One machine-readable table
   (`docs/capability-census.yaml` in the plugin) with a row per skill, hook, guard, workflow, command and
   lead-facing script: what it is for, where it is wired, and **the command that proves it fires**.
   A row without a firing proof is dead weight and must be marked so.
   Method note, learned the hard way today: mention-counting and `hooks.json` greps both LIE. Hooks are
   also wired as a name+predicate table inside `hooks/leadv2-bash-pre-dispatch.sh`; an agent that reads
   only `hooks.json` called 25 live hooks "orphans", one of which had blocked the lead's own command
   minutes earlier. Proof means: trigger the condition and observe the guard's own output.
2. **Parity across adopted repos.** `leadv2-repo-install.sh` must install the SAME enforcement set
   everywhere (or state, per hook, why a repo is exempt). The plugin's own repo must not be the least
   protected one. Prove parity with a script that diffs the wired set per repo and exits non-zero on an
   unexplained gap; run it for persona-engine, respiro-ios, getmany-followup-bot, m3-market (`~/MythicalGames/m3-market`)
   and leadv2. m3-market wires three events nobody else does — decide per event whether that is a
   per-repo exemption or a gap in the others.
3. **Dead-weight pass.** For every capability with no firing proof: wire it, document it, or delete it.
   Deletion is a valid and preferred outcome — 245 scripts / 43 skills / 37 hooks is more surface than
   the lead can hold, and the founder's complaint is that the lead gets heavier, not better.
4. **A no-overload budget.** Guards that fire on every turn cost tokens and turns. Measure how often each
   PreToolUse/PostToolUse guard fired in the last 7 days and what it prevented; any guard that fires
   often and prevents nothing is a candidate for deletion or a narrower predicate.
5. **Out of scope for now:** the self-learning layer (founder's explicit exclusion).

## Constraints
- Land changes in the plugin repo only; per-repo differences go to that repo's `leadv2-overrides/`.
- Every new check ships with a negative control that goes red in a mktemp FULL copy (including `lib/`)
  whose baseline is green — today three lanes shipped vacuous controls that passed with the mutation present.
- No nested agents, no background waits, commit after every step.

## Done when
- `docs/capability-census.yaml` exists with a firing proof or an explicit dead marker per capability;
- the parity script runs green (or its exceptions are written down) across the four live repos;
- the dead-weight pass has removed or wired everything with no proof, with the diff to show it;
- the guard-cost table for 7 days is in the report.

## Additional row — 2026-09-02: the pulse reads one repo and reports the wrong truth
The anti-silence pulse (`scripts/anti-silence-pulse.sh` + `leadv2-broad-status.sh`) composes its status from
the CURRENT repo's registry only. The lead session ran all day from persona-engine while every lane lived in
the leadv2 plugin repo, so the pulse printed "линий нет" twice while five lanes were building — a confident
false zero delivered to the founder. It also listed two dead codex jobs as the only rows.
Required: the status source must be the control-plane registry across every adopted repo (the same written
repo list the census uses), not `$PWD`. Until then the pulse must say WHICH repo it looked at, so a reader
can tell "nothing running" from "nothing running here".

## Symlink-farm drift — measured across four repos, 2026-09-02 (cross-repo find)

The getmany-followup-bot lead traced a two-day `provider_error rc=1` on the opus review arm to a REAL COPY
of `claude-subsession.sh` in `.claude/scripts/` (32105 bytes, 4 May) instead of a symlink to canonical
(69004 bytes, current) — 990 lines of drift. Four more drifted copies sat beside it, `leadv2-helpers.sh`
worst at 1142 lines. Replacing all five with symlinks fixed the arm on the next probe.

The same check here (a `.claude/scripts/*.sh` that is a regular file AND has a same-named file in
`plugins/leadv2/scripts` is drift; no canonical twin means a legitimate repo-native script):

| repo | real files | drifted copies |
|---|---|---|
| persona-engine | 40 | 1 — `leadv2-lane-detail.sh` (169 lines) |
| respiro-ios | 18 | 1 — `codex-guard.sh` (392) |
| m3-market | 31 | 1 — `codex-guard.sh` (392) |
| **leadv2 (the plugin's own repo)** | **202** | **~25**, worst: `leadv2-broad-status.sh` 568, `leadv2-dispatch-product-close.sh` 416, `leadv2-active-registry.sh` 414, `leadv2-status-collector.sh` 221, `leadv2-lane-status-line-tail.sh` 217, `leadv2-repo-install.sh` 110 |

The plugin's own `.claude/scripts` is 202 real copies of its own `plugins/leadv2/scripts`, and every lane of
2026-09-02 ran there. `leadv2-repo-install.sh` itself is one of the drifted copies (110 lines behind), which
explains why it reported `.claude/scripts linked 20` and `ok` while five stale copies sat next to it.

Additional requirements for this task:
- `leadv2-repo-install.sh --check` must FAIL (non-zero) on a drifted copy and name each file plus its line
  delta. Detection rule as above; it is mechanical and needs no judgement.
- The install must never report `ok` for a farm that contains a same-named real copy.
- Converting the plugin repo's own 202 copies to symlinks is its own step (`leadv2-scripts-symlink-plan.sh`),
  to be done with no lanes in flight, file by file — a drifted copy may contain unmerged work that has to go
  UP into canonical first, never be discarded.
