# syntax=docker/dockerfile:1
# Pi coding agent runtime — adds the same dev toolchain as src/opencode-stack on
# top of an Alpine base, then installs Pi.
#
# Pi is published on npm as @earendil-works/pi-coding-agent, so PI_VERSION pins
# the package version. Alpine 3.22 is deliberate: Pi requires Node >= 22.19 and
# that is the first Alpine release whose nodejs package satisfies it (3.21 has
# 22.x too, 3.20 stops at 20.x).
#
# --ignore-scripts is what upstream recommends for a global install; the shipped
# bundle needs no postinstall step.
#
# Verified on musl/Alpine: `pi --version` prints "1.4.0".

ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION}

ARG PI_VERSION=1.4.0
ENV PI_VERSION=${PI_VERSION}

# Pi keeps credentials, sessions and settings under ~/.pi/agent. State the path
# explicitly so the mounted volume and the process agree even if HOME changes.
ENV PI_CODING_AGENT_DIR=/home/pi/.pi/agent

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

# Install Pi from npm. Global installs land in /usr/local (npm's prefix in the
# Alpine package), which every user can read and execute, so no /root copy is
# needed the way Codex's installer required one.
RUN npm install -g --ignore-scripts "@earendil-works/pi-coding-agent@${PI_VERSION}" && \
    pi --version

# Non-root user, named for the agent. Each stack gets its own user and home so
# two agents never share credentials, session history, or settings. This mirrors
# the agent-prefixed volume names (pi_config, pi_data, ...).
RUN addgroup -S pi && adduser -S -h /home/pi -G pi pi

# XDG dirs that volumes mount over, so ownership is correct even on first run.
# ~/.pi/agent holds Pi's credentials, sessions and settings, hence created here.
RUN mkdir -p \
    /home/pi/.config/pi \
    /home/pi/.local/share/pi \
    /home/pi/.local/state/pi \
    /home/pi/.cache/pi \
    /home/pi/.pi/agent \
    && chown -R pi:pi /home/pi

# Shared bootstrap: profile, gh auth, git identity, then exec the agent.
COPY src/common/entrypoint.sh /home/pi/entrypoint.sh
RUN chown pi:pi /home/pi/entrypoint.sh && \
    chmod +x /home/pi/entrypoint.sh

USER pi
ENV AGENT_BIN=pi
WORKDIR /workspace

ENTRYPOINT ["/home/pi/entrypoint.sh"]
