---
description: Show and change which model providers (Codex / GLM / freepool / Claude) are allowed to do work in THIS repo — renders the current state, then an AskUserQuestion picker, then applies the change.
---

# /leadv2mode — provider mode for this repo

Founder-facing switch for "какие провайдеры работают в этом репо". No arguments.
Everything below is config, never application code — the lead performs the edits directly.

## The three layers (do not conflate them)

| Layer | Where it is decided | Scope |
|---|---|---|
| **Codex** | `<repo>/.claude/leadv2-overrides/codex-policy.yaml` → `codex_enabled` **and** a `[projects."<abs-repo-path>"]` block in `~/.codex/config.toml` | per repo |
| **GLM / glm-flash / freepool** | `router.dispatch_ladder` in the plugin's `config/leadv2-routing.yaml`; a repo may narrow it with its own `<repo>/.claude/ref/leadv2-routing.yaml` (`allowed_arms`, or its own `dispatch_ladder`) | plugin default, repo may narrow |
| **Claude (sonnet/opus)** | always the last rung of the ladder | everywhere |

Both Codex conditions must hold. `codex_enabled: true` with no `~/.codex/config.toml` entry
silently falls back to the global default sandbox — that is a half-on state, not "on".
A missing `codex-policy.yaml` reads as **disabled**, same as `false`.

## Step 1 — read the live state (never from memory)

```bash
R="$(git rev-parse --show-toplevel)"
grep -h '^codex_enabled' "$R/.claude/leadv2-overrides/codex-policy.yaml" 2>/dev/null || echo 'codex_enabled: MISSING (=off)'
grep -nE 'allowed_arms|dispatch_ladder' "$R/.claude/ref/leadv2-routing.yaml" 2>/dev/null || echo 'no repo routing yaml — plugin ladder applies as-is'
python3 -c "
import tomllib,os,sys
d=tomllib.load(open(os.path.expanduser('~/.codex/config.toml'),'rb'))
e=(d.get('projects') or {}).get(sys.argv[1],{})
print('codex config:', e.get('approval_policy'), e.get('sandbox_mode') or 'NO ENTRY (global default)')
" "$R"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lib/leadv2-freepool-gate.sh" >/dev/null 2>&1; echo "freepool gate rc=$?"
```

Print one compact table of what is ON / OFF / half-on before asking anything.

## Step 2 — ask

One `AskUserQuestion`, `multiSelect: true`, header `Providers`, one option per arm that is
**not already fully on**, plus an option to turn an arm OFF if it currently is on. Each option's
description names the exact file(s) that will change. Never ask about an arm whose state you
could not read — say you could not read it instead.

## Step 3 — apply exactly what was picked

- **Codex ON** → set `codex_enabled: true` (create the file from
  `<repo-with-codex-on>/.claude/leadv2-overrides/codex-policy.yaml` as the template if absent),
  and add/complete the `~/.codex/config.toml` block:
  `trust_level = "trusted"`, `approval_policy = "never"`, `sandbox_mode = "danger-full-access"`.
  Back the toml up first (`.bak-<YYYYMMDD>`) and re-parse it with `tomllib` afterwards —
  a hand-edited toml that no longer parses disables Codex everywhere, not just here.
- **Codex OFF** → `codex_enabled: false`. Leave the toml block alone; the yaml is the gate.
- **GLM / freepool ON** → nothing to do unless this repo narrows the ladder: remove the arm from
  `allowed_arms` restrictions in `<repo>/.claude/ref/leadv2-routing.yaml`, or delete an
  arm-exclusion entry. If the repo has no routing yaml, the plugin ladder already allows it —
  say so rather than creating a file.
- **GLM / freepool OFF** → add the arm to this repo's `review_arm_exclusions` / narrow
  `allowed_arms` in `<repo>/.claude/ref/leadv2-routing.yaml`. Repo-local only —
  **never** edit the plugin's canonical ladder to turn an arm off for one repo.
- **freepool half-on** → it also needs `~/.claude/secrets/freepool.env` with `FREEPOOL_AUTH_TOKEN`,
  the fcc proxy live on :8317, and a non-poisoned `~/.claude/leadv2-state/freepool-arm-state.json`
  (a window of pre-activation errors pins `error_rate=1.00` → `gate_broken`; move the json aside).

## Step 4 — report honestly

Re-read the state with Step 1's commands and print the table again. Say explicitly which arms are
**enabled but unproven** — an arm is proven only by a real dispatch landing on it, never by a
green gate. Anything left half-on gets a row in `docs/leadv2/open-threads.md` the same turn.

Safety invariants that this command may never relax: protected / safety / publish work never
routes to GLM or freepool regardless of what is picked here, and `approval_policy`/`sandbox_mode`
are only ever set for a repo the founder named in this invocation.
