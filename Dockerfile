# also consider ubuntu
FROM debian:stable-slim

# PACKAGE PURPOSES
# downloading stuff:        ca-certificates curl
# Claude's sandbox:         bubblewrap socat
# Claude installing stuff:  sudo
# git/github:               git gh openssh-client
# general shellery:         less procps
# dev stuff:                gcc libc6-dev make
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl \
    socat bubblewrap \
    sudo \
    less procps python3 \
    git gh openssh-client \
    gcc libc6-dev make \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash agent \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent
USER agent
WORKDIR /home/agent

RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH "/home/agent/.local/bin:${PATH}"
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
