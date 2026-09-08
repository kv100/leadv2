# False-green class detector — design + implementation (f1builderdet01, builder side)

## 0. Deliverables on disk (persona-engine working tree, uncommitted)

| Path | What |
|---|---|
| `/Users/kostiantyn.vlasenko/Projects/persona-engine/scripts/false-green-detector.py` | the detector (Python 3 stdlib, 5 sub-commands, every unit prints `checked=N`) |
| `/Users/kostiantyn.vlasenko/Projects/persona-engine/tests/false-green/run-build-set.sh` | hermetic runner: 7 build-set cases as heredoc fixtures + 6 honest controls + 3 control-for-the-control units |

Run: `bash tests/false-green/run-build-set.sh` → `checked=17 caught=17 missed=0`, rc=0. Shared tree `~/Projects/leadv2` untouched (`git status` there shows no new files from this task besides this handoff).

## 1. The class, stated as something a script can test

Invariant: **a verdict is produced by a path that never reached the logic obliged to decide it.** Every build-set case is one of five mechanical shapes of that invariant. The detector does not look for the symptom (wrong verdict); it looks for the shape (verdict without a deciding edge).

| Shape | Mechanical signature | Build cases |
|---|---|---|
| S1 **Verdict without a deciding edge** | a green token is emitted, and no command result, pipeline, `$(...)`, `$?` or external tool feeds it | 1 |
| S2 **Population of zero read as pass** | a gate iterates a set, never reports `checked=N`, and/or has an explicit `empty → exit 0` edge | 3 |
| S3 **Instrument that measures itself / measures once** | process scan without self-exclusion; a single process sample decides "dead" with no second sample or grace | 4, 7 |
| S4 **Decision with only one reachable value** | the decision variable is assigned only negative (or only positive) literals; an input is read into a variable that nothing consumes | 11 |
| S5 **Field/marker with an empty side of the ledger** | across the codebase, writers=0 or readers=0 for a field or marker; or several readers/writers hold different dictionaries for one concept | 2, 12a, 12b |

Two cross-cutting rules apply to *any* check, including this detector itself:
- **R1 `checked=0` is a hard refusal.** The detector exits 2 (not 0) when it scanned nothing. Its own runner asserts `checked>0`.
- **R2 Every negative control needs a control.** A mutation that "should make the test red" is only evidence if the mutated line demonstrably executed in that very run.

## 2. Sub-commands (interface contract)

Output contract for all sub-commands: one line per unit  
`FGD check=<id> target=<path|name> verdict=PASS|FAIL checked=<n> detail=<why>`  
then a trailer `checked=<sum> units=<k> failed=<f>`. Exit 0 = all PASS, 1 = any FAIL, 2 = the detector checked nothing.

### 2.1 `run-check --log F | --cmd "…" [--positive-control RE] [--require-population]`
Judges a verification's **output** (rule R1 + the "zero carries a positive control" and "sample names its composition" directions).
- FAIL `no-checked-count` — output never says how many units were examined.
- FAIL `checked-zero` — every population examined was empty.
- FAIL `positive-control-absent` — a token that must be visible if the instrument sees anything at all is missing ⇒ a 0 here is blindness, not absence.
- FAIL `population-unnamed` — a size without a composition (`population=…`).
- FAIL `verdict-without-count` — `PASS/OK/GREEN/SUCCESS` printed with no `checked=` behind it.

### 2.2 `static-scan PATH… [--only stub,selfcount,snapshot,emptygate,decision,deadread]`
Judges a check's **source** (`.sh/.bash/.py`, comments and shebang stripped first so policy comments cannot count as code):

| scan | fires when |
|---|---|
| `stub` (S1) | a green token is emitted by `echo/printf/print/cat/tee` and the file has **zero** deciding constructs (`$(`, backtick, `$?`, pipeline, `while read`, `codex/claude/curl/pytest/python/node/ssh/psql/jq/yq`). Argument `case` on `$1` is not a deciding construct — that is exactly what the 16-line mock had. |
| `selfcount` (S3) | `ps … \| grep` or `pgrep -f` with none of: `grep -v grep`, `[p]attern` trick, `$$`/`$PPID`, `pgrep -x`, `--exclude`. |
| `snapshot` (S3) | exactly one process sample (`ps`, `pgrep`, `kill -0`, `/proc/<pid>`, `os.kill(pid,0)`, `psutil.pid_exists`) in a file whose text decides `dead/terminal/stale/gone/orphan/zombie`, and no `sleep/retry/attempt/confirm/grace/resample/range(`. |
| `emptygate` (S2) | file is gate-like (`gate/check/verify/assert/guard/validate/audit` in name or body) and either has `[ -z … ] && exit 0` / `-eq 0 && return 0` / `if not x: return True` (`empty-set-passes`), or loops over a set without any `checked=` emission (`no-population-count`). |
| `decision` (S4) | a variable or `decision:/verdict:/status:/result:` key is assigned only values from NEG={deny,denied,refuse,reject,block,fail,…} → `no-reachable-yes`; only POS → `no-reachable-no`. |
| `deadread` (S4) | a variable assigned from a field read (`$(…)`, `.get(`, `["…"]`, `jq/yq/awk/grep/sed/cut`) is never referenced again in the file. |

### 2.3 `field-census --field NAME | --marker 'LITERAL' [--root DIR…] [--exclude …] [--verbose]` — the separate method for cases 11/12
Grep-based static census over the tree (`.sh .bash .py .js .mjs .ts .tsx .yaml .yml` + shebang files; `.git/node_modules/__pycache__/…` skipped; the detector excludes itself). Per code line:

- **field writer**: `NAME=` (not `==`), `NAME: value` (yaml/printf/heredoc emission), `"NAME":`, `d["NAME"] =`, `--NAME`, `.NAME =` (yq/attr assign), `set_NAME/write_NAME`.
- **field reader**: `$NAME`/`${NAME`, `.get("NAME")`, `d["NAME"]` not followed by `=`, `grep/rg/awk/sed/jq/yq/select … NAME`, `.NAME` read, comparisons (`== NAME`, `NAME -eq`), `if … NAME`, `case … NAME`.
- **marker writer**: marker literal preceded *in the same command segment* (split on `| ; && ||`) by an emit verb (`echo printf print tee write log cat<< >> f" .format json.dump`), or any line inside an open heredoc.
- **marker reader**: marker preceded in its segment by `grep rg awk sed match search find index contains startswith in if case elif assert re` or `-q` / `[[`.
- `\n \t` escapes inside printf strings are normalised to spaces first (otherwise `\nmodel_requested:` hides the identifier — this bit the first run).

Verdicts: `written-never-read` (12a), `read-never-written` (12b — the policy comment is stripped, so it cannot masquerade as a writer), `phantom-field/marker` (neither side). `checked=` is the number of files scanned.

### 2.4 `vocab-census --concept C --fields a,b,c [--root …]` — case 2
Runs the field census for each name that means the same concept, builds a per-file matrix `file[w={…}, r={…}]`, and fails on: `written-never-read` set, `read-never-written` set, `reader-dictionaries-diverge` (readers hold ≥2 distinct read-sets), `writer-dictionaries-diverge`. The divergence itself is the defect, before any symptom — exactly the 161-dead-rows failure, where three readers each knew a subset.

### 2.5 `negative-control --file CODE --line-re RE --cmd "TEST"` — rule R2
Baseline run must be green. Then the first non-comment line matching RE is replaced (backup + restore in `finally`) by  
bash: `{ printf '%s\n' 'FGD_SENTINEL_<rand>' >&2; false; }` / python: `raise RuntimeError("FGD_SENTINEL_<rand>")`  
and TEST re-runs. Verdicts: `never executed` (sentinel absent → the control is vacuous), `no teeth` (executed, rc still 0 → the test does not depend on that line), PASS only when `executed=yes went_red=yes`.

## 3. Build-set run (evidence)

```
== build set ==
case=1   caught=yes  static:stub        unconditional-verdict: green printed at line 7 … 0 deciding constructs
case=2   caught=yes  census:vocab       read-never-written=['status'] | reader-dictionaries-diverge=[terminal_status]<-[reaper.sh,status.sh]; [dead_at]<-[liveness.py]; [status]<-[fanout.sh] | writer-dictionaries-diverge…
case=3s  caught=yes  static:emptygate   empty-set-passes at line 5 | no-population-count: loop at line 6 never reports checked=N
case=3r  caught=yes  run-check          no-checked-count (gate printed "PASS" on write_set: [])
case=4   caught=yes  static:selfcount   lines [2] count processes without excluding the scanner itself
case=7   caught=yes  static:snapshot    one process sample at line 3 decides 'dead' with no second sample or grace
case=11  caught=yes  static:decision    no-reachable-yes: 'decision' only ever set to a negative value
                     static:deadread    'model_requested' read at line 4 and never used
case=12a caught=yes  census:field       written-never-read — writers=1 readers=0 files=2
case=12b caught=yes  census:marker      read-never-written — writers=0 readers=1 (comment mention excluded)
== honest controls (detector must stay quiet) ==
gate-static / count-static / reap-static / arbiter-static / run-check: clean=yes   (5/5)
== negative-control (control for the control) ==
negctl-covering clean=yes · vacuous caught=yes (never executed) · toothless caught=yes (no teeth)
checked=17 caught=17 missed=0
```
Honest controls are the same shapes fixed: a gate that prints `checked=$n population=…` and exits 1 on an empty set; `grep "[g]lm-coder"`; `kill -0` twice with `sleep 2`; an arbiter that can assign `allowed`.

Real-tree probe (persona-engine, 3150 files scanned, rc verbatim):
- `field-census --marker LEADV2-DIRECT-REASON:` → `phantom-marker writers=0 readers=0` — correct for this repo: the marker lives in the plugin repo, which the mission forbids touching.
- `field-census --field model_requested` → `writers=1 readers=1` PASS (post-fix state of the plugin, seen through the `.claude/scripts` symlinks).
- `static-scan --only selfcount,snapshot scripts/*.sh` → 6 FAIL. Spot-checked three: `scripts/auth-resume.sh:78,82` (`pgrep -f "v4-runner"` — matches any `bash -c` wrapper carrying that string), `scripts/leadv2-fanout.sh:1221` (`pgrep -f "/leadv2 ${tid}"`), `scripts/leadv2-lanes-snapshot.sh:608` (`os.kill(pid, 0)` single sample → `terminal`). These are review candidates, not confirmed defects; the scanner's job is to name the shape.

## 4. Where it plugs in (persona-engine only; no plugin edits)

1. **Gate outputs** — any lane gate the lead reads (`review-gate`, `e2e-gate`, `selfcheck`) is piped through `run-check --log … --positive-control <token the gate always prints when it ran>`; a `verdict=FAIL` from run-check overrides the gate's own green.
2. **Pre-review static pass** — `static-scan` over the diff's `.sh/.py` files in the review round; findings land as MEDIUM `false-green-shape` items for the critic.
3. **Schema/registry contracts** — `vocab-census` for every multi-writer concept (`dead`, `terminal`, `owner`, `phase`) runs in `tests/false-green/`, with the field lists pinned in the test so a new writer that invents a fourth name goes red.
4. **New gate authoring rule** — a gate that keys on a field or marker ships with its `field-census` line in the same commit (writers>0 ∧ readers>0), so 12a/12b cannot be re-introduced.

## 5. Risks and known blind spots (the adversary's likely angles)

| Risk | Mitigation / status |
|---|---|
| Regex census misses dynamic keys (`row[key] = …`, `yq ".[$f]"`), so a real reader looks like `readers=0` → false `written-never-read` | census prints `mentions=` and `--verbose` locations; a dynamic access shows up as a mention, and a reviewer must resolve it by hand. Flagged as **UNVERIFIED for dynamic-key code paths**. |
| `stub` needs a *green token*; a mock that returns 0 silently (no PASS text) is invisible to `stub` | covered from the other side by `run-check verdict-without-count / no-checked-count` on the output, and by `negative-control` on the reviewer wrapper (mutating the real reviewer call must turn the review red). |
| `snapshot` counts one sample per *file*; a two-sample liveness split across two files, or a one-sample check inside a loop with `sleep` elsewhere, is misjudged either way | the fail-loud direction is chosen: one sample + death word fires; suppress by adding a second sample or a `grace`/`retry` construct, which is the fix anyway. |
| `decision` only sees literal assignments; `decision=$(arbiter …)` hides the value set | that case is a field-census question: run `vocab-census --fields allowed,denied` on the arbiter's outputs. |
| Cross-repo fields (plugin writes, project reads) split the ledger across two trees | pass both roots: `--root ~/Projects/persona-engine ~/Projects/leadv2/plugins/leadv2` (read-only; no edits). |
| `negative-control` bash mutation assumes the matched line is a whole simple command; a line in the middle of a multi-line pipeline breaks syntax → rc≠0 looks like "teeth" | baseline is green and the sentinel must be *printed*; a syntax error prints no sentinel → reported as `never executed`, i.e. still FAIL, never a false PASS. |
| Detector scans `.claude/scripts` symlinks into the plugin, so persona-engine runs report plugin code | intended for census (the ledger must span both sides); use `--exclude .claude/scripts` for project-only scans. |

## 6. Out of scope for the implementing agent
- No edits under `~/Projects/leadv2` or `~/.claude/leadv2-shared` (mission constraint; the real cases 1/4/11/12 live there and are already fixed on `main` per the recent commits `9de02b18`, `197ece61`).
- No wiring into `tests/run-all.sh` yet; the runner is standalone. Nothing committed.
- No dynamic (AST/taint) analysis; every check is grep/regex by design so it stays readable and Bash-3.2/py3-stdlib portable.

## 7. Self-check against the mandatory checklist
1. Env vars: none introduced. 2. Paths: both deliverable files exist (see §0); fixtures are `(to-create at runtime)` in a `mktemp -d`. 3. No `claude -p` invocations. 4. Concurrent access: `negative-control` rewrites the target file in place and restores from `<file>.fgd-bak`; never run two negative-controls on one file concurrently — the runner is sequential. 5. Config contradictions: none.

DELIVERABLE_COMPLETE
