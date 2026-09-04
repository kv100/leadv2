verdict: NEEDS-INFO
next_action: escalate_to_founder

Mechanism-closed design done: 2 new scripts, 1 hooks.json entry, doc rewrite, 12-case test.

- Mission wrong on 3 points, proved from tree: `docs/single-lead-pulse.md` absent (it's under `plugins/leadv2/docs/`); `founder-status.md` is NOT a state-path file — the resolver would watch a path nothing writes.
- Monitor defaults to a 5-min timeout; `persistent=true` is part of the mechanism.
- Idle session composes no beat at all — watcher can't fix that. Founder call needed.

Full: architect.full.md
