# CODEX-LEAD-PLUGIN-01 — architect prepass (mechanism-closed)

Design only. No implementation. Base `8bd1758`, repo `~/Projects/leadv2`.

---

## §0. Where the mission's framing is contradicted by the tree

Three corrections, each read off the local CLI / disk, not assumed. Per HARD RULE: one line
each, PROCEED.

1. **`lv2guard.sh:3-4` says "Codex has no PreToolUse/blocking hooks". That is false on
   codex-cli 0.145.0-alpha.1.** The native binary ships a `pre-tool-use.command.output`
   JSON-Schema with `permissionDecision: deny` and an explicit runtime error string for
   `deny` without a reason. Design against the code: hooks are real and blocking, the deny
   floor becomes ENFORCED, and that comment block must be corrected in the same lane.
2. **Mission deliverable #4 names `docs/codex-lead-pilot-runbook.md`; the file is at
   `plugins/leadv2/docs/codex-lead-pilot-runbook.md`** (`ls docs/codex-lead-pilot-runbook.md`
   → "No such file or directory"). Use the real path.
3. **Manifest lives at `<plugin>/.codex-plugin/plugin.json`, not `<plugin>/plugin.json`**, and
   the marketplace index at `<root>/.agents/plugins/marketplace.json`, not
   `<root>/marketplace.json`. Mission's "known on-disk format" is one level off in both cases.

### Probe artifacts (EVIDENCE CONTRACT)

```
$ codex --version
codex-cli 0.145.0-alpha.1

$ codex plugin --help
Commands: add | list | marketplace | remove

$ codex plugin marketplace add --help
Usage: codex plugin marketplace add [OPTIONS] <SOURCE>
  <SOURCE>  Marketplace source: a local path, owner/repo[@ref], HTTPS Git URL, or SSH Git URL
  --json    Output add result as JSON
  codex plugin marketplace add ./path/to/marketplace

$ codex plugin add --help
Usage: codex plugin add [OPTIONS] <PLUGIN[@MARKETPLACE]>
  -m, --marketplace <MARKETPLACE>
      --json

$ codex plugin marketplace list
MARKETPLACE             ROOT
openai-primary-runtime  ~/.cache/codex-runtimes/codex-primary-runtime/plugins/openai-primary-runtime
openai-bundled          ~/.codex/.tmp/bundled-marketplaces/openai-bundled
openai-curated          ~/.codex/.tmp/plugins
```

Live on-disk marketplace root (`~/.codex/.tmp/bundled-marketplaces/openai-bundled`):

```
.agents/plugins/marketplace.json
plugins/<name>/.codex-plugin/plugin.json
plugins/<name>/skills/<skill>/SKILL.md
plugins/<name>/.mcp.json
plugins/<name>/hooks.json          # present in ~/.codex/.tmp/plugins/plugins/figma/hooks.json
```

Authoritative spec on disk (shipped by OpenAI's own `plugin-creator` skill):
`~/.codex/.tmp/plugins/.agents/skills/plugin-creator/references/plugin-json-spec.md` — 173
lines, documents `skills`, `hooks`, `mcpServers`, `apps` as relative-path string fields and
states: *"`skills`, `hooks`, and `mcpServers` are supplemented on top of default component
discovery; they do not replace defaults."*

Real hook config in the wild (`~/.codex/.tmp/plugins/plugins/figma/hooks.json`), verbatim:

```json
{ "hooks": { "PostToolUse": [ { "matcher": "Write|Edit",
  "hooks": [ { "type": "command", "command": "./scripts/post_write_figma_parity_check.sh" } ] } ] } }
```

PreToolUse wire contract, extracted verbatim from the native binary
(`.../codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex`, `strings -a`):

*input* `pre-tool-use.command.input` — required keys: `cwd`, `hook_event_name`
(const `PreToolUse`), `model`, `permission_mode` (enum `default|acceptEdits|plan|dontAsk|
bypassPermissions`), `session_id`, `tool_input` (schema `true` — arbitrary JSON), `tool_name`,
`tool_use_id`, `transcript_path`, `turn_id`. Optional: `agent_id`, `agent_type`.

*output* `pre-tool-use.command.output` — `{continue, decision, hookSpecificOutput, reason,
stopReason, suppressOutput, systemMessage}`; `hookSpecificOutput.permissionDecision` enum
`allow|deny|ask`; `decision` enum `approve|block`.

Runtime rejection strings, verbatim from the same binary — these are the real constraints:

```
PreToolUse hook returned unsupported permissionDecision:ask
PreToolUse hook returned unsupported permissionDecision:allow
PreToolUse hook returned unsupported decision:approve
PreToolUse hook returned permissionDecision:deny without a non-empty permissionDecisionReason
PreToolUse hook returned permissionDecisionReason without permissionDecision
PreToolUse hook returned updatedInput without permissionDecision:allow
PreToolUse hook returned unsupported continue:false
PreToolUse hook returned unsupported stopReason
PreToolUse hook returned unsupported suppressOutput
PreToolUse hook returned reason without decision
hook returned invalid permission-request JSON output
PostToolUse hook exited with code 2 but did not write feedback to stderr
```

**Read that carefully: in 0.145.0-alpha.1 the ONLY permissionDecision a PreToolUse hook may
emit is `deny`, and it MUST carry a non-empty `permissionDecisionReason`. `allow` and `ask`
are rejected.** An allow is expressed by emitting nothing (rc 0, empty stdout). This inverts
the naive Claude-hook port and is the single most likely round-2 finding if missed.

UNVERIFIED: whether `hooks.json` at plugin root is auto-discovered without a `"hooks"` key in
`plugin.json`. Figma ships `hooks.json` with no `hooks` key in its manifest, which suggests
auto-discovery; the spec's "supplemented on top of default component discovery" says the same.
Design declares it explicitly anyway (§2) — the build lane must confirm with
`codex plugin add leadv2@leadv2-local --json` that the hook registers exactly once.

---

## §1. CALLERS / CALLEES

### 1a. `lv2guard.sh` — every existing caller, and the one new one

`plugins/leadv2/codex-lead/lv2guard.sh` (281 lines). Entry points and call sites:

| Caller | file:line | Form used | Path |
|---|---|---|---|
| Prose mandate in the AGENTS brief | `plugins/leadv2/docs/codex-lead-AGENTS-pilot.md` | `lv2guard.sh -c '<cmd>'` | Codex lead, advisory |
| Test harness | `plugins/leadv2/codex-lead/tests/test-lv2guard.sh` | both argv and `-c` | test-only, `LEADV2_CODEX_GUARD_EXEC` seam |
| Shim | `plugins/leadv2/codex-lead/shim/{codex,git,rm}` | argv | PATH shim, advisory |
| **NEW: PreToolUse adapter** | `marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh` (to-create) | **`--check -c '<cmd>'`** | enforced, runtime |

`lv2guard.sh` internal callees: `python3` (yaml pattern matcher), `exec` of the wrapped
command. Reads `plugins/leadv2/config/leadv2-deny-patterns.yaml` (canonical, via
`REPO_ROOT="$SCRIPT_DIR/../../.."`) and `deny-extra.yaml` (sibling).

**The independent copy nobody named.** The deny floor exists TWICE in this repo on two
different paths: `plugins/leadv2/hooks/leadv2-deny-floor.sh` is the **Claude-side** PreToolUse
hook; `codex-lead/lv2guard.sh` is the **Codex-side** re-implementation. They share only the
yaml. This lane touches the Codex path only. Do NOT edit `leadv2-deny-floor.sh` — a change
there lands on every Claude session in three repos through the one-inode symlink tree.

**Caller-shape divergence — the reason a naive port fails.** `lv2guard.sh` today is an
*exec-replacing wrapper*: it takes a command, decides, and becomes the command. A PreToolUse
hook is an *out-of-band adjudicator*: it takes JSON on stdin, decides, and writes JSON on
stdout; it never runs the command. These are different contracts. The design therefore adds a
third mode to `lv2guard.sh` (`--check`) rather than reusing either existing mode.

### 1b. `install.sh` — callers and callees

| Caller | Path |
|---|---|
| Founder, by hand | `bash plugins/leadv2/codex-lead/install.sh [target-repo]` |
| Test harness | `plugins/leadv2/codex-lead/tests/test-codex-install.sh` (runs it TWICE under a fixture `$HOME`, asserts idempotency) |

Callees today: `cp`, `cmp`, `grep`, `python3` (tomllib parse-check + sentinel-block rewriter).
Callees added: `codex plugin marketplace list|add|remove`, `codex plugin list|add`.

**Consequence for the test harness that must not be missed:** `test-codex-install.sh`
redirects `$HOME` to a fixture but does NOT stub `codex`. The moment install.sh shells out to
`codex plugin marketplace add`, the test starts mutating the **founder's real
`~/.codex/config.toml`** — `codex` resolves `CODEX_HOME` from its own default, and the alias
in this shell is `codex --dangerously-bypass-approvals-and-sandbox`. This is the same class of
defect as the open `duplicate-caller-race` thread (a test that spawned real workers). The test
MUST gain a `LEADV2_CODEX_BIN` stub seam, and install.sh MUST invoke `"${LEADV2_CODEX_BIN:-codex}"`
— never a bare `codex`. Treat as CRITICAL, not nice-to-have.

### 1c. New-file call graph

```
codex (runtime)
 └─ PreToolUse dispatch, matcher ".*"
     └─ marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh     [stdin: JSON]
         ├─ python3 -c  (parse stdin, extract tool_name + candidate command string)
         ├─ resolve guard path (4-step chain, §3)
         └─ lv2guard.sh --check -c "<cmd>"        rc 0 = allow, rc 97 = deny
             ├─ python3  (yaml matcher)
             ├─ plugins/leadv2/config/leadv2-deny-patterns.yaml
             └─ plugins/leadv2/codex-lead/deny-extra.yaml
codex (runtime)
 └─ MCP startup
     └─ marketplace/plugins/leadv2/scripts/repowise-launch.sh
         └─ <target-repo>/.repowise/repowise-mcp.sh   (resolved from cwd at runtime)
```

---

## §2. Files, and what each one is

Marketplace root: `plugins/leadv2/codex-lead/marketplace/` (name: `leadv2-local`).

| Path (repo-relative, all to-create unless noted) | Purpose |
|---|---|
| `.../marketplace/.agents/plugins/marketplace.json` | marketplace index; one entry `leadv2` → `./plugins/leadv2`, `policy.installation=AVAILABLE`, `policy.authentication=ON_USE`, `category="Developer Tools"` |
| `.../marketplace/plugins/leadv2/.codex-plugin/plugin.json` | manifest: `name`,`version`,`description`,`author`,`repository`,`license`,`keywords`,`skills:"./skills/"`,`hooks:"./hooks.json"`,`mcpServers:"./.mcp.json"`,`interface{}` |
| `.../marketplace/plugins/leadv2/hooks.json` | `{"hooks":{"PreToolUse":[{"matcher":".*","hooks":[{"type":"command","command":"./hooks/lv2guard-pretooluse.sh"}]}]}}` |
| `.../marketplace/plugins/leadv2/hooks/lv2guard-pretooluse.sh` | stdin-JSON → lv2guard `--check` adapter (§3) |
| `.../marketplace/plugins/leadv2/.mcp.json` | `{"mcpServers":{"repowise":{"command":"./scripts/repowise-launch.sh","args":[],"cwd":"."}}}` |
| `.../marketplace/plugins/leadv2/scripts/repowise-launch.sh` | resolves `<cwd-ancestor>/.repowise/repowise-mcp.sh`, else `$LEADV2_REPOWISE_MCP`, else exits 0 silently |
| `.../marketplace/plugins/leadv2/skills/leadv2/SKILL.md` | from `prompts/leadv2.md` (18 lines) |
| `.../marketplace/plugins/leadv2/skills/leadv2-dispatch/SKILL.md` | from `prompts/leadv2-dispatch.md` (27) |
| `.../marketplace/plugins/leadv2/skills/leadv2-review/SKILL.md` | from `prompts/leadv2-review.md` (24) |
| `.../marketplace/plugins/leadv2/skills/leadv2-status/SKILL.md` | from `prompts/leadv2-status.md` (14) |
| `.../marketplace/plugins/leadv2/skills/leadv2-close/SKILL.md` | from `prompts/leadv2-close.md` (16) |
| `plugins/leadv2/codex-lead/lv2guard.sh` (**existing**) | add `--check` mode; correct the false header comment at :3-4 |
| `plugins/leadv2/codex-lead/install.sh` (**existing**) | plugin path + `LEADV2_CODEX_BIN` seam |
| `plugins/leadv2/codex-lead/tests/test-codex-install.sh` (**existing**) | codex stub, plugin-path assertions |
| `plugins/leadv2/codex-lead/tests/test-lv2guard.sh` (**existing**) | `--check` mode cases |
| `plugins/leadv2/codex-lead/tests/test-codex-plugin-manifest.sh` (**to-create**) | json.load all 3 JSON files, skills present + frontmatter, `bash -n` all shell |
| `plugins/leadv2/docs/codex-lead-pilot-runbook.md` (**existing**) | pilot → full-install framing; ENFORCED vs prose table |

### 2a. Skills and `$ARGUMENTS`

Codex `SKILL.md` frontmatter is `name` + `description` only (verified against
`~/.codex/.tmp/bundled-marketplaces/openai-bundled/plugins/visualize/skills/visualize/SKILL.md`
and the `plugin-creator` skill's own frontmatter). There is no documented argument-substitution
token. **Decision: strip `$ARGUMENTS`; each SKILL.md body opens with a `## Usage` line stating
that the user's request text following the skill invocation is the task brief.** Skill dir name
must equal the frontmatter `name`; `description` is the invocation trigger and must name the
concrete situation, because Codex skills are model-invoked, not slash-invoked. The five
prompt files stay in place unchanged as the fallback path's source (§4).

### 2b. Repowise MCP — why a launcher, not a literal path

`install.sh` today writes `[mcp_servers.repowise] command = "$TARGET_REPO/.repowise/repowise-mcp.sh"`
into `~/.codex/config.toml` — a per-target-repo absolute path. A plugin is host-global, so a
literal path cannot be baked into `.mcp.json`. `scripts/repowise-launch.sh` resolves at spawn
time by walking `$PWD` upward for `.repowise/repowise-mcp.sh`. install.sh keeps its config.toml
block for CLIs on the fallback path; on the plugin path it SKIPS writing it (the plugin owns
the declaration) to avoid two `repowise` servers racing for the same name.

---

## §3. STATES AND RETURN CODES

### 3a. `lv2guard.sh --check -c '<cmd>'` (new mode; existing modes unchanged)

| State | rc | stdout | What the caller (adapter) does | User-visible consequence |
|---|---|---|---|---|
| command matches no rule | 0 | — | emits nothing, exits 0 | Codex runs the command; nothing appears in the transcript |
| matches a CATASTROPHIC rule | 97 | — (reason on stderr) | emits `permissionDecision:deny` + reason | Codex refuses the tool call and shows the rule name and message inline; the model sees the reason and must pick another approach |
| matches a SOFT rule, no inline override | 97 | — | same as above | same |
| matches a SOFT rule with `# deny-floor: allow` | 0 | — | exits 0 | command runs |
| patterns yaml missing/empty/unreadable | 97 | — | deny | **every shell tool call in the session is refused** until the yaml is restored; reason text names the missing file |
| `python3` absent | 97 | — | deny | same as above |
| `--check` given with no `-c` | 2 | — | adapter treats rc 2 as *deny* with reason "guard usage error" | tool call refused; indicates a bug in the adapter, not in the user's command |

`--check` MUST NOT exec anything. Test seam `LEADV2_CODEX_GUARD_EXEC` is irrelevant in this
mode and must be ignored, not honoured.

### 3b. `hooks/lv2guard-pretooluse.sh` (the enforced surface)

| State | Exit | stdout | Runtime behaviour | User-visible consequence |
|---|---|---|---|---|
| guard says allow | 0 | *empty* | tool proceeds | nothing shown |
| guard says deny | 0 | `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"<rule + message>"}}` | tool call blocked | Codex prints the refusal reason in the transcript; the agent must choose another command |
| `tool_name` present but `tool_input` has no readable command (e.g. `apply_patch`, an MCP tool) | 0 | empty | tool proceeds | nothing shown, **plus** one line appended to `${CODEX_HOME:-$HOME/.codex}/lv2guard-unrecognized.log` |
| stdin is not valid JSON | 0 | deny JSON, reason "lv2guard: unreadable PreToolUse payload" | blocked | every tool call refused with that reason — a hard, legible stop, not a silent one |
| lv2guard.sh not resolvable on any of the 4 paths | 0 | deny JSON, reason naming `LEADV2_CODEX_LV2GUARD` | blocked | every tool call refused; the reason text tells the operator the one env var to set |
| adapter itself crashes | non-zero, ≠2 | — | **UNVERIFIED**: binary strings show a "hook exited without a status code" path and an explicit exit-2 contract, but not the rc≠{0,2} semantics. Build lane must probe: run a hook that `exit 7`s and record whether the tool proceeds. | must be determined before merge |
| adapter exits 2 with stderr text | 2 | — | documented block-with-feedback path | tool blocked, stderr shown |

**Never emit `permissionDecision:"allow"` or `"ask"`, never `decision:"approve"`, never
`continue:false`, `stopReason`, or `suppressOutput`** — each is an explicit runtime rejection
string in the binary (§0 artifacts). Allow = empty stdout, exit 0.

**Deny reason must be non-empty**, else the runtime rejects the hook output. The adapter must
substitute a literal fallback string if lv2guard's stderr came back empty.

### 3c. `install.sh` rc contract

| State | rc | Consequence |
|---|---|---|
| ran to completion (plugin path) | 0 (unchanged) | prints `plugin: installed leadv2@leadv2-local` |
| ran to completion (fallback path) | 0 | prints `plugin: CLI has no plugin support — installed prompt pack instead` |
| target repo missing | 3 (unchanged) | test asserts this today; must stay 3 |
| config.toml unwritable / unparseable | 4 (unchanged) | must stay 4 |
| `codex plugin marketplace add` fails (non-zero) | **0**, with `ACTION REQUIRED:` line | do NOT introduce a new failing rc: the installer's contract is "0 = ran, individual steps may print ACTION REQUIRED". Falls back to the prompt-copy path in the same run so the operator is never left with nothing. |

New rc values are forbidden — `test-codex-install.sh` asserts the existing set and the founder
runs this by hand.

---

## §4. CONFIGURATION BOUNDARIES

Every input the mechanism reads, at each boundary.

### `leadv2-deny-patterns.yaml` (canonical) / `deny-extra.yaml`

| Boundary | Behaviour |
|---|---|
| absent | rc 97, deny-all (existing fail-closed doctrine, `lv2guard.sh:12-15`) |
| empty | rc 97, deny-all |
| minimum (1 rule) | normal |
| over-cap | no cap exists on rule count. Matching is O(rules × 64 KiB command). **Recommend a 500-rule sanity cap**: above it, log once and continue — a large yaml must not become a per-tool-call latency tax on the whole session |
| malformed YAML | rc 97, deny-all. This is the correct blast radius only because the file is repo-owned and version-controlled |

### `tool_input` (runtime-supplied, arbitrary JSON per schema)

| Boundary | Behaviour |
|---|---|
| absent | schema says required; if missing → treat as unrecognized-shape → allow + log line |
| empty object | allow + log line |
| command string > 64 KiB | truncate to `MATCH_CAP_BYTES` (65536, existing constant) and match the prefix. **Do not deny on size alone** — an over-cap input taking down the session is a defect. Append a `TRUNCATED` note to the unrecognized log |
| deeply nested / non-string command field | unrecognized shape → allow + log line |
| malformed (stdin not JSON) | deny-all with a legible reason (§3b) |

### `LEADV2_CODEX_LV2GUARD` (new env var)

| Boundary | Behaviour |
|---|---|
| absent | fall through the 4-step resolution chain |
| empty string | treat as absent |
| set to a non-existent path | **do not silently fall through** — deny with a reason naming the bad path; a typo'd override that silently degrades to a different guard is worse than a stop |
| set to a non-executable file | invoked as `bash <path> --check` so the exec bit is not required |

Resolution chain, first hit wins:
1. `$LEADV2_CODEX_LV2GUARD`
2. `$(dirname "$0")/../../../../lv2guard.sh` — marketplace referenced in place
3. `$HOME/Projects/leadv2/plugins/leadv2/codex-lead/lv2guard.sh` — CLI snapshotted the tree elsewhere
4. unresolved → deny with an actionable reason

Step 3 is what makes snapshot-mode work with zero configuration on this host, and it is why
the plugin ships **no copy** of `lv2guard.sh` or the yaml — a copy would drift silently, which
is exactly the failure the global one-copy rule exists to prevent.

### `LEADV2_CODEX_BIN` (new test seam)

| Boundary | Behaviour |
|---|---|
| absent | `codex` from PATH |
| set | used verbatim; the test stub records argv to a fixture file and exits 0 |

### `~/.codex/config.toml`

| Boundary | Behaviour |
|---|---|
| absent | created with the managed block (existing behaviour) |
| unparseable TOML | rc 4, refuse to touch (existing) |
| already has a hand-written `[mcp_servers.repowise]` | left untouched (existing) |
| already has `[plugins."leadv2@leadv2-local"]` | plugin already installed → `codex plugin add` is skipped, printed as `unchanged` |
| marketplace `leadv2-local` already registered at a *different* root | print `ACTION REQUIRED` naming both roots; do not silently re-point |

---

## §5. COUNTEREXAMPLE

*After every finding in this mission is fixed, what can still violate the invariant "no
CATASTROPHIC command executes in a Codex lead session"?*

Four things, and I could not eliminate them in this design.

**(1) The hook only sees tools it is dispatched for, and `tool_input`'s shape is undocumented.**
The binary's schema declares `"tool_input": true` — literally *any* JSON. I found only one
quoted tool name in the binary (`apply_patch`); the shell tool's name and its input key are not
recoverable by static inspection. The matcher is therefore `".*"` and the adapter decides — but
if the shell tool's command lives under a key the adapter does not read, the adapter allows and
the floor is silently absent. The `lv2guard-unrecognized.log` and the runbook check "this file
must be empty after a session" exist precisely to convert that silent hole into an observable
one. **This makes the build lane's first step non-optional: install a logging-only PreToolUse
hook, run one `codex exec` that does `ls`, and read the captured stdin.** Design against the
recorded payload, not against this document's guesses.

**(2) A Codex upgrade can change the wire shape and re-open the hole.** The CLI is
`0.145.0-alpha.1`. A renamed field turns every tool call into an unrecognized shape, which this
design deliberately treats as *allow* (denying would brick every session after every upgrade).
The floor degrades to zero, loudly in a log nobody reads. Mitigation is procedural only: the
runbook's measurement checklist must include the log check, and the manifest test should pin
the observed CLI version so a version bump forces a re-probe.

**(3) The plugin can be uninstalled, and prose cannot stop that.** `codex plugin remove leadv2`
is one command and the floor is gone. The enforced floor is stronger than the pilot's prose
floor, but it is not tamper-proof against the lead agent itself — and `deny-extra.yaml` already
denies direct `codex exec`, not `codex plugin remove`. **Recommend adding a `codex plugin
remove leadv2` pattern to `deny-extra.yaml` in this lane** — a floor that can remove itself is
a floor with one bypass.

**(4) The bypass alias is already in this shell.** `codex` on this host is aliased to
`codex --dangerously-bypass-approvals-and-sandbox`. That flag governs *approval prompts*;
whether it also short-circuits PreToolUse hook dispatch is **UNVERIFIED and decision-critical** —
if it does, the entire enforced floor is inert on the founder's actual invocation path and this
whole deliverable buys nothing. The build lane must probe it explicitly: run the same denied
command with and without the flag and compare. If the flag bypasses hooks, say so in the summary
in the first line and keep the prose mandate as the primary floor.

Everything else I checked and could not break: rc collision (97 is reserved and unused by the
adapter), double hook registration (idempotent for a deny), yaml drift (no copies exist), and
install non-idempotency (guarded by the existing twice-run test plus the new stub).

---

## §6. Migration / sequencing

Additive, backward-compatible, in this order — each step independently revertable:

1. `lv2guard.sh --check` mode + header-comment correction. Existing modes byte-identical in
   behaviour. `test-lv2guard.sh` green before anything else lands.
2. Build-lane probe: logging-only PreToolUse hook → capture real `tool_name`/`tool_input`;
   probe the bypass alias (§5.4) and the rc≠{0,2} semantics (§3b). Record all three in the
   summary as probe artifacts.
3. Marketplace tree + adapter, written against the recorded payload.
4. `codex plugin marketplace add` → `codex plugin add leadv2@leadv2-local --json` →
   `codex plugin list` → **`codex plugin remove leadv2@leadv2-local` and
   `codex plugin marketplace remove leadv2-local`**. Capture all five outputs. Host left clean;
   installing for real is the founder's call.
5. `install.sh` plugin path + `LEADV2_CODEX_BIN` seam; `test-codex-install.sh` stub and new
   assertions; new manifest test.
6. Runbook rewrite last, describing what actually happened in steps 2–4.

---

## §7. Out of scope (implementing agent: ignore these)

- `plugins/leadv2/hooks/leadv2-deny-floor.sh` — the Claude-side hook. Not this lane.
- `plugins/leadv2/config/leadv2-deny-patterns.yaml` — content unchanged (the `codex plugin
  remove` rule from §5.3 goes in `deny-extra.yaml`, the codex-lead-only file).
- Persistent installation of the plugin on this host.
- Git-sourced marketplace (`owner/repo@ref`) — local path only.
- `.app.json` / apps capability.
- Any change to the five `prompts/*.md` bodies beyond the mechanical SKILL.md conversion.
- `~/.claude/leadv2-shared/` and the one-copy regressions in the session-start digest.
- The open `duplicate-caller-race` thread.

---

## acceptance:

```
acceptance:
  - surface: log_line
    observable: >
      In the captured terminal transcript of the install proof, `codex plugin list`
      shows a row for the plugin named leadv2 from the marketplace named leadv2-local,
      where before the proof no such row appeared; and after the cleanup commands the
      same listing again shows no leadv2 row and no leadv2-local marketplace.
    authored_at: 2026-08-24T12:11:13Z
  - surface: rendered_line
    observable: >
      With the plugin installed, a Codex session asked to run a command that the deny
      floor forbids does not run it, and the reply visibly states the name of the rule
      that refused it together with that rule's message — rather than the command's
      output or an ordinary error.
    authored_at: 2026-08-24T12:11:13Z
  - surface: rendered_line
    observable: >
      With the plugin installed, a Codex session asked to run an ordinary harmless
      command shows that command's normal output, with no refusal text and no mention
      of the guard.
    authored_at: 2026-08-24T12:11:13Z
  - surface: file_artifact
    observable: >
      The runbook at plugins/leadv2/docs/codex-lead-pilot-runbook.md no longer describes
      the work as a pilot, gives the founder two install commands to type, and contains a
      table in which each gate is marked either enforced-by-the-plugin or still-prose-only.
    authored_at: 2026-08-24T12:11:13Z
  - surface: log_line
    observable: >
      Running the repo's codex-lead test scripts twice in a row prints a passing result
      both times, and the second run reports the installer made no further changes.
    authored_at: 2026-08-24T12:11:13Z
```

LANE_WRITES: plugins/leadv2/codex-lead/marketplace/**, plugins/leadv2/codex-lead/lv2guard.sh, plugins/leadv2/codex-lead/install.sh, plugins/leadv2/codex-lead/deny-extra.yaml, plugins/leadv2/codex-lead/tests/test-lv2guard.sh, plugins/leadv2/codex-lead/tests/test-codex-install.sh, plugins/leadv2/codex-lead/tests/test-codex-plugin-manifest.sh, plugins/leadv2/docs/codex-lead-pilot-runbook.md

DELIVERABLE_COMPLETE
