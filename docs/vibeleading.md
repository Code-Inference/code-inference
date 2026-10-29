# Vibe Leading skills

The five open-source [Vibe Leading](https://vibeleading.org/) skills are
optional. The project templates ship no skills; `--add-skills` installs them
from the upstream repositories at `github.com/VibeLeading/<name>` (MIT,
copyright Jean Machuca) with the `skills` CLI, so a project gets whatever
upstream publishes today instead of a copy frozen in this repository.

| Skill | What it does | Upstream |
|---|---|---|
| `mission-script` | Writes high-fidelity Mission Scripts — strategic intent an agent can execute. Covers the Prompt Ladder. | `VibeLeading/mission-script` |
| `ira-prompting` | The seven Intent-Result Alignment techniques, plus the rubric for scoring a prompt. | `VibeLeading/ira-prompting` |
| `hud-setup` | Designs the scoreboard HUD with IRA thresholds and Circuit Delta targets, replacing the status meeting. | `VibeLeading/hud-setup` |
| `pit-stop-audit` | The monthly Vibe Audit and the Pilot's Final Checklist. | `VibeLeading/pit-stop-audit` |
| `org-geometry` | The Diamond Squad — one Pilot, four Specialists, NPC agents — and how to assign roles. | `VibeLeading/org-geometry` |

`ghw` (git workflow) comes from
[agentic-framework-skills/GHW](https://github.com/agentic-framework-skills/GHW)
and is installed by the same command.

## Installing

```bash
code-inference --add-skills
code-inference --agent claude --add-skills
```

The flag installs all six sources into the current directory, then launches the
agent. It passes `-y --copy` and an explicit agent list, so every agent gets a
copy where it actually looks:

| Path | Agents |
|------|--------|
| `.agents/skills/<name>/` | OpenCode, Cursor, Codex, Pi |
| `.claude/skills/<name>/` | Claude Code |
| `.grok/skills/<name>/` | Grok Build |
| `.hermes/skills/<name>/` | Hermes |

`--copy` writes real files instead of symlinks, which is what a bind mount into
the container handles predictably. The CLI also writes `skills-lock.json` at the
project root, recording each skill's source; commit it. `npx skills experimental_install`
restores those sources into `.agents/skills/` on a clean clone, but does not recreate the
three native copies.

The CLI is pinned in `start.sh` (`SKILLS_CLI`, default `skills@1.7.4`) and needs
Node.js plus network access on the host. The install is one `npx skills add` per
source, because `skills add` accepts several positional sources but installs only
the first.

To add a single skill, or to update the copies later, run the CLI directly:

```bash
npx skills add VibeLeading/hud-setup -y --copy -a opencode
npx skills update -p
```

Upstream publishes `GHW` with `name: GHW`. The CLI lowercases the folder to
`ghw/` but leaves the frontmatter field unchanged, and OpenCode requires `name`
to match the directory and be lowercase — so after an install, edit that field
to `ghw` if the skill does not appear in the agent's skill list.

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
