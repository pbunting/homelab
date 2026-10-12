#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check the Buildkite agent token is set (":+set" keeps the token out of "bash -x" traces).
[[ -n "${BUILDKITE_AGENT_TOKEN:+set}" ]] || { echo "BUILDKITE_AGENT_TOKEN is not set."; exit 1; }

buildkite-agent stop

source ~/.homelab/.venv/bin/activate
# It is expected that vman has already been installed, see README.md

$SCRIPT_DIR/cluster-down.sh

if [ $(whoami) == "root" ]; then
    VM_CMD="vman"
else
    VM_CMD="sudo vman"
fi

$VM_CMD stop kb0
$VM_CMD stop kb1
$VM_CMD stop kb2

docker compose -f homelab-docker/docker-compose.yml down
