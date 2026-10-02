#!/bin/sh
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Prompt to create default config files if missing (skip for --help)
case "${1:-}" in
  --help|-h) ;;
  *)
    MISSING=""
    if [ ! -f "./opencode.json" ]; then
      MISSING="$MISSING  - opencode.json                              (provider config — models, instructions, provider URL)\n"
    fi
    if [ ! -f "./AGENTS.md" ]; then
      MISSING="$MISSING  - AGENTS.md                                  (instructions for the AI agent — conventions, commands)\n"
    fi
    if [ ! -f "./.opencode/instructions/git-workflow.md" ]; then
      MISSING="$MISSING  - .opencode/instructions/git-workflow.md     (git workflow rules — branching, PRs, tags, sync)\n"
    fi
    if [ ! -f "./.pre-commit-config.yaml" ]; then
      MISSING="$MISSING  - .pre-commit-config.yaml                    (pre-commit hooks — whitespace, YAML, large files)\n"
    fi
    if [ ! -f "./dev-requirements.txt" ]; then
      MISSING="$MISSING  - dev-requirements.txt                       (dev dependencies — pre-commit, linters, type checkers)\n"
    fi
    if [ ! -f "./.github/workflows/ci.yml" ]; then
      MISSING="$MISSING  - .github/workflows/                         (CI/CD — lint, test, auto-PR, release workflows)\n"
    fi
    if [ -n "$MISSING" ]; then
      echo "Missing config files in $(pwd):"
      printf '%b' "$MISSING"
      printf "Create from templates? [Y/n]: "
      read -r REPLY || true
      case "$REPLY" in
        n|N|no|No) echo "Skipping." ;;
        *)
          if [ ! -f "./opencode.json" ]; then
            cp "$SCRIPT_DIR/templates/default/opencode.json" "./opencode.json"
            echo "Created $(pwd)/opencode.json"
          fi
          if [ ! -f "./AGENTS.md" ]; then
            cp "$SCRIPT_DIR/templates/default/AGENTS.md" "./AGENTS.md"
            echo "Created $(pwd)/AGENTS.md"
          fi
          if [ ! -f "./.opencode/instructions/git-workflow.md" ]; then
            mkdir -p "./.opencode/instructions"
            cp "$SCRIPT_DIR/templates/default/.opencode/instructions/git-workflow.md" "./.opencode/instructions/git-workflow.md"
            echo "Created $(pwd)/.opencode/instructions/git-workflow.md"
          fi
          if [ ! -f "./.pre-commit-config.yaml" ]; then
            cp "$SCRIPT_DIR/templates/default/.pre-commit-config.yaml" "./.pre-commit-config.yaml"
            echo "Created $(pwd)/.pre-commit-config.yaml"
          fi
          if [ ! -f "./dev-requirements.txt" ]; then
            cp "$SCRIPT_DIR/templates/default/dev-requirements.txt" "./dev-requirements.txt"
            echo "Created $(pwd)/dev-requirements.txt"
          fi
          if [ ! -f "./.github/workflows/ci.yml" ]; then
            mkdir -p "./.github/workflows"
            for f in "$SCRIPT_DIR"/templates/default/.github/workflows/*.yml; do
              [ -f "$f" ] || continue
              cp "$f" "./.github/workflows/$(basename "$f")"
              echo "Created $(pwd)/.github/workflows/$(basename "$f")"
            done
          fi
          echo "Customize as needed."
          ;;
      esac
    fi
    ;;
esac

case "${1:-}" in
  --fresh)
    shift
    exec "$SCRIPT_DIR/launch-fresh-opencode.sh" "$@"
    ;;
  --full-isolation)
    shift
    exec "$SCRIPT_DIR/launch-opencode.sh" --full-isolation "$@"
    ;;
  --help|-h)
    echo "Usage: code-inference [--fresh|--full-isolation] [-- opencode-args]"
    echo ""
    echo "Options:"
    echo "  --fresh              Run opencode standalone (no inference stack, persistent named volumes)"
    echo "  --full-isolation     Run opencode via compose with scoped project name (inference, ephemeral)"
    echo "    --disk-name NAME   Use external disk for volumes (default: EXT1TB)"
    ;;
  *)
    exec "$SCRIPT_DIR/launch-opencode.sh" "$@"
    ;;
esac
