FROM debian:stable-slim

# PACKAGE PURPOSES
# ca-certificates curl              downloading stuff
# bubblewrap socat                  Claude's sandbox
# sudo                              Claude installing stuff
# git gh openssh-client             git/github
# less procps                       misc shellery
# ripgrep fd-find jq                misc
# patch file tree rsync             misc dev
# build-essential pkg-config        c/rust dev
# libssl-dev                        common native crate dependency
# mold                              fast linker, used for rust
# unzip xz-utils zstd               archives
# python3 python3-venv pipx         python dev
# vim-tiny nano-tiny                editors ($EDITOR, git)
# shellcheck                        linting the shell scripts in here
# buildah                           checking Dockerfile changes
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates bubblewrap curl git less procps python3 socat sudo \
    openssh-client gh \
    vim-tiny nano-tiny ripgrep fd-find jq \
    build-essential pkg-config libssl-dev mold \
    unzip xz-utils zstd patch file tree rsync \
    python3-venv pipx shellcheck buildah \
    && rm -rf /var/lib/apt/lists/*

ENV EDITOR nano-tiny

# ~120MB for buildah plus ~40MB for shellcheck is a real chunk of this image;
# consider removing once claudebox's image is more stable. buildah needs no OCI
# runtime here: only --isolation chroot works in this VM.

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
# Also moves .claude.json in here, so one mount holds all of Claude's state.
# Set before the installer, which otherwise leaves a stray ~/.claude.json.
ENV CLAUDE_CONFIG_DIR /home/agent/.claude

ENV PATH "/home/agent/.local/bin:${PATH}"
RUN curl -fsSL https://claude.ai/install.sh | bash

# Rust via rustup, not apt: Debian's rustc lags and can't switch toolchains.
# clippy and rustfmt only -- rust-analyzer (42MB) is an LSP server nothing in
# here drives, and rust-src (82MB) exists mostly to feed it.
# --component takes one comma-separated value, not a space-separated list.
RUN curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile minimal \
      --component clippy,rustfmt
ENV PATH "/home/agent/.cargo/bin:${PATH}"

# Link with mold; agents iterate on cargo build/test a lot and linking is the
# slow tail of each one. cfg() keeps this arch-agnostic.
RUN mkdir -p /home/agent/.cargo && cat > /home/agent/.cargo/config.toml <<'TOML'
[target.'cfg(target_os = "linux")']
rustflags = ["-C", "link-arg=-fuse-ld=mold"]
TOML
ENV TERM xterm-256color
ENV COLORTERM truecolor

# image/ holds the files copied into the image, one COPY each. Their names
# there are deliberately not the names they land under: a repo file called
# CLAUDE.md would read as instructions to an agent working on claudebox
# itself, and one called .gitconfig gets bind-mounted read-only by Claude
# Code's sandbox, which makes it uneditable and undeletable.
COPY image/claude-CLAUDE.md /etc/claude-code/CLAUDE.md
# Defaults the entrypoint merges into $CLAUDE_CONFIG_DIR, which claudebox
# mounts per project; baking them into ~/.claude would be hidden by that mount.
COPY image/claude-settings.json /etc/claudebox/settings.json
COPY image/claude.json /etc/claudebox/.claude.json
COPY image/entrypoint /usr/local/bin/claudebox-entrypoint
# `gh` as the github credential helper. Contains no secrets: `gh auth
# git-credential` reads from gh's own config, so the container still needs
# `gh auth login` or a GH_TOKEN passed through `container run --env`.
COPY --chown=agent:agent image/gitconfig .gitconfig
# Referenced by gitconfig's core.excludesFile. Hides the files the sandbox
# bind-mounts into the workspace, which `git add -A` otherwise chokes on.
COPY --chown=agent:agent image/gitexclude .gitexclude
# Identity comes from the host's git config, passed by bin/buildbox.
ARG GIT_USER_NAME=
ARG GIT_USER_EMAIL=
RUN if [ -n "$GIT_USER_NAME" ]; then git config --global user.name "$GIT_USER_NAME"; fi; \
    if [ -n "$GIT_USER_EMAIL" ]; then git config --global user.email "$GIT_USER_EMAIL"; fi

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/claudebox-entrypoint"]
# Setting ENTRYPOINT clears the CMD inherited from debian.
CMD ["bash"]
