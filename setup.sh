#!/bin/bash -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check Docker is running.
docker info >/dev/null 2>&1 || { echo "Docker is not running. Start Docker."; exit 1; }

source ~/.homelab/.venv/bin/activate
# It is expected that vman has already been installed, see README.md

# Check VMan is available
vman -h >/dev/null 2>&1 || { echo "vman is not installed. See README.md."; exit 1; }

# Launch core services on Docker
# Run the OTel stack and the BuildKite agent using Docker Compose.
( cd ~/.homelab; docker compose -f ${SCRIPT_DIR}/homelab-docker/docker-compose.yml up -d )

# Launch VMs and run Kubernetes on VMs
if [ $(whoami) == "root" ]; then
    VM_CMD="vman"
else
    VM_CMD="sudo vman"
fi

# Define the machines only if they are not already defined
vman list 2>&1 | grep -q "kb0" || KB0_BUILD=1

if [[ "${KB0_BUILD}" ]]; then
    $VM_CMD define kb0 --user-data $SCRIPT_DIR/vms/kb0/user-data --meta-data $SCRIPT_DIR/vms/kb0/meta-data
fi
$VM_CMD start kb0 || { echo "Failed to start kb0"; exit 1; }

echo "Waiting ..."
sleep 200
$VM_CMD scp kb0 :/home/ubuntu/.kube/config ./kube.conf

vman list 2>&1 | grep -q "kb1" || KB1_BUILD=1
if [[ "${KB1_BUILD}" ]]; then
    $VM_CMD define kb1 --user-data $SCRIPT_DIR/vms/kb1/user-data --meta-data $SCRIPT_DIR/vms/kb1/meta-data
fi
$VM_CMD start kb1

vman list 2>&1 | grep -q "kb2" || KB2_BUILD=1

if [[ "${KB2_BUILD}" ]]; then
    $VM_CMD define kb2 --user-data $SCRIPT_DIR/vms/kb1/user-data --meta-data $SCRIPT_DIR/vms/kb1/meta-data
fi
$VM_CMD start kb2

echo "Waiting ..."
sleep 100

KUBEADM_JOIN_CMD=`$VM_CMD ssh kb0 --command "kubeadm token create --print-join-command" 2>/dev/null| grep kubeadm`
echo "About to attach # $KUBEADM_JOIN_CMD # "
if [[ "${KB1_BUILD}" ]]; then
    $VM_CMD ssh kb1 --command "sudo $KUBEADM_JOIN_CMD"
fi
if [[ "${KB2_BUILD}" ]]; then
    $VM_CMD ssh kb2 --command "sudo $KUBEADM_JOIN_CMD"
fi

$SCRIPT_DIR/cluster-up.sh

# Start Buildkite (if not running already)
ps aux | grep -v grep | grep buildkite-agent || nohup (buildkite-agent start >> ~/.homelab/logs/buildkite.log 2>&1) >/dev/null &
