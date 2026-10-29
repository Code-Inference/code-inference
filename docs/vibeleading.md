# Vibe Leading skills

The project templates bundle the five open-source [Vibe Leading](https://vibeleading.org/)
skills, so every new workspace has them the moment the agent starts. They are
vendored from the upstream repositories at `github.com/VibeLeading/<name>` (MIT,
copyright Jean Machuca), `SKILL.md` and `LICENSE` unchanged apart from a trailing
newline on the licence that the `end-of-file-fixer` hook requires.

| Skill | What it does | Upstream |
|---|---|---|
| `mission-script` | Writes high-fidelity Mission Scripts — strategic intent an agent can execute. Covers the Prompt Ladder. | `VibeLeading/mission-script` |
| `ira-prompting` | The seven Intent-Result Alignment techniques, plus the rubric for scoring a prompt. | `VibeLeading/ira-prompting` |
| `hud-setup` | Designs the scoreboard HUD with IRA thresholds and Circuit Delta targets, replacing the status meeting. | `VibeLeading/hud-setup` |
| `pit-stop-audit` | The monthly Vibe Audit and the Pilot's Final Checklist. | `VibeLeading/pit-stop-audit` |
| `org-geometry` | The Diamond Squad — one Pilot, four Specialists, NPC agents — and how to assign roles. | `VibeLeading/org-geometry` |

`ghw` (git workflow) is bundled the same way; see
[agents.md](agents.md#bundled-skills).

## Where they land

Every template carries the skills at `.agents/skills/<name>/`, the path OpenCode,
Cursor, Codex and Pi read. Claude, Grok Build and Hermes read skills only from
their own dotdir, so `templates/claude-default`, `templates/grok-default` and
`templates/hermes-default` carry a second copy at `.claude/`, `.grok/` and
`.hermes/skills/<name>/`.

`scripts/check-template-sync.sh` compares the agent-specific copies against the
canonical `.agents/` one. Every copy is byte-identical; the same-path check
cannot see copies that live at different paths, hence the second pass.

## Updating a skill

Re-vendor, do not hand-edit one template — the guard would flag the other nine
copies immediately, which is the point. Copy the upstream `SKILL.md` and
`LICENSE` into all ten locations, then run `./scripts/check-template-sync.sh`.
The upstream frontmatter is already spec-compliant (lowercase `name` matching the
folder), so no edit is needed.

## MCP servers are not wired in

[vibeleading.org](https://vibeleading.org/) also ships four MCP servers. They are
documented here but deliberately absent from the templates, because each one
needs something a fresh project does not have:

| Server | Role | Needs |
|---|---|---|
| `mcp-hybrid-data-engine` | SQL + vector + columnar memory hub | Database connection strings |
| `mcp-document-architect` | Read/write the corporate paper trail | Google Workspace or Microsoft 365 credentials |
| `mcp-real-time-scout` | Web and API monitoring for the HUD | API keys for the feeds it watches |
| `mcp-privacy-shield` | Turns PII into tokens before it reaches the model | Data-zone classification policy |

Shipping a `.mcp.json` that points at none of that would start a server that
fails on every call, which is worse than not starting it. Each server is
TypeScript, stdio and MIT-licensed; its repository
(`github.com/VibeLeading/<server>`) documents the `npx` invocation and the
environment variables it expects.

The site's *Agent Quick Start* prompt does the whole setup in one pass: it
installs the skills, writes the MCP configuration (`.mcp.json` for OpenCode,
`claude_desktop_config.json` for Claude Desktop) and asks for the environment
variables.
