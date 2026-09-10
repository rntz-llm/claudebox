# also consider ubuntu
FROM debian:stable-slim

# PACKAGE PURPOSES
# downloading stuff:        ca-certificates curl
# Claude's sandbox:         bubblewrap socat
# Claude installing stuff:  sudo
# git/github:               git gh openssh-client
# general shellery:         less procps
# editor ($EDITOR, git):    vim-tiny
# fast search (Claude):     ripgrep fd-find
# JSON wrangling:           jq
# C toolchain, Rust linker: build-essential pkg-config
# native crate deps:        libssl-dev
# archives:                 unzip xz-utils zstd
# misc dev:                 patch file tree rsync
# python envs/apps:         python3-venv pipx
# real editor:              emacs-nox
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates bubblewrap curl git less procps python3 socat sudo \
    openssh-client gh \
    vim-tiny emacs-nox ripgrep fd-find jq \
    build-essential pkg-config libssl-dev \
    unzip xz-utils zstd patch file tree rsync \
    python3-venv pipx \
    && rm -rf /var/lib/apt/lists/*

# Debian names the fd binary `fdfind`; everyone (including Claude) types `fd`.
RUN ln -s /usr/bin/fdfind /usr/local/bin/fd

# Node from the official tarball, resolved to the newest LTS at build time so
# nothing is pinned here. Debian's nodejs is stale and its `npm` unbundles into
# 364 packages. Skips include/ (67MB of addon headers) -- node-gyp downloads its
# own into ~/.cache/node-gyp -- and the top-level docs.
RUN set -eux; \
    version="$(curl -fsSL https://nodejs.org/dist/index.json \
      | jq -r '[.[] | select(.lts != false)][0].version')"; \
    case "$(dpkg --print-architecture)" in \
      amd64) arch=x64 ;; \
      arm64) arch=arm64 ;; \
      *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac; \
    tarball="node-$version-linux-$arch.tar.xz"; \
    cd /tmp; \
    curl -fsSL -O "https://nodejs.org/dist/$version/$tarball"; \
    curl -fsSL "https://nodejs.org/dist/$version/SHASUMS256.txt" \
      | grep " $tarball\$" | sha256sum -c -; \
    tar -xJf "$tarball" -C /usr/local --strip-components=1 --no-same-owner \
      --exclude='*/include' --exclude='*/*.md' --exclude='*/LICENSE'; \
    rm "$tarball"; \
    node --version; npm --version

RUN useradd -m -s /bin/bash agent \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent
USER agent
WORKDIR /home/agent

RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH "/home/agent/.local/bin:${PATH}"

# Rust via rustup, not apt: Debian's rustc lags and can't switch toolchains.
# rust-analyzer + rust-src are what make editors/LSP useful; drop them to save ~150MB.
RUN curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile minimal \
      --component clippy rustfmt rust-src rust-analyzer
ENV PATH "/home/agent/.cargo/bin:${PATH}"
ENV TERM xterm-256color

COPY --chown=agent:agent CLAUDE-TEMPLATE.md .claude/CLAUDE.md
COPY --chown=agent:agent claude-settings-json.json .claude/settings.json
# Avoid prompting for trust of /workspace.
RUN cat > /home/agent/.claude.json <<EOF
{
  "projects": { "/workspace": { "hasTrustDialogAccepted": true } }
}
EOF

WORKDIR /workspace
