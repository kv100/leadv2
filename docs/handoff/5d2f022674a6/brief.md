# ROUTE-ARBITER-DIES-SILENTLY-ON-LINUX-01

Wave B0. Files: the route-arbiter lib under `plugins/leadv2/lib/`
(locate it first: `grep -rn route_arbiter plugins/leadv2/lib`).

## Defect (measured 2026-09-03)
`route_arbiter` returns exit code 2 with **ZERO bytes on stdout AND stderr** on
Linux, while the identical call on macOS returns 0 with a full route line.
Reproduced in a debian bookworm container with jq, python3, sqlite3, bc,
uuid-runtime and coreutils present, against the same fixture quota JSON.
Confirmed PRE-EXISTING: main and the CLASSIFIER-MUST-SEE-QUOTA-AND-RESET-DATE-01
lane both fail identically — no lane caused it.

Two consequences. Every arbiter-dependent suite is meaningless in CI, which runs
Linux (this pairs with CI-SUITES-ARE-MACOS-ONLY-01 and explains part of it). And
the failure is SILENT: a non-zero code with no diagnostic on either stream is
indistinguishable from a crash, a missing dependency, or a refusal — anyone
debugging it starts with no information at all.

## Deliver — IN THIS ORDER
1. **The diagnostic comes first and is worth shipping on its own.** Find where the
   exit 2 originates and make it print a named reason before returning. The silent
   non-zero is the thing that makes this expensive.
2. Then fix the platform difference itself.

## Probing rule (this was confused twice while measuring)
Capture the exit code on its OWN line, never after a pipe, and report stdout and
stderr byte counts separately — otherwise empty output and a masked exit code get
confused again. Probe bash libs under `bash -c`, never zsh.

## Negative control (declare it, and RUN it)
Mutation: silence the new diagnostic inside the failing branch.
Suite MUST go red. Paste to `docs/handoff/5d2f022674a6/round1-red.txt`.

## Done
- a Linux run of route_arbiter either succeeds or prints a named reason
- suite green clean / red mutated, both pasted, with byte counts per stream
