verdict: APPROVE
next_action: continue

Insert one validated `GITGLOBAL` flag fragment after `git` in all 5 git deny rules (4 canonical + worktree prune); 35 probe cases pass, zero false positives.

- Census: only those 5 rules have the gap; non-git rules clean. No shared helper exists → fragment-drift test substitutes.
- Mismatch: mission's `echo "git reset --hard"` allow-case would open a new hole — pinned as BLOCK instead.
- Yaml is same-inode as plugin root, no cache copy → edit is live immediately.

Full: architect.full.md
