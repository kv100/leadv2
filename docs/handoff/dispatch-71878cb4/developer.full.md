verdict: APPROVE
next_action: review_round_2

# CODEX-CONFIG-GROWS-FOREVER-01 follow-up — final red assertion

## Root cause

In `prune()`, the dedup loop computed `winner = real if real in paths else paths[0]`
where `real = os.path.realpath(path)` and `paths` are the *raw* strings from the file
(the alias spelling and the live spelling). This only picked the resolved path when
one of the raw spellings happened to be byte-identical to its own `realpath()` output.
On this host (and generally on macOS, where `TMPDIR` resolves through `/tmp ->
/private/tmp` and often `/var -> /private/var`), neither raw spelling equals its
resolved form, so the fallback `paths[0]` (an arbitrary, first-seen alias) survived
under its own spelling instead of the physical path. The table content collapsed
correctly (dedup worked), but the surviving key was wrong — which is exactly the
requirement the test encodes: `str(live.resolve()) in tomllib.loads(cfg.read_text())['projects']`.

## Fix

`plugins/leadv2/scripts/leadv2-codex-config-prune.sh`:

1. Added `rewrite_header(lines, real)` — replaces only the header line's quoted key
   with `json.dumps(real)`, preserving any inline comment or trailing newline on that
   line and every other line in the table untouched (uses the existing `scan_line`
   comment-detection so it never corrupts an inline comment).
2. In `prune()`, track whether a `real` group actually had a duplicate collapse into
   the winner (`collapsed` flag, distinct from a policy `conflict`). Only when
   `collapsed and winner != real` is the winner added to a `renames` map.
3. Output construction now checks `renames` first (rewrite header via
   `rewrite_header`), then falls back to the pre-existing `removed`/unchanged paths.

This keeps the "conflicting live policies untouched" assertion byte-identical: a bare
policy conflict (no duplicate collapse) never touches `renames`, so the config is
untouched, matching the test's `cfg.read_bytes() == before` check.

## Diff

```
diff --git a/plugins/leadv2/scripts/leadv2-codex-config-prune.sh b/plugins/leadv2/scripts/leadv2-codex-config-prune.sh
@@ comments_only(...) @@
+def rewrite_header(lines, real):
+    """Re-key a surviving [projects."..."] table's header to its resolved path.
+
+    Only the header line's quoted key changes; any inline comment or trailing
+    newline on that line, and every other line in the table, is untouched.
+    """
+    header = lines[0]
+    quote, comment, _ = scan_line(header, None)
+    suffix = header[comment:] if comment is not None else ('\n' if header.endswith('\n') else '')
+    new_header = '[projects.' + json.dumps(real, ensure_ascii=False) + ']' + suffix
+    return ''.join([new_header] + lines[1:])
@@ prune() @@
     removed = set()
+    renames = {}
     live = {}
     ...
     for real, paths in live.items():
         winner = real if real in paths else paths[0]
+        collapsed = False
         for path in paths:
             if path != winner:
                 if projects[path] == projects[winner]:
                     removed.add(path)
                     duplicates += 1
+                    collapsed = True
                 else:
                     conflicts += 1
+        if collapsed and winner != real:
+            renames[winner] = real
-    output = ''.join(comments_only(p['lines'])
+    output = ''.join(rewrite_header(p['lines'], renames[p['keys'][1]])
+                     if len(p['keys']) == 2 and p['keys'][0] == 'projects'
+                     and p['keys'][1] in renames
+                     else comments_only(p['lines'])
                      if len(p['keys']) >= 2 and p['keys'][0] == 'projects'
                      and p['keys'][1] in removed else ''.join(p['lines'])
                      for p in parts)
```

## Test output — full suite (before restoring, no negative control)

```
PASS: dry-run does not write
PASS: dead-path surviving table count
PASS: reported count matches observed drop
PASS: backup preserves original bytes and permissions
PASS: live bytes and all comments retained
PASS: second prune is a byte-identical no-op
PASS: identical live aliases collapse to physical entry
PASS: conflicting live policies untouched
PASS: first write registers one canonical path
PASS: second-write table count
PASS: writer leaves existing alias policy untouched
PASS: concurrent writers produce one table
PASS: writer escapes TOML path keys
PASS: multiline strings and nested tables
PASS: invalid input fails without changing config
PASS: unsupported inline layout fails without changing config
test-codex-config-prune: 16 passed, 0 failed
```

## Negative control (E2E-KILLRATE-01)

Inside `prune()`'s body, replaced `real = os.path.realpath(path)` with
`real = path  # NEGATIVE CONTROL: skip realpath resolution` (a one-line change inside
the loop body, never at top level). Re-ran the suite:

```
PASS: dry-run does not write
PASS: dead-path surviving table count
PASS: reported count matches observed drop
PASS: backup preserves original bytes and permissions
PASS: live bytes and all comments retained
PASS: second prune is a byte-identical no-op
FAIL: identical live aliases collapse to physical entry
FAIL: conflicting live policies untouched
PASS: first write registers one canonical path
PASS: second-write table count
PASS: writer leaves existing alias policy untouched
PASS: concurrent writers produce one table
PASS: writer escapes TOML path keys
PASS: multiline strings and nested tables
PASS: invalid input fails without changing config
PASS: unsupported inline layout fails without changing config
test-codex-config-prune: 14 passed, 2 failed
```

`count() == 1` — the value that has never varied — went red on the targeted assertion
(the fault means `alias` and `live` never map to the same `real` key any more, so
neither collapses nor conflicts fire correctly). Reverted the one-line fault via
`cp` of the pre-fault backup; re-ran the suite and confirmed 16 passed, 0 failed again
(shown above under "Test output — full suite").

## Falsification (bash -n / py_compile / changed-scope suite)

```
$ bash -n plugins/leadv2/scripts/leadv2-codex-config-prune.sh
bash -n OK
$ python3 -m py_compile <extracted embedded python heredoc>
py_compile OK
```

Changed-scope run (`plugins/leadv2/scripts/tests/run-core-offline.sh --scope changed`):
0 failed across all shards (38 passed(red->green) in one shard, 4 in
test-lane-root-not-a-worktree, 9 in test-lane-worktree-registry-pointer, exit code 0).
`test-codex-config-prune.sh` itself run directly (see above): 16 passed, 0 failed.

## Constraints honored

- Touched only `plugins/leadv2/scripts/leadv2-codex-config-prune.sh` (did not need to
  touch `leadv2-lane-worktree.sh` — its `codex_trust_worktree`/`trust()` path already
  resolves `realpath` independently and was unaffected by this bug).
- Staged explicitly (`git add <path>`), verified `git diff --cached --stat` before
  committing without a pathspec.
- No `reset --hard`, `clean`, `stash`, `worktree prune`, no push.
- No context.yaml existed for this task at the handoff path; mission text and repo
  state were the sole source of truth (verified: no `docs/handoff/dispatch-71878cb4/context.yaml`
  file present at start).

## Left alone

Nothing else in the file was touched. No new tests added — the existing suite already
encoded the requirement; only the implementation needed to change.

DELIVERABLE_COMPLETE
