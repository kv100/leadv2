verdict: APPROVE
next_action: continue

# architect.summary — PULSE-IS-A-PLUGIN-DUTY-01

The 30-min beat is already plugin-owned; only its delivery is missing.

- `leadv2-broad-status.sh` has zero `URGENT` tags, so the mandated `grep URGENT`
  Monitor filters every beat out — hence session `CronCreate`.
- Fix: one URGENT `BROAD_STATUS_READY` pointer per beat, pump-before-beat order,
  PULSE MODE reworded duty-vs-narration.
- Survives compact + session death (≤10 min, crontab watchdog); not a cron-less host.

Full: architect.full.md
