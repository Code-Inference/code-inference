# Workspace

**This root is scaffolding, not code.**

It exists to hold independent project repositories side by side and to give every
agent working in it the same conventions. Do not add application code here.

## What this scaffold is

- The root tracks only scaffolding: these instructions, the git workflow, CI
  templates, pre-commit config, dev requirements, the bundled skills and
  `opencode.json`. There is no project code at the root, and none belongs there.
- **Every subfolder is a standalone git repository** with its own language,
  framework, CI and instruction file. The root repository does not track them.
- `.gitignore` ignores every root subfolder (`/*/`) and re-includes only the
  scaffolding directories. That is what keeps projects independent: cloning,
  branching and committing inside `./api` never touches the workspace repo.
- A subfolder's own instruction file adds to these rules. It must not contradict
  the git workflow below, which applies to every repository in the workspace.

## Working in the workspace

- Clone or create projects **inside** the root, one directory per repository:
  `gh repo clone owner/repo ./repo` or
  `git clone git@github.com:owner/repo.git ./repo`.
- Run git commands from inside the project directory, not from the root. The
  root repo only tracks the scaffold.
- The root's only dev tool is `pre-commit`:
  `pip install -r dev-requirements.txt && pre-commit install`. Each project
  defines its own lint, format, test and type-check commands.
- Use `/tmp` (or a temp subdirectory under the root) for throwaway files, never
  the root itself.

## Git workflow

See `docs/git-workflow.md` for the full workflow: topic branches from
`development`, PRs, no rebase, SemVer tags and SSH-only auth. It applies to every
repository here, including each project subfolder.

The same rules ship as the `ghw` skill under `.agents/skills/ghw/`; skill-aware
agents discover it without being told to read a document. Skills are loaded on
demand, so this file remains the entry point — read it, and
`docs/git-workflow.md`, before committing, pushing or opening a PR.

## Bundled skills

`.agents/skills/` ships `ghw` (git workflow) and the five Vibe Leading
methodology skills: `mission-script`, `ira-prompting`, `hud-setup`,
`pit-stop-audit` and `org-geometry`. Claude, Grok Build and Hermes read skills
from `.claude/`, `.grok/` and `.hermes/skills/` instead — the same copies, so
whichever agent you launch finds them.

## CI templates

`.github/workflows/` holds the workspace repository's own workflows:

- `open-pr-to-development.yml` — opens a PR when a `feature/*`, `fix/*` or
  `bugfix/*` branch is pushed.
- `main-pr-source.yml` — rejects PRs to `main` that do not come from
  `development`.
- `ci.yml` and `publish.yml` — placeholders. Each project subfolder replaces them
  with its own, and the root's copies stay inert.

Enable "Read and write permissions" for Actions in the repository settings, or
the auto-PR workflow cannot open pull requests.
