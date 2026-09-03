# ARM-CAPABILITY-FROM-OUTCOMES-01 — alternatives considered

Four framings were considered for "know what each model is actually good at". Three were rejected
for reasons that are worth recording, because each is the obvious next suggestion.

## A — published benchmarks as the routing signal (rejected)

Take SWE-bench / LiveCodeBench numbers per model and rank arms by them.

Rejected as the *routing* signal, kept only as a cold-start prior. Benchmarks measure other people's
tasks, they rot as models are silently re-pointed underneath a route name, and they say nothing
about the failure mode we actually pay for — a lane that dies without producing work, or one that
needs a second review round. They are still useful for a brand-new arm with no history, which is why
the brief allows a prior but forbids it as the ongoing signal.

## B — hand-tuned `tags` / `kinds` in the routing yaml (rejected — it is the status quo, and it failed)

Keep capability as config, just curate it better.

This is exactly what exists today, and it is what produced the defect: `glm-flash` carries
`tags: [cheap, mechanical]` yet took five of eight lanes including "compute the task class" and
"make the phase gate passable in every repo", because `sizes: [standard]` matches nearly everything
and `tags` did no work. A cell that is never checked against outcomes stays wrong forever. Curating
it harder does not change that property.

## C — a hand-kept exclusion list (rejected on standing founder rule)

Name the weak arms in a script branch and skip them for hard work.

Forbidden by the standing rule: quota, task shape and complexity decide routing; a hand-kept
exclusion list never does. It also cannot recover — an arm that improves, or a freepool route that
changes underneath us, stays condemned. This is the same disease as `util_freepool=100` meaning "no
telemetry" and silently removing the arm.

## D — aggregate our own lane outcomes (chosen)

Build the ledger from records we already write (`leadv2-lane-outcome.sh`, `leadv2-dispatch-ledger.sh`,
`model_select_telemetry`), keyed by `(arm, work_kind, complexity)`, and feed it back as a signal
alongside cost.

Chosen because the ground truth is already being produced and thrown away — `model_select_telemetry`'s
only consumer today is its own test. It measures our tasks, not someone else's; it degrades
gracefully (counts, not a score, until there is enough data); and it satisfies both guarantees the
brief requires — an arm with no history is not penalised, and an arm can recover because recent
outcomes are weighted over old ones.

The known risk, recorded rather than hidden: if very few usable historical records exist, this
starts as an empty ledger that accumulates from today. The brief requires that fact to be reported
in `report.md` rather than papered over with a confident score from four samples.
