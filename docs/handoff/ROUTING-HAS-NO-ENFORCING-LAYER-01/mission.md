ROUTING-HAS-NO-ENFORCING-LAYER-01 — arm routing rests on three layers and NOT ONE of them stands
in the path of the call. Make exactly one of them stand there.

FOUNDER DECISION 2026-09-04: fix it in the SHARED plugin tree, so it works for every consumer of
the plugin and in every repository on this machine. Not a repo-local override.

THE DEFECT, measured — file and line, not inference.

- `plugins/leadv2/hooks/leadv2-codex-first-nudge.sh:113` emits a hardcoded
  `'permissionDecision': 'allow'`. The hook is STRUCTURALLY incapable of refusing; it can only
  print. Its own header at :44 says so plainly.
- `leadv2-router.sh` is a calculator: it prints the chosen model and a command template. It
  intercepts nothing.
- The shoulder table in `.claude/leadv2-overrides/extensions.md` is a document.

So a direct `Agent(subagent_type=developer, model=sonnet)` walks past all three and bypasses the
dispatcher, the quota gate and the arm ladder entirely. This has now happened TWICE — 2026-08-27
and 2026-09-04 — and BOTH times the nudge fired and was ignored, because being ignored is all it
can do. "The consumer does not obey" is the wrong frame: there is nothing to obey.

THE BOUNDARY — read this twice, it is the whole design.

Gate on the CAPABILITY TO WRITE, never on a list of subtype names.

A name list is the same defect one level up: `Agent` also accepts `general-purpose` and `claude`,
both catch-alls with the full tool set, both able to write code as well as `developer`. Gate the
three obvious names and the next bypass is `Agent(subagent_type="general-purpose", model=sonnet)`
— quieter than today's, because a guard now stands nearby creating the impression the path is
closed. (Credit: this hole was found by the getmany-followup-bot session before implementation.)

SECOND CORRECTION, from the founder, on this same mission before it was dispatched. The first
draft said "carries Write/Edit AND runs on a CLAUDE model". That reproduces the identical blindness
one level over: the freepool arm, GLM and Kimi are not Claude models, so a direct write-capable
spawn on any of them sails straight through a gate that looks closed. The provider was never the
point. What the dispatcher supplies is the RECORDED DECISION — arm selection, quota accounting,
the fallback ladder — and a direct spawn loses all of that on freepool exactly as it does on
sonnet.

So the boundary is: an agent that carries `Write`/`Edit` in its tool set and was NOT launched
through the dispatcher → the gate applies, **on every provider, with no model or provider name
anywhere in the predicate**. Read-only reconnaissance → passes untouched.

If your implementation contains a list of model names, provider names, or subtype names as the
discriminator, it is wrong by construction and will be bypassed by whatever is not on the list.
Two independent reviewers found two separate holes of exactly this shape in this mission before a
single line was written. Assume there is a third.

MUST NOT be touched — these bypass the dispatcher BY DESIGN and a blanket block breaks daily work
in all three repos at once: `Explore` and any haiku reconnaissance, the architect on opus, plan
synthesis, judge panels.

KNOWN GAPS, deliberately out of the first version — record them in the report so the next reader
does not mistake omission for oversight: `devops-engineer` edits deploy scripts, and
`critic`/`security-auditor` burn quota on review (the repo's own table admits review to GLM, but
not over its own code).

WHAT THE REFUSAL MUST DO.

1. Name the way forward, never just "denied": route through `leadv2-dispatch-code.sh`, or record
   why Claude specifically is needed here. A refusal with no exit gets worked around, correctly.
   Verify the path you print EXISTS before printing it — a refusal pointing at a script that is
   not there is worse than no refusal. (It does exist, both in the plugin and repo-locally;
   confirm, do not assume.)
2. The reason is RECORDED, not asserted — it lands in the journal and can be read back. Otherwise
   in a week every call carries `reason=needed` and we are back here.

ACCEPTANCE — four cases. The fourth is the one that decides whether this is real.

1. A code-writing spawn with no recorded reason → DENIED. Verbatim output, including the text
   naming the way forward.
2. The same spawn WITH a recorded reason → passes, and the reason is readable afterwards where
   you claim it is written. Show the read-back.
3. `Explore` / haiku reconnaissance → NOT denied. Without this the gate ships breaking recon.
4. `Agent(subagent_type="general-purpose", model=<claude>)` with write tools → DENIED. If this one
   passes, the gate is closed only on paper.
4b. A write-capable spawn on a NON-Claude arm — freepool, glm, kimi → DENIED TOO. This is the
   founder's own objection and the case most likely to be missed, because it is the door nobody
   names. Show it explicitly. A gate that denies sonnet and admits freepool has moved the bypass,
   not closed it.
5. NEGATIVE CONTROL, mandatory: restore `permissionDecision: 'allow'` inside the function body,
   re-run case 1, show it goes GREEN-through (not denied); restore the fix, show denied again.
   Both outputs verbatim. An inert guard and a working guard are indistinguishable by silence —
   this class of mistake was caught four separate times on 2026-09-04.

DEPLOYMENT — the step that decides whether any of this changes behaviour.

Hooks load from the plugin CACHE, not from the tree you edit. Editing the file changes nothing by
itself. Copy the hook into the cache and state in the report whether the hook ROSTER changed
(`hooks.json`) — if it did, a session restart is required and you must say so plainly rather than
claim the fix is live. `claude plugin update` no-ops for directory-source marketplaces when
content changed but the version did not. A "fixed" file with unchanged behaviour is the exact
lying-green disease this task exists to end.

CONSTRAINTS. Shared plugin tree feeding three repositories; the founder authorised this change
explicitly. Never `git add -A`. Do not push to origin. Do not widen
`tests/known-red-suites.txt` / `tests/known-failures.txt` — they may only shrink. The suite carries
a `# run-all-triggers:` header naming the hook, and CI selection is proven with
`tests/run-all.sh --scope changed`. Report the suite's final count line verbatim; if it prints
none, say so. If the close gate returns `e2e_regression`, run the named suites on main WITHOUT
your commit before believing it — a verdict is not evidence.
