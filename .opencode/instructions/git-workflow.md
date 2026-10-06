---
description: Git workflow — follow docs/git-workflow.md; topic branches; no rebase; tags; how to sync
alwaysApply: true
---

# Git workflow (this repo)

**Normative doc:** [docs/git-workflow.md](docs/git-workflow.md). Follow that document for branches, PRs, releases, and tags. Private repos on GitHub Free may **not** enforce branch protection in the UI—**process and this rule** still apply.

## Topic branch prefixes matter

**`.github/workflows/open-pr-to-development.yml` only fires on `feature/**`, `fix/**` and `bugfix/**`.** A branch named anything else (`chore/…`, `docs/…`) pushes fine and then silently does nothing — no PR, no CI. Use one of the three prefixes, or open the PR yourself.

## Branching and PRs (default)

- **Do not** commit new work **directly** on **`main`** or **`development`**. Use a **topic branch** from **`development`**:  
  `git fetch origin` then `git checkout -b feature/<topic> development` (or `fix/<topic>` / `bugfix/<topic>`).
- **Push** the topic branch so CI and **`.github/workflows/open-pr-to-development.yml`** can open a PR into **`development`** (or open the PR via GitHub / `gh pr create`).
- Merge to **`development`** via **PR** after review. Promotion **`development` → `main`** uses the release flow in [docs/git-workflow.md §9](docs/git-workflow.md#9-release-pr-and-tag-automation).

**Exception:** If the user **explicitly** asks to commit or push **directly** to **`development`** or **`main`** (e.g. maintainer emergency), follow their instruction and remind them it bypasses the usual topic-branch flow.

## Never use `git rebase`

Prefer plain **`git pull`** (merge) when updating from remote, unless the user specifies otherwise. Do not use **`git pull --rebase`** or **`git rebase`** for this repo's workflow.

## When the user says "sync git"

Meaning: **save local work and push the current branch** to the remote—**not** "skip branching."

1. If the current branch is **`main`** or **`development`** and there are **new** changes, **prefer** moving work to a topic branch first (unless the user explicitly wants a direct push—see Exception above):  
   e.g. `git fetch origin && git checkout -b feature/<short-description> development`, then bring commits across if needed.
2. Stage, commit with a **clear message**, push:

   ```bash
   git add .
   git commit -m "<concise message describing the changes>"
   git push -u origin HEAD
   ```

   Use `-u origin HEAD` when the branch has no upstream yet; otherwise `git push`. If there is **nothing to commit**, run **`git push`** if there are unpushed commits.

   > **SSH config workaround (Linux container, macOS host):** If `git push` fails with `Bad configuration option: usekeychain`, filter out the macOS-only `UseKeychain` lines:
   > ```bash
   > cp ~/.ssh/config /tmp/ssh_config && sed -i '/UseKeychain/d' /tmp/ssh_config && GIT_SSH_COMMAND="ssh -F /tmp/ssh_config" git push
   > ```

3. **Untracked files:** Use **`git add .`** (or add paths explicitly); do not rely on **`git commit -a`** alone if new files exist.

Do not substitute stash/rebase flows for "sync git" unless the user asks for a pull-only or merge-from-remote step.

## Merged branches

**Do not delete** merged **`feature/*`**, **`fix/*`**, or **`bugfix/*`** branches (local or **`git push origin --delete`**), and **disable** GitHub **"Automatically delete head branches"** unless the user explicitly asks to remove a branch—see [docs/git-workflow.md §2.1](docs/git-workflow.md#21-keep-merged-feature-branches-standard).

## Opening a PR

Use **`.github/workflows/open-pr-to-development.yml`** (push to **`feature/**`**, **`fix/**`**, **`bugfix/**`**), the GitHub UI, or **`gh pr create`**. Provide a clear title and description of the changes.

## Releases and tags

- **Feature releases:** Merge by PR with a **merge commit** (no squash). Then open a **release PR** from **`development`** → **`main`**, merge it once CI and **`allowed-source-for-main`** are green, and add an **annotated** SemVer tag on **`main`**—see [docs/git-workflow.md §9](docs/git-workflow.md#9-release-pr-and-tag-automation) and [§3.1](docs/git-workflow.md#31-tag-every-feature-release-normative). Pushing the tag is what triggers **`.github/workflows/publish.yml`** to build and push the images. (There is **no** `release-to-main.yml` workflow; the flow above is the real one.)
- **Integration tags:** Do **not** push `vMAJOR.MINOR.PATCH-dev.N` tags to **`development`** unless you have first narrowed `publish.yml`'s `tags: ['v*']` trigger—otherwise the dev tag publishes an image built from an unreleased commit. See [docs/git-workflow.md §3.2](docs/git-workflow.md#32-tag-when-a-feature-branch-merges-to-development-normative).
