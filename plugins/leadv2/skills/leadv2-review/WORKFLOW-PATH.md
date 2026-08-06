# Review path — sole-owner engine (ONE-PATH-EVERYWHERE-01)

The lead/interactive Review phase calls the sole-owner review engine,
`plugins/leadv2/scripts/leadv2-review-run.sh`, over **Bash**, **unconditionally** — this
does NOT depend on `LEADV2_WORKFLOW_ENABLED` (that flag remains plan-phase-only; see
SKILL.md) and does NOT depend on `LEADV2_REVIEW_ENGINE` either (that flag only gates
whether the product-close *lane* calls the engine internally — the interactive path
below always calls the engine script directly, because it exists on disk regardless of
the flag's value).

```
bash plugins/leadv2/scripts/leadv2-review-run.sh \
  --task "<sig8>" --root "$(pwd)" \
  --handoff "docs/handoff/<id>" \
  --diff "docs/handoff/<id>/review.diff" \
  --author "<arm>" [--fanout 3]
```

The engine resolves an ordered, quota-filtered, author-excluding reviewer pool
(`resolve_review_pool_call`, lifted from the product-close lane), fans out to the first
`--fanout` (default 3, `LEADV2_REVIEW_FANOUT`) distinct `:ok:` arms in parallel, runs an
always-on cheap hack-detect pass alongside them (not counted toward the fan-out), and
verifies every Critical/High finding on an arm distinct from the one that raised it. It
writes `docs/handoff/<id>/review-gate.md` (status/reason contract unchanged, plus two new
additive lines: `arms: <csv>` and `verified: <n>/<m>`) and
`docs/handoff/<id>/review-findings.json` via `.tmp` + `mv` (atomic).

Exit codes: `0` reviewed/pass, `6` blocked (provider_error / review_body_lost /
empty_response / no_verdict_marker), `7` reviewed/FAIL, `9` unreviewed
(all_arms_unavailable). Read `review-gate.md`'s `status:` line, then proceed to §3
(SKILL.md) using the structured findings in `review-findings.json`.

**Former Workflow path (deleted):** `workflows/leadv2-review.js` and its shared copy at
`~/.claude/workflows/leadv2-review.js` are gone (ONE-PATH-EVERYWHERE-01) — the lane never
called it (the workflow-bypass-guard hook was structurally blind to the Bash-invoked
product-close lane) and this skill now calls the engine directly instead of the
`Workflow(name: "leadv2-review", ...)` shape described here previously. If you still see
a reference to that Workflow anywhere, it is stale — file it, do not resurrect the `.js`.
