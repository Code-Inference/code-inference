# syntax=docker/dockerfile:1
# OpenCode runtime — adds dev tooling on top of ghcr.io/anomalyco/opencode.
#
# Published to ghcr.io/jeanmachuca/code-inference for pre-built use.
# The compose service builds from this Dockerfile; the pre-built image
# is used via `docker run ghcr.io/jeanmachuca/code-inference` or in CI.
#
# For the recommended CLI workflow, see README.md and docs/installation.md.

ARG OPENCODE_VERSION=2.0.22
FROM ghcr.io/anomalyco/opencode:${OPENCODE_VERSION}

# Git + SSH are needed by opencode's git-aware features (push, pull)
# Dev dependencies for linting/formatting (pre-commit, ruff, mypy)
# Set environment variables to force Playwright to use Alpine's native Chromium
ENV PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium-browser

# Git + SSH are needed by opencode's git-aware features (push, pull)
# Dev dependencies for linting/formatting (pre-commit, ruff, mypy)
RUN apk --update --no-cache add \
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
    cmake \
    build-base

# Copy dev requirements before installing
COPY dev-requirements.txt /tmp/dev-requirements.txt

# Initialize git, install Python dependencies, and set up pre-commit
RUN git init && \
    pip install --no-cache-dir --break-system-packages -r /tmp/dev-requirements.txt && \
    pre-commit install

RUN apk add --no-cache bash gcompat libstdc++ libgcc unzip && \
    curl -fsSL https://bun.sh/install | bash && \
    mv /root/.bun/bin/bun /usr/local/bin/

# Create non-root user for running opencode
RUN addgroup -S opencode && adduser -S -h /home/opencode -G opencode opencode

# Create XDG directories that volumes will mount over (ensures correct
# ownership even when volumes are empty on first run)
RUN mkdir -p \
    /home/opencode/.config/opencode \
    /home/opencode/.local/share/opencode \
    /home/opencode/.local/state/opencode \
    /home/opencode/.cache/opencode \
    && chown -R opencode:opencode /home/opencode

# Entrypoint: sets up profile, gh auth, git identity, then execs opencode
COPY src/opencode-stack/entrypoint.sh /home/opencode/entrypoint.sh
RUN chown opencode:opencode /home/opencode/entrypoint.sh && \
    chmod +x /home/opencode/entrypoint.sh

# Override WORKDIR so the container always opens at the mounted source
WORKDIR /workspace
# Tell Puppeteer to skip the glibc download
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium  

ENTRYPOINT ["/home/opencode/entrypoint.sh"]
