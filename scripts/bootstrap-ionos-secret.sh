#!/usr/bin/env bash
set -euo pipefail
set +x

umask 077

SECRETS_FILE="${SHARVESTER_SECRETS_FILE:-$HOME/.config/sharvester/secrets.env}"

if [[ -f "${SECRETS_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${SECRETS_FILE}"
fi

if [[ -z "${IONOS_PUBLIC_PREFIX:-}" ]]; then
  echo "Fehler: IONOS_PUBLIC_PREFIX ist nicht gesetzt." >&2
  exit 1
fi

if [[ -z "${IONOS_SECRET:-}" ]]; then
  echo "Fehler: IONOS_SECRET ist nicht gesetzt." >&2
  exit 1
fi

if [[ -z "${IONOS_PUBLIC_PREFIX}" || -z "${IONOS_SECRET}" ]]; then
  echo "Fehler: Public Prefix oder Secret ist leer." >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"

cleanup() {
  unset IONOS_PUBLIC_PREFIX IONOS_SECRET
  rm -rf "${TMPDIR}"
}
trap cleanup EXIT

printf '%s' "${IONOS_PUBLIC_PREFIX}" > "${TMPDIR}/IONOS_PUBLIC_PREFIX"
printf '%s' "${IONOS_SECRET}"        > "${TMPDIR}/IONOS_SECRET"

chmod 600 \
  "${TMPDIR}/IONOS_PUBLIC_PREFIX" \
  "${TMPDIR}/IONOS_SECRET"

install_secret() {
  local context="$1"

  echo "==> ${context}"

  if ! kubectl config get-contexts "${context}" >/dev/null 2>&1; then
    echo "Fehler: Kubeconfig-Context '${context}' existiert nicht." >&2
    exit 1
  fi

  if ! kubectl --context "${context}" get namespace cert-manager >/dev/null 2>&1; then
    echo "Fehler: Namespace cert-manager existiert in '${context}' nicht." >&2
    exit 1
  fi

  kubectl \
    --context "${context}" \
    -n cert-manager \
    create secret generic ionos-secret \
    --from-file="IONOS_PUBLIC_PREFIX=${TMPDIR}/IONOS_PUBLIC_PREFIX" \
    --from-file="IONOS_SECRET=${TMPDIR}/IONOS_SECRET" \
    --dry-run=client \
    -o yaml \
  | kubectl \
      --context "${context}" \
      -n cert-manager \
      apply -f -

  echo "    ionos-secret vorhanden."
}

install_secret sharvester
install_secret rancher-vcluster
install_secret main-direct

echo
echo "IONOS Secrets wurden erfolgreich eingerichtet."
