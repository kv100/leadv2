# Model Routing — leadv2 plugin (universal, all consuming repos)

This is the plugin-level template for per-repo `docs/model-routing.md`. Each consuming
repo (persona-engine, m3-market, respiro-ios, ...) may keep its own concrete copy with
repo-specific numbers; this file is the shared authority for the ARCHITECTURE behind it.

## Gating metric = Claude token QUOTA, not dollars

If the founder is on a Claude subscription, $/token pricing is irrelevant. Measured burn
across repos: the overwhelming majority of tokens is **cache-read** (context re-read every
turn), not output. Per-turn token load is roughly MODEL-INDEPENDENT — the real cost of a
heavier model (e.g. Opus) is its weight against a plan's tighter weekly cap, not raw
token count. Route on QUOTA PRESSURE, not sticker price.

## The three quota levers (in order of impact)

1. **Codex offload** — a separate ChatGPT token pool = ZERO Claude quota. The single
   biggest lever available. Route anything code-shaped to Codex FIRST where the repo has
   opted in (see below).
2. **Context discipline** — compact at the turn cap, fewer parallel sessions, don't revive
   cold sessions. This dwarfs any model-choice saving.
3. **Model choice** — second-order. Route by difficulty × volume (below).

## Route by DIFFICULTY x VOLUME

| Workload | Lane | Why |
|---|---|---|
| Code (any volume) | **Codex** (where `codex_enabled: true`) | off Claude quota entirely; more volume = more saved |
| High-volume Claude bulk (fan-out, reads, mechanical) | **Sonnet-low / Haiku** | light quota weight; protects the Opus cap at volume |
| Hard / high-value minority (architecture, root-cause, tricky logic, safety) | **Opus** | few turns, quality pays for itself |
| Lead decisions / routing | **Opus** (or the repo's pinned lead model) | thin router, not a thinker |

Rule: **VOLUME -> cheap lane (Codex/Sonnet/Haiku); HARDNESS -> smart lane (Opus).**
Codex-first for anything code-shaped, in any repo that has opted in. Sonnet's effort
cap is `high`, and `high` is reserved for gate/verdict roles (critic, security-auditor,
verify) — build spawns run `medium`, reads `low`. If a sonnet spawn seems to need
`xhigh`, escalate the MODEL (Opus or Codex), never the effort.
Canonical two-axis matrix (model × effort, per class × phase):
`plugins/leadv2/docs/model-effort-matrix.md`.

**GLM lane (second zero-Claude-quota pool):** GLM-5.3 has live transport acceptance
evidence in `plugins/leadv2/docs/evidence/glm-5.3-probe.md`. Benchmark, context, and
price claims from GLM-5.2 are UNVERIFIED for GLM-5.3 and are deliberately not used for
routing. Route background latency-class work (bulk/mechanical transforms, mass audits,
standard code nobody waits on) to GLM where the repo has a GLM lane configured. Banned
for architecture/design/safety. Priority per spawn: Codex → GLM → Claude ladder.

## Per-agent defaults (template — tune per repo)

| Subagent | Model | Codex? |
|---|---|---|
| lead (orchestrator) | repo's pinned lead model (e.g. Opus) | -- |
| **developer** | Codex-first where enabled; Sonnet fallback (parallel fan-out) | YES |
| **critic / review** | Codex-primary + Sonnet/Opus critic as second opinion | YES |
| architect | Sonnet (Opus on Heavy classification) | -- |
| postgres-pro | Sonnet | opt |
| frontend-developer | Sonnet | rare |
| devops-engineer | Sonnet (commits on Haiku) | no |
| security-auditor | Sonnet | opt |
| Explore / discovery | Haiku | no |
| product-owner / strategist | Sonnet | no |

## Codex-first is gated per-repo, never global

Codex-first routing is **NOT** a plugin-wide default — it is gated by each repo's own
`.claude/leadv2-overrides/codex-policy.yaml`:

```yaml
codex_enabled: true          # opt-in; default is false/absent = Codex OFF
codex_first_class: true      # optional: default to Codex on plan/review + fitting dev
```

- `leadv2-block-codex.sh` (PreToolUse:Agent+Bash) hard-BLOCKS any Codex invocation
  (`subagent_type=codex:*`, `codex-task.sh`, raw `codex` CLI) when `codex_enabled` is
  false or the policy file is missing. This is the enforcement half.
- `leadv2-codex-first-nudge.sh` (PreToolUse:Agent) is the WARN-only companion: when a
  repo HAS opted in (`codex_enabled: true`) and the lead spawns a fitting build/review
  role (`developer`, `postgres*`, `frontend*`, `critic`, `security*`) WITHOUT routing to
  Codex, it prints a single stderr reminder — never blocks, never denies, always exits 0.
  Silent everywhere else (policy absent/false, or subagent already Codex-routed).
- **Never edit another repo's `codex-policy.yaml` from this plugin repo or from a
  different repo's session.** Each repo's founder-directive opt-in is authoritative and
  repo-local; the plugin only supplies the mechanism (both hooks), not the policy value.

## Codex quota EXHAUSTION — fallback ladder

Codex runs on its own subscription pool with its own rolling usage caps. When Codex
fails (login down OR quota exhausted — `codex-task.sh` exits non-zero / rate-limited):

1. **SURFACE to founder** ("Codex unavailable: `<login|quota>` — falling back to
   Claude"). Never degrade silently.
2. **Fall back by task type onto Claude quota:**
   - code, hard → Opus (low/med effort)
   - code, bulk → Sonnet (low effort)
   - review/critic → Sonnet critic (Opus if safety-touched)
3. This loads the Claude quota — watch the Opus weekly cap. A `downgrade_chain`
   (e.g. `opus->sonnet`) should auto-catch cap strain; Haiku is the last-resort floor.
4. Codex caps are a ROLLING window — retry Codex-first on the next session/task; don't
   stay parked on the Claude fallback once Codex recovers.

**Full ladder:**
`Codex -> [hard: Opus | bulk: Sonnet | review: Sonnet-critic] -> Sonnet (cap valve) -> Haiku`

## Per-repo concrete copies

- `persona-engine/docs/model-routing.md` — Codex first-class (founder directive
  2026-07-01), full measured-burn numbers.
- `m3-market/.claude/leadv2-overrides/codex-policy.yaml` — `codex_enabled: true`.
- Other repos (respiro-ios, ...) — Codex OFF by default until the founder explicitly
  opts in via that repo's own `codex-policy.yaml`. Do not flip it from here.

## Claude multi-profile selection (CLAUDE-MULTIPROFILE-QUOTA-02, opt-in)

A Claude lane can pick the healthiest of several Anthropic profiles before spawning
`claude`. **Off by default**; set `LEADV2_CLAUDE_MULTIPROFILE=1` to enable.

**Registry** — user-level, NEVER committed to a repo
(`${LEADV2_CLAUDE_PROFILES_FILE:-$HOME/.claude/state/leadv2/claude-profiles.tsv}`, TSV):

```
# label<TAB>config_dir<TAB>credential_source(optional)
alpha	/abs/path/to/config/dir	keychain:Claude Code-credentials
beta	/abs/path/to/other/dir	file:/abs/path/to/other/dir/.credentials.json
```

- `label`: `^[a-z0-9][a-z0-9_-]{0,31}$` (rejects `@`/`.` — emails are a hard reject).
  The label is the ONLY field ever journalled or logged.
- `config_dir`: absolute, existing directory. It is passed to the child as
  `CLAUDE_CONFIG_DIR` only; it is never journalled. The operator owns registry
  content — a non-default config dir must carry the settings/hooks the lane needs.
- `credential_source`: `keychain:<service>` or `file:<abs path>`; absent defaults to
  `file:<config_dir>/.credentials.json`. The registry states it explicitly because
  how Claude Code derives a keychain service from a config dir is UNVERIFIED and is
  deliberately never derived in code.

**Selection** (`plugins/leadv2/scripts/leadv2-claude-profile-select.sh`): each entry is
probed independently (`leadv2-quota-read.py anthropic --no-cache`, `--credential-file`
for `file:` sources, per-profile cache dir + service pin), bounded by one total budget
(`LEADV2_CLAUDE_PROFILE_TIMEOUT`, default 12s, clamped 1..60). Score =
max(five_hour_pct, seven_day_pct) (worst window); lowest score wins; ties break by
registry order. Every fault path (missing registry, <2 valid entries, all probes
hung, crash) fails open to single-profile: the inherited `CLAUDE_CONFIG_DIR` is left
untouched and the lane runs exactly as before.

**Observable**: one stderr line per lane, label-only —
`[claude-profile] selected=<label> score=<n> source=live candidates=<n>` (or
`[claude-profile] single-profile fallback`) — mirrored, ISO-8601-prefixed, into
`docs/handoff/<task-id>/claude-profile.log`. No path, service name, email, or token
ever appears on either surface.

Tests: `plugins/leadv2/scripts/tests/test-claude-profile-select.sh` (hermetic; stubbed
probe, fake `claude`, T1–T10 + integration legs).

---
Template source: adapted from `persona-engine/docs/model-routing.md` (2026-07-01) for
plugin-wide reuse. Each repo may extend with its own measured burn data; the mechanism
(policy gate + WARN-only nudge hook) is shared and lives in this plugin.
