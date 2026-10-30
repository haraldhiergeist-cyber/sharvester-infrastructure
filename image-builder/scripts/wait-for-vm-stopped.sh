#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 || $# -gt 5 ]]; then
  echo "usage: $0 <kubeconfig> <context> <namespace> <vm-name> [timeout-seconds]" >&2
  exit 2
fi

kubeconfig="$1"
context="$2"
namespace="$3"
vm_name="$4"
timeout_seconds="${5:-3600}"
start="$(date +%s)"

kubectl_cmd=(
  kubectl
  --kubeconfig="$kubeconfig"
  --context="$context"
)

while true; do
  now="$(date +%s)"

  if (( now - start > timeout_seconds )); then
    echo "ERROR: timed out waiting for VM ${namespace}/${vm_name} to stop" >&2
    echo "Current VM:" >&2

    "${kubectl_cmd[@]}" \
      -n "$namespace" \
      get vm "$vm_name" -o wide >&2 || true

    exit 1
  fi

  status="$(
    "${kubectl_cmd[@]}" \
      -n "$namespace" \
      get vm "$vm_name" \
      -o jsonpath='{.status.printableStatus}' \
      2>/dev/null || true
  )"

  case "$status" in
    Stopped)
      echo "VM ${namespace}/${vm_name} is Stopped; golden-image build completed."
      exit 0
      ;;
    *)
      printf 'waiting for %s/%s: status=%s\n' \
        "$namespace" "$vm_name" "${status:-unknown}"
      sleep 10
      ;;
  esac
done
