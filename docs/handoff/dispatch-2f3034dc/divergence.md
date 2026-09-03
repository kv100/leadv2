# MON-PULSE-01 divergence (mini, evidence-driven)
- A. Lead session Monitors (status quo) — REJECTED by todays live failure: race-prone (tail -n 0 missed terminal), dies with session, founder blind.
- B. Revive supervise-loop beat — REJECTED: supervisor retired permanently (founder order 2026-08-17).
- C. SessionStart-hook watcher — REJECTED: fires only when a session starts; lanes run between sessions.
- D. Dispatcher-owned detached watcher + dispatch-armed beat — CHOSEN: lives exactly as long as lanes do, plugin-owned, session-independent.
