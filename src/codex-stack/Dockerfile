# syntax=docker/dockerfile:1
# Codex CLI runtime — adds the same dev toolchain as src/opencode-stack on
# top of an Alpine base, then installs the Claude Code CLI.
#
# The CLI is installed by its official installer rather than a published image,
# so there is no FROM to pin. CODEX_VERSION pins it via --release.
#
# Verified on musl/Alpine: the installer fetches an
# x86_64-unknown-linux-musl build, printing e.g. "codex-cli 0.160.0".

ARG ALPINE_VERSION=3.20
FROM alpine:${ALPINE_VERSION}

ARG CODEX_VERSION=0.160.0
ENV CODEX_VERSION=${CODEX_VERSION}

# Env vars are set before the long apk layer so they survive as image config.
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Git + SSH are needed by the agent's git-aware features (push, pull).
# Dev dependencies for linting/formatting (pre-commit, ruff, mypy).
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

RUN apk add --no-cache libstdc++ libgcc unzip && \
    curl -fsSL https://bun.sh/install | bash && \
    mv /root/.bun/bin/bun /usr/local/bin/

# Install the Codex CLI.
#
# The installer writes a versioned tree under /root/.codex and a symlink in
# /root/.local/bin. /root is mode 700, so the whole *release root* is copied to
# a world-readable path, preserving its internal layout -- the binary loads a
# sibling helper (codex-code-mode-host) from its own bin/ directory, so copying
# the ELF alone would break it. Runtime config and credentials go to
# $HOME/.codex, which is the mounted volume.
RUN curl -fsSL https://chatgpt.com/codex/install.sh | sh -s "--release=$CODEX_VERSION" && \
    mkdir -p /opt/codex && \
    cp -a "$(dirname "$(dirname "$(readlink -f /root/.local/bin/codex)")")/." /opt/codex/ && \
    chmod -R a+rX /opt/codex && \
    ln -sf /opt/codex/bin/codex /usr/local/bin/codex && \
    codex --version

# Non-root user, named for the agent. Each stack gets its own user and home so
# two agents never share credentials, session history, or settings. This mirrors
# the agent-prefixed volume names (codex_config, codex_data, ...) and keeps
# the opencode stack's existing /home/opencode and volumes untouched.
RUN addgroup -S codex && adduser -S -h /home/codex -G codex codex

# XDG dirs that volumes mount over, so ownership is correct even on first run.
# ~/.codex holds Codex credentials and config, hence created here.
RUN mkdir -p \
    /home/codex/.config/codex \
    /home/codex/.local/share/codex \
    /home/codex/.local/state/codex \
    /home/codex/.cache/codex \
    /home/codex/.codex \
    && chown -R codex:codex /home/codex

# Shared bootstrap: profile, gh auth, git identity, then exec the agent.
COPY src/common/entrypoint.sh /home/codex/entrypoint.sh
RUN chown codex:codex /home/codex/entrypoint.sh && \
    chmod +x /home/codex/entrypoint.sh

USER codex
ENV AGENT_BIN=codex
WORKDIR /workspace

ENTRYPOINT ["/home/codex/entrypoint.sh"]