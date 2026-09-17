# The probe is not just "slower than the budget" — it is slower than the same command

Measured 2026-09-17, leadv2 main, macOS. **This corrects the framing the row was filed with.**

## The two numbers

Acceptance command for row `d353f0bee7ca`:

```
cd /Users/kostiantyn.vlasenko/Projects/leadv2 && bash plugins/leadv2/scripts/tests/test-review-arm-no-verdict.sh
```

| context | result |
|---|---|
| run standalone by the lead, board live (349 dispatch dirs) | `rc=0`, **45s**, 15 passed / 0 failed |
| run as the premise probe by `leadv2-dispatch-code.sh` | killed at **900s**, `verdict=unknown reason=probe_budget_exceeded` |

Same command. Same tree. Same machine. Same hour. **20× apart, at minimum** — 900s is a floor, not
the runtime, because the probe was killed rather than finishing.

## What this falsifies

The row was filed saying the 120s default "is straddling this repo's suite runtimes". For this
suite that is **false**: 45s is comfortably inside 120s. Raising the budget would not have fixed
this dispatch; it was raised to 900s and the probe still died.

So the defect is not (only) a mis-set constant. Something about executing the command *inside the
probe* changes its cost by more than an order of magnitude.

## What is NOT yet known — do not skip this section

The mechanism is **unidentified**. Candidates considered and their status:

- **Inherited `LEADV2_*` stub vars defeat the suite's fakes** — *excluded*. The suite assigns
  `LEADV2_DISPATCH_GLM_BIN` / `LEADV2_DISPATCH_ARCHITECT_BIN` / `LEADV2_GLM_POLICY_RESOLVER` as
  per-invocation command prefixes (`:146`, `:160`, `:186`, `:206`, `:235`), so an inherited value
  cannot win over them.
- **Lock contention / deadlock** — *not excluded, and the leading candidate*. The suite's
  `run_close` helper invokes the product-close path, and the probe runs at
  `leadv2-dispatch-code.sh:8542` from inside the dispatcher, which may already hold a lock that
  path wants. A wait on a held lock looks exactly like this: fine standalone, forever inside.
- **`_pp_root` cwd** — *not excluded*, though the acceptance command begins with its own absolute
  `cd`, which should neutralise it.
- **Other inherited environment** — *not excluded*.

Anyone picking this up: the decisive experiment is to make the probe's captured stdout survive.
Right now it cannot — the probe writes to a `mktemp` file and every refusal branch `rm -f`s it, so
the one artifact that would name the mechanism is deleted at the moment it becomes interesting.
That deletion is itself worth fixing first; it is cheap and it unblocks everything else here.

## A second suite, and it is NOT the same shape

`tests/test-status-surface-bash32.sh` (acceptance for row `53e7c176f3f6`) also blew through 900s in
the probe — but that suite is **genuinely slow standalone too**, still running past several minutes
in a direct measurement. Do not merge the two cases: one is a fast suite that hangs only inside the
probe, the other may simply be a slow suite. They probably have different causes.
