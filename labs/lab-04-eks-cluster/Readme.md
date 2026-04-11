# Lab 04 — EKS Cluster con eksctl

> **Bloque 2 — Kubernetes / EKS | Lab 2.1**
>
> **Objetivo:** Crear un cluster EKS básico con managed node groups, desplegar
> nginx y practicar los comandos de troubleshooting más preguntados en entrevistas.
>
> **Tiempo estimado:** 30-40 min (15 el cluster, 5 el deploy, el resto troubleshooting)
>
> **Costo estimado:** ~$0.18/hr total → destruir al terminar
>
> **Prerequisitos:**
> - Lab-01 y Lab-02 completados
> - `eksctl`: `brew tap weaveworks/tap && brew install weaveworks/tap/eksctl`
> - `kubectl`: `brew install kubectl`
> - AWS CLI con permisos de administrador

---

## Arquitectura

```
AWS Cloud (us-east-1)
│
├── EKS Control Plane (managed by AWS — $0.10/hr)
│   ├── API Server      → recibe los kubectl apply
│   ├── etcd            → base de datos de estado del cluster
│   ├── Scheduler       → decide en qué nodo va cada pod
│   └── Controller Mgr  → reconcilia el estado deseado vs actual
│
└── Managed Node Group (tu data plane)
    ├── Node 1 (t3.medium) — us-east-1a
    │   └── kubelet + kube-proxy + aws-node (VPC CNI)
    └── Node 2 (t3.medium) — us-east-1b
        └── kubelet + kube-proxy + aws-node (VPC CNI)
```

---

## Estructura del Lab

```
lab-04-eks-cluster/
├── Readme.md
├── eksctl/
│   └── cluster.yaml       ← definición declarativa del cluster
├── k8s/
│   ├── nginx-deployment.yaml
│   └── nginx-service.yaml
└── cli/
    ├── commands.sh        ← paso a paso del lab
    ├── verify.sh          ← health checks post-deploy
    └── destroy.sh         ← limpieza completa
```

---

## Paso 1: Crear el Cluster

```bash
# Siempre usar el archivo declarativo — nunca flags sueltos en prod
eksctl create cluster -f eksctl/cluster.yaml

# Tarda ~15 min. Output final esperado:
# [✔]  EKS cluster "epam-prep" in "us-east-1" region is ready
```

Internamente eksctl crea dos CloudFormation stacks:
```bash
aws cloudformation list-stacks   --query "StackSummaries[?contains(StackName,'epam-prep')].StackName"   --output table
```

---

## Paso 2: Verificar el Cluster

```bash
# Script de verificación completo
bash cli/verify.sh

# O manualmente:
kubectl get nodes -o wide
kubectl get pods -n kube-system
```

| Pod en kube-system | Función |
|--------------------|---------|
| `coredns-*` | DNS interno — resuelve `<svc>.<ns>.svc.cluster.local` |
| `aws-node-*` | VPC CNI — asigna IPs de la VPC a cada pod |
| `kube-proxy-*` | Maneja iptables para routing de Services |

---

## Paso 3: Deploy de Nginx

```bash
kubectl apply -f k8s/

# Esperar que el LoadBalancer tenga hostname (~2 min)
kubectl get svc nginx-service -w

# Probar
curl http://$(kubectl get svc nginx-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

---

## Paso 4: Troubleshooting (practicar para entrevista)

### Scenario A — ImagePullBackOff
```bash
kubectl run bad-pod --image=nginx:tag-que-no-existe
kubectl describe pod bad-pod | grep -A10 Events
kubectl delete pod bad-pod
```

### Scenario B — Pending por recursos insuficientes
```bash
kubectl run hungry --image=nginx   --overrides='{"spec":{"containers":[{"name":"hungry","image":"nginx","resources":{"requests":{"cpu":"100","memory":"200Gi"}}}]}}'
kubectl describe pod hungry | grep -A5 "Events:"
kubectl delete pod hungry
```

### Scenario C — Escalar y ver distribución por nodo
```bash
kubectl scale deployment nginx-deployment --replicas=4
kubectl get pods -o wide   # Ver distribución en nodos
kubectl scale deployment nginx-deployment --replicas=2
```

---

## Verificar OIDC (necesario para Lab 2.2 — IRSA)

```bash
# El cluster.yaml ya habilita OIDC (withOIDC: true)
# Verificar que quedó registrado:
aws iam list-open-id-connect-providers

aws eks describe-cluster \
  --name epam-prep \
  --query "cluster.identity.oidc.issuer" \
  --output text
```

---

## Preguntas de Entrevista

### "¿Qué es IRSA y por qué es mejor que access keys en pods?"
> IRSA usa el OIDC Provider del cluster para que pods individuales asuman IAM Roles
> vía tokens JWT temporales. No hay secrets que gestionar, los permisos son por
> Service Account (no por nodo entero), y las credenciales expiran automáticamente.

### "¿Qué pasa cuando haces `kubectl apply`?"
> 1. API Server autentica + autoriza (RBAC) la request
> 2. Admission Controllers validan/mutan el objeto
> 3. Se persiste en etcd
> 4. Controller Manager detecta el delta y crea ReplicaSet → Pods
> 5. Scheduler asigna pods a nodos según resources, taints y affinity
> 6. kubelet en el nodo instrucye al CRI (containerd) a levantar el container

### "¿Diferencia entre Deployment y StatefulSet?"
> Deployment: pods intercambiables, nombres aleatorios, para workloads stateless.
> StatefulSet: identidad estable (mongo-0, mongo-1), volúmenes que siguen al pod,
> startup/shutdown ordenado. Usar para databases, message brokers, etc.

---

## Limpieza

```bash
# SIEMPRE borrar los recursos K8s primero (para que AWS limpie el ELB)
bash cli/destroy.sh
```

---

## Relación con otros Labs

| Lab | Concepto aplicado aquí |
|-----|------------------------|
| lab-01-vpc | eksctl crea su VPC con el mismo patrón (subnets públicas + privadas, IGW, NAT GW) |
| lab-02-iam | eksctl crea IAM Roles para el cluster y node group automáticamente |
| lab-03-asg-alb | Los managed node groups son ASGs internamente |
| lab-05 (siguiente) | IRSA — dar permisos AWS a pods con el OIDC Provider habilitado aquí |
