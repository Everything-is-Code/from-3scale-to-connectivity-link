#!/usr/bin/env bash
# Print access URLs and credentials for workshop consoles that are NOT
# OpenShift OAuth (ArgoCD local admin, Grafana, Gitea, Keycloak, 3scale, …).
#
# Prerequisites: oc logged in with permission to read Routes and Secrets.
# Usage: ./scripts/get-credentials.sh

set -euo pipefail

if ! command -v oc >/dev/null 2>&1; then
  echo "ERROR: oc CLI not found in PATH" >&2
  exit 1
fi

if ! oc whoami >/dev/null 2>&1; then
  echo "ERROR: not logged in to a cluster (oc whoami failed)" >&2
  exit 1
fi

b64() {
  # portable base64 decode
  if base64 --help 2>&1 | grep -q -- '-d'; then
    printf '%s' "$1" | base64 -d 2>/dev/null || true
  else
    printf '%s' "$1" | base64 -D 2>/dev/null || true
  fi
}

secret_key() {
  local ns=$1 name=$2 key=$3
  # Prefer python: handles keys with dots (admin.password) portably
  if command -v python3 >/dev/null 2>&1; then
    local val
    val=$(oc get secret "$name" -n "$ns" -o json 2>/dev/null | python3 -c "
import sys, json, base64
try:
    data = json.load(sys.stdin).get('data') or {}
    raw = data.get('${key}')
    if not raw:
        sys.exit(2)
    sys.stdout.write(base64.b64decode(raw).decode('utf-8', errors='replace'))
except Exception:
    sys.exit(2)
" 2>/dev/null || true)
    if [[ -n "${val:-}" ]]; then
      printf '%s\n' "$val"
      return
    fi
  fi
  local raw
  raw=$(oc extract secret/"$name" -n "$ns" --keys="$key" --to=- 2>/dev/null || true)
  if [[ -z "$raw" ]]; then
    echo "(not found)"
    return
  fi
  printf '%s\n' "$raw"
}

route_url() {
  local ns=$1 name=$2
  local host
  host=$(oc get route "$name" -n "$ns" -o jsonpath='{.spec.host}' 2>/dev/null || true)
  if [[ -z "$host" ]]; then
    # fallback: first route in namespace
    host=$(oc get route -n "$ns" -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
  fi
  if [[ -z "$host" ]]; then
    echo "(route not found in $ns/$name)"
  else
    echo "https://${host}"
  fi
}

route_by_label_or_first() {
  local ns=$1
  local host
  host=$(oc get route -n "$ns" -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
  if [[ -z "$host" ]]; then
    echo "(no routes in $ns)"
  else
    echo "https://${host}"
  fi
}

hr() { printf '\n%s\n' "────────────────────────────────────────────────────────────"; }
title() { printf '\n## %s\n' "$1"; }
kv() { printf '  %-14s %s\n' "$1" "$2"; }

DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || true)
USER=$(oc whoami 2>/dev/null || echo unknown)

echo "Workshop console credentials"
echo "Cluster user : ${USER}"
echo "Ingress domain: ${DOMAIN:-unknown}"
echo "Generated at  : $(date -u +%Y-%m-%dT%H:%M:%SZ)"

hr
title "OpenShift Console (OAuth — kubeadmin / platform users)"
CONSOLE=$(oc whoami --show-console 2>/dev/null || echo "(unavailable)")
kv "URL:" "$CONSOLE"
kv "Auth:" "OpenShift OAuth (kubeadmin / platformadmin / HTPasswd)"
# kubeadmin password is often only available from the install-time kubeadmin-password file
if oc get secret kubeadmin -n kube-system >/dev/null 2>&1; then
  kv "kubeadmin:" "$(secret_key kube-system kubeadmin password)"
else
  kv "kubeadmin:" "(secret not present — use install kubeadmin-password or RHDP credentials)"
fi
kv "Kuadrant UI:" "OpenShift Console → Connectivity Link plugin"

hr
title "Red Hat Developer Hub"
kv "URL:" "$(route_url developer-hub backstage-developer-hub)"
kv "Auth:" "Keycloak OIDC (workshop users user1…userN / platformadmin)"

hr
title "ArgoCD"
kv "URL:" "$(route_url openshift-gitops openshift-gitops-server)"
kv "User:" "admin"
kv "Password:" "$(secret_key openshift-gitops openshift-gitops-cluster admin.password)"

hr
title "Grafana (observability)"
kv "URL:" "$(route_url openshift-cluster-observability-operator grafana-observability-route)"
kv "User:" "$(secret_key openshift-cluster-observability-operator grafana-observability-admin-credentials GF_SECURITY_ADMIN_USER)"
kv "Password:" "$(secret_key openshift-cluster-observability-operator grafana-observability-admin-credentials GF_SECURITY_ADMIN_PASSWORD)"

hr
title "Thanos Querier (Connectivity Link)"
kv "URL:" "$(route_url openshift-cluster-observability-operator thanos-querier-connectivity-link)"
kv "Auth:" "OpenShift OAuth / bearer token (oc whoami -t)"

hr
title "Kiali"
kv "URL:" "$(route_url openshift-cluster-observability-operator kiali)"
kv "Auth:" "OpenShift OAuth"

hr
title "Tempo (Jaeger UI)"
kv "URL:" "$(route_url openshift-tempo tempo-connectivity-link-jaegerui)"
kv "Auth:" "OpenShift OAuth / cluster network"

hr
title "Gitea"
kv "URL:" "$(route_url gitea gitea)"
# Chart defaults from examples/helm/values.yaml; override if your Secret differs
GITEA_USER=$(oc get secret gitea -n gitea -o jsonpath='{.data.username}' 2>/dev/null || true)
GITEA_PASS=$(oc get secret gitea -n gitea -o jsonpath='{.data.password}' 2>/dev/null || true)
if [[ -n "$GITEA_USER" ]]; then
  kv "User:" "$(b64 "$GITEA_USER")"
  kv "Password:" "$(b64 "$GITEA_PASS")"
else
  kv "User:" "gitea_admin (chart default)"
  kv "Password:" "openshift (chart default — rotate in production)"
fi

hr
title "Keycloak (RHBK)"
# Route name is generated by the operator; take the first route in the namespace.
RHBK_HOST=$(oc get route -n rhbk-operator -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
if [[ -n "$RHBK_HOST" ]]; then
  kv "URL:" "https://${RHBK_HOST}"
else
  kv "URL:" "(route not found in rhbk-operator)"
fi
kv "User:" "$(secret_key rhbk-operator keycloak-initial-admin username)"
kv "Password:" "$(secret_key rhbk-operator keycloak-initial-admin password)"

hr
title "3scale Admin Portal"
# Prefer the provider admin host
SCALE_ADMIN=$(oc get route -n 3scale-system -o jsonpath='{range .items[*]}{.spec.host}{"\n"}{end}' 2>/dev/null | grep -E '3scale-admin|^admin\.' | head -1 || true)
[[ -z "$SCALE_ADMIN" ]] && SCALE_ADMIN=$(oc get route -n 3scale-system -o jsonpath='{.items[0].spec.host}' 2>/dev/null || true)
kv "URL:" "${SCALE_ADMIN:+https://${SCALE_ADMIN}}"
kv "User:" "$(secret_key 3scale-system system-seed ADMIN_USER)"
kv "Password:" "$(secret_key 3scale-system system-seed ADMIN_PASSWORD)"
kv "AccessToken:" "$(secret_key 3scale-system system-seed ADMIN_ACCESS_TOKEN)"
MASTER_HOST=$(oc get route -n 3scale-system -o jsonpath='{range .items[*]}{.spec.host}{"\n"}{end}' 2>/dev/null | grep -E '^master\.' | head -1 || true)
[[ -n "$MASTER_HOST" ]] && kv "Master URL:" "https://${MASTER_HOST}"
kv "Master user:" "$(secret_key 3scale-system system-seed MASTER_USER)"
kv "Master pass:" "$(secret_key 3scale-system system-seed MASTER_PASSWORD)"

hr
title "APIShift"
kv "URL:" "$(route_url gateforge apishift)"
kv "Auth:" "App login / configured tokens (see Secret apishift-config)"
kv "Notes:" "Same migration path as Migration Toolkit; adds AI (litemaas) + DevHub registration. Tokens in Argo valuesObject / Secrets — not OpenShift OAuth"

hr
title "Migration Toolkit RHCL"
kv "URL:" "$(route_url migration-toolkit migration-toolkit-rhcl-frontend)"
kv "Auth:" "UI form — 3scale URL/token prefilled from THREESCALE_DEFAULT_* when configured"
kv "Config Secret:" "migration-toolkit-rhcl-config (DB + optional THREESCALE_DEFAULT_TOKEN)"

hr
title "Showroom (lab guide)"
kv "URL:" "$(route_url showroom showroom)"
kv "Auth:" "none (public lab guide)"
kv "Registration:" "$(route_url showroom workshop-registration)"

hr
title "Microcks"
kv "URL:" "$(route_url microcks microcks)"
kv "Keycloak:" "$(route_url microcks microcks-keycloak)"
MICROCKS_USER=$(secret_key microcks microcks-keycloak-admin username 2>/dev/null || echo admin)
MICROCKS_PASS=$(secret_key microcks microcks-keycloak-admin password 2>/dev/null || echo "(see microcks-keycloak-admin)")
kv "Admin user:" "$MICROCKS_USER"
kv "Admin pass:" "$MICROCKS_PASS"

hr
title "Mailpit / n8n (openshift-lightspeed)"
kv "Mailpit:" "$(route_url openshift-lightspeed n8n-mailpit)"
kv "n8n:" "$(route_url openshift-lightspeed n8n)"
kv "Auth:" "Check chart values / Secrets in openshift-lightspeed (not OpenShift OAuth)"

hr
echo "Done. Rotate default passwords before sharing this output outside the workshop."
echo "Tip: oc whoami -t  # bearer token for APIs that accept OpenShift tokens"
