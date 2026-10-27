#!/bin/bash -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Stop the Buildkite agent started by setup.sh. SIGTERM lets any running job finish first.
pkill -TERM -f "buildkite-agent start" || echo "Buildkite agent is not running."

source ~/.homelab/.venv/bin/activate
# It is expected that vman has already been installed, see README.md

export KUBECONFIG_VMAN=$SCRIPT_DIR/kube.conf
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
