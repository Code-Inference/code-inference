# Project

<!-- TODO: Describe your project here -->

## Git workflow

See `docs/git-workflow.md` for the SDLC workflow (topic branches, PRs, no rebase, SemVer).
This file is loaded automatically, so read it before committing, pushing or opening a PR.

The same rules ship as the `ghw` skill at `.grok/skills/ghw/SKILL.md`. Agents discover
skills up front but load them on demand, so this file stays the entry point.

## Commands

<!-- TODO: Replace with your project's actual commands -->

| Action | Command |
|--------|---------|
| Install dependencies | `pip install -r requirements.txt` |
| Install dev dependencies | `pip install -r dev-requirements.txt` |
| Install pre-commit hooks | `pre-commit install` |
| Lint | `ruff check .` |
| Format check | `ruff format --check .` |
| Type check | `mypy src/` |
| Run tests | `pytest -v` |

## Conventions

<!-- TODO: Describe your code style conventions -->
