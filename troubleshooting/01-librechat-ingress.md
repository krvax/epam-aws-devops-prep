# 🐛 Troubleshooting: LibreChat Ingress no generaba ALB en EKS

> **Cuándo usar esta guía:** El `helm install` completó sin errores, el objeto
> Ingress existe en Kubernetes, pero `ADDRESS` está vacío y no hay ALB en AWS.
>
> Si el ALB ya existe pero los targets están `unhealthy`, ver
> [03-eks-target-group-unhealthy.md](./03-eks-target-group-unhealthy.md).

---

## Resumen ejecutivo

| Campo | Detalle |
|-------|---------|
| **Proyecto** | LibreChat en EKS |
| **Herramienta** | Helm + AWS Load Balancer Controller |
| **Síntoma** | Ingress creado pero `ADDRESS` vacío, ALB nunca apareció en AWS |
| **Causa raíz** | Annotations del ALB Controller ausentes en `values.yaml`; el controller queda en **silencio** |
| **Solución** | Agregar annotations correctas + `helm upgrade` para forzar reconciliación |

---

## Por qué este bug es confuso

El ALB Controller **no lanza error cuando las annotations están mal o faltan**.
Simplemente no actúa. Sin eventos, sin logs de error, sin señal visible.

```text
helm install
  └─→ Ingress creado en K8s
        └─→ ALB Controller lo detecta
              ├─→ Annotations correctas → crea ALB en AWS ✅
              └─→ Annotations ausentes  → silencio total ❌
                    Sin error. Sin evento. Sin ALB.
```

La trampa es que todo parece “bien” en Kubernetes: el pod corre, el Ingress existe,
el controller está `Running`. El problema solo se ve en que `ADDRESS` nunca llega.

---

## Diagnóstico paso a paso

### Paso 1 — Verificar ADDRESS del Ingress

```bash
kubectl get ingress -n librechat
```

| ADDRESS vacío | ADDRESS con hostname |
|---|---|
| Controller no actuó | Controller creó el ALB |

```text
# ❌ Problema
NAME        CLASS   HOSTS              ADDRESS   PORTS   AGE
librechat   alb     chat.ejemplo.com             80      10m

# ✅ Funcionando
NAME        CLASS   HOSTS              ADDRESS                              PORTS   AGE
librechat   alb     chat.ejemplo.com   k8s-xxxx.us-east-1.elb.amazonaws.com 80     5m
```

---

### Paso 2 — Verificar que los pods están bien (descartar app)

```bash
kubectl get pods -n librechat
```

Si los pods están `1/1 Running`, el problema **no** es la aplicación.
Continuar al siguiente paso.

---

### Paso 3 — Verificar el ALB Controller

```bash
# ¿Está corriendo?
kubectl get pods -n kube-system | grep load-balancer

# Ver logs — ¿hay actividad relacionada con el Ingress?
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=50
```

Si los logs no muestran nada relacionado con el Ingress de LibreChat,
el controller lo está ignorando. Esto confirma el problema de annotations.

---

### Paso 4 — Inspeccionar el Ingress (buscar `Events: <none>`)

```bash
kubectl describe ingress librechat -n librechat
```

La señal definitiva está al final del output:

```text
Events:  <none>
```

`Events: <none>` = el controller nunca intentó crear el ALB.

Comparar con el estado sano:

```text
Events:
  Type    Reason                  Age   Message
  ────    ──────                  ───   ───────
  Normal  SuccessfullyReconciled  30s   Successfully reconciled
```

---

### Paso 5 — Identificar qué annotations faltan

```bash
kubectl get ingress librechat -n librechat -o yaml | grep -A20 annotations
```

**Annotations mínimas requeridas por el ALB Controller:**

```yaml
annotations:
  kubernetes.io/ingress.class: alb
  alb.ingress.kubernetes.io/scheme: internet-facing
  alb.ingress.kubernetes.io/target-type: ip
```

**Annotations completas recomendadas para LibreChat:**

```yaml
annotations:
  kubernetes.io/ingress.class: alb
  alb.ingress.kubernetes.io/scheme: internet-facing
  alb.ingress.kubernetes.io/target-type: ip
  alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
  alb.ingress.kubernetes.io/healthcheck-path: /
  alb.ingress.kubernetes.io/healthcheck-interval-seconds: "30"
  alb.ingress.kubernetes.io/healthcheck-timeout-seconds: "5"
  alb.ingress.kubernetes.io/healthy-threshold-count: "2"
  alb.ingress.kubernetes.io/unhealthy-threshold-count: "3"
  alb.ingress.kubernetes.io/success-codes: "200"
```

---

## Solución

### 1. Corregir `values.yaml`

```yaml
ingress:
  enabled: true
  className: alb
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/healthcheck-path: /
    alb.ingress.kubernetes.io/success-codes: "200"
  hosts:
    - host: chat.ejemplo.com
      paths:
        - path: /
          pathType: Prefix
```

### 2. Aplicar con `helm upgrade`

```bash
helm upgrade librechat ./librechat \
  --namespace librechat \
  --values values.yaml
```

### 3. Monitorear hasta que aparezca ADDRESS

```bash
kubectl get ingress -n librechat -w
```

### 4. Verificar que el controller actuó

```bash
kubectl describe ingress librechat -n librechat | grep -A5 Events
# Debe aparecer: Successfully reconciled
```

---

## ¿Cuándo borrar y recrear el Ingress vs helm upgrade?

`helm upgrade` es suficiente cuando solo agregas o cambias annotations.
El controller detecta el diff y reconcilia.

Borrar y recrear el Ingress es necesario cuando:

| Cambio | ¿Requiere recrear? |
|--------|-------------------|
| Agregar annotations faltantes | ❌ upgrade es suficiente |
| Cambiar `scheme` de `internal` a `internet-facing` | ✅ sí, recrear |
| Cambiar tipo de LB (ALB → NLB) | ✅ sí, recrear |
| Cambiar `target-type` | ✅ sí, recrear |

Para recrear manualmente:

```bash
kubectl delete ingress librechat -n librechat
helm upgrade librechat ./librechat --namespace librechat --values values.yaml
```

---

## Checklist pre-deploy

Antes de cada `helm install` con Ingress, verificar:

```text
[ ] ALB Controller instalado y Running en kube-system
[ ] OIDC Provider habilitado en el cluster
[ ] IAM Role del controller con permisos para crear ALBs
[ ] values.yaml incluye annotations mínimas
[ ] healthcheck-path devuelve 200 desde el pod
[ ] Security Group del ALB permite tráfico entrante en 80/443
[ ] Security Group de los pods permite tráfico desde el ALB
```

---

## Lecciones aprendidas

**✅ Qué funcionó bien**
- Descartamos la aplicación antes de buscar en el Ingress
- `Events: <none>` como señal diagnóstica fue clave

**⬜ Action items**

| Acción | Owner | Estado |
|--------|-------|--------|
| Agregar annotations completas al `values.yaml` base del chart | Dev | ✅ |
| Documentar checklist pre-deploy para Ingress en EKS | SRE | ⬜ |
| Agregar alerta si un Ingress lleva >5 min sin ADDRESS | SRE | ⬜ |

---

## Documentación relacionada

- [03-eks-target-group-unhealthy.md](./03-eks-target-group-unhealthy.md)
- [docs/01-eks-ingress-alb.md](../docs/01-eks-ingress-alb.md)
- [AWS Load Balancer Controller — Annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/)