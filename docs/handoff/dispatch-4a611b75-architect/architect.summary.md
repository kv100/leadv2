verdict: APPROVE
next_action: continue

Round-2 design ready: rebase onto origin/main first (kills M3, skips M4), then H1/H2 at two single choke points.

- H1: resolve SKILL.md from plugin root (repo-local override first) + warn on empty; unconditional prefix-path log so a test can probe the rendered prompt.
- H2: inject canonical contract once at `_spawn_worker_body:2519` (all 4 arms) + idempotent copy in glm-coder.
- Suite: C7 rendered-prefix, C8 rendered-mission (model on test-lane-placement-pin.sh), C9 drift pin, M2/L2-L5.

Full: architect.full.md
