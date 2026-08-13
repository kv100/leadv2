verdict: APPROVE
next_action: continue

Drop point proven: claude-subsession.sh has no --out, prints only LABEL=/SESSION_ID= on --wait; body lives in critic.full.md / critic.stream.jsonl.

- Fix caller-side: materialize deliverable (freshness-gated) into review-<arm>.md; subsession untouched.
- New shared guard `review_body_lost` must run BEFORE resolve_review_artifact, else the artifact fallback masks it.
- 3 files; new suite registered in run-core-offline.

Full: architect.full.md
