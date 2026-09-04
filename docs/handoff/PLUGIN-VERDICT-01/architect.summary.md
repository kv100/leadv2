verdict: REVISE
next_action: escalate_to_founder

Do not rewrite in Python. 496 fix commits/90d split: architecture 71%, surface 12%, bash 9%, process 8%.

- In-repo control (`scripts/lib/`): Python 9.59 vs bash 10.09 fixes/KLOC — language effect is noise. Rewrite = 20-27 wk for 9%.
- Delete: 3 stale cache trees (512,422 LOC) + 53 real copies in leadv2-shared, 4 already drifted.
- Highest yield/day: collapse install to one inode (11.7% for 1 day). Then one SQLite state owner (43.4%).

Full: architect.full.md
