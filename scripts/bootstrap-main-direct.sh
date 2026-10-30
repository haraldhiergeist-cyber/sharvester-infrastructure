#!/usr/bin/env bash
set -euo pipefail

umask 077

DEST_KUBECONFIG="${HOME}/.kube/config"
SSH_USER="harald"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

RANCHER_KUBECONFIG="${TMPDIR}/rancher-main.yaml"
RKE2_KUBECONFIG="${TMPDIR}/rke2.yaml"
DIRECT_KUBECONFIG="${TMPDIR}/main-direct.yaml"
MERGED_KUBECONFIG="${TMPDIR}/merged.yaml"

echo "==> Ermittle kube-vip-Adresse aus OpenTofu"

VIP="$(tofu output -raw main_api_vip)"

if [[ -z "${VIP}" ]]; then
  echo "Fehler: main_api_vip konnte nicht ermittelt werden." >&2
  exit 1
fi

echo "    API VIP: ${VIP}"

echo "==> Extrahiere Rancher-Kubeconfig für main aus dem OpenTofu-State"

tofu state pull \
  | jq -er '
      .resources[]
      | select(
          .type == "rancher2_cluster_v2"
          and .name == "main"
        )
      | .instances[0].attributes.kube_config
      | select(. != null and . != "")
    ' > "${RANCHER_KUBECONFIG}"

chmod 600 "${RANCHER_KUBECONFIG}"

echo "==> Ermittle einen Control-Plane-Knoten"

CONTROLPLANE_IP="$(
  kubectl \
    --kubeconfig="${RANCHER_KUBECONFIG}" \
    get nodes \
    -l node-role.kubernetes.io/control-plane \
    -o json \
  | jq -er '
      .items[0].status.addresses[]
      | select(.type == "InternalIP")
      | .address
    '
)"

echo "    Control Plane: ${CONTROLPLANE_IP}"

echo "==> Hole RKE2-Admin-Kubeconfig per SSH"

ssh \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o StrictHostKeyChecking=accept-new \
  "${SSH_USER}@${CONTROLPLANE_IP}" \
  'sudo cat /etc/rancher/rke2/rke2.yaml' \
  > "${RKE2_KUBECONFIG}"

chmod 600 "${RKE2_KUBECONFIG}"

echo "==> Extrahiere CA und Admin-Clientzertifikat"

kubectl \
  --kubeconfig="${RKE2_KUBECONFIG}" \
  config view --raw -o json \
  > "${TMPDIR}/rke2.json"

jq -er '
  .clusters[0].cluster["certificate-authority-data"]
' "${TMPDIR}/rke2.json" \
  | base64 -d > "${TMPDIR}/ca.crt"

jq -er '
  .users[0].user["client-certificate-data"]
' "${TMPDIR}/rke2.json" \
  | base64 -d > "${TMPDIR}/client.crt"

jq -er '
  .users[0].user["client-key-data"]
' "${TMPDIR}/rke2.json" \
  | base64 -d > "${TMPDIR}/client.key"

echo "==> Erzeuge main-direct"

kubectl \
  --kubeconfig="${DIRECT_KUBECONFIG}" \
  config set-cluster main-direct \
  --server="https://${VIP}:6443" \
  --certificate-authority="${TMPDIR}/ca.crt" \
  --embed-certs=true \
  >/dev/null

kubectl \
  --kubeconfig="${DIRECT_KUBECONFIG}" \
  config set-credentials main-direct \
  --client-certificate="${TMPDIR}/client.crt" \
  --client-key="${TMPDIR}/client.key" \
  --embed-certs=true \
  >/dev/null

kubectl \
  --kubeconfig="${DIRECT_KUBECONFIG}" \
  config set-context main-direct \
  --cluster=main-direct \
  --user=main-direct \
  >/dev/null

echo "==> Teste neuen direkten API-Zugang"

kubectl \
  --kubeconfig="${DIRECT_KUBECONFIG}" \
  --context=main-direct \
  get --raw='/version' \
  >/dev/null

echo "    Direkter API-Zugang funktioniert."

echo "==> Merge nach ${DEST_KUBECONFIG}"

mkdir -p "$(dirname "${DEST_KUBECONFIG}")"

CURRENT_CONTEXT=""

if [[ -f "${DEST_KUBECONFIG}" ]]; then
  CURRENT_CONTEXT="$(
    kubectl \
      --kubeconfig="${DEST_KUBECONFIG}" \
      config current-context 2>/dev/null || true
  )"

  cp \
    "${DEST_KUBECONFIG}" \
    "${DEST_KUBECONFIG}.bak.$(date +%Y%m%d-%H%M%S)"

  kubectl \
    --kubeconfig="${DEST_KUBECONFIG}" \
    config delete-context main-direct \
    >/dev/null 2>&1 || true

  kubectl \
    --kubeconfig="${DEST_KUBECONFIG}" \
    config delete-cluster main-direct \
    >/dev/null 2>&1 || true

  kubectl \
    --kubeconfig="${DEST_KUBECONFIG}" \
    config delete-user main-direct \
    >/dev/null 2>&1 || true

  KUBECONFIG="${DEST_KUBECONFIG}:${DIRECT_KUBECONFIG}" \
    kubectl config view --raw --flatten \
    > "${MERGED_KUBECONFIG}"
else
  cp "${DIRECT_KUBECONFIG}" "${MERGED_KUBECONFIG}"
fi

install -m 600 \
  "${MERGED_KUBECONFIG}" \
  "${DEST_KUBECONFIG}"

if [[ -n "${CURRENT_CONTEXT}" ]] \
   && kubectl \
        --kubeconfig="${DEST_KUBECONFIG}" \
        config get-contexts "${CURRENT_CONTEXT}" \
        >/dev/null 2>&1; then

  kubectl \
    --kubeconfig="${DEST_KUBECONFIG}" \
    config use-context "${CURRENT_CONTEXT}" \
    >/dev/null
fi

echo "==> Abschlusstest"

kubectl \
  --kubeconfig="${DEST_KUBECONFIG}" \
  --context=main-direct \
  get nodes \
  >/dev/null

echo
echo "main-direct wurde erfolgreich eingerichtet."
echo "Endpoint: https://${VIP}:6443"
