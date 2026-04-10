# 🐛 Issue: LibreChat Ingress no generaba ALB en EKS

## Resumen ejecutivo

| Campo | Detalle |
|-------|---------|
| **Fecha** | [YYYY-MM-DD] |
| **Proyecto** | LibreChat en EKS |
| **Herramienta** | Helm |
| **Cluster** | [nombre del cluster] |
| **Región** | [us-east-1, etc.] |
| **Síntoma** | Ingress creado pero sin ALB, Target Group con targets unhealthy |
| **Causa raíz** | Annotations incorrectas desde el `helm install` inicial; el ALB Controller quedó en silencio |
| **Solución** | Corregir annotations en `values.yaml` + `helm upgrade` para forzar reconciliación |

---

## Síntoma

Al hacer `helm install` de LibreChat, el Ingress se creó pero:

- No se generaba el ALB en AWS
- `kubectl get ingress` mostraba la columna `ADDRESS` vacía
- El Target Group en AWS Console mostraba targets **unhealthy**
- Al acceder al dominio: timeout / 502

---

## Contexto: cómo funciona el ALB Controller

Antes del diagnóstico, es clave entender el flujo:

```text
helm install / upgrade
    │
    └─→ Crea/actualiza el objeto Ingress en Kubernetes
              │
              └─→ ALB Controller detecta el cambio
                        │
                        ├─→ Si las annotations son correctas
                        │     → Crea / reconcilia el ALB en AWS ✅
                        │
                        └─→ Si las annotations están mal o faltan
                              → El controller no sabe qué hacer
                              → Se queda en SILENCIO ❌
                              → No loggea error, simplemente no actúa
```

> ⚠️ **Esto es lo confuso:** el ALB Controller no grita cuando algo está mal.
> Si las annotations son incorrectas o incompletas, simplemente no hace nada,
> y es difícil saber si el problema está en Kubernetes, en AWS, o en Helm.

---

## Diagnóstico paso a paso

### Paso 1: Verificar si el Ingress tiene ADDRESS

```bash
kubectl get ingress
```

**Output esperado (funcionando):**
```
NAME        CLASS   HOSTS              ADDRESS                                           PORTS   AGE
librechat   alb     chat.ejemplo.com   k8s-xxxx.us-east-1.elb.amazonaws.com             80      5m
```

**Output real (con el problema):**
```
NAME        CLASS   HOSTS              ADDRESS   PORTS   AGE
librechat   alb     chat.ejemplo.com             80      10m
```

`ADDRESS` vacío = el ALB Controller no creó el ALB. El problema está
antes de AWS, en cómo el controller interpreta el Ingress.

---

### Paso 2: Verificar que los pods están corriendo

```bash
kubectl get pods
```

```
NAME                         READY   STATUS    RESTARTS   AGE
librechat-xxxxxxxxx-xxxxx    1/1     Running   0          10m
mongodb-xxxxxxxxx-xxxxx      1/1     Running   0          10m
```

Los pods están bien. El problema no es la aplicación, es el Ingress.

---

### Paso 3: Verificar que el ALB Controller está instalado y corriendo

```bash
kubectl get pods -n kube-system | grep load-balancer
```

```
aws-load-balancer-controller-xxxxxxxxx-xxxxx   1/1   Running   0   2d
```

El controller está corriendo. Entonces el problema no es que falte,
sino que está en silencio.

---

### Paso 4: Revisar los logs del ALB Controller

```bash
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=50
```

**Lo que vimos:** sin mensajes de error. Sin actividad relacionada con el Ingress de LibreChat.

Esto confirma el patrón: **el controller no está rechazando el Ingress,
simplemente lo está ignorando** porque las annotations no le dicen qué hacer.

---

### Paso 5: Inspeccionar el Ingress en detalle

```bash
kubectl describe ingress librechat
```

```
Name:             librechat
Namespace:        default
Address:
Ingress Class:    alb
Rules:
  Host              Path  Backends
  ────              ────  ────────
  chat.ejemplo.com  /     librechat:3080 (10.0.x.x:3080)
Annotations:
  kubernetes.io/ingress.class: alb
  # ← faltan annotations críticas del ALB Controller
Events:
  <none>    # ← sin eventos = el controller no intentó nada
```

`Events: <none>` es la señal definitiva. El ALB Controller nunca intentó
crear el ALB porque no tenía suficiente información en las annotations.

---

### Paso 6: Identificar las annotations que faltaban

El ALB Controller de AWS requiere annotations específicas para saber
cómo crear el ALB. Sin ellas, no actúa.

**Annotations mínimas necesarias:**

```yaml
annotations:
  kubernetes.io/ingress.class: alb                          # tipo de ingress
  alb.ingress.kubernetes.io/scheme: internet-facing         # público o interno
  alb.ingress.kubernetes.io/target-type: ip                 # ip (pods) o instance (nodos)
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
```

---

## Causa raíz

```text
El helm install inicial creó el Ingress sin las annotations
requeridas por el ALB Controller de AWS.

El ALB Controller, al no encontrar las annotations que necesita
para tomar decisiones, no generó ningún error ni evento:
simplemente no actuó.

Como el objeto Ingress existía pero estaba incompleto,
los helm upgrade posteriores no cambiaban las annotations
(porque tampoco estaban en el values.yaml), por lo que
el controller seguía sin recibir la señal para actuar.

El ciclo de confusión:
  helm upgrade → Ingress no cambia → Controller sigue en silencio
  → ALB sigue sin crearse → targets siguen unhealthy
```

---

## Solución

### 1. Corregir el `values.yaml` de Helm

```yaml
# values.yaml
ingress:
  enabled: true
  className: alb
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/healthcheck-path: /
  hosts:
    - host: chat.ejemplo.com
      paths:
        - path: /
          pathType: Prefix
```

### 2. Aplicar con helm upgrade

```bash
helm upgrade librechat ./librechat \
  --namespace default \
  --values values.yaml
```

Al cambiar las annotations, el objeto Ingress cambia en Kubernetes.
El ALB Controller detecta el cambio y ahora sí tiene la información
para crear el ALB correctamente.

### 3. Verificar que el ALB se está creando

```bash
# Monitorear el Ingress hasta que aparezca ADDRESS
kubectl get ingress -w

# Verificar que el controller actuó
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=50

# Ver eventos del Ingress (ahora sí debe haber)
kubectl describe ingress librechat
```

**Output esperado en los eventos:**
```
Events:
  Type    Reason                  Age   Message
  ────    ──────                  ───   ───────
  Normal  SuccessfullyReconciled  30s   Successfully reconciled
```

### 4. Verificar en AWS Console

```text
EC2 → Load Balancers → buscar el ALB creado
  → Listeners: debe existir el puerto 80
  → Target Groups → Targets → deben pasar a "healthy" en ~2 minutos
```

---

## ¿Por qué helm upgrade funcionó y no fue necesario borrar el Ingress?

```text
Borrar y recrear el Ingress es necesario cuando el cambio que
necesitas hacer NO puede aplicarse en caliente, por ejemplo:

  - Cambiar scheme de "internal" a "internet-facing"
  - Cambiar el tipo de load balancer (ALB → NLB)
  - Modificar subnets o VPC

En este caso, el cambio era agregar annotations que antes no
existían. Eso sí puede aplicarse en caliente:

  helm upgrade actualiza el Ingress
      → el objeto cambia en Kubernetes
      → el controller detecta el diff
      → reconcilia el ALB con la nueva configuración ✅

Si el upgrade no hubiera funcionado, el siguiente paso
hubiera sido:

  kubectl delete ingress librechat
  helm upgrade librechat ./librechat --values values.yaml
  # El controller crea un ALB nuevo desde cero
```

---

## Lecciones aprendidas

### ✅ Qué hicimos bien
- Descartamos la aplicación (pods corriendo) antes de buscar el problema en el Ingress
- Identificamos el silencio del controller como señal, no como ausencia de problema

### ❌ Qué debemos mejorar
1. **El ALB Controller en silencio es el síntoma más confuso** — revisar `kubectl describe ingress` y buscar `Events: <none>` debe ser el primer paso
2. **Las annotations no estaban en el `values.yaml` desde el inicio** — deben vivir en el chart, no aplicarse manualmente después
3. **Faltaba un checklist pre-deploy** que verificara annotations antes del `helm install`

### 🛡️ Action items

| # | Acción | Owner | Estado |
|---|--------|-------|--------|
| 1 | Agregar annotations completas al `values.yaml` base del chart | Dev | ✅ |
| 2 | Documentar checklist pre-deploy para Ingress en EKS | SRE | ⬜ |
| 3 | Agregar alerta si un Ingress lleva más de 5 min sin ADDRESS | SRE | ⬜ |
| 4 | Revisar todos los Ingress del cluster que no tengan annotations mínimas | SRE | ⬜ |

---

## Checklist: Ingress + ALB en EKS

Antes de hacer `helm install` con un Ingress, verificar:

```text
[ ] ALB Controller instalado en kube-system
[ ] IAM Role del controller con permisos para crear ALBs
[ ] annotations mínimas en el Ingress:
    [ ] kubernetes.io/ingress.class: alb
    [ ] alb.ingress.kubernetes.io/scheme
    [ ] alb.ingress.kubernetes.io/target-type
[ ] Security Group del ALB permite tráfico entrante (80/443)
[ ] Security Group de los pods permite tráfico desde el ALB
[ ] El healthcheck-path devuelve 200 en la app
```

---

## Documentación relacionada

- [Conceptos: Ingress, ALB y Target Groups](../docs/01-eks-ingress-alb.md)
- [Lab: LibreChat en EKS](../labs/lab-01-librechat-eks/README.md)
- [AWS Load Balancer Controller - Annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.6/guide/ingress/annotations/)
