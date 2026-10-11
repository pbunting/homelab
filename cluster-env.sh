# Shared settings for cluster-down.sh and cluster-up.sh.
# Override any of these by exporting them before running the scripts.

export KUBECONFIG="${KUBECONFIG_VMAN:-/Users/paulb/Code/VMan/kube.conf}"

KB_SSH_USER="${KB_SSH_USER:-$USER}"          # SSH user on both VMs
KB_CONTROL_HOST="${KB_CONTROL_HOST:-192.168.2.18}"
read -r -a KB_WORKER_HOSTS <<< "${KB_WORKER_HOSTS:-192.168.2.19}"   # space-separated list
KB_CONTROL_NODE="${KB_CONTROL_NODE:-kb0}"    # Kubernetes node names
read -r -a KB_WORKER_NODES <<< "${KB_WORKER_NODES:-kb1}"            # space-separated list

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

port_open() { nc -z -G 3 "$1" "$2" >/dev/null 2>&1; }

# wait_until <timeout-seconds> <description> <command...>
wait_until() {
  local timeout=$1 desc=$2; shift 2
  local start=$SECONDS
  printf '    waiting for %s ' "$desc"
  until "$@"; do
    (( SECONDS - start >= timeout )) && { echo; return 1; }
    printf '.'; sleep 5
  done
  echo " ok ($((SECONDS - start))s)"
}
