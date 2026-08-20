---
name: leadv2-supervise
description: "[internal] Retired 2026-08-17 (founder order, SUPERVISOR-DELETE-01). Refuse to run this mode."
allowed-tools:
  - Read
---

# Lead v2 Supervise Mode — retired

This mode was retired 2026-08-17 (founder order, SUPERVISOR-DELETE-01). The
standalone supervisor loop/pick/watchdog daemon no longer exists. If invoked,
refuse to run it and point the founder at `scripts/leadv2-lanes-snapshot.sh`,
which now owns lane reconciliation.
