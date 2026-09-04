```yaml
verdict: APPROVE
next_action: continue
```

Design for the three GLM-ladder visibility levers, scoped to 5 files, no env vars, no routing change.

- Park write goes in the `7)` refusal branch before fall-through; exception bump reads `attempted[]`, not `LAST_ARM_OUTCOME` (overwritten by then).
- D0: rejects `repo_facts` as the surface — repo-override-owned, and reaches the founder only via the Haiku writer, which was down this very beat. Renders through deterministic `queue_md` instead.
- Risks: unbounded park file, counter clobber, fd-9 inheritance near spawn, `--retry-all` double-dispatch.

Full: architect.full.md
