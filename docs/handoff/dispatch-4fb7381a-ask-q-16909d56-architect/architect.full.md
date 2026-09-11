# architect — decision for dispatch-4fb7381a

## Question
Two out-of-repo `leadv2-review.js` copies (`~/.claude/workflows/leadv2-review.js` and the
plugin-cache copy) cannot be deleted from this session — the sandbox refuses edits to
sensitive files outside the worktree. The canonical in-repo copy is already deleted, and all
three were confirmed byte-identical by md5 before deletion.

## Decision

DECISION_OPTION: a
RATIONALE: byte-identical copies mean zero behavioural delta today, so blocking a merged lane on a sandbox-refused `rm` buys nothing that a one-line founder follow-up does not.

## Analysis

### Why (a)

1. **No correctness delta exists right now.** md5 equality across all three copies was
   established before deletion. Whichever path the resolver actually loads, it loads the same
   bytes it loaded yesterday. There is no window in which the system behaves differently
   because the in-repo copy is gone and the out-of-repo ones are not.
2. **The blocked operation is not retryable in-session.** The sandbox refusal is a
   session-scoped capability boundary, not a transient error. Parking the task
   `human-needed` (option b) does not unblock it any faster than a follow-up note does —
   both terminate on the same founder action. Option b just holds the lane hostage while
   waiting.
3. **Lane hygiene.** A dispatch lane blocked on an action its own runtime provably cannot
   perform is a lane that will sit in `human-needed` until timeout and then need manual
   reconciliation anyway. Closing it with an explicit, written follow-up is the cheaper and
   more honest terminal state.

### Residual risk (must be carried in the follow-up, not dropped)

- **Drift, not breakage, is the exposure.** The copies are identical *today*. The moment
  anyone edits the canonical source, `~/.claude/workflows/leadv2-review.js` and the plugin
  cache become silently stale — exactly the 2026-07-29 failure mode named in the global
  shared-trees policy ("while a file is a copy it will drift, and it will drift silently").
- **The plugin cache is the known-hostile one.** `claude plugin update` no-ops for
  directory-source marketplaces when content changed but the version did not, so the cache
  copy can outlive its source indefinitely and still be what actually loads.
- Therefore the follow-up is not "delete two files when convenient". It is:
  delete both out-of-repo copies **before** the next edit to the review workflow lands, and
  prefer a symlink to canonical over a fresh copy if either path must continue to exist.

### Follow-up to hand to the founder (verbatim)

```
rm ~/.claude/workflows/leadv2-review.js
rm <plugin-cache>/leadv2-review.js     # path from `claude plugin` cache root
```
Blocked from the dispatch-4fb7381a session by sandbox sensitive-file policy. All three copies
were md5-identical at deletion time, so this is drift-prevention, not a live fix. Do it before
the next edit to the review workflow, or restore each as a symlink to canonical.

## Out of scope
- Locating the exact plugin-cache path (session could not read outside the worktree).
- Any change to the review workflow's content or resolution order.
- Re-attempting the deletion under a different permission mode.

DELIVERABLE_COMPLETE
