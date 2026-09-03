# ANTI-SILENCE-STATUSLINE-01 — round 8: the perf round changed behaviour and both suites hid it

LANE ROOT: `/Users/kostiantyn.vlasenko/Projects/leadv2/.claude/worktrees/ANTI-SILENCE-STATUSLINE-01`

LANE_WRITES: plugins/leadv2/scripts/leadv2-lane-status-line-tail.sh,plugins/leadv2/scripts/leadv2-lane-status-line.sh,plugins/leadv2/scripts/tests/test-statusline-readable.sh,docs/handoff/ANTI-SILENCE-STATUSLINE-01/

Full review: `docs/handoff/ANTI-SILENCE-STATUSLINE-01/review-r7.md`. HEAD is `0a18afc`.

**Round 7's two control fixes are real and the reviewer reproduced both himself — keep them.** F5
no longer mutates a scratch copy: it drives `_surf_clip_plain` in the production file, and a raw
slice mutation at `leadv2-lane-status-line.sh:227-244` goes RED (44/1) and back GREEN (45/0) with
a clean `git diff --stat`. The locale control now asserts `один·?·1s` / `+5` / `visible_len<=60`
— strings the renderer genuinely emits — and removing `export LC_ALL` from both scripts turns it
RED. The `round7-red/*.log` artifacts are honest RED→GREEN pairs and, unlike round 5, are actually
committed. Both suites are 45/0 and 90/0. None of that is in question.

**The F9 speedup is also real and bigger than claimed**: 105.6 ms/render at `75b6a04` → 54.7
ms/render at `0a18afc`, ~48%. It can stand — once it stops changing the output.

## [Critical] `read` cannot split a multi-line here-string, and the fallback render is corrupted

`leadv2-lane-status-line-tail.sh:47`:

```bash
IFS=$'\n' read -r CWD_FROM_INPUT MODEL REMAINING TRANSCRIPT_PATH <<< "$PARSED"
```

`read`'s line terminator is a literal newline **regardless of `IFS`**. With a multi-line
here-string this fills only the first variable; `MODEL`, `REMAINING` and `TRANSCRIPT_PATH` are
always empty. Reproduced bare:

```
$ P=$'a\nb\nc'; IFS=$'\n' read -r X Y Z <<< "$P"; echo "X=[$X] Y=[$Y] Z=[$Z]"
X=[a] Y=[] Z=[]
```

Downstream at `tail.sh:57`, `${MODEL:-?}` fires on the empty string, so **every fallback render
shows model `?`**, remaining-pct is always dropped, and `OWN_SESSION_ID` — derived from
`TRANSCRIPT_PATH` — is always empty, which changes lane-ownership accounting (`+1` became `+3`
dropped lanes in the reviewer's repro) and produced a corrupted multibyte byte in the lane token.
Confirmed with both empty and realistic `transcript_path`, so it is not a harness artifact. This
regression came in with `0a18afc` alone; `370d47c` is clean.

Fix it with `mapfile -t`, four separate `read` calls, or by reverting to the sed/printf split —
whichever keeps the speed. Then re-run the byte-identity check: render at `75b6a04` and at your
new HEAD on identical input and diff the two outputs byte for byte. `F9-before-after*.log` records
only timing; identity was never checked, which is why the commit message's "pure perf, no
behaviour change" was false.

## [Critical] both suites were 45/0 and 90/0 while this was broken — close that hole

Every fixture in `test-statusline-readable.sh` wraps a `statusLine.command` (`printf '<literal>'`)
that always succeeds, so the passthrough path never falls through to `FALLBACK_BASE` and
`MODEL` / `REMAINING` / `TRANSCRIPT_PATH` are never asserted at all. FIX5c explicitly requires a
configured-but-failing or timed-out user command to land on that path — the path the product
actually degrades into, and the one with no test.

Add a test that forces `FALLBACK_BASE`: no configured `statusLine.command`, and separately one
that fails and one that times out. Assert the rendered model name, the remaining-pct, and the
own-session lane accounting. Mutation-prove it by restoring the broken `read` line and showing
that test RED by name.

## [Low] `LC_ALL` is still hard-exported

Carried from round 6, non-blocking: both scripts `export LC_ALL=en_US.UTF-8` unconditionally and
will emit `setlocale` warnings on a host without that locale generated. Probe `locale -a`, or
measure width locale-independently. Fix it or say in `report.md` that it stays and why.

## Rules

- Every fix keeps a control you RUN: mutation INSIDE the production function body, RED, revert,
  GREEN, clean `git diff --stat`. A zero-match anchor is a hard failure, not a skip.
- No `grep` against script source as an assertion; no negated command as an assertion (`set -e`
  never trips on it); no scratch-copy mutation; no `git show HEAD:` pre-image.
- Bash 3.2.57 is the floor — `mapfile` does NOT exist there. If you use it, gate it and provide a
  3.2 path, and say which you chose in `report.md`.
- Every `${arr[@]}` guarded under `set -u`.
- Commit round-8 artifacts beside the round-7 ones with `git add -f <file>`; do not edit
  `.gitignore`.
- `git add <file> <file>`, never `git add <dir>`. Commit before you stop.

## Done means

The fallback render byte-identical to `75b6a04` on identical input with the timing gain kept, a
test that exercises the fallback path and dies when the broken `read` is restored, and both suites
green with counts pasted.
