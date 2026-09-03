# Ten repos from the reel — extracted list

Source: instagram.com/reel/Dcw20sWpLgs/ by `chase.h.ai`, titled **"Top 10 NEW Github Repos for
Claude Users"** (148 s). The caption gates the list behind commenting "agent"; the list itself is
shown on screen in the video. Extracted 2026-09-03 by downloading the reel and reading contact
sheets of its frames — no comment was posted, no message sent.

Method (repeatable): `yt-dlp --cookies-from-browser chrome -o reel.mp4 <url>` then
`ffmpeg -i reel.mp4 -vf "fps=1/3,scale=400:-1,tile=5x5" sheet%d.jpg`. Two sheets, read as two
images instead of ~50. Screenshotting the page does not work — Instagram's video surface returns
a blurred background only.

## The ten

| # | Repo | What it is | Relevant to leadv2? |
|---|---|---|---|
| 1 | **Omarchy** (omarchy.org, by DHH) | "Beautiful, Fun & Agentic Linux" distribution | No |
| 2 | **DeepSeek Harness** (deepseek-ai) | Open-source agent harness, "everything-is-a-plugin" architecture, powered by Cordis. Developer preview, MIT | **Yes — compare to our harness** |
| 3 | **anydoc** | Rust library: Word/PowerPoint/Excel/OpenDocument/RTF → GitHub-Flavored Markdown. Node/Python bindings, WebAssembly demo, ships an **Agent Skill**. Benchmarked against six converters on 100 real documents | Marginal |
| 4 | **herdr** (herdr.dev, Apache-2.0) | CLI, purpose not legible from the frames | Unknown — check |
| 5 | **Orca** | "Run Codex, ClaudeCode, OpenCode or PI **side-by-side — each in its own worktree, tracked in one** place" | **Yes — this is our lane model** |
| 6 | **CLAUDEX LOOP** | "Two AI models harden your plan before a line of code exists — then swap jobs to build it." | **Yes — this is our Phase-2 triad** |
| 7 | **OpenMontage** | "The first open-source, agentic video production system" | No |
| 8 | **OmniRoute** | "The Free AI Gateway — every AI tool → 352 providers → 150+ free — through one endpoint." Claims **~1.51B free tokens/month**, dedupes keys, computes headroom on a dashboard | **Yes — directly touches the quota question** |
| 9 | **Archify** | "From plain English to architecture in seconds." Node.js rendering + validation system for Cursor, Claude Code, Codex CLI and OpenCode; emits HTML/SVG diagrams, deterministic | **Maybe — our systems map** |
| 10 | **Claude of Tanks** | Browser-native armored combat in Three.js, 123 procedural vehicles, 20 battlefields — a demo of what Claude can build | No |

Sponsors shown in-video, not part of the ten: Atlas Cloud, Biome.

## What to look at first, and why

**Orca** and **DeepSeek Harness** answer questions we are actively paying for. Orca's one-line pitch
is the exact problem `CONTROL-PLANE-HAS-NO-OWNER-01` exists to solve — many agents, one worktree
each, tracked in one place. If they solved lane ownership and liveness, we should read how before
building D1–D6.

**OmniRoute** matters for a different open decision: the founder moves to two Max 5x seats on
2026-09-15 and buys Codex on 09-08. A gateway claiming 150+ free models and ~1.51B free
tokens/month is either a real relief valve for worker volume or an overstated aggregator — worth
one hour to find out which, before the 09-15 downgrade rather than after.

**CLAUDEX LOOP** overlaps our Phase-2 planning triad (architect + Codex second brain + critic).
Read for the swap mechanic specifically: they claim the planner and the builder trade roles.

Everything else is either unrelated to an orchestrator (Omarchy, OpenMontage, Claude of Tanks) or a
utility we have no current need for (anydoc). `herdr` is unreadable from the frames — resolve it
from GitHub before judging.

**Nothing here is adopted on the strength of this file.** Each "yes" row still needs the
take/don't-take pass described in the task, with a link to their file and to ours.
