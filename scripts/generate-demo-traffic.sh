#!/usr/bin/env bash
# Generates traffic against the kuadrant-console-demo gateway APIs.
# Useful for populating Grafana dashboards, Tempo traces, and the
# Cost Monitoring page with realistic data.
#
# Usage:
#   ./scripts/generate-demo-traffic.sh              # 5 rounds, auto-detect domain
#   ./scripts/generate-demo-traffic.sh 20            # 20 rounds
#   ./scripts/generate-demo-traffic.sh 10 my.domain  # 10 rounds, explicit domain
set -uo pipefail

ROUNDS="${1:-5}"
DOMAIN="${2:-}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

if [[ -z "$DOMAIN" ]]; then
  if ! command -v oc &>/dev/null; then
    echo -e "${RED}oc not found. Pass the cluster domain as second argument.${NC}"
    echo "  $0 $ROUNDS apps.cluster-xxx.example.com"
    exit 1
  fi
  DOMAIN=$(oc get ingress.config cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
  if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}Could not detect cluster domain. Pass it as second argument.${NC}"
    exit 1
  fi
fi

HOST="kuadrant-demo.${DOMAIN}"
RESULTS_FILE=$(mktemp)
trap 'rm -f "$RESULTS_FILE"' EXIT

call() {
  local path="$1" key="$2" label="$3"
  local code
  code=$(curl -sk -o /dev/null -w "%{http_code}" \
    "https://${HOST}/${path}/api/v1/customers" \
    -H "X-API-Key: ${key}" 2>/dev/null)
  echo "$code" >> "$RESULTS_FILE"
  case "$code" in
    200) printf "${GREEN}%s${NC} " "$label:$code" ;;
    429) printf "${YELLOW}%s${NC} " "$label:$code" ;;
    401) printf "${RED}%s${NC} " "$label:$code" ;;
    *)   printf "${CYAN}%s${NC} " "$label:$code" ;;
  esac
}

echo -e "${BOLD}${CYAN}Kuadrant Console Demo Traffic Generator${NC}"
echo -e "Host:   ${BOLD}${HOST}${NC}"
echo -e "Rounds: ${BOLD}${ROUNDS}${NC}"
echo -e "APIs:   6 basic + 3 free + 3 pro + 1 unauthenticated = 13 req/round"
echo ""

for ((r=1; r<=ROUNDS; r++)); do
  printf "${BOLD}[%d/%d]${NC} " "$r" "$ROUNDS"

  # All 6 APIs with basic key
  for path in loyalty payments orders inventory notifications shipping; do
    case "$path" in
      loyalty)       key="demo-customer-loyalty-key" ;;
      payments)      key="demo-payment-gateway-key" ;;
      orders)        key="demo-order-management-key" ;;
      inventory)     key="demo-inventory-service-key" ;;
      notifications) key="demo-notification-hub-key" ;;
      shipping)      key="demo-shipping-tracker-key" ;;
    esac
    call "$path" "$key" "$path" &
  done

  # 3 APIs with free key
  call "loyalty"  "demo-customer-loyalty-free-key"  "loyalty/free" &
  call "payments" "demo-payment-gateway-free-key"   "payments/free" &
  call "orders"   "demo-order-management-free-key"  "orders/free" &

  # 3 APIs with pro key
  call "loyalty"  "demo-customer-loyalty-pro-key"   "loyalty/pro" &
  call "payments" "demo-payment-gateway-pro-key"    "payments/pro" &
  call "orders"   "demo-order-management-pro-key"   "orders/pro" &

  # 1 unauthenticated request (expect 401)
  call "inventory" "invalid-key" "nokey" &

  wait
  echo ""
  sleep 1
done

echo ""
OK=$(grep -c '^200$' "$RESULTS_FILE" 2>/dev/null || true)
RATE_LIMITED=$(grep -c '^429$' "$RESULTS_FILE" 2>/dev/null || true)
UNAUTHORIZED=$(grep -c '^401$' "$RESULTS_FILE" 2>/dev/null || true)
BACKEND=$(grep -c '^404$' "$RESULTS_FILE" 2>/dev/null || true)
TOTAL=$(wc -l < "$RESULTS_FILE" 2>/dev/null | tr -d ' ')

echo -e "${BOLD}Summary${NC}"
echo -e "  ${GREEN}200 OK:${NC}             ${OK:-0}"
echo -e "  ${YELLOW}429 Rate Limited:${NC}   ${RATE_LIMITED:-0}"
echo -e "  ${RED}401 Unauthorized:${NC}   ${UNAUTHORIZED:-0}"
[[ "${BACKEND:-0}" -gt 0 ]] && echo -e "  ${CYAN}404 Backend:${NC}        ${BACKEND}"
echo -e "  ${BOLD}Total requests:${NC}     ${TOTAL:-0}"
