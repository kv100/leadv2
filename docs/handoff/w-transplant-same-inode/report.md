# w-transplant-same-inode — the transplant can never succeed: both slots look into one tree

## Defect (structural, measured live 2026-09-10)

`~/.claude-work/projects` is a **symlink** to `~/.claude/projects` (created
2026-09-08T20:00, the SD-SYNC-TRANSCRIPT-RESIDUE root-merge).  The transplant
target is therefore always the source itself — measured on the real
transcript, both paths, `stat`:

```
16777232:567096999  ~/.claude/projects/-Users-...-m3-market/678952be-029b-486b-aa58-20f3b162000e.jsonl
16777232:567096999  ~/.claude-work/projects/-Users-...-m3-market/678952be-029b-486b-aa58-20f3b162000e.jsonl
lrwxr-xr-x  ~/.claude-work/projects -> /Users/kostiantyn.vlasenko/.claude/projects
```

Guard 5 refused on bare `-e $DEST`, so the happy path was unreachable on this
machine in principle.  The founder's live full run (2026-09-10T16:22Z, real
m3-market transcript, expanded plugin path) — the switch itself took, then:

```
account-switch: OK switched from=personal to=work (score=46 binding=seven_day:46)
account-switch: observed_next_pick=work observed_score=46 -- the NEXT selection runs on the new account
account-switch: staying_children=2 pids=87767,88460 -- running sessions keep the old account until they exit
interactive-switch: FAILED reason=transplant_target_exists -- .../678952be-....jsonl already exists;
never overwriting a session in the target slot
```

## Fix

`leadv2-interactive-session-switch.sh`, guard 5 only.  When `$DEST` exists,
its inode identity (`stat` `dev:ino` — never path equality: the paths differ;
never content: hashing 70 MB to learn a file is itself) is compared with the
transcript's:

- **same inode** → the transplant is satisfied by construction: said aloud
  (`OK transplant already in place: ...`), journaled with its OWN word
  `transplant_same_inode` (never a silent skip, never a false `transplanted=`
  copy claim), and the resume command is emitted — rc=0.
- **a different file** → the loud `transplant_target_exists` refusal stands,
  unchanged, and the target slot's own session is never overwritten.

Copy path byte-identical to before (say/journal formats, fixtures untouched).
The symlink itself was NOT touched — machine state, out of this lane's scope.

## Live full run, before and after

Before: the 16:22Z capture above (rc=5 at guard 5).

After (fixed bytes, 2026-09-10T16:40Z): a full-command run against the REAL
transcript, REAL config dirs (`~/.claude`, `~/.claude-work`) and the REAL
symlink, deciding from the REAL banner string.  Only the account inputs are
pinned (fixture registry rows pointing at the two real dirs, stubbed
credential reader + probe, cooldown marker in a tmp cache): the live selector
is mid-cooldown from the 16:22Z switch (`selector_reason=single_profile`, see
w-resume-cwd), so an unpinned re-run refuses at the switch stage on account
state, not on the transplant — the same honesty note the prior step's report
carries.  Everything downstream of the account decision is the real machine:

```
interactive-switch: detector: verdict=limit source=screen label=a pct=- attempt=1/300
account-switch: OK switched from=a to=b (score=30 binding=five_hour:30)
account-switch: observed_next_pick=b observed_score=30 -- the NEXT selection runs on the new account
account-switch: staying_children=0 -- running sessions keep the old account until they exit; new spawns use b
interactive-switch: OK transplant already in place: /Users/kostiantyn.vlasenko/.claude-work/projects/-Users-kostiantyn-vlasenko-MythicalGames-m3-market/678952be-029b-486b-aa58-20f3b162000e.jsonl is the transcript itself (both slots share one projects tree)
interactive-switch: OK switched from=a to=b; transplant already satisfied, same inode (sha256 11194790af42)
interactive-switch: exit the stuck session, then continue it on the free account with:
interactive-switch: resume: cd "/Users/kostiantyn.vlasenko/MythicalGames/m3-market" && CLAUDE_CONFIG_DIR="/Users/kostiantyn.vlasenko/.claude-work" claude --resume 678952be-029b-486b-aa58-20f3b162000e
rc=0
```

Journal (one decision line, own word, real cwd — the transcript itself is
untouched, no copy happened):

```
2026-09-10T16:40:00Z [interactive-switch] switched from=a to=b transplant_same_inode dest=/Users/kostiantyn.vlasenko/.claude-work/projects/-Users-kostiantyn-vlasenko-MythicalGames-m3-market/678952be-029b-486b-aa58-20f3b162000e.jsonl sha12=11194790af42 session=678952be-029b-486b-aa58-20f3b162000e target_dir=/Users/kostiantyn.vlasenko/.claude-work cwd=/Users/kostiantyn.vlasenko/MythicalGames/m3-market
```

Side note from the brief, now standing on the fix: `claude --resume
678952be-…` with `CLAUDE_CONFIG_DIR=~/.claude-work` finds the transcript
precisely because the tree is shared — the same fact the guard now recognizes.

## Mutation matrix (mutation → what reddened)

Suite `tests/test-interactive-session-switch.sh`: new case 9 (same inode →
rc=0, said aloud, resume emitted, own journal word, no false `transplanted=`
claim) and case 10 (a DIFFERENT file in the target slot → loud
`transplant_target_exists`, that file untouched).  Both mutation runs backed
by leadv2-mutation-control.sh artifacts (worker mode, scratch copy,
`lane_diff_hash=516b1a64…`, bound to the final commit bb42ec18):

| mutation | reddened | stayed green | raw |
|---|---|---|---|
| M9: same-inode condition → `if false` (recognition disabled — the shipped defect replayed) | case 9 (5 checks) | cases 1–8, 10 — PASS=55 FAIL=5 | `mutation-control/20260910T163832Z-50222.txt` |
| M10: same-inode condition → `if true` (refusal disabled — over-trusting) | case 10 (3 checks) | cases 1–9 — PASS=57 FAIL=3 | `mutation-control/20260910T163912Z-59564.txt` |

Raw FAIL lines:

```
M9 (if false):
[TEST] FAIL: case9 rc=0 (transplant satisfied by the shared tree) -- rc=5 want=0
[TEST] FAIL: case9 SAYS the transplant is already in place (never silently skipped) -- no match for 'OK transplant already in place' in: interactive-switch: detector: verdict=limit source=screen label=a pct=- attempt=1/300
[TEST] FAIL: case9 emits the exact resume command pinned to slot b -- no fixed match for 'resume: cd "/tmp/proj" && CLAUDE_CONFIG_DIR=".../slot-b" claude --resume 11111111-2222-3333-4444-555555555555' in: interactive-switch: detector: verdict=limit source=screen label=a pct=- attempt=1/300
[TEST] FAIL: case9 journal carries its OWN word for the already-done transplant -- no match for 'switched from=a to=b transplant_same_inode dest=' in: 2026-09-10T16:39:26Z [limit-detect] verdict=limit source=screen label=a pct=- attempt=1/300
[TEST] FAIL: case9 journal still names the session + target dir -- no match for 'switched from=a to=b transplant_same_inode.*session=' in: 2026-09-10T16:39:26Z [limit-detect] verdict=limit source=screen label=a pct=- attempt=1/300
[TEST] summary: PASS=55 FAIL=5
M10 (if true):
[TEST] FAIL: case10 rc=5 (failed, loud) -- rc=0 want=5
[TEST] FAIL: case10 keeps the loud transplant_target_exists refusal -- no match for 'FAILED reason=transplant_target_exists' in: interactive-switch: detector: verdict=limit source=screen label=a pct=- attempt=1/300
[TEST] FAIL: case10 journal names the target-exists guard + dest -- no match for 'FAILED reason=transplant_target_exists dest=' in: 2026-09-10T16:39:41Z [limit-detect] verdict=limit source=screen label=a pct=- attempt=1/300
[TEST] summary: PASS=57 FAIL=3
```

Note M9's red output is the 16:22Z live failure replayed verbatim: the
existing file is met with `transplant_target_exists` — the exact behaviour
the founder saw live.

## A defect my own first cut shipped, caught by verification

The first version of this fix left the old unconditional trailing
`journal "... transplanted=$DEST ..."` line in place after the branch — the
same-inode path then journaled BOTH `transplant_same_inode` and a false
`transplanted=` copy claim (and the copy path journaled its decision twice).
The live-shape run surfaced it; two suite assertions now pin it (case 1:
exactly ONE `switched` line; case 9: no `transplanted=` claim) and the stray
line is gone before anything was merged.

## Falsification set (raw)

```
$ bash -n plugins/leadv2/scripts/leadv2-interactive-session-switch.sh \
  && bash -n plugins/leadv2/scripts/tests/test-interactive-session-switch.sh
SYNTAX-OK

$ bash plugins/leadv2/scripts/tests/test-interactive-session-switch.sh | tail -1
[TEST] summary: PASS=60 FAIL=0          (prior 48 + 12 new; prior 48 unchanged)

$ bash tests/run-all.sh --scope changed | tail -1
run-all: 5 passed, 0 failed, scope=changed   (rc=0)
```

Post-mutation restores verified clean: the mutation-control tool's scratch
copies never touch the lane checkout; `git status --porcelain` clean after
every run, suite 60/0 on the committed bytes.
