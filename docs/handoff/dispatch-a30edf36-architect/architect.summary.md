verdict: APPROVE
next_action: continue

Scoped design for all 6 critic findings, 5 files, no new env vars or suites.

- C1: after `rc=$?`, grep this attempt's log bytes for the usage-limit signature → `codex_circuit_parse_until` → `codex_circuit_open … session-runner` → exit 2 (retires M6).
- C2: Group F f1/f2/f3 drives the real runner with a stubbed codex; suite 16→19.
- H3/M4/M5/LOW: delete the unreachable hatch (d2 inverted), codex-task.sh calls `codex_spawn_gate`, c2 rewritten on a fixture log.

Full: architect.full.md
