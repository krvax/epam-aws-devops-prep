#!/bin/bash
# Lab 04 — EKS: limpieza completa
# ORDEN IMPORTANTE: K8s resources primero → luego el cluster
# Si borras el cluster primero, el ELB de AWS queda huérfano y genera costo
set -euo pipefail

CLUSTER_NAME="epam-prep"
REGION="us-east-1"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
confirm() {
  read -r -p "$1 [y/N] " response
  [[ "$response" =~ ^[Yy]$ ]] || { log "Cancelado."; exit 0; }
}

log "═══════════════════════════════════════════════"
log " DESTRUCCIÓN DEL LAB 04 — EKS"
log "═══════════════════════════════════════════════"
log "Cluster: $CLUSTER_NAME | Región: $REGION"
confirm "¿Confirmas que quieres destruir TODO el lab?"

# ─── 1. Verificar que kubectl apunta al cluster correcto ─────────────────────
log "[1/4] Verificando contexto de kubectl..."
CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "none")
if ! echo "$CURRENT_CTX" | grep -q "$CLUSTER_NAME"; then
  log "Actualizando kubeconfig..."
  aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" || true
fi

# ─── 2. Borrar recursos K8s (deja que AWS limpie el ELB/NLB) ─────────────────
log "[2/4] Eliminando recursos K8s (Service, Deployment)..."
if kubectl get svc nginx-service &>/dev/null; then
  kubectl delete -f k8s/ --ignore-not-found
  log "Esperando que AWS elimine el LoadBalancer (~60s)..."
  sleep 60
  # Verificar que el LB ya no existe
  LB=$(kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
  if [[ -z "$LB" ]]; then
    log "LoadBalancer eliminado correctamente."
  else
    log "⚠️  LoadBalancer aún presente. Puede quedar huérfano en AWS."
  fi
else
  log "No se encontraron recursos K8s — posiblemente ya eliminados."
fi

# ─── 3. Eliminar el cluster con eksctl ────────────────────────────────────────
log "[3/4] Eliminando cluster EKS con eksctl (tarda ~10 min)..."
if aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" &>/dev/null; then
  eksctl delete cluster -f eksctl/cluster.yaml --wait
  log "Cluster eliminado."
else
  log "Cluster '$CLUSTER_NAME' no encontrado — posiblemente ya eliminado."
fi

# ─── 4. Verificar que no quedaron stacks de CloudFormation ───────────────────
log "[4/4] Verificando CloudFormation..."
REMAINING=$(aws cloudformation list-stacks   --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE   --query "StackSummaries[?contains(StackName,'$CLUSTER_NAME')].StackName"   --output text --region "$REGION" 2>/dev/null || echo "")

if [[ -z "$REMAINING" ]]; then
  log "✅ Sin stacks de CloudFormation residuales."
else
  log "⚠️  Stacks residuales encontrados — revisar manualmente:"
  echo "$REMAINING"
fi

# ─── Limpieza de kubeconfig local ─────────────────────────────────────────────
log "Limpiando contexto de kubeconfig local..."
kubectl config delete-context   "$(kubectl config get-contexts -o name | grep "$CLUSTER_NAME" || echo '')"   2>/dev/null || true

log "═══════════════════════════════════════════════"
log "✅ Destrucción del Lab 04 completada."
log "   Recuerda verificar en la consola de AWS que no"
log "   quedaron ELBs o volúmenes EBS huérfanos."
log "═══════════════════════════════════════════════"
