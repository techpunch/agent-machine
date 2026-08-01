# Managed by the agent-machine cookbook (recipes/have-containers).
#
# The interactive agent image: Claude Code and, once signed in, Codex. Both are the same
# trust tier, so they share this image rather than getting one each — see
# docs/host-agent-design.md, "Containers inside the VM".
#
# Nothing secret is baked in. Credentials arrive at run time on a named volume, because
# image layers leak if an image is ever shared.
FROM debian:bookworm-slim

ARG AGENT_UID=1000
ARG AGENT_GID=1000

RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends \
      ca-certificates curl git openssh-client ripgrep jq less \
    && rm -rf /var/lib/apt/lists/*

# Non-root by default. An agent running as root inside the container is one container
# escape away from being root in the VM, and there is no reason for it here.
RUN groupadd -g "$AGENT_GID" agent \
    && useradd -m -u "$AGENT_UID" -g "$AGENT_GID" -s /bin/bash agent

USER agent
WORKDIR /home/agent

# The native installer, so the image carries no Node runtime of its own.
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/agent/.local/bin:${PATH}"

# /work is where a project is mounted; /home/agent/.claude is the credential volume.
VOLUME ["/home/agent/.claude"]
WORKDIR /work

CMD ["bash", "-l"]
