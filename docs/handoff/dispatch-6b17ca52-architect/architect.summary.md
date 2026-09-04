```yaml
verdict: APPROVE
next_action: continue
```

Design closes the gate: compute DUE/OVERDUE in-gate, mix `id:status` into a three-part digest.

- Finding 5 is a no-op unless `leadv2-task-anchor.sh:59`'s `2>/dev/null` goes — analysed safe.
- Finding 3's `/tmp` marker is never created on this path; the test must create it or it passes vacuously.
- Residual: re-inject fires, body still won't name the overdue row (renderer is id-keyed, other repo).

Full: architect.full.md
