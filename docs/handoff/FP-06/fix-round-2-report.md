FP-06 fix-round 2 verification tails:

`test-model-select-telemetry.sh` tail: PASS `(g3)` telemetry row parseable; PASS `(g3)` terminal/cause correct; PASS `(g3)` freepool benched; PASS `(g4)` one telemetry row; PASS `(g4)` row parseable; PASS `(g4)` terminal/cause correct; PASS `(g4)` freepool excluded.

`test-freepool-capability-floor.sh` tail: PASS `(e3)` garbage env falls through to YAML; PASS `(e3)` default is bulk_only; PASS `(e4)` env full journaled; PASS `(e4)` full route picks freepool; PASS `(e4b)` YAML bulk_only journaled. `=== 31 passed, 0 failed ===`
