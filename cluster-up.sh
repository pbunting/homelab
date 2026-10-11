#!/usr/bin/env bash
# Bring the cluster back after the VMs have been started (control plane
# first, then worker): wait for the API server and both nodes, uncordon
# the worker, and wait for workloads to become ready.
#
# Usage: ./cluster-up.sh
set -euo pipefail
source "$(dirname "$0")/cluster-env.sh"

log "Waiting for control plane $KB_CONTROL_HOST"
wait_until 300 "API server on $KB_CONTROL_HOST:6443" port_open "$KB_CONTROL_HOST" 6443 \
  || die "API server port not open after 300s; is $KB_CONTROL_NODE running?"
READYZ_CMD="kubectl --kubeconfig $KUBECONFIG get --raw /readyz >/dev/null 2>&1"

wait_until 300 "API server /readyz"  bash -c "${READYZ_CMD}" \
  || die "API server not ready after 300s"

log "Waiting for nodes to be Ready"
kubectl wait node "$KB_CONTROL_NODE" --for=condition=Ready --timeout=300s
for node in "${KB_WORKER_NODES[@]}"; do
  kubectl wait node "$node" --for=condition=Ready --timeout=300s \
    || die "$node not Ready; is the worker VM running?"
done

for node in "${KB_WORKER_NODES[@]}"; do
  log "Uncordoning $node"
  kubectl uncordon "$node"
done

log "Waiting for system pods"
kubectl -n kube-system wait pod --all --for=condition=Ready --timeout=300s
kubectl -n kube-flannel wait pod --all --for=condition=Ready --timeout=300s

log "Waiting for deployments in all namespaces"
kubectl get deploy -A --no-headers -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name |
  while read -r ns name; do
    kubectl -n "$ns" rollout status "deploy/$name" --timeout=300s
  done

log "Cluster status"
kubectl get nodes
kubectl get pods -A -o wide | grep -v -E '\s(Running|Completed)\s' | grep -v '^NAMESPACE' \
  && warn "some pods are not Running (listed above)" || echo "    all pods Running"
