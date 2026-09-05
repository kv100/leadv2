# The fork is NOT drifted — measured by the lead, 2026-09-02

```
git show main:plugins/leadv2/hooks/leadv2-pulse-json.sh > /tmp/canon-pulse.sh
diff -u /tmp/canon-pulse.sh ~/Projects/persona-engine/.claude/hooks/leadv2-pulse-json.sh
→ 0 lines of difference
```

The persona-engine copy is **byte-identical to canonical `main`**. Five weeks old by mtime, but
never edited. So:

- **There is no fork-only fix to carry up.** Item 1 of the round brief ("port anything canonical
  lacks") is answered: nothing to port. Do not spend a round re-deriving this — the command above is
  the whole proof, re-runnable.
- **The danger was never drift; it was wiring.** Canonical wires `pulse-json.sh` to nothing. The
  copy is wired at `persona-engine/.claude/settings.json:336` to
  `Bash|Edit|Write|MultiEdit|NotebookEdit|Agent|Workflow|Skill`. An identical file, active in one
  repo and inert in every other, is worse than a drifted one: it looks harmless in review and it
  behaves differently in production.
- **What remains is mechanical:** remove the copy and its wiring (or symlink it to canonical and let
  the canonical manifest decide), check nothing reads the `pulse.json` it produces before removing
  the writer, and add the guard that fails while any real copy of a plugin-owned hook exists under a
  consumer repo's `.claude/hooks/`.

Note for whoever writes the guard: identity is not safety. The check must be "is it a symlink",
never "does it match canonical" — this copy would have passed a content check on every one of its
five weeks.
