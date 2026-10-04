# syntax=docker/dockerfile:1
# Cursor CLI runtime — same dev toolchain as src/opencode-stack, but on a
# Debian base because the Cursor installer bundles a glibc-linked Node
# runtime. Verified: on Alpine/musl it fails with
# "cannot execute: required file not found"; on Debian it runs.
#
# The CLI is installed by its official installer rather than a published image.
# CURSOR_VERSION pins it.
#
# Debian bookworm rather than -slim so the toolchain packages below resolve
# without building Chromium from source.

FROM debian:bookworm

ARG CURSOR_VERSION=2026.10.01

ENV DEBIAN_FRONTEND=noninteractive \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium

# Git + SSH for the agent's git-aware features (push, pull).
# Dev dependencies for linting/formatting (pre-commit, ruff, mypy).
# Chromium and its shared libraries cover the Playwright system deps.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget gnupg unzip \
    git git-lfs openssh-client \
    python3 python3-pip python3-venv pipx \
    nodejs npm \
    golang-go \
    rustc cargo \
    build-essential cmake pkg-config \
    make g++ gcc \
    shellcheck \
    chromium \
    libnss3 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libpango-1.0-0 libcairo2 libasound2 libatspi2.0-0 \
    fonts-liberation fonts-noto-color-emoji \
    xclip \
    && rm -rf /var/lib/apt/lists/*

# The compose plugin is not in bookworm main, so take docker-ce-cli and
# docker-compose-plugin from Docker's own repository. Parity with the Alpine
# stacks, where apk provides docker-cli and docker-cli-compose.
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/docker.list

# GitHub CLI and GitLab CLI ship as .deb from upstream.
RUN curl -fsSL -o /tmp/gh.deb \
      "https://github.com/cli/cli/releases/download/v2.74.0/gh_2.74.0_linux_amd64.deb" \
    && dpkg -i /tmp/gh.deb >/dev/null && rm -f /tmp/gh.deb || true
RUN curl -fsSL "https://gitlab.com/api/v4/projects/17569419/packages/debian/stable/packages.list" \
      -o /etc/apt/sources.list.d/gitlab-cli.list \
    && curl -fsSL "https://packages.gitlab.com/gpg.key" | gpg --dearmor \
      -o /etc/apt/trusted.gpg.d/gitlab-cli.gpg \
    && apt-get update && apt-get install -y --no-install-recommends gitlab-cli \
    && rm -rf /var/lib/apt/lists/* /etc/apt/sources.list.d/gitlab-cli.list \
    || echo ">>> Warn: gitlab-cli unavailable, skipping"

# Python dev tooling. pip is externally managed on Debian, so --break-system-packages.
COPY dev-requirements.txt /tmp/dev-requirements.txt
RUN pip3 install --no-cache-dir --break-system-packages -r /tmp/dev-requirements.txt \
    && pip3 install --no-cache-dir --break-system-packages pre-commit ruff

RUN git init

# Install the Cursor CLI.
#
# The installer builds a versioned tree under
# $HOME/.local/share/cursor-agent/versions/<version>/ containing the launcher
# script, a bundled glibc Node runtime, and bundled JS. The launcher resolves
# its own directory to find those siblings, so the whole version directory is
# copied -- preserving that layout -- rather than the single script.
#
# $HOME/.local/bin/cursor-agent is a symlink back into /root (mode 700), so a
# copied symlink would dangle for the runtime user; the version directory is
# copied instead and /usr/local/bin/cursor-agent execs it. Runtime config and
# credentials live in $HOME/.cursor-agent and $HOME/.config/cursor-agent,
# which are the volumes.
RUN curl https://cursor.com/install -fsS | bash && \
    mkdir -p /opt/cursor-agent && \
    cp -a "$(dirname "$(readlink -f /root/.local/bin/cursor-agent)")/." /opt/cursor-agent/ && \
    chmod -R a+rX /opt/cursor-agent && \
    printf '#!/bin/sh\nexec /opt/cursor-agent/cursor-agent "$@"\n' \
      > /usr/local/bin/cursor-agent && \
    chmod 0755 /usr/local/bin/cursor-agent && \
    cursor-agent --version

# Install deno and bun, both of which self-install to $HOME.
RUN curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh \
    && curl -fsSL https://bun.sh/install | bash \
    && install -m 0755 /root/.bun/bin/bun /usr/local/bin/bun

# Non-root user, named for the agent so two agents never share credentials,
# session history, or settings. Mirrors the agent-prefixed volume names and
# leaves the opencode stack's /home/opencode untouched.
# useradd -r not -S: the Alpine stacks use busybox, where -S means system
# account. Debian's shadow tools spell that -r for both groupadd and useradd.
#
# /etc/skel is emptied first: its .profile contains bash-isms (BASH_VERSION)
# that the shared entrypoint would hit when it sources ~/.profile under
# `set -eu` with dash. The entrypoint writes its own ~/.profile block.
RUN rm -f /etc/skel/.profile /etc/skel/.bashrc /etc/skel/.bash_logout && \
    groupadd -r cursor && \
    useradd -r -m -d /home/cursor -g cursor -s /bin/bash cursor

# XDG dirs that volumes mount over, so ownership is correct even on first run.
RUN mkdir -p \
    /home/cursor/.config/cursor-agent \
    /home/cursor/.local/share/cursor-agent \
    /home/cursor/.local/state/cursor-agent \
    /home/cursor/.cache/cursor-agent \
    /home/cursor/.cursor-agent \
    && chown -R cursor:cursor /home/cursor

# Shared bootstrap: profile, gh auth, git identity, then exec the agent.
COPY src/common/entrypoint.sh /home/cursor/entrypoint.sh
RUN chown cursor:cursor /home/cursor/entrypoint.sh && \
    chmod +x /home/cursor/entrypoint.sh

USER cursor
ENV AGENT_BIN=cursor-agent
WORKDIR /workspace

ENTRYPOINT ["/home/cursor/entrypoint.sh"]