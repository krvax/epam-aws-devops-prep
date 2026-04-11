#!/bin/bash
# Lab 04 — EKS Cluster: comandos paso a paso
# Ejecutar uno a uno, no como script completo
set -euo pipefail

# ─── PASO 1: Crear cluster ───────────────────────────────────────────────────
eksctl create cluster -f eksctl/cluster.yaml
# Tarda ~15 min. Actualiza ~/.kube/config automáticamente.

# ─── PASO 2: Verificar nodos ─────────────────────────────────────────────────
kubectl get nodes -o wide
kubectl get pods -n kube-system

# ─── PASO 3: Deploy nginx ────────────────────────────────────────────────────
kubectl apply -f k8s/

# Esperar LoadBalancer (hasta ~2 min)
kubectl get svc nginx-service -w

# Test cuando tenga EXTERNAL-IP
curl http://$(kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# ─── PASO 4: Explorar objetos ────────────────────────────────────────────────
kubectl get all                              # Todo en el namespace default
kubectl describe deployment nginx-deployment # Detalle del deployment
kubectl get replicaset                       # ReplicaSet creado por el Deployment
kubectl get endpoints nginx-service          # IPs de los pods detrás del Service

# ─── PASO 5: Escalar ─────────────────────────────────────────────────────────
kubectl scale deployment nginx-deployment --replicas=4
kubectl get pods -o wide                     # Ver distribución por nodo
kubectl scale deployment nginx-deployment --replicas=2

# ─── PASO 6: Rolling update (simular deploy de nueva versión) ─────────────────
kubectl set image deployment/nginx-deployment nginx=nginx:1.25.4
kubectl rollout status deployment/nginx-deployment
kubectl rollout history deployment/nginx-deployment

# Rollback si algo sale mal
kubectl rollout undo deployment/nginx-deployment
kubectl rollout status deployment/nginx-deployment

# ─── PASO 7: Troubleshooting ─────────────────────────────────────────────────
# A) ImagePullBackOff
kubectl run bad-pod --image=nginx:tag-que-no-existe
kubectl describe pod bad-pod | grep -A10 Events
kubectl delete pod bad-pod

# B) Pending por recursos insuficientes
kubectl run hungry --image=nginx   --overrides='{"spec":{"containers":[{"name":"hungry","image":"nginx","resources":{"requests":{"cpu":"100","memory":"200Gi"}}}]}}'
kubectl describe pod hungry | grep -A5 "Events:"
kubectl delete pod hungry

# ─── PASO 8: Verificar OIDC para Lab 2.2 (IRSA) ──────────────────────────────
aws iam list-open-id-connect-providers
aws eks describe-cluster   --name epam-prep   --query "cluster.identity.oidc.issuer"   --output text
