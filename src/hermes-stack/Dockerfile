# syntax=docker/dockerfile:1
# Hermes Agent runtime — adds the same dev toolchain as src/opencode-stack on
# top of an Alpine base, then installs the Hermes Agent CLI.
#
# Hermes publishes the whole agent on PyPI as `hermes-agent`, so the version pin
# is a plain package version rather than an installer argument: HERMES_VERSION
# pins it. The upstream install.sh clones the git checkout and sets up a managed
# Python; installing the published package is reproducible, needs no git clone
# and no managed runtime, and lands `hermes` in /usr/bin.
#
# Verified on musl/Alpine: `hermes --version` prints e.g.
# "Hermes Agent v0.19.0 (2026.7.20)".

ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION}

ARG HERMES_VERSION=0.19.0
ENV HERMES_VERSION=${HERMES_VERSION}

# Hermes sets HERMES_HOME; state, skills and credentials live there. It is the
# volume the launchers mount, so make the path explicit rather than relying on
# $HOME resolving the same way for every user.
ENV HERMES_HOME=/home/hermes/.hermes

# Env vars are set before the long apk layer so they survive as image config.
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Git + SSH are needed by the agent's git-aware features (push, pull).
# Dev dependencies for linting/formatting (pre-commit, ruff, mypy).
# Build tools are needed because some Python dependencies ship no musllinux
# wheel and are compiled locally.
RUN apk --update --no-cache add \
    bash \
    git \
    openssh \
    python3 \
    py3-pip \
    pre-commit \
    xclip \
    ruff \
    nodejs \
    npm \
    deno \
    github-cli \
    git-lfs \
    glab \
    go \
    curl \
    ca-certificates \
    gnupg \
    docker-cli \
    docker-cli-compose \
    # --- Playwright System Dependencies ---
    chromium \
    nss \
    freetype \
    harfbuzz \
    ttf-freefont \
    font-noto-emoji \
    # --- Python build dependencies ---
    libffi-dev \
    openssl-dev \
    # --- Rust Dependencies ---
    rust \
    cargo \
    build-base \
    shellcheck \
    make \
    gcc \
    musl-dev \
    linux-headers \
    cmake

# Copy dev requirements before installing so the pip layer caches independently
# of the rest of the toolchain.
COPY dev-requirements.txt /tmp/dev-requirements.txt

RUN git init && \
    pip install --no-cache-dir --break-system-packages -r /tmp/dev-requirements.txt && \
    pre-commit install

# Install Hermes Agent from PyPI.
#
# Installed as root on purpose: the console script lands in /usr/bin and the
# package in the system site-packages, both readable by the unprivileged runtime
# user. /root is mode 700, so installing into root's home would be unreachable.
# The version is quoted so a PEP 440 pre-release (0.20.0rc1) is not read as a
# shell redirect.
RUN pip install --no-cache-dir --break-system-packages "hermes-agent==${HERMES_VERSION}" && \
    hermes --version

# Non-root user, named for the agent. Each stack gets its own user and home so
# two agents never share credentials, session history, or settings. This mirrors
# the agent-prefixed volume names (hermes_config, hermes_data, ...).
RUN addgroup -S hermes && adduser -S -h /home/hermes -G hermes hermes

# XDG dirs that volumes mount over, so ownership is correct even on first run.
# ~/.hermes holds Hermes state, skills and credentials, hence created here.
RUN mkdir -p \
    /home/hermes/.config/hermes \
    /home/hermes/.local/share/hermes \
    /home/hermes/.local/state/hermes \
    /home/hermes/.cache/hermes \
    /home/hermes/.hermes \
    && chown -R hermes:hermes /home/hermes

# Shared bootstrap: profile, gh auth, git identity, then exec the agent.
COPY src/common/entrypoint.sh /home/hermes/entrypoint.sh
RUN chown hermes:hermes /home/hermes/entrypoint.sh && \
    chmod +x /home/hermes/entrypoint.sh

USER hermes
ENV AGENT_BIN=hermes
WORKDIR /workspace

ENTRYPOINT ["/home/hermes/entrypoint.sh"]
