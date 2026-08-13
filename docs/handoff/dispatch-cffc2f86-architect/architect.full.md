# M-6 — memory-GC via batched merge verdicts — architect design

TASK_ID: dispatch-cffc2f86-architect · repo `~/Projects/leadv2` (canonical plugin) · base `2018c80`
Role: architect prepass. **No implementation in this document.**

---

## 0. Ground truth established at design time (2026-08-03)

| Fact | Evidence |
|---|---|
| Live index = 149 lines, cap ~100 | `wc -l ~/.claude/projects/-Users-kostiantyn-vlasenko-Projects-persona-engine/memory/MEMORY.md` → `149` |
| Index is sectioned | 4 `## ` headers at lines 1, 65, 92, 109; 8 non-entry lines total |
| Entry line grammar | `- [Title](slug.md) — hook` , optionally `. Also: [label](slug2.md), [label](slug3.md)` — merging **already happened by hand**, so the merge shape is a proven, human-accepted format |
| Entry files | 251 files in `memory/`, frontmatter `name` / `description` / `metadata.{node_type,type,originSessionId}`; body has `**Why:**` / `**How to apply:**` and `[[wikilinks]]` |
| Type distribution | `feedback` 108, `reference` 79, `project` 56 (`user` type exists per memory contract but is not present as a `type:` line in this dir — the user-profile entry is index line 2) |
| Archive already exists | `memory/archive/` with `ARCHIVE.md`, moved entry files, and a prior `GC-report-20260706.md` (MEMORY-RESTRUCTURE-01, 2026-06-23) — **the archive convention is pre-existing and must be extended, not replaced** |
| Immunity marker in this corpus | `STANDING:` appears on **19** index lines. There is no `ACTIVE` literal in the Claude-memory dir; `ACTIVE` is the yaml-store (`immune-patterns.yaml`, `leadv2-negative-memory.yaml`) marker |
| Existing surface | `plugins/leadv2/skills/leadv2-memory-gc/SKILL.md` (52 ln) + `scripts/leadv2-memory-gc.sh` (87 ln) → `leadv2-memory-gc-logic.py` (136 ln) + `leadv2-memory-gc-render.py` (47 ln). Current scope = 4 **yaml/md leadv2 stores**, not the Claude memory dir |
| Canonical `claude -p` shape in this repo | `leadv2-task-judge.sh:214` — `"${CLAUDE_BIN}" -p "$prompt" --model "$M" --max-turns 3 --permission-mode bypassPermissions --output-format json`, wrapped in `gtimeout`/`timeout`, result unwrapped from `.result` via python | 

**Consequence for scope:** the mission's target (a project memory index) is a *different store shape* from the four stores the current GC walks. The design adds a **second mode** to the same surface rather than rewriting the existing one — the existing yaml-store path stays byte-identical and its callers (`leadv2-phase8-close.sh` weekly trigger) keep working unchanged.

---

## 1. Data flow (numbered)

```
leadv2-memory-gc.sh --memory-dir <DIR> [--cap N] [--apply] [--sim F] [--model M]
   │
   │ (no --memory-dir → legacy 4-store yaml GC, unchanged path, exits as today)
   ▼
 1. LOCK        flock memory/.memory-gc.lock (non-blocking; busy → exit 4)
 2. EARLY-EXIT  count entry lines in MEMORY.md; if <= cap → print no-op line, exit 0
                (this is what makes re-run #3 a genuine no-op with zero LLM cost)
 3. PARSE       MEMORY.md → [Entry{line_no, section, title, slug, extra_slugs[],
                hook, raw_line}] + non-entry lines kept verbatim with their anchors
 4. LOAD        for each slug → memory/<slug>.md frontmatter(name, description,
                metadata.type) + body first 400 chars.  Missing file → entry marked
                `orphan_index_line`, immune from merge, reported.
 5. IMMUNE      classify in CODE (§3). immune entries: eligible as ANCHOR only,
                never as absorbed member.
 6. CLUSTER     deterministic, NO LLM (§4) → clusters[] of size >= 2
 7. SEEN-FILTER drop clusters whose exact member-set was already judged `keep`
                (memory/.memory-gc-state.yaml) → idempotence guard
 8. LLM         ONE batched `claude -p` call over ALL remaining clusters → verdicts
 9. VALIDATE    reject-and-downgrade-to-keep on any contract breach (§6). FAIL-CLOSED.
10. PROJECT     projected_lines = current_entry_lines - absorbed_count
                render plan report with per-cluster verdict list
11a. dry-run    write report only. NOTHING else touched. (DEFAULT)
11b. --apply    re-hash MEMORY.md; if changed since step 3 → abort (exit 5)
                write archive/gc-<stamp>/{MEMORY.md.pre, manifest.yaml, <moved>.md}
                rewrite MEMORY.md; git-mv-free `mv` of absorbed entry files
                append run section to archive/ARCHIVE.md
                update .memory-gc-state.yaml
12. --restore <run-dir>   MEMORY.md.pre → MEMORY.md ; move entry files back
```

---

## 2. Files — exact list

| Path | Action | Purpose |
|---|---|---|
| `plugins/leadv2/scripts/leadv2-memory-gc.sh` | **edit** | add `--memory-dir`, `--cap`, `--sim`, `--model`, `--restore`, `--verdicts-file` (test injection); dispatch to index mode when `--memory-dir` present; legacy path untouched otherwise |
| `plugins/leadv2/scripts/leadv2-memory-index-gc.py` | **create** | all index-mode logic: parse, immune-classify, cluster, validate verdicts, project, apply, restore. Deterministic; LLM call is *not* made here (shell owns it) — this file takes clusters-in / verdicts-in via stdin+env so it is unit-testable with a stub verdicts file |
| `plugins/leadv2/prompts/memory-gc-verdict.md` | **create** | the single batched prompt template (`<<<CLUSTERS_JSON>>>` placeholder), mirroring `leadv2-task-judge.sh`'s template convention |
| `plugins/leadv2/skills/leadv2-memory-gc/SKILL.md` | **edit** | document index mode, flags, immunity rules, archive/restore contract. No new slash command, no new skill |
| `plugins/leadv2/tests/test-memory-index-gc.sh` | **create** | fixture-driven: immunity enforcement, orphan-`absorbed_by` rejection, idempotence, byte-exact restore. Uses `--verdicts-file` so the test never calls an LLM |

Confirmed on disk: `plugins/leadv2/scripts/`, `plugins/leadv2/tests/`, `plugins/leadv2/skills/leadv2-memory-gc/SKILL.md` all exist. `plugins/leadv2/prompts/` — **(to-create if absent)**; implementer must `ls` it first and place the template beside the existing prompt templates if a different dir name is already in use (`leadv2-task-judge.sh` resolves `PROMPT_TMPL` — follow whatever that variable points at rather than inventing a directory).

---

## 3. Immunity — enforced in code, not in the prompt

An entry is **immune** (verdict forced to `keep`, and it is excluded from every cluster's absorbable set before the prompt is even built) if ANY holds:

| Rule | Detection |
|---|---|
| STANDING directive | `STANDING:` (case-sensitive) in the index line or in the entry body |
| user-type memory | frontmatter `metadata.type == user` |
| yaml-store ACTIVE | slug or its `name:` appears in `docs/leadv2/immune-patterns.yaml` or `docs/leadv2-negative-memory.yaml` with `status: ACTIVE` (project-root-relative; skipped silently if the store is absent — tenant-generic) |
| explicit opt-out | frontmatter `metadata.memory_gc: keep` |
| orphan index line | index line whose target `<slug>.md` does not exist — cannot be safely merged, report-only |
| section header / blank / prose | non-entry lines are never candidates and are re-emitted verbatim |

Two-layer enforcement (defence in depth):
- **Pre-prompt**: immune slugs are sent to the LLM only inside an `anchors_only` array; they never appear in `absorbable`.
- **Post-verdict**: step 9 re-checks — any verdict assigning `merge`/`archive` to an immune slug is rejected, the whole cluster downgrades to `keep`, and the report gets a `rejected_verdict: immune_violation` row. A prompt-only guarantee would be a FAIL by the mission's own hard rule.

---

## 4. Clustering — cheap, deterministic, no LLM

Candidate pairing is intentionally conservative; the LLM's job is to *veto and choose the anchor*, not to discover clusters.

- **Partition first** by (`section`, `metadata.type`). Never cluster across `## ` sections — the sections are semantic buckets a human authored (`User profile & durable preferences` vs `References (durable)`), and cross-section merges silently change what a reader expects to find where.
- **Similarity** between two entries = `jaccard(tokens(a), tokens(b))` where `tokens(x)` = lowercased alnum tokens from `slug` (split on `_`) ∪ `title` ∪ `description`, minus a stoplist (`the,a,is,to,for,not,and,leadv2,feedback,project,reference`).
- **Prefix bonus**: `+0.15` when the two slugs share the first two underscore-segments (`feedback_codex_*`, `reference_postgrest_*`).
- **Threshold** default `0.34`, override `--sim` / `LEADV2_MEMGC_SIM`.
- **Union-find** over pairs above threshold → clusters. Cluster member order and cluster order are both by index `line_no` — so the same input always produces byte-identical cluster JSON, and therefore a cacheable prompt.
- Clusters of size 1 are dropped before the prompt.
- Cap `--max-clusters` (default 40) so the single prompt stays bounded; overflow is **reported explicitly** in the plan (`deferred_clusters: N` — silent truncation would read as "covered everything").

---

## 5. Interface contract — the one batched LLM call

Invocation (shell, mirrors `leadv2-task-judge.sh:214`):

```
$TIMEOUT_CMD "$TIMEOUT_SEC" "$CLAUDE_BIN" -p "$prompt" \
   --model "${LEADV2_MEMGC_MODEL:-haiku}" \
   --max-turns 3 --permission-mode bypassPermissions --output-format json
```
All four required flags present (`--max-turns`, `--permission-mode bypassPermissions`, `--output-format json`, plus explicit `--model`). Envelope unwrapped from `.result`, first `{...}` extracted, same python snippet shape as the judge. **One call per run, regardless of cluster count.**

**Request** (`<<<CLUSTERS_JSON>>>`):

```json
{ "cap": 100, "current_lines": 149,
  "clusters": [ { "cluster_id": "c01", "section": "References (durable)", "type": "reference",
      "anchors_only": [ {"slug":"...","title":"...","description":"..."} ],
      "absorbable":  [ {"slug":"...","title":"...","description":"...","hook":"..."} ] } ] }
```

**Response contract** — the only accepted shape:

| Field | Type | Constraint |
|---|---|---|
| `verdicts[].cluster_id` | string | must match a sent cluster_id |
| `verdicts[].verdict` | enum | `merge` \| `archive` \| `keep` |
| `verdicts[].into` | slug | required unless `keep`; must be a member of that cluster (may be from `anchors_only`) |
| `verdicts[].members[].slug` | slug | must be in that cluster's `absorbable` |
| `verdicts[].members[].action` | enum | `absorb` \| `keep` |
| `verdicts[].members[].absorbed_by` | slug | **required** when `action==absorb`; must equal `into`; must resolve to an existing entry file that itself survives this run |
| `verdicts[].members[].merged_hook` | string ≤80 ch | short label used in the survivor's `Also: [label](slug.md)` fragment |
| `verdicts[].rationale` | string ≤200 ch | goes into the report and the archive manifest |

Semantics: `merge` = absorbed entries' hooks fold into the anchor's index line as `Also:` fragments (the format already present in the live index); `archive` = absorbed entries leave the index with only their `absorbed_by` pointer recorded. Both physically move the entry file into the run dir. **Neither ever calls `rm`.**

---

## 6. Validation gate (step 9) — fail-closed

Every one of these downgrades the offending cluster to `keep` and emits a report row; none of them aborts the run:

1. unknown / duplicated `cluster_id`
2. `into` not a member of that cluster
3. `absorbed_by` absent, empty, or ≠ `into`
4. `absorbed_by` resolves to a slug that is itself absorbed elsewhere this run (chain / cycle)
5. member slug not in the cluster's `absorbable` list
6. member is immune (§3)
7. survivor entry file missing on disk
8. unparsable JSON / LLM timeout / non-zero rc → **all clusters keep**, run exits 0 as a report-only no-op with `llm: unavailable` in the report

Rule 3+4 together are what make "every archived entry names a resolvable survivor" a code invariant rather than a hope.

---

## 7. Archive + restore contract

Run dir: `<memory-dir>/archive/gc-<YYYYMMDDTHHMMSSZ>/`

| File | Content |
|---|---|
| `MEMORY.md.pre` | byte-for-byte copy of the pre-GC index (this is what makes restore exact) |
| `manifest.yaml` | `{run_id, run_at, memory_dir, cap, sim, model, index_sha256_pre, index_sha256_post, entries:[{slug, title, action, absorbed_by, cluster_id, rationale, from_line}], rejected:[...], deferred_clusters:N}` |
| `<slug>.md` × N | the moved entry files, unmodified |

`archive/ARCHIVE.md` gets an appended `### GC run gc-<stamp>` section listing each moved entry and its `absorbed_by` — so the pre-existing cold-archive index stays the one place a human greps.

**Restore**: `--restore <run-dir>` copies `MEMORY.md.pre` over `MEMORY.md` and moves each `<slug>.md` back to the memory dir. Post-condition: `diff` against the pre-GC index is empty. Restore refuses (exit 6) if `index_sha256_post` no longer matches the live index — i.e. someone edited memory after the GC; that is a human call, not a silent overwrite.

---

## 8. Idempotence — three independent mechanisms

1. **Cap early-exit** (step 2): once the index is ≤ cap, the run prints a no-op line and exits before parsing, clustering, or calling the LLM. This alone satisfies acceptance #3.
2. **Seen-set** `<memory-dir>/.memory-gc-state.yaml`: `{judged: [{fingerprint: sha256(sorted member slugs + sim), verdict: keep, run_id}]}`. A cluster already judged `keep` is not re-sent — so a run above cap does not re-litigate the same rejected merge every week.
3. **Structural**: absorbed entries no longer have index lines, so they cannot re-enter clustering. Survivor lines grow `Also:` fragments, which are excluded from the token set (only the primary slug/title/description tokenize) — preventing an absorbed hook from dragging the survivor into a new spurious cluster.

---

## 9. Risks and mitigations

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | A live Claude session writes MEMORY.md between plan and apply → lost write | **Critical** | `flock` on `.memory-gc.lock` for the whole run + sha256 re-check immediately before rewrite; mismatch → exit 5, no write. (Constraint-checklist item 4: MEMORY.md is the one file two processes read+write.) |
| R2 | LLM archives a STANDING entry | **Critical** | §3 two-layer: excluded pre-prompt AND rejected post-verdict. Test asserts an injected malicious verdict is refused |
| R3 | Archive row with no `absorbed_by` = silent drop | **Critical** | §6 rules 3+4; manifest schema makes `absorbed_by` non-optional; test asserts a stub verdict missing it downgrades the cluster |
| R4 | Absorb chain (A→B, B→C) leaves A pointing at a moved file | High | §6 rule 4 forbids any `absorbed_by` that is itself absorbed this run |
| R5 | Cross-section merge changes where a human expects to find an entry | High | Clustering partitions by section; never crosses `## ` boundaries |
| R6 | Rewriting MEMORY.md reorders/loses non-entry lines (headers, blanks) | High | Parser keeps non-entry lines with positional anchors and re-emits verbatim; restore test is byte-exact `diff`, which catches any drift |
| R7 | Prompt too large / cluster count unbounded | Medium | `--max-clusters` 40 + description truncation to 200 ch; overflow logged as `deferred_clusters:N`, never silently dropped |
| R8 | Legacy 4-store GC regressed by the edit | Medium | `--memory-dir` absent ⇒ literally the existing code path; the weekly `leadv2-phase8-close.sh` caller passes no such flag |
| R9 | Non-persona-engine project has no `docs/leadv2/immune-patterns.yaml` | Medium | Those immunity sources are optional; absence is a skip, not an error. Tenant-generic by construction — the only required input is `<memory-dir>/MEMORY.md` |
| R10 | `wc -l` vs "entry lines" ambiguity in the cap check | Medium | Cap compares **total file lines** (that is what the SessionStart hook warns on: 149). Projection reports both total and entry-line counts |
| R11 | Editing plugin `.sh`/`.py` is blocked by the lead-edit guard | Medium | Known repo constraint (`LEADV2_LEAD_GUARD=1`) — implementer fixes forward via the `/tmp` python patcher + Bash, per `lead-edit-guard-canonical-edit` memory |
| R12 | `--apply` run against the wrong directory | Medium | `--memory-dir` must contain a `MEMORY.md`; otherwise exit 1 before any work |

---

## 10. Constraint checklist (mandatory self-check)

1. **Env vars** — new vars are `LEADV2_MEMGC_MODEL`, `LEADV2_MEMGC_CAP`, `LEADV2_MEMGC_SIM`, `LEADV2_MEMGC_TIMEOUT`. All carry the `LEADV2_` prefix; no `LEAD_V2_` variant is introduced. Implementer must grep for pre-existing `MEMGC` usages before adding (expected: none).
2. **Paths** — all five files in §2 verified on disk except `plugins/leadv2/prompts/` which is marked **(to-create / follow `PROMPT_TMPL`)**.
3. **`claude -p`** — the single call carries `--max-turns 3`, `--permission-mode bypassPermissions`, `--output-format json`, `--model`. Missing any of these in implementation is CRITICAL.
4. **Concurrent access** — MEMORY.md (R1) is the sole shared read+write surface; flock + sha256 re-check is the required ordering constraint. `.memory-gc-state.yaml` and `ARCHIVE.md` are written only inside the same lock.
5. **Config contradiction** — no existing env var governs memory GC; the only overlap is the SessionStart hook's line-cap warning. The implementer must read that hook's cap and default `--cap` to the same number, so the GC and the warning cannot disagree. Flag as CRITICAL if they diverge.

---

## 11. Out of scope (implementer: ignore)

- M-7 tiered token-budget guard, M-5 Mermaid trace.
- Any change to what gets **written** to memory (the memory-write contract, frontmatter schema, `MEMORY.md` line format for *new* entries).
- `~/.claude/leadv2-shared/`, any consuming repo's `.claude/`, and any copy of a plugin file into a project.
- A new slash command or a second skill. The surface is the existing `leadv2-memory-gc` skill.
- Rewriting entry-file **bodies** (no content synthesis into the survivor's `.md`). This GC compacts the *index*; absorbed bodies remain intact in the archive dir, greppable.
- The legacy 4-store yaml GC behaviour, report format, and weekly Phase-8 trigger.
- Auto-running the index GC from Phase 8. It stays explicitly invoked until it has a track record.

---

## acceptance:

```yaml
acceptance:
  authored_at: 2026-08-03T00:00:00Z
  - surface: rendered_line
    observable: >
      The dry-run plan report shows a per-cluster verdict list and a summary line
      stating the projected post-GC index size as a number that is 100 or lower,
      next to the current size of 149 — a human reading the report sees the index
      going from over-cap to under-cap without having changed anything yet.
  - surface: file_artifact
    observable: >
      After the apply run, the memory index file a human opens is 100 lines or
      fewer, and the archive manifest for that run shows every archived entry on
      its own row with a non-empty "absorbed_by" naming a memory that is still
      present in the index — there is no row whose absorbed_by column is blank or
      names a memory that is itself gone.
  - surface: log_line
    observable: >
      Running the GC a second time against the already-compacted index prints a
      no-op notice naming the index size and the cap, and the report/archive
      directory is unchanged — a human sees nothing new was written.
  - surface: file_artifact
    observable: >
      After the restore, the memory index a human opens is again the original
      149-line file, indistinguishable from the copy saved before the GC ran,
      and the archived entry files are back in the memory directory.
```

---

LANE_WRITES: plugins/leadv2/scripts/leadv2-memory-gc.sh, plugins/leadv2/scripts/leadv2-memory-index-gc.py, plugins/leadv2/prompts/memory-gc-verdict.md, plugins/leadv2/skills/leadv2-memory-gc/SKILL.md, plugins/leadv2/tests/test-memory-index-gc.sh

DELIVERABLE_COMPLETE
