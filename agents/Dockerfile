# Autonomous agent container for this repo. Built by agents/agent.
#
# The toolchain is exactly what `make test` and `make lint` need: Dart SDK,
# uv + Python 3.13, Postgres client + pg_prove, Terraform — plus gh, the AWS
# CLI and Claude Code. No Flutter, no Docker: the database is reached on the
# host (agents/agent --db), never started in here.
FROM ubuntu:24.04

# Keep these at the versions you develop and CI runs with.
ARG DART_VERSION=3.13.1
ARG TERRAFORM_VERSION=1.14.8

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git curl ca-certificates unzip xz-utils zip jq sudo make \
      iptables ipset dnsutils \
      postgresql-client libtap-parser-sourcehandler-pgtap-perl \
 && rm -rf /var/lib/apt/lists/*

# GitHub CLI (issue triage; agents have read-only PATs, so no push risk)
RUN mkdir -p -m 755 /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# Dart SDK, pinned. Archive arch names differ from dpkg's.
RUN arch="$(dpkg --print-architecture)"; case "$arch" in amd64) arch=x64 ;; arm64) arch=arm64 ;; esac \
 && curl -fsSL "https://storage.googleapis.com/dart-archive/channels/stable/release/${DART_VERSION}/sdk/dartsdk-linux-${arch}-release.zip" \
      -o /tmp/dart.zip \
 && unzip -q /tmp/dart.zip -d /opt && rm /tmp/dart.zip
ENV PATH="/opt/dart-sdk/bin:${PATH}"

# Terraform, pinned to what CI runs (terraform-checks.yml).
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_$(dpkg --print-architecture).zip" \
      -o /tmp/terraform.zip \
 && unzip -q /tmp/terraform.zip -d /usr/local/bin && rm /tmp/terraform.zip

# uv — the Python entrypoint (uv.lock is the only install path in this repo)
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Non-root user; sudo is limited to the firewall script and nothing else.
# (Claude Code refuses bypassPermissions as root — non-root is load-bearing.)
RUN useradd -m -s /bin/bash agent \
 && echo "agent ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/agent

USER agent
WORKDIR /home/agent
# UTF-8 by default: Dart and Python print the repo's non-ASCII content (locale
# overlays, em-dashes in prompts) and a C locale mangles it.
ENV PATH="/home/agent/.local/bin:${PATH}" LANG=C.UTF-8 LC_ALL=C.UTF-8

# Python 3.14 (uv.lock resolves for >=3.14; Ubuntu ships 3.12) while the
# build still has an open network.
RUN uv python install 3.14

# Cache dirs pre-created as the agent user: named volumes copy the image's
# ownership on first use, and Terraform refuses a missing plugin cache dir.
RUN mkdir -p /home/agent/.pub-cache /home/agent/.cache/uv /home/agent/.terraform.d/plugin-cache

# AWS CLI v2, user-local. Only useful with `--aws` session creds.
RUN curl -fsS "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o /tmp/awscli.zip \
 && unzip -q /tmp/awscli.zip -d /tmp \
 && /tmp/aws/install --install-dir /home/agent/aws-cli --bin-dir /home/agent/.local/bin \
 && rm -rf /tmp/awscli.zip /tmp/aws

# Claude Code (native installer). Config lives on a named volume so
# auth/session state survives --rm.
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV CLAUDE_CONFIG_DIR=/home/agent/.claude

# Caches on named volumes (see agents/agent) so the second run is fast.
ENV UV_CACHE_DIR=/home/agent/.cache/uv \
    TF_PLUGIN_CACHE_DIR=/home/agent/.terraform.d/plugin-cache \
    TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=1

# Scripts last: they change most often, and here that costs seconds, not a
# toolchain re-download.
COPY --chmod=755 init-firewall.sh /usr/local/bin/init-firewall.sh
COPY --chmod=755 entrypoint.sh /usr/local/bin/agent-entrypoint

ENTRYPOINT ["/usr/local/bin/agent-entrypoint"]
CMD ["bash"]
