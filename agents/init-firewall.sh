#!/bin/bash
# Egress lockdown for agent containers, modeled on Anthropic's devcontainer
# reference. Default-deny outbound; allow only the hosts the toolchain needs.
#
# Env knobs (set by agents/agent):
#   AGENT_ALLOW_AWS=1      also allow AWS's published ranges for AWS_REGION
#   AGENT_ALLOW_HOST_DB=1  allow the dev Postgres on the host (PGPORT)
#   AGENT_EXTRA_DOMAINS    space-separated extra hosts to allow
#
# Known weakness: domains are resolved once at container start; large CDNs
# rotate IPs, so a long-lived container can start failing egress. Restarting
# the container re-resolves.
set -euo pipefail

ALLOWED_DOMAINS=(
  # Claude Code
  api.anthropic.com claude.ai claude.com platform.claude.com
  console.anthropic.com statsig.anthropic.com code.claude.com downloads.claude.ai
  # Dart: pub get (pub.dev serves package archives off GCS)
  pub.dev pub.dartlang.org storage.googleapis.com
  # Python: uv resolves against PyPI
  pypi.org files.pythonhosted.org
  # Terraform: provider registry + the release host downloads redirect to
  registry.terraform.io releases.hashicorp.com
  # GitHub (issues, python-build-standalone, providers hosted on releases)
  github.com api.github.com codeload.github.com
  objects.githubusercontent.com raw.githubusercontent.com
  # Sentry API
  sentry.io us.sentry.io
)

iptables -F OUTPUT 2>/dev/null || true
ipset destroy allowed 2>/dev/null || true
ipset create allowed hash:net

resolve_into_set() {
  local domain="$1" ip
  for ip in $(dig +short A "$domain" | grep -E '^[0-9.]+$' || true); do
    ipset add allowed "$ip" -exist
  done
}

for d in "${ALLOWED_DOMAINS[@]}" ${AGENT_EXTRA_DOMAINS:-}; do
  resolve_into_set "$d"
done

# GitHub publishes its ranges — cover the fleet, not one DNS answer.
curl -fsS --max-time 15 https://api.github.com/meta \
  | jq -r '(.git + .api + .web)[] | select(contains(":") | not)' \
  | while read -r range; do ipset add allowed "$range" -exist; done || true

if [[ "${AGENT_ALLOW_AWS:-0}" == "1" ]]; then
  curl -fsS --max-time 30 https://ip-ranges.amazonaws.com/ip-ranges.json \
    | jq -r --arg r "${AWS_REGION:-ca-central-1}" \
        '.prefixes[] | select(.region == $r) | .ip_prefix' \
    | while read -r range; do ipset add allowed "$range" -exist; done
fi

iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -j ACCEPT

if [[ "${AGENT_ALLOW_HOST_DB:-0}" == "1" ]]; then
  for ip in $(dig +short A host.docker.internal | grep -E '^[0-9.]+$' || true); do
    iptables -A OUTPUT -d "$ip" -p tcp --dport "${PGPORT:-5432}" -j ACCEPT
  done
fi

iptables -A OUTPUT -m set --match-set allowed dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-port-unreachable

echo "firewall up: $(ipset list allowed -terse | awk '/entries/ {print $4}' || echo '?') allowed networks"
