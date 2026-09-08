verdict: BLOCK
next_action: review_round_2
REVIEW_VERDICT: FAIL
REVIEW_FINDINGS: critical=1 high=0 medium=4 low=4

review.diff is not the lane's change: it fails `git apply --check` at a138edd0, every hunk is already in main, and it collapses tiers onto astra while the mission un-collapses them.
- Lane branch/worktree absent; 17/17 suite UNVERIFIED.
- Regenerate diff from lane head.
Full: full.md
