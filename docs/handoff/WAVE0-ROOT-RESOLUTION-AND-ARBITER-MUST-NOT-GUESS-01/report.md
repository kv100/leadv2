# WAVE0-ROOT-RESOLUTION-AND-ARBITER-MUST-NOT-GUESS-01 — report

Lane `518b42814626` (dispatch-cfc95378), 2026-09-09. Rows `518b42814626`
(STATE-PATH-RESOLVER-FAILS-OPEN-UNDER-ZSH-01) and `5d2f022674a6`
(ROUTE-ARBITER-DIES-SILENTLY-ON-LINUX-01). Commit: `f6491694` (+ this
report/artifacts commit).

## Files changed (write set respected)

- `plugins/leadv2/scripts/leadv2-state-path.sh` — +21 lines (fail-closed guard)
- `plugins/leadv2/scripts/lib/leadv2-route-arbiter.sh` — +283/−4 (stdlib YAML-subset loader)
- `plugins/leadv2/scripts/tests/test-state-path-zsh-refusal.sh` — NEW suite (7 cases)
- `plugins/leadv2/scripts/tests/test-route-arbiter-loud-refusal.sh` — NEW suite (4 cases)

Off-limits files untouched (`leadv2-active-registry.sh`, the nine
wave0-lib-silent-swallow files, salvage/deploy-merge). `test-route-arbiter.sh`
was touched intra-lane and restored to HEAD bytes (see §Row 2 — why).

## Row 1 — STATE-PATH-RESOLVER-FAILS-OPEN-UNDER-ZSH-01

### Root cause (re-measured this lane, current bytes)

`leadv2-state-path.sh` resolves its own directory via `BASH_SOURCE[0]`
(SCRIPT_DIR, used to find the sibling `leadv2-portable-lock.sh`). Sourced from
zsh that variable does not exist. Pre-patch probe (HEAD bytes, this lane):

```
zsh -c "source …/leadv2-state-path.sh"   # cwd = scripts dir
rc=127  stderr line 1: …leadv2-state-path.sh:98: BASH_SOURCE[0]: parameter not set
        stderr line 2: …no such file or directory: <cwd>/leadv2-portable-lock.sh
```

That is a refusal wearing a MISLEADING diagnostic (it names a file lookup,
not the unset BASH_SOURCE) — and from a cwd that happens to contain a
`leadv2-portable-lock.sh` the source SUCCEEDS with SCRIPT_DIR pinned to the
caller's cwd: the fail-open shape the row measured on 2026-09-04
(wrong repo-relative `active.yaml`, rc=0).

### Fix

Guard placed BEFORE `set -euo pipefail` (a refused source also leaves the
caller's shell options untouched): if `BASH_VERSION` or `BASH_SOURCE[0]` is
unset → one stderr line `[leadv2-state-path] ABORT rc=4
reason=not_file_backed_bash …`, `return 4` (sourced) / `exit 4` (executed),
zero stdout bytes. Executed and bash-file-sourced resolution unchanged.

### Приёмка probes (verbatim, rc captured unpiped, streams counted separately)

```
A(zsh-source, cwd=scripts) rc=4 stdout_bytes=0 stderr_bytes=504
[leadv2-state-path] ABORT rc=4 reason=not_file_backed_bash: … Refusing to guess. …
B(zsh-source, cwd=/tmp)    rc=4 stdout_bytes=0 stderr_bytes=504
C(bash-exec, cwd=leadv2 repo) rc=0
  stdout=[/Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/active.yaml] stderr_bytes=0
registry under bash -c (the exact 2026-09-04 failing shape):
  stdout=[/Users/kostiantyn.vlasenko/.claude/leadv2-state/leadv2/active.yaml]
```

zsh refuses (never the repo path); bash returns the live state path.

### Suite (green run, whole)

`bash plugins/leadv2/scripts/tests/test-state-path-zsh-refusal.sh` →

```
[TEST] PASS: zsh source from the scripts dir refuses closed (rc=4, stdout empty)
[TEST] PASS: refusal names the real cause, not a bogus portable-lock lookup
[TEST] PASS: zsh source from a neutral cwd refuses closed (rc=4)
[TEST] PASS: executed under bash: control-plane root, not a repo-relative path
[TEST] PASS: sourced from a real bash file context: resolves normally
[TEST] PASS: negative control confirmed: guard-less copy fails OPEN under zsh (rc=0, printed '/var/folders/…/zsh-refusal-mut.fKXthD/state2')
[TEST] PASS: bash -n clean
[TEST] ----------------------------------------
[TEST] RESULTS: 7 passed, 0 failed
```

Registered via `# run-all-triggers: leadv2-state-path` (selected by
`run-all --scope changed`, verified in the selection preview).

### Mutation control (red run)

`leadv2-mutation-control.sh … test-state-path-zsh-refusal.sh
leadv2-state-path.sh '/STATE-PATH-RESOLVER-FAILS-OPEN-UNDER-ZSH-01
(2026-09-09)/,/^fi$/d'` → **MUTATION-CONTROL ok**, red line:

```
[TEST] FAIL: zsh source from the scripts dir: rc=0 out='/Users/kostiantyn.vlasenko/.claude/leadv2-state/.ephemeral/leadv2-mutctl.dkFFR2' err='…leadv2-state-path.sh:99: BASH_SOURCE[0]: parameter not set'
```

The guard-less mutant fails OPEN (rc=0 + a printed path) — exactly the
defect shape. Artifact: `mutation-control/mutation-control/20260909T175450Z-21772.txt`.

## Row 2 — ROUTE-ARBITER-DIES-SILENTLY-ON-LINUX-01

### State on entry (already on main)

The 2026-09-05 half (commit `75634884`, ancestor of this lane's HEAD)
delivered the diagnostics: five mute exits (four bash preconditions via
`_arb_fatal`, one python via `_fatal`) now print a FATAL line naming
reason/detail, and its suite case asserts it. What remained: the platform
difference itself — with the dependency absent a bare Linux image still
could not route, so every arbiter-dependent CI suite stayed meaningless.

### This lane's fix

PyYAML is now OPTIONAL. When `import yaml` fails (or
`LEADV2_ROUTE_ARBITER_YAML_LOADER=stdlib` forces it), a strict stdlib
YAML-SUBSET loader parses both shipped configs — block maps/lists, flow
maps/lists, quoted/plain scalars, `null/true/false`, int/float, comments.
PARSE-OR-REFUSE, never guess: anchors, aliases, tags, merge keys, block
scalars, multi-doc markers, tabs-in-indent raise `_YamlSubsetError` with the
line number → `FATAL rc=2 reason=yaml_subset_unsupported … install PyYAML …`.
Modes: `auto` (default; PyYAML if importable, else subset + one stderr NOTE),
`pyyaml` (demand the real dependency; the 2026-09-05 `pyyaml_missing` hard
rc=2 stays available), `stdlib` (test seam). Invalid pin → named refusal
`yaml_loader_mode_invalid`. Both `yaml.safe_load` call sites (routing yaml,
freepool-arm.yaml floor) go through the same resolved loader.

### Linux measurement (debian:bookworm-slim, docker; rc unpiped, streams counted separately)

Same fixture quota JSON and stubbed probe/gate as the suite; pre-patch bytes
= `git show HEAD:` of the arbiter:

```
### container: debian 12.15, python3 Python 3.11.2, pyyaml: ABSENT (bare image)
===== LEG 1: pre-patch arbiter (HEAD bytes), no PyYAML =====
== before-nopyaml rc=2 stdout_bytes=0 stderr_bytes=207
-- stderr: [route-arbiter] FATAL rc=2 reason=pyyaml_missing detail=ModuleNotFoundError: No module named 'yaml' hint=install PyYAML …
===== LEG 2: patched arbiter (worktree bytes), no PyYAML =====
== after-nopyaml rc=0 stdout_bytes=895 stderr_bytes=194
-- stdout: arm=glm kind=code model=glm-5.3 tier=standard effort=medium reason=capability_fit chain=glm,codex,sonnet,glm-flash …
-- stderr: [route-arbiter] NOTE: PyYAML unavailable … strict stdlib YAML-subset loader active (parse-or-refuse) …
##### apt-get install python3-yaml ##### pyyaml: 6.0
===== LEG 3: patched arbiter, WITH PyYAML (auto) =====
== after-pyyaml rc=0 stdout_bytes=895 stderr_bytes=0
===== LEG 4: pre-patch arbiter, WITH PyYAML (Sep-5 refutation re-check) =====
== before-pyyaml rc=0 stdout_bytes=895 stderr_bytes=0
```

Reading: LEG 1 re-proves the diagnostics half on real Linux with today's
bytes (loud rc=2, not the original 0-byte mute). LEG 2 is the platform-difference
fix: identical call now ROUTES on bare Linux (rc=0, full 895-byte line via the
subset loader + a NOTE naming the fallback). LEG 3 shows the PyYAML path is
byte-identical when the dependency exists; LEG 4 re-verifies the 2026-09-05
refutation (with the dependency present Linux == macOS; it was a dependency,
not a platform bug).

### Suite (green run, whole) + differential

`bash plugins/leadv2/scripts/tests/test-route-arbiter-loud-refusal.sh` →

```
PASS: stdlib YAML-subset loader routes byte-identically to real PyYAML on the real configs
PASS: subset-unsupported yaml refuses loudly (rc=2, stderr names the line), never routes on a guess
PASS: invalid LEADV2_ROUTE_ARBITER_YAML_LOADER value is a named refusal (rc=2, stderr bytes > 0)
PASS: unreadable routing yaml: FATAL rc=65 on stderr, zero decision bytes on stdout
SUMMARY: pass=4 fail=0
```

The differential case runs the SAME call through real PyYAML and the forced
subset loader on the REAL `leadv2-routing.yaml` + REAL `freepool-arm.yaml`
(`floor_mode_source=yaml` in the line proves the freepool file went through
the subset too) and requires byte-identical decision lines, distinct
last-arm state files so nothing couples the two arms.

### Mutation controls (red runs)

```
CONTROL 2 (mute python _fatal stderr write):
MUTATION-CONTROL ok … red_line=FAIL: subset refusal out='WRAP_RC=2' err=''
CONTROL 3 (mute bash _arb_fatal printf):
MUTATION-CONTROL ok … red_line=FAIL: bash-half refusal out='WRAP_RC=65' err=''
```

Both halves of "any non-zero exit prints" are proven red-capable — strip the
diagnostic inside the function body and the suite goes red on empty stderr.
Artifacts: `mutation-control/mutation-control/20260909T175515Z-33343.txt`,
`…20260909T175524Z-36088.txt`.

## Pre-existing reds (measured, not introduced)

`test-route-arbiter.sh` on this lane's tree: `SUMMARY: pass=27 fail=3`
(`standard-cell outputs=…`, `arm_excluded protected=…`, `no_capable_cell
policy=…`). Baseline proof: the same suite run against a scratch copy of the
tree with the PRE-PATCH arbiter (HEAD bytes, my three new cases stripped)
gives `SUMMARY: pass=24 fail=3` — the SAME three cases. They are
capability_fit-policy drift on main, present before this lane's diff; my
change adds +3 green cases (27 = 24 + 3). My s-case additions were then moved
OUT of that suite into the green `test-route-arbiter-loud-refusal.sh` and
`test-route-arbiter.sh` restored to HEAD bytes, so (a) attribution stays
clean and (b) mutation controls have a green baseline (the control tool
refuses `baseline_not_green`). Also pre-existing on this tree:
`test-leadv2-state-path.sh` 8/4 (fails on `docs/leadv2/active.yaml` being
git-tracked at HEAD — `git ls-files` proves it) and
`test-state-path-no-raw-paths.sh` (raw-reference allow-list drift in
`leadv2-status-collector.sh:212`, `leadv2-broad-status.sh:268`,
`hooks/leadv2-single-lead-beat.sh:193` — files this lane never touched;
zero mentions of `leadv2-state-path.sh` in its failure log).
`test-route-arbiter-failure-memory.sh` 14/0 and
`test-route-arbiter-symlink-install.sh` 3/0 are green.

## Falsification set

- `bash -n` on all five shell files touched/added (incl. the restored
  `test-route-arbiter.sh`): clean.
- Embedded arbiter python extracted and `python3 -m py_compile`d: clean
  (no standalone .py changed).
- Mutation controls: 3/3 ok (red lines above).
- Changed-scope runner: `LEADV2_RUN_ALL_SELECT_ONLY=1 bash tests/run-all.sh
  --scope changed` → 51 suites selected, incl. both new suites. Full run
  result: see §Changed-scope run below.

## Changed-scope run

(to be filled by the lane close; see /tmp/runall-changed.log on the work
machine if this section is empty — the run was launched and awaited in the
worker turn)
