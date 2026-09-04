# Census — PHASE-GATE-DEFAULT-CLASS-ESCAPES-IT-01 (2026-09-04)

Source of truth: `plugins/leadv2/scripts/leadv2-dispatch-code.sh` @ lane HEAD (75f72daa),
read at `:3731-3743`, `:4083-4086`, `:4147-4246`, `:7196-7197`, `:7236-7238`, `:7372`,
`:7384`, `:8230-8235`, `:8565-8594`; `plugins/leadv2/scripts/leadv2-phase-record.sh`
`_phase_class_level` `:195-226`, `cmd_assert` `:819-1013`; `lib/leadv2-lane-guard.sh`
`_lv2_class_canonical` `:10-15`.

## 1. Every class each classifier can emit → gate mode → journal line

There are TWO classifiers; only the second one feeds the phase gate.

**A. `classify_product_work` (dispatch-code.sh:3731-3743) → `product` | `non_product`.**
Journaled at :7238 (`dispatch_classified task= class= reason= kind=`), ALWAYS, before
any spawn side effect. This class **never reaches `_phase_precondition_guard`** — the
guard is called with `task_class` (:7372) / `_adv_class` (:8594), i.e. the admission
class, not the product class. So "product passes the gate" is not literally possible;
what the founder saw on dispatch-96d97702 was `dispatch_classified class=product` next
to a Standard admission (`task_class=Standard route=phases source=flag`).

**B. admission class (`_admission_classify` :7196 → canonicalized :4083-4086) → exactly
`Light | Standard | Heavy | Strategic`.** Anything the judge/explicit flag produces is
canonicalized; the `*` arm maps to `Light`. This is the only vocabulary the gate sees
on the cmd_resolve path. The advance-arm path (:8568-8587) reads the class **verbatim
from the dispatch-ledger row / task receipt / brain.yaml with no canonicalization** —
measured live: dispatch-4ab257f9's router lines carry `task_class=heavy` lowercase.

| class at the gate | mode (env `LEADV2_REQUIRE_PHASES` unset, D3 default) | scope | journal line written? |
|---|---|---|---|
| Standard | enforce (mode=1) | pre-build | only on refusal / config-error / unexpected rc; **pass = silence** |
| Heavy | enforce (mode=1) | pre-build | same — **pass = silence** |
| Strategic | enforce (mode=1) | pre-build | **never dispatchable**: phase-record `assert` rejects the class itself (`:846-849` valid set `Trivial\|Light\|Standard\|Heavy`) → rc=4 → guard refuses as `phase_precondition_config_error` |
| Light | warn | full | `phase_precondition_warn task= class= missing= mode=warn` — but **only when rc=3**; satisfied pass = silence |
| anything non-canonical (e.g. ledger-borne `heavy`, `garbage`) | **warn** (exact-case `case` at :4166 misses) | full | as Light — and lowercase classes then also die in assert's own validation |
| Trivial | warn (unreachable on cmd_resolve: canonicalizer never emits it) | full | — |
| any class, `LEADV2_REQUIRE_PHASES=0` | kill switch | — | byte-identical silence (deliberate, :4152) |
| any class, `=warn` / `=1` explicit | unchanged pre-D3 semantics | full | as above |

Passage visibility summary: **no mode ever journaled a successful passage.** Bootstrap
admission (fresh lane, zero records, pre-build scope — phase-record.sh:999-1006 exits 0)
was supposed to journal `phase_precondition_bootstrap` via phase-record's `_emit`
(:1005), but `_emit` invokes `leadv2-journal.sh <event> <detail>` while the real CLI is
`append <task-id> <type> <text>` (leadv2-journal.sh:3-5) — the event dies in
`>/dev/null 2>&1 || true`. The e2e suites never noticed because their journal stubs are
argv-agnostic `echo "$@"` (test-phase-precondition.sh:276-279,
test-phase-precondition-bootstrap.sh:45-50). A passing stub, a dead line.

## 2. Why `product` exists — and it IS load-bearing

`product_class == "product"` is read downstream at:
- :7384-7431 — the architect-prepass loop (retry → park, PREPASS-RETRY-THEN-PARK-01)
  and the plan-phase record;
- :8230-8235 — `spawn_product_close` (cross-provider review + e2e gate).

So the classifier default must NOT change (PRODUCT-READINESS-GATES-01: "unknown means
product and gets all three gates"). The gate's set is what changes — fix (A) closes the
exact-case/permissive-default hole inside `_phase_precondition_guard`, not the
classifier. `product` is not read by any ladder; it was never the phase-gate input.

**Separate finding (named, not fixed):** `Strategic` sits in the gate's enforce set
(:4167) but is rejected by `assert`'s own class validation — an explicit
`--task-class Strategic` dispatch is refused with `phase_precondition_config_error`
before any phase question is asked. No live Strategic dispatch exists in
docs/leadv2/tasks/ (grep, 2026-09-04). Out of this lane's scope (fixing it means
teaching the phase table a fifth class).

## 3. G1 (`journal should contain phase_precondition_warn`) — verdict

Suite re-run on lane HEAD: **pass=79 fail=0, RC=0** — G1 is GREEN. The premise "G1 уже
красная" does not reproduce on HEAD (the 8/4 red baseline in memory predates it). G1
stays green because `--kind tooling` + its mission admission-classifies as **Light** →
warn mode → full-scope assert rc=3 (classify/build/test/review/close mandatory for
Light) → the warn line fires. The red the founder inferred from live journals is real
but lives elsewhere: enforced-class passages (bootstrap + satisfied) leave no line at
all — which is exactly fix (B).

## 4. Live lanes that passed the gate silently (24h window)

Method: every `docs/leadv2/tasks/*/journal.md` in the live leadv2 checkout; window
`2026-09-03T17:01Z .. 2026-09-04T17:02Z` (time of measurement); a lane counts if it has
≥1 `dispatch_classified` line in-window; it "escaped" if it has 0 `phase_precondition*`
lines in-window.

**77 lanes dispatched in-window; 31 (40%) left zero phase_precondition trace.** The 31:
04841c4f, 0591e643, 07401216, 0a699fc6, 1197b130, 15a3abee, 1cba2dfa, 2236d405,
23221626, 271bdd7d, 3011c36c, 362205f9, 4ab257f9, 52e3c5ba, 5fb5add1, 75c06b61,
7d442bf7, 8f5611ba, 96d97702, 9df0851b, 9e1f4297, a5f20647, a7c512b8, ab933592,
af1f1d6e, beee6495, c064956c, ca94be73, e2e9bf0c, e3cec9b5, e525df4d. All are
Standard/Heavy (the ENFORCED classes): fresh dispatches admitted by the bootstrap
exemption (dispatch-96d97702 has no `docs/handoff/dispatch-96d97702/phases.d/` at all)
or re-entries whose records satisfied the assert — both rc=0, both silent. Every Light
lane in-window left a warn trace. The hole is not "some tasks skip the gate"; it is
"the gate's permissive spelling default + its invisible passes".
