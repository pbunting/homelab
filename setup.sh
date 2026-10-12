#!/bin/bash -x

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check the Buildkite agent token is set (":+set" keeps the token out of "bash -x" traces).
[[ -n "${BUILDKITE_AGENT_TOKEN:+set}" ]] || { echo "BUILDKITE_AGENT_TOKEN is not set."; exit 1; }

# Check Docker is running.
docker info >/dev/null 2>&1 || { echo "Docker is not running. Start Docker."; exit 1; }

source ~/.homelab/.venv/bin/activate
# It is expected that vman has already been installed, see README.md

vman config

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

# "vman list" reports root-owned VMs as stopped when run unprivileged, so ask
# the Qemu monitor via "vman status" instead.
vm_running() {
    $VM_CMD status "$1" 2>&1 | grep -Eq "actual=(running|paused)"
}

# Start a VM unless it is already running. Sets VM_STARTED if it had to start one.
start_vm() {
    if vm_running "$1"; then
        echo "$1 is already running, not starting it"
    else
        VM_STARTED=1
        $VM_CMD start "$1"
    fi
}

# Give freshly started VMs time to boot; skip the wait if none were started.
wait_for_boot() {
    if [[ "${VM_STARTED}" ]]; then
        echo "Waiting ..."
        sleep "$1"
    fi
    VM_STARTED=
}

# Define the machines only if they are not already defined
$VM_CMD list 2>&1 | grep -q "kb0" || KB0_BUILD=1

if [[ "${KB0_BUILD}" ]]; then
    $VM_CMD define kb0 --user-data $SCRIPT_DIR/vms/kb0/user-data --meta-data $SCRIPT_DIR/vms/kb0/meta-data
fi

start_vm kb0 || { echo "Failed to start kb0"; exit 1; }

wait_for_boot 200
$VM_CMD scp kb0 :/home/ubuntu/.kube/config $SCRIPT_DIR/kube.conf
# Under sudo the copy is owned by root; hand it back so kubectl can read it.
[ $(whoami) == "root" ] || sudo chown $(whoami) $SCRIPT_DIR/kube.conf

$VM_CMD list 2>&1 | grep -q "kb1" || KB1_BUILD=1
if [[ "${KB1_BUILD}" ]]; then
    $VM_CMD define kb1 --user-data $SCRIPT_DIR/vms/kb1/user-data --meta-data $SCRIPT_DIR/vms/kb1/meta-data
fi
start_vm kb1

$VM_CMD list 2>&1 | grep -q "kb2" || KB2_BUILD=1

if [[ "${KB2_BUILD}" ]]; then
    $VM_CMD define kb2 --user-data $SCRIPT_DIR/vms/kb1/user-data --meta-data $SCRIPT_DIR/vms/kb1/meta-data
fi
start_vm kb2

wait_for_boot 100

KUBEADM_JOIN_CMD=`$VM_CMD ssh kb0 --command "kubeadm token create --print-join-command" 2>/dev/null| grep kubeadm`
echo "About to attach # $KUBEADM_JOIN_CMD # "
if [[ "${KB1_BUILD}" ]]; then
    $VM_CMD ssh kb1 --command "sudo $KUBEADM_JOIN_CMD"
fi
if [[ "${KB2_BUILD}" ]]; then
    $VM_CMD ssh kb2 --command "sudo $KUBEADM_JOIN_CMD"
fi

# Point cluster-up.sh at this cluster. The VMs get their addresses from DHCP,
# so take the control plane address from the kubeconfig.
export KUBECONFIG_VMAN=$SCRIPT_DIR/kube.conf
export KB_CONTROL_HOST=$(sed -n 's|.*server: https://\(.*\):6443.*|\1|p' $SCRIPT_DIR/kube.conf)
export KB_WORKER_NODES="kb1 kb2"
$SCRIPT_DIR/cluster-up.sh

# Start Buildkite (if not running already)
ps aux | grep -v grep | grep buildkite-agent || ( nohup buildkite-agent start >> ~/.homelab/logs/buildkite.log 2>&1  & )
