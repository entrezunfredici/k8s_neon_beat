#!/bin/bash
# =============================================================================
# setup.sh - Ingress HTTPS generique Neon Beat
#
# Usage:
#   bash k8s/setup.sh --email you@mail.com \
#                     --api-domain api.yourdomain.com \
#                     --front-domain app.yourdomain.com
#
# This script applies:
#   1. namespace.yml
#   2. cert-manager/cluster-issuer.yml with the provided email
#   3. app/ingress.yml with the provided domains
#
# Workloads are managed separately:
#   kubectl apply -f k8s/preprod/
#   kubectl apply -f k8s/prod/
# =============================================================================

set -euo pipefail

LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
API_DOMAIN="${API_DOMAIN:-api.yourdomain.com}"
FRONT_DOMAIN="${FRONT_DOMAIN:-app.yourdomain.com}"
NAMESPACE="neon-beat"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step() { echo -e "\n${GREEN}== $*${NC}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --email) LETSENCRYPT_EMAIL="$2"; shift 2 ;;
    --api-domain) API_DOMAIN="$2"; shift 2 ;;
    --front-domain) FRONT_DOMAIN="$2"; shift 2 ;;
    *) error "Unknown argument: $1" ;;
  esac
done

step "Checking prerequisites"
command -v kubectl >/dev/null 2>&1 || error "kubectl not found."
kubectl cluster-info >/dev/null 2>&1 || error "kubectl cannot reach the cluster."
kubectl get ingressclass nginx >/dev/null 2>&1 || error "nginx ingress class not found."
kubectl get namespace cert-manager >/dev/null 2>&1 || error "cert-manager namespace not found."

if [[ -z "$LETSENCRYPT_EMAIL" ]]; then
  read -r -p "Let's Encrypt email: " LETSENCRYPT_EMAIL
  [[ -z "$LETSENCRYPT_EMAIL" ]] && error "Email is required."
fi

info "ACME email  : ${LETSENCRYPT_EMAIL}"
info "API domain  : ${API_DOMAIN}"
info "Front domain: ${FRONT_DOMAIN}"
info "Namespace   : ${NAMESPACE}"

step "Applying namespace"
kubectl apply -f "${SCRIPT_DIR}/namespace.yml"

step "Applying cert-manager ClusterIssuer"
ISSUER_TMP=$(mktemp)
sed "s/LETSENCRYPT_EMAIL/${LETSENCRYPT_EMAIL}/g" \
  "${SCRIPT_DIR}/cert-manager/cluster-issuer.yml" > "${ISSUER_TMP}"
kubectl apply -f "${ISSUER_TMP}"
rm "${ISSUER_TMP}"

step "Applying generic Neon Beat ingress"
INGRESS_TMP=$(mktemp)
sed "s/api\.yourdomain\.com/${API_DOMAIN}/g; s/app\.yourdomain\.com/${FRONT_DOMAIN}/g" \
  "${SCRIPT_DIR}/app/ingress.yml" > "${INGRESS_TMP}"
kubectl apply -f "${INGRESS_TMP}" -n "${NAMESPACE}"
rm "${INGRESS_TMP}"

echo ""
info "Setup complete."
echo "API   : https://${API_DOMAIN}"
echo "Front : https://${FRONT_DOMAIN}"
echo ""
warn "Before deploying workloads, create the CouchDB secret:"
echo "kubectl create secret generic neon-beat-prod-secrets \\"
echo "  --namespace neon-beat \\"
echo "  --from-literal=COUCH_USERNAME=admin \\"
echo "  --from-literal=COUCH_PASSWORD='<password>'"
