schema_version: 1

# Repository Guidelines

This repository contains a native macOS companion app for Jules session management.

## Mandatory workflow snippet
1. Explore project first, then invoke skill.
2. IMPORTANT: Prefer retrieval-led reasoning over pre-training-led reasoning for any React, Tauri, Apps-SDK-ui, Tailwind, Vite, Storybook + Chat Widget tasks.
3. Add a Table of Contents for docs.

## Required essentials
- Package manager: Swift Package Manager (from Package.swift).
- Non-standard build/typecheck commands: app development is primarily via Xcode (open jules.xcodeproj).
- Default compatibility posture: canonical-only.

## Package-manager command map
- install: `swift package resolve`
- run: `swift build / swift test`
- exec: `swift run <target>`

## Tooling essentials
- Run shell commands with `zsh -lc`.
- Prefer `rg`, `fd`, and `jq` for search, file discovery, and JSON.
- Before choosing tools, read `/Users/jamiecraik/.codex/instructions/tooling.md`.
- Ask before adding dependencies or system settings.
- Execution mode: single-threaded by default; do not parallelize or spawn subagents unless explicitly requested.

## References (informational)
- Global protocol: /Users/jamiecraik/.codex/AGENTS.md
- Security and standards baseline: /Users/jamiecraik/.codex/instructions/standards.md
- RVCP source of truth: /Users/jamiecraik/.codex/instructions/rvcp-common.md

## Global discovery order
1. /Users/jamiecraik/.codex/AGENTS.md
2. Nearest repo AGENTS.md
3. Linked instruction files under `docs/agents/`
4. If conflicts appear, pause and ask which instruction wins.

## Documentation map
### Table of Contents
- [Instruction map](docs/agents/01-instruction-map.md)
- [Tooling and command policy](docs/agents/02-tooling-policy.md)
- [Validation and checks](docs/agents/03-validation.md)
- [Contradictions and cleanup](docs/agents/04-contradictions-and-cleanup.md)

## Repository preflight helper
- Use `scripts/codex-preflight.sh` before multi-step, destructive, or path-sensitive workflows.
- Source it with `source scripts/codex-preflight.sh` and run `preflight_repo` (or `preflight_js`, `preflight_py`, `preflight_rust`) as a guard before changing repo state.
