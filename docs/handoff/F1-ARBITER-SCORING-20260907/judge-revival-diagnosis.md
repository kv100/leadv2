# Judge revival — Part 0 diagnosis: the mechanism, named with runtime evidence

**Verdict: mechanism 2 — the judge IS called on Standard/Heavy dispatches and fails silently.**
`_invoke_judge()` is reached (cache does not absorb this population, Light-skip is inapplicable),
the real `claude -p` call fails — timeout under concurrent-session gateway load is the
demonstrated, reproducible failure mode — and the failure falls through to
`_fallback_estimate()` (leadv2-task-judge.sh:500) with **zero distinguishing telemetry**: no
stderr from the failure itself, script exit 0, and a journal line indistinguishable from the
disable / Light-skip / fallback lines. The lack of a marker is itself part of the defect. The
exact sub-mode (timeout vs non-zero exit vs empty output vs envelope/JSON parse) of each
production failure is unrecoverable retroactively because no marker was ever written.

## Evidence

### E1 — live corpus census (path-excluded, the seam-diagnosis.md trap avoided)

Command (verbatim):

```
find ~/.claude/leadv2-state -path '*/tasks/*/journal.md' | grep -vE 'ephemeral|deadbeef' \
  | xargs grep -h 'route_v2_estimate'
```

Output distribution (checked=122 lines, 2026-09-07 ~12:50Z):

```
estimate_source:  120 fallback · 2 judge
cache_hit:        121 false · 1 true
complexity_basis:  31 class_hint · 32 line_count · 59 (token absent — pre-step-2 binary runs)
class_hint lines by complexity:  22 simple (=Light skip, by design) · 9 complex (Heavy) · 0 standard
```

### E2 — the 9 Heavy production fallback lines (the mechanism-2 population)

All 9 `complexity=complex complexity_basis=class_hint` lines, persona-engine, today 11:29–11:45Z
(one dispatch ≈ every 1–2 min — a live batch), every one `cache_hit=false`, every one
`estimate_source=fallback`. Representative line (tasks/33db6bcf/journal.md):

```
- 2026-09-07T11:40:03Z [decision] route_v2_estimate estimate_id=e2bf4950 estimate_source=fallback complexity=complex work_kind=build duration_class=long risk_class=none flag_source=title subsystems_touched=2 needs_live_verification=False cache_hit=false safety_floor=none
```

checked=9/9. Branch order (:463-500) leaves exactly one way to journal this line on a Heavy class
hint: not disabled, not Light, cache miss **⇒ `_invoke_judge` ran and produced no validated
estimate**. That is mechanism 2 by elimination, on production lines.

### E3 — invoke IS reached today, and succeeds when unloaded (instrumented live run)

Unmodified live binary (main checkout — what live sessions run), real mission
(persona-engine WORKTREE-DIRT-CENSUS-01/mission.md, 62 lines), `--class Heavy`, `claude` wrapped
via the script's own `LEADV2_JUDGE_CLAUDE_BIN` seam to log rc/elapsed/output:

```
=== 2026-09-07T12:54:47Z argv_n=10 ... prompt_bytes=7422 real=/Users/kostiantyn.vlasenko/.local/bin/claude
    rc=0 elapsed=22s out_bytes=1690 ...
```

stdout: `{"complexity": "standard", ..., "estimate_source": "judge", "flag_source": "judge", ...}`
— checked=1 healthy run: the full path prompt→claude→envelope-parse→validate→judge-emit works.

### E4 — controlled failure repro: silent, indistinguishable, exit 0

Same binary/mission, only `LEADV2_JUDGE_TIMEOUT_SEC=5`:

```
$ time env ... LEADV2_JUDGE_TIMEOUT_SEC=5 bash .../leadv2-task-judge.sh --class Heavy ...
{"complexity": "complex", ..., "estimate_source": "fallback", ..., "subsystems_touched": 2, ...}
        0.36s user 0.35s system 12% cpu 5.828 total
JUDGE_RC=0
```

checked=1: wrapper trace shows the invoke started and was killed by gtimeout at 5s; output is the
fallback JSON; rc=0; no failure marker of any kind. This output is shape-identical to the E2
production lines. **The 45s budget against a 22s unloaded call (E3) is the margin that the
11:29–11:45 batch burned**: 9 dispatches each spawning workers on the same gateway (this machine
runs 4+ concurrent claude sessions; 24h burn 1.42B per SessionStart telemetry).

### E5 — where the other 3s go (found during E3)

claude's stderr on every judge call:

```
Warning: no stdin data received in 3s, proceeding without it. If piping from a slow command, redirect stdin explicitly: < /dev/null to skip, or wait longer.
```

The invoke sites (:313/:315) never redirect stdin, so every judge call pays a fixed 3s stdin
wait inside its timeout budget. (checked=2 runs, warning present both times.)

### E6 — why the exact sub-mode of the 9 production failures is unrecoverable

`2>/dev/null` on both invoke arms swallows claude's stderr; every `return 1` in `_invoke_judge`
is silent; `_validate_estimate` failure is silent; the fallback `_emit` at :500 carries no
reason. checked: grep for any invoke-failure marker across the 122-line corpus → 0 hits. The fix
must add the marker; it cannot reconstruct the past.

## Mechanism 1 and 3 — excluded, with evidence

- **M1 (never called / cache absorbs): excluded.** checked=122: exactly 1 `cache_hit=true` line
  in the whole corpus (getmany-followup-bot 11:58:27Z — a re-dispatch 2s after its own
  successful judge call wrote the cache). Cache keys on sig8 of the full mission text, so only
  identical re-dispatches hit; it cannot absorb first-time Standard/Heavy traffic.
- **M3 (answered, discarded downstream): excluded.** checked=2: the getmany-followup-bot 11:58
  judge calls survived to the journal (`estimate_source=judge` on real lines). Seam-diagnosis §2
  already verified the dispatch-code derivation (est_src=='judge' → complexity_source='judge')
  is reachable; nothing downstream discards a judge answer.
- Note: those 2 judge lines carry no `complexity_basis` because the live tree runs **main**, and
  steps 2/3 are not on main (checked: `git branch --contains 8d6dbe6d` → worktree branch only).
  The live plugin is the pre-step-2 binary — expected mid-lane, and why this mission's live
  demonstration must run the lane-branch binary.

## R2 mitigation #3 (Light-skip) — deliberately untouched

The 22 `complexity=simple complexity_basis=class_hint` lines are the Light population skipping
the judge by design. No decision record authorizing its removal was found (the revival estimate
doc records the same absence), and this mission does not authorize removing it. The fix touches
only the failure-mode silence, not the skip policy.

## Fix scope this implies (Part 1)

1. `judge_path=` token on every `route_v2_estimate` journal line:
   `disable|light_skip|cache_hit|judge|judge_fail` — the marker whose absence E4/E6 demonstrated.
2. `judge_fail_reason=` on judge_fail lines: `template_missing|prompt_build|timeout|
   nonzero_rc|empty_output|envelope_parse|schema_invalid` — makes E6's question answerable
   forever after.
3. `< /dev/null` on the `claude -p` invocations — removes the 3s stdin wait (E5), widening the
   timeout margin at zero cost.
4. No change to: Light-skip, disable flag, cache semantics, timeout default (45s), fallback
   behavior, exit codes. The judge still never blocks a dispatch (R2 invariant).

---

## Part 1–3 outcomes (same day, post-fix)

### Part 1 — shipped as described above

`leadv2-task-judge.sh`: `judge_path=` on every route_v2_estimate line, `judge_fail_reason=`
on judge_fail lines (7 modes), fd-3 plumbing across the `$( )` subshell (a plain global set
inside `_invoke_judge` dies with the subshell — the first smoke run journaled
`judge_fail_reason=unknown` for every mode until this was caught), `stdin </dev/null` on both
invoke arms. Suite `plugins/leadv2/tests/test-judge-complexity-path.sh` pins all five paths
and all reachable failure modes (18 checks, green).

### Part 2 — negative control, execution-proven inside the function body

Mutated the exact line Part 0 named (`_fail "timeout"` → `_fail "MUTANT_TIMEOUT_9E1F"`) in
the real committed binary, ran the timeout repro, restored. The mutation's own token in the
journal line is the proof of execution:

```
... cache_hit=false safety_floor=none complexity_basis=class_hint judge_path=judge_fail judge_fail_reason=MUTANT_TIMEOUT_9E1F
... cache_hit=false safety_floor=none complexity_basis=class_hint judge_path=judge_fail judge_fail_reason=timeout
```

(first line = mutated binary, second = restored wild type; `git diff` clean after restore).
The suite's §6 runs the same control as a throwaway copy on every run.

### Part 3 — live demonstration (path-excluded census, the trap avoided)

Generated a genuinely live Heavy dispatch through the fixed binary:
`leadv2-dispatch-code.sh @<real mission> --no-spawn --task-class heavy --task-id
JUDGE-REVIVAL-DEMO-01` (resolve+journal only, no worker; exit 0; the declared-class floor
correctly made route_resolved read `complexity_source=flag` — §5.1 precedence, not a
discard). Census command and output, verbatim:

```
$ find ~/.claude/leadv2-state -path '*/tasks/*/journal.md' | grep -vE 'ephemeral|deadbeef' \
    | xargs grep -h 'route_v2_estimate' 2>/dev/null | grep -c 'complexity_basis=judge'
1

$ find ~/.claude/leadv2-state -path '*/tasks/*/journal.md' | grep -vE 'ephemeral|deadbeef' \
    | xargs grep -l 'complexity_basis=judge' 2>/dev/null
/Users/kostiantyn.vlasenko/.claude/leadv2-state/persona-engine/tasks/2506182c/journal.md
```

The line itself (real path, judge decision journaled end-to-end, new markers live):

```
- 2026-09-07T13:19:52Z [decision] route_v2_estimate estimate_id=921e39fd estimate_source=judge complexity=simple work_kind=diagnose duration_class=short risk_class=none flag_source=judge subsystems_touched=3 needs_live_verification=True cache_hit=false safety_floor=none complexity_basis=judge judge_path=judge
```

checked=1 line: **complexity_basis=judge > 0 on real, path-excluded journal lines — the
acceptance condition.** The judge answered `complexity=simple` for a light-shaped demo
mission under a heavy class hint, and the declared-class floor raised it at route_resolved —
both layers doing exactly their designed jobs. Observation, not investigated further: the
estimate journal of this leadv2-worktree dispatch was keyed under persona-engine's state dir
(pre-existing repo-key mapping in the state-path resolution, unchanged by this fix).
Demo residue cleaned: lane worktree removed, registry row tombstoned by the dispatcher's own
exit trap, judge-cache droppings deleted; only the journal line (evidence) remains.
