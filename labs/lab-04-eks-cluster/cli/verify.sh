#!/bin/bash
# Lab 04 — EKS: health checks post-deploy
set -euo pipefail

CLUSTER_NAME="epam-prep"
REGION="us-east-1"
NAMESPACE="default"
LOG_FILE="/tmp/lab-04-verify-$(date +%Y%m%d-%H%M%S).log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }
pass() { echo "  ✅ $*" | tee -a "$LOG_FILE"; }
fail() { echo "  ❌ $*" | tee -a "$LOG_FILE"; }
section() { echo "" | tee -a "$LOG_FILE"; echo "── $* ──────────────────────" | tee -a "$LOG_FILE"; }

log "Iniciando verificación del Lab 04 — EKS"
log "Log guardado en: $LOG_FILE"

# ─── 1. Cluster ──────────────────────────────────────────────────────────────
section "Cluster EKS"
CLUSTER_STATUS=$(aws eks describe-cluster   --name "$CLUSTER_NAME"   --region "$REGION"   --query "cluster.status"   --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "$CLUSTER_STATUS" == "ACTIVE" ]]; then
  pass "Cluster '$CLUSTER_NAME' está ACTIVE"
else
  fail "Cluster '$CLUSTER_NAME' no encontrado o no está ACTIVE (status: $CLUSTER_STATUS)"
  exit 1
fi

# ─── 2. kubeconfig ───────────────────────────────────────────────────────────
section "kubeconfig"
CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "none")
if echo "$CURRENT_CTX" | grep -q "$CLUSTER_NAME"; then
  pass "kubeconfig apunta al cluster correcto: $CURRENT_CTX"
else
  log "Actualizando kubeconfig..."
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
  pass "kubeconfig actualizado"
fi

# ─── 3. Nodos ────────────────────────────────────────────────────────────────
section "Nodos"
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null   | grep -c " Ready " || echo "0")
TOTAL_NODES=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [[ "$READY_NODES" -ge 1 ]]; then
  pass "$READY_NODES/$TOTAL_NODES nodos en estado Ready"
  kubectl get nodes -o wide 2>/dev/null | tee -a "$LOG_FILE"
else
  fail "No hay nodos Ready ($READY_NODES/$TOTAL_NODES)"
fi

# ─── 4. Pods del sistema ─────────────────────────────────────────────────────
section "Pods kube-system"
NOT_RUNNING=$(kubectl get pods -n kube-system --no-headers 2>/dev/null   | grep -v "Running\|Completed" | wc -l | tr -d ' ')

if [[ "$NOT_RUNNING" -eq 0 ]]; then
  pass "Todos los pods de kube-system están Running"
else
  fail "$NOT_RUNNING pods en kube-system NO están Running:"
  kubectl get pods -n kube-system --no-headers | grep -v "Running\|Completed" | tee -a "$LOG_FILE"
fi

# ─── 5. Deployment nginx ─────────────────────────────────────────────────────
section "Deployment nginx"
DESIRED=$(kubectl get deployment nginx-deployment -n "$NAMESPACE"   -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
AVAILABLE=$(kubectl get deployment nginx-deployment -n "$NAMESPACE"   -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")

if [[ "$AVAILABLE" == "$DESIRED" && "$DESIRED" -gt 0 ]]; then
  pass "nginx-deployment: $AVAILABLE/$DESIRED réplicas disponibles"
else
  fail "nginx-deployment: $AVAILABLE/$DESIRED réplicas disponibles"
  kubectl describe deployment nginx-deployment -n "$NAMESPACE" 2>/dev/null     | grep -A5 "Conditions:" | tee -a "$LOG_FILE"
fi

# ─── 6. Service y LoadBalancer ───────────────────────────────────────────────
section "Service LoadBalancer"
LB_HOSTNAME=$(kubectl get svc nginx-service -n "$NAMESPACE"   -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [[ -n "$LB_HOSTNAME" ]]; then
  pass "LoadBalancer hostname: $LB_HOSTNAME"
  # Test HTTP
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}"     --max-time 10 "http://$LB_HOSTNAME" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    pass "HTTP test OK (200) → http://$LB_HOSTNAME"
  else
    fail "HTTP test falló (code: $HTTP_CODE) — el LB puede estar calentando, espera 1-2 min"
  fi
else
  fail "LoadBalancer aún no tiene hostname — ejecuta 'kubectl get svc nginx-service -w'"
fi

# ─── 7. OIDC Provider ────────────────────────────────────────────────────────
section "OIDC Provider (para IRSA)"
OIDC_ISSUER=$(aws eks describe-cluster   --name "$CLUSTER_NAME"   --region "$REGION"   --query "cluster.identity.oidc.issuer"   --output text 2>/dev/null || echo "")

OIDC_ID=$(echo "$OIDC_ISSUER" | cut -d'/' -f5)
OIDC_REGISTERED=$(aws iam list-open-id-connect-providers   --query "OIDCProviderList[?contains(Arn,'$OIDC_ID')].Arn"   --output text 2>/dev/null || echo "")

if [[ -n "$OIDC_REGISTERED" ]]; then
  pass "OIDC Provider registrado en IAM: $OIDC_REGISTERED"
else
  fail "OIDC Provider NO registrado — ejecutar: eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --approve"
fi

# ─── Resumen ─────────────────────────────────────────────────────────────────
section "Resumen"
log "Verificación completa. Log completo en: $LOG_FILE"
