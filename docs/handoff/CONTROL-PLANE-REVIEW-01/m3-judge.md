# CONTROL-PLANE-REVIEW-01 / M3 — the judge: does its verdict gate anything

READ FIRST: `docs/handoff/CONTROL-PLANE-REVIEW-01/seed-facts.md`.

Repo: `leadv2`. **READ-ONLY review.** Your only write target is
`docs/handoff/CONTROL-PLANE-REVIEW-01/f3-judge.md`.

## Subject

`plugins/leadv2/scripts/leadv2-llm-judge.sh`,
`plugins/leadv2/scripts/leadv2-llm-judge-parse.sh`,
`plugins/leadv2/scripts/leadv2-llm-judge-haiku.sh`,
`plugins/leadv2/scripts/leadv2-task-judge.sh`,
`plugins/leadv2/scripts/leadv2-task-judge-prompt.tmpl`.

## The one question that matters

**Is the judge's verdict load-bearing, or advisory?** A gate that prints a
verdict nobody reads is theatre, and this repo has shipped that before: the
status pulse lived only inside a retired supervise loop, so it never fired for
the founder at all.

So, with `file:line` for each:

1. **Find every caller.** Who invokes the judge, in which phase, and what does
   the caller DO with a no-go — abort, retry, or log and continue? Trace the
   return value to its consumer. An unread exit code is the finding.

2. **The refusal path.** What happens when the judge itself fails — timeout,
   unparseable answer, provider 429? Is that a refusal with a named reason, or
   does it degrade into a pass? Our standing disease is the false green: a check
   that could not run must never read as "clean".
   Related measured lesson from 2026-09: a judge that answered was discarded at
   the timeout threshold, which cost as much as a false green. Check the
   timeout/parse boundary specifically.

3. **Two judges, one job.** There is a `-haiku` variant and a main one. Which
   runs when? If model choice is hardcoded anywhere rather than resolved through
   the router/arbiter, that is a finding — a standing rule says the arm is never
   picked by a hand-kept list.

4. **Does it see enough to judge?** What is actually in the prompt — the diff,
   the premortem, the hack findings? If a claimed input is not really passed,
   the verdict is being formed on less than it says. Compare the template's
   placeholders against what the caller substitutes.

5. **Is a verdict ever recorded?** Can a later session tell what the judge said
   about a given task, or is the verdict lost with the process? Name the file or
   table, or say there is none.

## Rules

- Every finding: `file:line`, mechanism in one sentence, concrete failure
  scenario (what ships that should not, or what is blocked that should not be).
- Something you checked and found SOUND is a finding — say so with the line.
- Do not propose a fix longer than two sentences.
- Do not run a live judge call that consumes Anthropic quota: the shared weekly
  window is at 67% and another session is working. Read the code.
