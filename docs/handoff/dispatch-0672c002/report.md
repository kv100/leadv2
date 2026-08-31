# PREPASS-MECHANISM-CLOSURE-01 — census falsified

## Disposition

Stopped without changing the estimator/routing mechanism.  The authoritative
prepass requires a stop when its caller census is wrong; implementing the
context-only mission against this checkout would widen scope over work that is
already on the default path.

## Evidence

The prepass says the task judge is not called on the live path and that the
only relevant chain is behind `LEADV2_ROUTER_V2=1`.  The pinned checkout has a
separate default-path caller:

```text
$ rg -n -C 3 '_admission_classify[[:space:]]|TASK_JUDGE_BIN' \\
    plugins/leadv2/scripts/leadv2-dispatch-code.sh plugins/leadv2/scripts/leadv2-backlog-pump.sh
plugins/leadv2/scripts/leadv2-dispatch-code.sh:3514:  estimate="$(PROJECT_ROOT="${PROJECT_ROOT}" bash "${TASK_JUDGE_BIN}" \\
plugins/leadv2/scripts/leadv2-dispatch-code.sh:6082:  _admission_classify "${mission}" "${sig}" "${sig8}" "${task_class}" "${task_class_flagged:-0}"
plugins/leadv2/scripts/leadv2-backlog-pump.sh:703:  estimate="$(PROJECT_ROOT="${CANONICAL_ROOT}" bash "${TASK_JUDGE_BIN}" \\
```

`_admission_classify` maps the resulting `TaskEstimate` to the dispatch class
and route (`Light -> dispatch`, `Standard|Heavy -> phases`), and it runs before
lane registration or any spawn side effect:

```text
$ sed -n '3474,3545p' plugins/leadv2/scripts/leadv2-dispatch-code.sh
# _admission_classify ... Deterministic TaskEstimate->class map
...
estimate="$(PROJECT_ROOT="${PROJECT_ROOT}" bash "${TASK_JUDGE_BIN}" ... )"
...
case "${ADMISSION_CLASS}" in
  Standard|Heavy|Strategic) ADMISSION_ROUTE="phases" ;;
  *)                        ADMISSION_CLASS="Light"; ADMISSION_ROUTE="dispatch" ;;
esac

$ sed -n '6079,6085p' plugins/leadv2/scripts/leadv2-dispatch-code.sh
# lane registration, or spawn side effect. task_class becomes the estimate-
# mapped class ...
_admission_classify "${mission}" "${sig}" "${sig8}" "${task_class}" "${task_class_flagged:-0}"
task_class="${ADMISSION_CLASS}"
```

The prepass's v2-only chain still exists, and it still collapses
`complexity`/`duration_class` into the binary bandit context key at
`leadv2-dispatch-code.sh:2556`.  It is not, however, the only caller of the
judge or the only way an estimate influences a dispatch.  The default
`LEADV2_ROUTER_V2=0` path has the admission caller above, and the backlog pump
has another caller.  This is a material census change, not harmless line
drift.

## Required correction before a new design

Re-census all judge consumers and decide whether the intended change is:

1. to extend the existing admission-class path,
2. to promote v2 to the default resolver while preserving admission semantics,
   or
3. to merge the two estimate flows behind one owned interface.

That decision necessarily changes the mechanism and tests, so it is outside
this prepass's fixed solution space.  No production code, configuration, or
tests were edited in this stopped lane.
