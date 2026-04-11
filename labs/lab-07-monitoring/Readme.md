# Lab 07 — Monitoring: Prometheus + Grafana en EKS

**Bloque:** 5 — Observabilidad & Monitoreo

**Objetivo:** Instalar `kube-prometheus-stack` con Helm, crear dashboards de Kubernetes y configurar alertas básicas con Alertmanager.

---

## Prerequisitos

- Lab 04 completado (cluster EKS corriendo)
- Helm 3 instalado
- `kubectl` configurado contra el cluster

---

## Arquitectura

```
EKS Cluster
  └─→ namespace: monitoring
        ├─→ Prometheus        ← scrape de métricas K8s + apps
        ├─→ Grafana           ← dashboards y visualización
        ├─→ Alertmanager      ← routing de alertas
        ├─→ node-exporter     ← métricas de nodos (DaemonSet)
        └─→ kube-state-metrics ← métricas de objetos K8s
```

---

## Estructura del lab

```
lab-07-monitoring/
├── Readme.md
├── helm/
│   ├── values.yaml         ← configuración del stack
│   └── alerts/
│       └── custom-rules.yaml ← reglas de alerta personalizadas
└── dashboards/
    └── slo-dashboard.json  ← dashboard de SLO para entrevista
```

---

## Paso a paso

### 1. Instalar kube-prometheus-stack

```bash
# Agregar repo
helm repo add prometheus-community \
  https://prometheus-community.github.io/helm-charts
helm repo update

# Instalar en namespace monitoring
helm install kube-prometheus-stack \
  prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values helm/values.yaml \
  --version 58.0.0  # pinear versión

# Verificar
kubectl get pods -n monitoring
```

### 2. Acceder a Grafana localmente

```bash
# Port-forward
kubectl port-forward svc/kube-prometheus-stack-grafana \
  3000:80 -n monitoring

# Obtener password de admin
kubectl get secret kube-prometheus-stack-grafana \
  -n monitoring \
  -o jsonpath='{.data.admin-password}' | base64 -d

# Abrir http://localhost:3000
# Usuario: admin
```

### 3. PromQL básico a practicar

```promql
# CPU usage por pod
rate(container_cpu_usage_seconds_total{
  namespace="default"
}[5m])

# Memory usage
container_memory_working_set_bytes{namespace="default"}

# HTTP error rate (si la app expone métricas)
rate(http_requests_total{status=~"5.."}[5m]) /
rate(http_requests_total[5m])

# Burn rate del error budget (SLO 99.9%)
1 - (
  rate(http_requests_total{status!~"5.."}[1h]) /
  rate(http_requests_total[1h])
)
```

### 4. Verificar alertas

```bash
# Ver reglas cargadas
kubectl get prometheusrule -n monitoring

# Port-forward a Alertmanager
kubectl port-forward svc/kube-prometheus-stack-alertmanager \
  9093:9093 -n monitoring
# http://localhost:9093
```

---

## Preguntas de entrevista

**"¿Cuáles son los golden signals?"**

Respuesta: Latencia, tráfico (requests/seg), errores y saturación. En Kubernetes los mapeas a métricas concretas: latencia con histogramas de la app, tráfico con `rate(http_requests_total)`, errores con el ratio de 5xx, y saturación con CPU/memory limits vs usage.

**"¿Cómo calculas un error budget burn rate en Prometheus?"**

Respuesta: Si el SLO es 99.9%, el error budget es 0.1%. Un burn rate de 1 significa que lo consumes exactamente en el período. Burn rate de 14.4 en 1 hora significa que consumiste el 2% del budget mensual en una sola hora — es la regla estándar de alerta "fast burn" del Google SRE Book.

**"¿Por qué Prometheus y no solo CloudWatch?"**

Respuesta: Prometheus es el estándar de facto para métricas en Kubernetes. CloudWatch no entiende objetos K8s nativamente (pods, deployments, namespaces). Además, PromQL es mucho más expresivo para cálculos como SLOs y burn rates. En producción se usan ambos: Prometheus para métricas de aplicación y K8s, CloudWatch para métricas de infraestructura AWS.

---

## Cleanup

```bash
helm uninstall kube-prometheus-stack -n monitoring
kubectl delete namespace monitoring
```

---

## Documentación relacionada

- [Lab 04 — EKS Cluster](../lab-04-eks-cluster/Readme.md)
- [kube-prometheus-stack Helm chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [PromQL cheatsheet](https://promlabs.com/promql-cheat-sheet/)
