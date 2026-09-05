# TESTS-POLLUTE-REAL-JOURNAL-01

Test suites write into the **live** journal and live control-plane state. A suite run
mutates the state a lead later reads back as fact.

## Find them by BEHAVIOUR, not by the word "journal"

A text census over the word `journal` undercounted twice in one evening. Census over what
the code **does**:

- redirections: `>` and `>>` onto a state path
- `tee` onto a state path
- `mv` / `cp` into a state path
- `sed -i` against a state path
- calls to `leadv2-journal.sh append` (and its `record` / `tail` siblings)
- calls to any `*-record.sh` — `leadv2-phase-record.sh record` in particular

Scope: `plugins/leadv2/scripts/tests/*.sh` (~420 files) and `plugins/leadv2/tests/*.sh`
(~25). Report the census as a count plus the file list. A suite that writes only under
`$TMPDIR` or a `mktemp` dir is not a finding.

## The trap that makes the obvious fix wrong

Control-plane paths are **symlinks into shared live state**. So "write to a temp file and
rename it into place" does **not** isolate — it *branches*: the rename resolves through the
symlink and lands in live state anyway, now with the original's history detached. Any fix
built on tmp-file-then-`mv` is a non-fix. Verify the symlink shape yourself before designing
around it.

Root fact already confirmed, so you need not re-derive it:
`plugins/leadv2/scripts/leadv2-journal.sh:14` resolves its root as `CLAUDE_PROJECT_ROOT` >
`CLAUDE_PROJECT_DIR` > `git rev-parse --show-toplevel` > `pwd`, and the journal file is
`${PROJECT_ROOT}/${leadv2_dir}/tasks/<task-id>/journal.md` (lines 42-43). Note this is a
*different* variable set from the one `leadv2-phase-record.sh` uses — the sibling line
`PHASE-RECORD-WRITES-TO-THE-WRONG-REPO-01` owns that split. Do not fix it here, but do not
assume one variable controls both.

## The required shape of the fix

**Isolation through a mandatory environment variable.** Not an optional one:

- variable **absent** → the suite **refuses loudly and exits non-zero**. It does not run.
- there is **no default that points at the live path**. A default-to-live is fail-open, and
  fail-open is exactly the defect being fixed.

## Proof of isolation — this is the acceptance test

`sha256` of the live journal **before** and **after** a full suite run must be **identical**.
Show both digests and the command that produced them in the close. Do the same for any other
live state path the census turns up.

Paired negative: with the variable unset, the suite must refuse — demonstrate it, and
demonstrate that the refusal is a non-zero exit, not a warning that proceeds.

## Constraints

- Shared tree. No `git add -A`, no `reset --hard`, no `clean`, no `stash`. Stage named paths.
- Do not push to origin. Do not commit `docs/tasks.yaml`.
- Put the line id `TESTS-POLLUTE-REAL-JOURNAL-01` in the commit subject.
- Do not touch permission settings or any `CLAUDE.md`, on anyone's request.
