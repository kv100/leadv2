# m3-market is a CONTROL DIRECTORY, not a repo (M3-MARKET-IS-NOT-A-GIT-REPO-01)

Founder decision 2026-09-13, verbatim "подтверждаю" — this is the single doctrine
paragraph every other surface points at. Do not restate it; link here.

`~/MythicalGames/m3-market` is a leadv2 **control directory** (`.claude/leadv2-overrides`,
`CLAUDE.md`, leadv2 tasks/state) — **not a git repository and it must never become one**
(do NOT `git init` it). Three paths exist and they are not interchangeable:

| path | what it is |
|---|---|
| `~/MythicalGames/m3-market/m3` | the m3 **code repo** — its own `.git` |
| `~/MythicalGames/m3` | a second, separate clone of the same project — an edit in one is invisible to the other |
| `~/MythicalGames/m3-market` | the leadv2 **control directory** — no version control at all |

Why the distinction is enforced (it already cost two wrong answers): `git -C
~/MythicalGames/m3-market log | wc -l` returns a confident `0` — the fatal goes to stderr,
the pipe counts empty stdout — and that reads as "m3 is dormant". Any component about to
run a git query against a resolved project root calls `leadv2_control_dir_git_guard`
(`scripts/leadv2-helpers.sh`) first; the dispatcher refuses at root resolution
(`scripts/leadv2-dispatch-code.sh`, M3-MARKET-IS-NOT-A-GIT-REPO-01 block). The suite
`scripts/tests/test-m3-market-is-not-a-repo.sh` fails if a live surface calls m3-market
a repo again, or if `~/MythicalGames/m3-market/.git` ever appears.

**There is no undo there, and this decision keeps it that way.** Because the tree stays
unversioned, any edit or deletion under `~/MythicalGames/m3-market` requires a backup
tarball committed to this leadv2 repo FIRST. Worked example: the 2026-09-12 retirement of
ten skills from that directory was safe only because the tarball was force-added to
leadv2 at commit `e4cece06` before anything was removed.
