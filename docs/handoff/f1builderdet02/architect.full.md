# f1builderdet02 — false-green detector, round 2 (four forms)

**Outcome.** The round-1 detector caught 2 of the 9 known adversary artifacts on a full `static-scan` (blind case-2 via `stub`, astra case-4 via `emptygate`, both incidental). After this round every one of the 9 is caught by a scan written for its *form*, none by file or directory name. The build set grew from 20 to 42 checks and is fully green. The detector stays advisory.

Files changed (persona-engine working tree, uncommitted, both still untracked from round 1):

| File | Change |
|---|---|
| `scripts/false-green-detector.py` | +9 scans, heredoc unit model, `--only` help derived from `SCANS`. 501 → ~760 lines. |
| `tests/false-green/run-build-set.sh` | +9 form fixtures, +7 honest controls, +9-artifact regression block (auto-skips when the corpus dir is absent). 232 → ~400 lines. |

Pre-existing dirty files in persona-engine (`docs/tasks.yaml`, `docs/LEAD_V2_STATE.md`, `docs/leadv2/*.md`) are not mine and were not touched. Shared tree `~/Projects/leadv2` untouched. Nothing committed, per mission.

## 1. Measurement

Baseline vs after, full `static-scan` on each artifact directory (all 15 scans, no `--only`):

| Case | Form (README) | Before | After — scan that fires | Detail anchor |
|---|---|---|---|---|
| blind-1 | A | clean | `emptyscan` | line 17 swallows grep failure, line 19 reads empty as clean, no `-d` guard / count |
| blind-2 | original | `stub` (incidental) | `localstub` (+`stub`) | test defines `verify_signature`, sibling `webhook_verify.sh` ships it, never sourced |
| blind-3 | A | clean | `mutantcopy` | line 19 mutates `$TMP_COPY`, suite at line 33 runs original |
| blind-4 | B | clean | `pipestatus` | line 23 `… \| tee`, `$?` at 24, no pipefail |
| astra-1 | A | clean | `shadowdef` | `validate_release` defined at 15 and 23; 23 is a heredoc written to a file and then sourced |
| astra-2 | original | clean | `earlyaccept` | `verify_deployment` `return 0` at 17 precedes reject at 21 |
| astra-3 | V | clean | `cachekey` | `current_key=$(cksum < …)` at 30, no policy/version in key, line 32 short-circuits green |
| astra-4 | B | `emptygate` (incidental) | `noopflag` (+`emptygate`) | `checker_options=(--help)` at 35 forwarded into the `if` at 36 |
| astra-5 | A | clean | `syntaxonly` | `if bash -n policy conf` at 32; trailing args ignored |

**checked/caught:** blind-measure 2/9 → **9/9**. Build set: `checked=42 caught=42 missed=0` (was 20/20). Evidence: the run output in this session, reproduced by `bash tests/false-green/run-build-set.sh`.

## 2. The class rules (what each scan latches onto)

All operate on comment-stripped `(line_no, text)` from the existing `code_lines()`, return a detail string or `None`, and plug into `SCANS` unchanged. Names in `--only` are now generated from `SCANS`.

**Form A — surrogate weaker than claimed / wrong target**

- `syntaxonly`: a parse-only invocation (`bash|sh|zsh|dash|ksh … -n <tgt>`, `py_compile`, `node --check`, `ast.parse(`, `shellcheck`) that is either inside a decision (`if`/`&&`/`||`/`$(`) or coexists with a green emit / `exit 0`, **and** `<tgt>` is never executed or sourced by any other line. Extra tell reported: trailing arguments after the `-n` target (ignored by the shell). An honest "`bash -n` then run" passes because the target is really run later (control `honest-syntax-then-run`).
- `mutantcopy`: `cp|rsync|install <src> <dst>` where `<dst>` is a variable, `/tmp…`, or `mktemp`-derived; a later `sed -i|perl -pi|patch|>>` on `<dst>`; then a suite run (`bash|source|.|pytest|python|npm test|make test` on a path matching `test|spec|suite|check`) that does **not** reference `<dst>` and no copy-back of `<dst>` over `<src>`. Honest control routes the copy into the suite (`RL_IMPL="$TMP_COPY" bash ./test…`).
- `shadowdef`: a function name defined twice in the same *unit*. Unit = the file **minus heredoc bodies**, plus any heredoc body whose target file is later `source`d / `.`-ed by this file (heredoc model below). Also: a literal local `source x.sh` whose file defines a name this file already defines.
- `emptyscan`: a `grep|rg|ag|ack|find|git grep` whose failure is swallowed (`|| true`, `|| :`, `2>/dev/null`), followed within 12 lines by an emptiness test on its result (`-z`, `! -s`, `= ""`, `-eq 0`) that leads to green within 3 lines, in a file with **no** target guard (`-d/-e/-f/-s` test, `checked=`, `population=`, `wc -l`, `ls`). This is `emptygate`'s idea without requiring gate vocabulary in the file name.

**Original form — verdict never reaches the deciding logic**

- `localstub`: file name matches `test|spec|check`; it defines a function that a non-test sibling in the same directory also defines; and the sibling's name (with or without extension) never appears in the test text. Reports "green suite exercised its own copy, not shipped code".
- `earlyaccept`: within a function body, ≥2 accept paths (`return 0`/`exit 0`) and ≥1 reject path (`return N>0`/`exit N>0`/`REJECT`/`FAIL`), with the **first accept textually before the first reject**. Honest verifiers reject early and accept last (control `honest-verifier`).

**Form B — verdict decided, lost on the way out**

- `pipestatus`: file has no `pipefail`/`PIPESTATUS`; a line pipes into a sink (`tee|cat|sort|uniq|head|tail|tr|sed|awk|column|less|more`) as the last stage and is either itself the `if`/`while` condition (or `&&`/`||` after the sink) or is followed within 3 lines by a `$?` read. Lines starting with `echo|printf|cat ` are ignored (not deciding).
- `noopflag`: a runner invocation (`bash|sh|python|node|npx|exec|./x` at a token boundary — a `.sh` extension no longer counts as `sh`, that was the first-run bug) inside a decision, carrying a no-op flag literal (`--help|-h|--version|--dry-run|--noop|--list|--check-only|--print-config`) directly or through a variable/array assigned such a literal earlier (`opts=(--help)`). A bare `bash x --help >/dev/null` outside any decision is not flagged (control `honest-checker-call`).

**Form V — real verdict, stale key**

- `cachekey`: file mentions a policy/version token somewhere (`policy|version|schema|rule|rev|v<digit>|_ver|VER|epoch|generation`); an assignment whose RHS contains a hash command (`cksum|sha*sum|shasum|md5|b2sum|crc32|hashlib.*|hexdigest|xxh*sum`) where **the whole RHS** carries no such token (so `{ echo "$POLICY_VERSION"; cat f; } | cksum` is honest — control `honest-cache`); and a later comparison of that variable (`=`/`==`/`-eq`/`in`/`.get(`) whose next 3 lines emit green, accept, or say `cached|accepted|skip`.

**Heredoc model (shared).** `heredoc_map()` tracks `<<TAG` / `<<'TAG'` / `<<-TAG` bodies and, when the opener redirects to a file (`cat > X <<TAG`), remembers X. `shadowdef` treats a body as a foreign unit (a separate script, as in astra-4/5 which embed a full checker) unless X is later sourced into this file (astra-1). Without this, astra-4 and astra-5 both tripped `shadowdef` on the embedded `contains_line` helper — a plausible-looking but wrong catch that would have masked the real forms.

## 3. Advisory contract (SD-FALSE-GREEN-DETECTOR-STAYS-ADVISORY-01)

Unchanged. `finish()` still returns 0/1/2 for the detector's **own** process only (that is what `run-build-set.sh` asserts on and what existed in round 1); no wrapper, hook, CI step, or dispatch path consumes that code. Nothing added reads `$?` of a caller, writes a gate file, or blocks. The new scans only append to `REPORT` via `emit()`. Fixtures under `tests/false-green/` are hermetic (heredocs into `mktemp -d`), and the 9-artifact regression block is guarded by an `-d` check so the suite does not go red in a checkout without the corpus — the same rule `emptyscan` enforces on others.

## 4. Known limits / false-positive surface (advisory, so tolerable, but worth knowing)

- `earlyaccept` will flag honest "fast-path" functions (`[ -z "$1" ] && return 0` before validation). That is a real review prompt more often than not, but it is noise on option-parsers.
- `shadowdef` cannot see a `source "$VAR"` whose target is dynamic (astra-1 was caught only because the sourced file is materialised in the same script). Cross-file dynamic sourcing stays out of reach for a regex scanner.
- `cachekey` requires the file to *mention* a policy/version token; a stale-key cache in a file that never names the policy dimension passes. The token list is the lever.
- `noopflag` looks one assignment deep; `opts+=(--help)` or a flag set inside a function is missed.
- `localstub` keys on file-name vocabulary (`test|spec|check`) and same-directory siblings only.
- `pipestatus` is file-global on `pipefail`: a `set -o pipefail` anywhere silences it even if scoped in a subshell.
- All scans are line-oriented; a decision split across a multi-line `if` with the sink on a continuation line can slip.

## 5. Process notes

- `context.yaml` did not exist for this task; no `decisions`/`off_limits` to honour beyond the mission text (advisory-only, no shared-tree edits, no commit).
- Delegation was attempted three times (Explore sonnet, Explore haiku, Explore no-model). The spawn-arbiter gate returned `arm=freepool model=freepool-default`, which no `Agent` model satisfies, and the model-guard rejects a spawn without `model=`. The two gates deadlock for recon spawns from a headless subsession. I did the recon and the edits directly to stay inside the 30-call cap (18 calls used). **LEAD_ACTION:** the arbiter's `freepool-default` verdict needs a mapping to a spawnable `model=` (or the model-guard needs to honour an on-record freepool decision); otherwise every subagent that tries to fan out hits this wall.
- Honest round-1 controls still pass under the full 15-scan `static-scan` (`gate-static` runs with no `--only`); the other round-1 controls run with their original `--only` filters, and the seven new controls run under all nine new scans.

## 6. Out of scope (left deliberately)

- Wiring the detector into any hook, CI, or dispatch path (forbidden by the standing decision).
- Python-file coverage for `pipestatus`/`noopflag`/`mutantcopy` (bash-shaped regexes; `syntaxonly`, `shadowdef`, `cachekey`, `earlyaccept` do handle `def` / `hashlib`).
- Re-tuning the round-1 scans (`stub` still fires on blind-2, `emptygate` still fires on astra-4 — harmless duplicates).
- Committing: mission says leave in the working tree.

DELIVERABLE_COMPLETE
