#!/usr/bin/env bash
# Safely shut down the 2-node kubeadm cluster: drain the worker,
# power off the worker, then power off the control plane.
#
# Usage: ./cluster-down.sh [--dry-run] [--yes]
#   --dry-run  run the pre-flight checks only; change nothing
#   --yes      skip the confirmation prompt
set -euo pipefail
source "$(dirname "$0")/cluster-env.sh"

DRY_RUN=0 ASSUME_YES=0
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=1 ;;
    --yes|-y)  ASSUME_YES=1 ;;
    *) die "unknown option: $arg" ;;
  esac
done

log "Pre-flight checks"
kubectl get --raw /readyz >/dev/null 2>&1 || die "API server not reachable (KUBECONFIG=$KUBECONFIG)"
kubectl get nodes

for host in "$KB_CONTROL_HOST" "${KB_WORKER_HOSTS[@]}"; do
  echo "--- $host"
  ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$KB_SSH_USER@$host" true 2>/dev/null \
    || die "cannot SSH to $KB_SSH_USER@$host without a password prompt (check host key / key auth)"
  ssh "${SSH_OPTS[@]}" "$KB_SSH_USER@$host" '
    for s in kubelet containerd; do
      printf "  %-10s %s\n" "$s" "$(systemctl is-enabled $s 2>&1)"
    done
    if [ -n "$(swapon --show 2>/dev/null)" ]; then echo "  SWAP IS ON"; else echo "  swap       off"; fi
  ' | tee /dev/stderr | grep -qE 'SWAP IS ON|disabled|not-found' \
    && warn "$host may not come back cleanly after reboot (see above)" || true
done

if (( DRY_RUN )); then
  log "Dry run complete; nothing was changed"
  exit 0
fi

if (( ! ASSUME_YES )); then
  read -r -p "Drain ${KB_WORKER_NODES[*]} and power off ${KB_WORKER_HOSTS[*]} then $KB_CONTROL_HOST? [y/N] " ans
  [[ $ans =~ ^[Yy]$ ]] || die "aborted"
fi

for node in "${KB_WORKER_NODES[@]}"; do
  log "Draining $node"
  kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout=180s
done

for host in "${KB_WORKER_HOSTS[@]}"; do
  log "Powering off worker $host"
  ssh "${SSH_OPTS[@]}" "$KB_SSH_USER@$host" 'sudo shutdown -h now' || true   # SSH drops as the host goes down
done
for host in "${KB_WORKER_HOSTS[@]}"; do
  wait_until 180 "$host to power off" bash -c "! nc -z -G 3 $host 22 >/dev/null 2>&1" \
    || die "$host still reachable; not shutting down the control plane"
done

log "Powering off control plane $KB_CONTROL_HOST"
vman stop "$KB_CONTROL_HOST"
wait_until 180 "$KB_CONTROL_HOST to power off" bash -c "! nc -z -G 3 $KB_CONTROL_HOST 22 >/dev/null 2>&1" \
  || die "$KB_CONTROL_HOST still reachable after 180s"

log "Cluster is down. After rebooting, start $KB_CONTROL_NODE, then ${KB_WORKER_NODES[*]}, then run ./cluster-up.sh"
