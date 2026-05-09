# speccraft dev container.
# Linux-only (devcontainers don't run macOS images). The macOS binaries are
# verified separately via the GitHub Actions release matrix on macOS runners.
FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

ARG GO_VERSION=1.22.6
ARG NODE_VERSION=20

ENV DEBIAN_FRONTEND=noninteractive

# System packages: build chain, test prereqs, helpers.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        jq \
        pkg-config \
        unzip \
        bats \
        ripgrep \
        less \
    && rm -rf /var/lib/apt/lists/*

# Go toolchain (used to build speccraft helper binaries from source inside
# the container — the source-fallback path of install-binaries.sh).
RUN ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" \
       | tar -C /usr/local -xz \
    && ln -s /usr/local/go/bin/go /usr/local/bin/go \
    && ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt

ENV GOPATH=/home/vscode/go
ENV PATH=/home/vscode/go/bin:/usr/local/go/bin:${PATH}

# Node (some aux-agent CLIs are npm-distributed; useful for `claude setup-token`
# style flows; the Claude Code Feature also installs Node, but having a fixed
# version simplifies aux-agent installs).
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

#RUN sed -i '/^::1.*localhost/d' /etc/hosts

# Optional: pre-install Codex/OpenCode if you want real-agent tests in the
# container. Commented out by default to keep the image lean and tests
# hermetic. Uncomment one or both as needed.
# RUN npm install -g @openai/codex
# RUN npm install -g opencode-ai

USER vscode
WORKDIR /workspaces/speccraft
