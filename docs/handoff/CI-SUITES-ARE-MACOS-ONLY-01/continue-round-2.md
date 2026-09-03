# CI-SUITES-ARE-MACOS-ONLY-01 — round 2 (continue an unfinished round 1)

Round 1 died at the turn cap with its work UNCOMMITTED in this lane. Nothing is lost:
10 files are modified and `plugins/leadv2/scripts/lib/mktemp-guard.sh` is new and untracked.
Read the working tree first (`git status --porcelain`, then `git diff`). Do not start over.

## The defect

CI run 33694115147 was red on Linux, not from a regression: suites use the BSD form
`mktemp -d -t <prefix>` with no `XXX` in the template. GNU mktemp treats that argument as
a template that must end in XXX, so the resulting path is wrong and the suite dies.

## What round 1 chose, and what you must reconsider

Round 1 injected a 13-line sourcing preamble into each test file:

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    GUARD_SCRIPT="$SCRIPT_DIR/../plugins/leadv2/scripts/lib/mktemp-guard.sh"
    if [ ! -f "$GUARD_SCRIPT" ]; then GUARD_SCRIPT="$SCRIPT_DIR/../../lib/mktemp-guard.sh"; fi
    ...
    mktemp_guard

That is heavy and fragile: a two-branch relative-path guess that breaks the moment a suite
moves directory, and it hard-exits a test when the library is missing. Prefer the minimal
change — fix each offending call site, add NO preamble:

    -  D="$(mktemp -d -t leadv2-foo)"
    +  D="$(mktemp -d "${TMPDIR:-/tmp}/leadv2-foo.XXXXXX")"

Keep `mktemp-guard.sh` ONLY if it earns its place as a LINT (a suite that greps the tree for
the bad form and fails), never as a runtime dependency of every test.

## Definition of done

1. `grep -rnE 'mktemp (-d )?-t [^ ]*$' plugins/leadv2/scripts/tests/ tests/` returns nothing
   outside comments. Call sites that already pass an explicit `.XXXXXX` template are portable
   on both platforms — do not churn them.
2. Every file you touched still passes: run each modified suite INDIVIDUALLY and paste its
   exit code. Do NOT run the whole 83-suite `run-core-offline.sh` — the lead holds the machine
   and a parallel run has already killed one worker on the core-offline lock today.
3. A negative control: name the mutation you apply (restore one bad `mktemp -d -t` call site),
   show the lint/suite goes red, then revert it and show it goes green.
4. COMMIT your work in this lane before you finish. Round 1 left everything uncommitted and
   that cost a whole round.

Off limits: do not touch `main`, do not run the full suite runner, do not reformat anything
beyond the mktemp call sites and any lint you add.
