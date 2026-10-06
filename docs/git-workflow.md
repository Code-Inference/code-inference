# Git workflow (normative)

This is the normative document for branching, PRs, releases and tags in this
repository. `.opencode/instructions/git-workflow.md` is the short agent-facing
version loaded into context; where the two differ, this document wins.

**Why this file exists:** the agent instructions referenced `docs/git-workflow.md`
as normative in six places while no such file existed, so the rules agents
follow pointed at nothing. If you change the workflow, change it here first and
then mirror it into the instruction file and the five
`templates/*-default/.opencode/instructions/git-workflow.md` copies.

## 1. Branch model

Two long-lived branches:

| Branch | Role | Receives |
|--------|------|----------|
| `development` | integration branch, the default branch for day-to-day work | merged topic PRs |
| `main` | released, stable | release PRs from `development` only |

Everything else is a topic branch off `development`:

```
feature/<topic>   fix/<topic>   bugfix/<topic>
```

### 1.1 The auto-PR workflow only fires on three prefixes

`.github/workflows/open-pr-to-development.yml` triggers on:

```yaml
branches:
  - "feature/**"
  - "fix/**"
  - "bugfix/**"
```

A topic branch named anything else — `chore/…`, `docs/…`, `refactor/…` — pushes
successfully and then **silently does nothing**: no PR, no CI. Either use one of
the three prefixes, or open the PR yourself with `gh pr create`.

This is the single most common way to lose ten minutes here.

## 2. Branching and PRs

- **Never commit new work directly on `main` or `development`.** Branch from
  `development`, push, and merge by PR.
- Push the topic branch so CI and the auto-PR workflow can act, or open the PR
  directly:

  ```bash
  git fetch origin
  git checkout -b feature/<topic> development
  # ...work...
  git add .
  git commit -m "<clear message>"
  git push -u origin HEAD
  ```

- Merge to `development` by PR after review. Use a **merge commit**, matching the
  repository's history:

  ```bash
  gh pr merge <n> --merge
  ```

  Do not squash: the topic branch's individual commits are the record of how the
  change was built, and the release PRs below are merge commits too.

- **Exception:** if the maintainer explicitly asks for a direct commit or push to
  `development` or `main`, do it and note that it bypasses the topic-branch flow.

### 2.1 Keep merged feature branches (standard)

**Do not delete merged `feature/*`, `fix/*` or `bugfix/*` branches** — not
locally, and not with `git push origin --delete`.

Also disable GitHub's **Settings → General → Pull Requests → Automatically
delete head branches**. The default is off; leave it off.

Rationale: a merged topic branch is the cheapest way to recover the exact
sequence of commits behind a release, and deleting it makes bisecting a
regression that spans several PRs materially harder. The cost is a branch list,
which is cheap. This repository currently carries all 61 branches for that
reason.

## 3. Releases and tags

### 3.1 Tag every feature release (normative)

Every change promoted to `main` gets an **annotated** [SemVer](https://semver.org/)
tag. Not a lightweight tag: `-a`, so the tag carries a message and is identifiable
as intentional.

Version selection:

| Change | Bump | Example |
|--------|------|---------|
| Bug fix, refactor, docs, CI change | PATCH | `v1.5.2` → `v1.5.3` |
| New feature, addition, non-breaking change | MINOR | `v1.5.2` → `v1.6.0` |
| Breaking change (API, config, interface) | MAJOR | `v1.x` → `v2.0.0` |

Tag on `main`, after the release PR merges:

```bash
git checkout main && git pull --ff-only
git tag -a v1.6.0 -m "v1.6.0 — <one-line summary>

<why it changed, and anything a user must do differently>"
git push origin v1.6.0
```

Pushing the tag is what triggers `.github/workflows/publish.yml`, which builds
and pushes the container images to GHCR. See §9.

Never move or overwrite an existing tag. If a release is wrong, cut a new one.

### 3.2 Tag when a feature branch merges to development (normative)

*Optional, and read the caveat first.*

A `vMAJOR.MINOR.PATCH-dev.N` tag on `development` marks an integration point.
This repository has **no such tags**: the practice was never exercised, because
of the caveat below.

> **Caveat — do not push `v*` tags to `development`.** `publish.yml` triggers on
> `tags: ['v*']` regardless of which branch the tag points at. A `-dev.N` tag
> would therefore trigger a real image publish built from `development` — an
> unreviewed, unreleased commit — and push it to the registry under a semver
> tag. If you want integration tags, narrow the workflow trigger to
> `tags: ['v[0-9]*']` with a `ref` filter for `main` first, or drop §3.2
> entirely. Until one of those is done, treat integration tags as unsupported.

## 4. Never rebase

Do not use `git rebase` or `git pull --rebase` in this repository. Prefer a plain
`git pull` (merge).

Merged topic branches are kept and referenced from release notes; rewriting
history makes both harder. When your local branch is behind, `git pull` produces
a merge commit, which is the intended outcome.

## 5. When the maintainer says "sync git"

Meaning: **save local work and push the current branch** — not "skip branching".

1. If you are on `main` or `development` with uncommitted changes, **move the
   work to a topic branch first** (unless a direct push was explicitly asked
   for):

   ```bash
   git fetch origin
   git checkout -b fix/<short-description> development
   ```

   Then bring the commits across.

2. Stage, commit with a clear message, push:

   ```bash
   git add .
   git commit -m "<concise message describing the changes>"
   git push -u origin HEAD
   ```

   Use `-u origin HEAD` when the branch has no upstream yet, otherwise
   `git push`. If there is nothing to commit, still run `git push` if there are
   unpushed commits.

3. **Untracked files:** use `git add .` or add paths explicitly. Do not rely on
   `git commit -a`, which misses new files — the most common way a change
   silently fails to ship.

   > **SSH workaround (macOS host, Linux container):** if a push fails with
   > `Bad configuration option: usekeychain`, strip the macOS-only directive:
   >
   > ```bash
   > cp ~/.ssh/config /tmp/ssh_config && sed -i '/UseKeychain/d' /tmp/ssh_config
   > GIT_SSH_COMMAND="ssh -F /tmp/ssh_config" git push
   > ```

Do not substitute a stash or rebase flow for "sync git" unless asked for a
pull-only or merge-from-remote step.

## 6. What CI enforces

`.github/workflows/ci.yml` runs on any PR or push to `main` or `development`.

| Job | Checks |
|-----|--------|
| `lint` | `shellcheck` over every shell script, both sync guards, `ruff check`, `ruff format --check`, `mypy src/` |
| `test` | `pytest -v` |

Two behaviours that look like failures but are not:

- **`action_required` with zero jobs** means GitHub is holding the run for
  maintainer approval, which it does whenever a PR modifies
  `.github/workflows/**`. It is a pending approval, not a pass. Approve from the
  Actions tab or with
  `gh api -X POST repos/<owner>/<repo>/actions/runs/<id>/approve`.
- **`tests/api/test_postprocessing.py` has 6 known failures** that predate the
  multi-agent work. Confirm the count against `origin/development` before
  treating a failure as your own.

`.github/workflows/main-pr-source.yml` rejects any PR into `main` whose head is
not `development`. That is intentional: `main` is fed only by release PRs.

## 7. Repository settings

For the automated workflows to work:

- **Settings → Actions → General → Workflow permissions:** *Read and write*, and
  *Allow GitHub Actions to create and approve pull requests*. Without this,
  `open-pr-to-development.yml` gets `403 not permitted`.
- **Settings → Pull Requests:** *Automatically delete head branches* **off**
  (§2.1).
- Branch protection may be unavailable on private repos on GitHub Free. The
  process and this document still apply.

## 8. Adding a change

1. `git fetch origin && git checkout -b feature/<topic> development`
2. Make the change, including its tests and docs.
3. Run the gates locally: `pre-commit run --all-files`, or the individual
   commands in [sdlc.md](sdlc.md#code-quality-gates).
4. `git add . && git commit -m "<message describing what changed and why>"`
5. `git push -u origin HEAD` — the auto-PR workflow opens the PR into
   `development`.
6. Merge by PR with a merge commit. Leave the branch in place.

## 9. Release PR and tag automation

The full path from a merged topic branch to a published release.

```
topic branch  ──push──▶  auto-PR  ──▶  PR → development  ──merge──▶  development
                                                                            │
                            release PR: development → main  ◀────────────────┘
                                    │
                          allowed-source-for-main gate + CI
                                    │
                                 merge ──▶  main
                                    │
                     git tag -a vX.Y.Z -m "..."   (on main)
                                    │
                        git push origin vX.Y.Z
                                    │
                    publish.yml triggered by tags: ['v*']
                                    │
              images pushed to GHCR: <version>, <major>.<minor>, latest, <sha>
```

### 9.1 Step by step

```bash
# 1. Topic branch merges into development (automatic PR, or gh pr create)
gh pr merge <topic-pr> --merge

# 2. Wait for CI on development to pass

# 3. Release PR: development -> main
gh pr create --base main --head development \
  --title "release: vX.Y.Z — <summary>" --body "<what changed, why, upgrade notes>"

# 4. Merge it once allowed-source-for-main and CI are green
gh pr merge <release-pr> --merge

# 5. Annotated SemVer tag on main
git checkout main && git pull --ff-only
git tag -a vX.Y.Z -m "vX.Y.Z — <summary>"
git push origin vX.Y.Z
```

### 9.2 What `publish.yml` publishes

Triggers: push to `main`, push of a `v*` tag, or manual dispatch.

Builds every agent stack and pushes to `ghcr.io/<owner>/<repo>` — the path is
derived from `github.repository`, so it follows a repository move with no
change. Tags produced:

| Tag | When |
|-----|------|
| `<version>` (e.g. `1.6.0`) | on a `v*` tag — **no `v` prefix**, `docker/metadata-action` strips it |
| `<major>.<minor>` (e.g. `1.6`) | on a `v*` tag |
| `latest` | only on a push to `main`, and only written by the **opencode** job |
| `<short-sha>` | always |

Agent images carry a suffix: `1.6.0-claude`, `latest-cursor`, and so on. opencode owns the
bare tags.

`latest` is gated on the agent as well as the ref on purpose. With the ref check alone, a tag
push still emitted `latest` from every matrix job, five jobs raced on the one shared tag, and
the last writer won — which left `latest` pointing at the cursor image in v1.7.2. One writer
means no race regardless of what the ref check does.

So `docker pull ghcr.io/<owner>/<repo>:1.6.0`, not `:v1.6.0`. A pull of
`:v1.6.0` fails with `not found` even though the tag exists in git.

Note that `publish.yml` builds on **every** push to `main` as well as on tags,
so a merge to `main` publishes a `:latest` image before the tag exists.

### 9.3 After tagging

- Confirm the workflow succeeded and the image is pullable:

  ```bash
  gh run list --limit 1 --name "Publish image"
  docker pull ghcr.io/<owner>/<repo>:<version>
  ```

- Open the installer URL from `README.md` and confirm it serves the current
  `install.sh`, since a stale `REPO_URL` there makes new installs clone the old
  location.