# 🚨 Troubleshooting: EKS Target Group Unhealthy

> **Cuándo usar esta guía:** El ALB ya fue creado y el Ingress tiene `ADDRESS`,
> pero el Target Group muestra targets `unhealthy` y los usuarios reciben `502` o timeouts.
>
> Si el problema es que el Ingress no genera ALB, ver primero
> [01-librechat-ingress.md](./01-librechat-ingress.md).

---

## Resumen ejecutivo

| Campo | Detalle |
|-------|---------|
| **Proyecto** | LibreChat en EKS |
| **Herramientas** | Terraform, Helm, AWS ALB Ingress Controller |
| **Síntoma** | ALB existía, Target Group mostraba targets `unhealthy` |
| **Impacto** | Usuarios con `502 Bad Gateway`, timeouts o tráfico intermitente |
| **Causa raíz** | Desalineación en alguna capa del flujo ALB → Ingress → Service → Endpoints → Pods |
| **Solución** | Validar el flujo completo capa por capa y corregir la capa defectuosa |

---

## Flujo de tráfico en EKS con ALB

Entender este flujo es el prerequisito del troubleshooting. El síntoma está en AWS,
pero la causa puede estar en cualquier capa intermedia.

```text
Usuario
  └─→ ALB
        └─→ Target Group  ← aquí aparece "unhealthy"
              └─→ Ingress (aws-load-balancer-controller)
                    └─→ Service
                          └─→ Endpoints
                                └─→ Pods
                                      └─→ Container LibreChat (:3080)
```

---

## Diagnóstico: de afuera hacia adentro

### Paso 1 — Target Group en AWS

```bash
# Ver el motivo exacto de fallo
aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

O en consola: **EC2 → Target Groups → seleccionar TG → pestaña Targets**

| Mensaje de fallo | Qué indica |
|-----------------|------------|
| `Request timed out` | La app no responde o hay problema de red/SG |
| `Response code mismatch` | El path responde pero con código incorrecto (ej. 302, 404) |
| `Connection refused` | Puerto incorrecto o proceso no escuchando |
| Sin targets registrados | Problema en el controller, Service o endpoints |

---

### Paso 2 — Ingress y annotations

```bash
kubectl get ingress -n librechat
kubectl describe ingress librechat -n librechat
```

**Annotations críticas a verificar:**

```yaml
annotations:
  kubernetes.io/ingress.class: alb
  alb.ingress.kubernetes.io/scheme: internet-facing
  alb.ingress.kubernetes.io/target-type: ip
  alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
  alb.ingress.kubernetes.io/healthcheck-path: /
  alb.ingress.kubernetes.io/success-codes: "200"
```

> ⚠️ Si el ALB hace health check a `/health` pero LibreChat solo devuelve `200` en `/`,
> el Target Group quedará `unhealthy` aunque la app funcione.

---

### Paso 3 — Service

```bash
kubectl get svc librechat -n librechat
kubectl describe svc librechat -n librechat
```

**Ejemplo de configuración correcta:**

```yaml
spec:
  selector:
    app: librechat
  ports:
    - port: 80
      targetPort: 3080
```

**Errores frecuentes:**
- `targetPort: 3000` cuando el container escucha en `3080`
- `selector` que no coincide con los labels del Deployment

---

### Paso 4 — Endpoints

```bash
kubectl get endpoints librechat -n librechat
kubectl get endpoints librechat -n librechat -o yaml
```

**Si el output muestra `subsets: []` o está vacío → el Service no tiene pods asociados.**

Causa: selector incorrecto o pods no `Ready`.

---

### Paso 5 — Pods

```bash
kubectl get pods -n librechat
kubectl describe pod <pod-name> -n librechat
kubectl logs <pod-name> -n librechat --tail=50
```

**Estados críticos a detectar:**

```text
READY   STATUS              RESTARTS
0/1     Running             0
0/1     CrashLoopBackOff    5
0/1     ImagePullBackOff    0
```

> Un pod `Running` pero `0/1` en READY no recibe tráfico del Service.

---

### Paso 6 — Readiness probe

```yaml
readinessProbe:
  httpGet:
    path: /
    port: 3080
  initialDelaySeconds: 10
  periodSeconds: 10
  failureThreshold: 3
```

**Causas de fallo:**
- `path` o `port` incorrecto
- `initialDelaySeconds` muy corto
- el endpoint devuelve `302`, `401`, `404` o `500`

---

### Paso 7 — Validar la app desde dentro del pod

```bash
kubectl exec -it <pod-name> -n librechat -- sh
curl -i http://localhost:3080/
```

O directamente:

```bash
kubectl exec -it <pod-name> -n librechat -- curl -i localhost:3080/
```

Si esto falla, el problema está en la aplicación o su configuración interna,
no en Ingress ni en el ALB.

---

## Checklist de diagnóstico rápido

```text
[ ] ALB existe y el Ingress tiene ADDRESS
[ ] Target Group tiene targets registrados con motivo de fallo legible
[ ] healthcheck-path devuelve 200
[ ] Annotations del Ingress son correctas
[ ] Service tiene selector correcto
[ ] Service apunta al targetPort correcto
[ ] kubectl get endpoints muestra IPs
[ ] Pods están Running y Ready
[ ] Readiness probe usa el mismo path y puerto que el health check del ALB
[ ] Security Groups permiten el tráfico necesario
```

---

## Causas raíz más frecuentes

| # | Causa | Síntoma |
|---|-------|---------|
| 1 | `healthcheck-path` responde distinto a 200 | `Response code mismatch` |
| 2 | `targetPort` incorrecto en Service | `Connection refused` |
| 3 | Selector del Service no coincide con pods | Endpoints vacíos |
| 4 | Readiness probe falla | Pods `NotReady` |
| 5 | `target-type` incorrecto | Targets no registrados o timeout |
| 6 | Security Groups incompletos | `Request timed out` |
| 7 | App crashea por dependencias | `CrashLoopBackOff` |

---

## Solución aplicada

La resolución consistió en validar capa por capa y corregir el punto de desalineación:

```bash
# 1. Alinear healthcheck-path con la ruta real que responde 200
alb.ingress.kubernetes.io/healthcheck-path: /

# 2. Corregir targetPort en el Service
targetPort: 3080

# 3. Verificar que existen endpoints después del fix
kubectl get endpoints librechat -n librechat

# 4. Ajustar readiness probe
readinessProbe:
  httpGet:
    path: /
    port: 3080
  initialDelaySeconds: 10
  periodSeconds: 10

# 5. Confirmar desde dentro del pod
kubectl exec -it <pod> -n librechat -- curl -i localhost:3080/
```

Después de alinear estas capas, los targets pasaron a `healthy` y el tráfico se normalizó.

---

## Verificación posterior

```bash
kubectl get ingress -n librechat
kubectl get svc librechat -n librechat
kubectl get endpoints librechat -n librechat
kubectl get pods -n librechat

aws elbv2 describe-target-health --target-group-arn <target-group-arn>
```

**Resultado esperado:**
- targets en estado `healthy`
- tráfico respondiendo por el ALB
- dominio accesible sin `502` ni timeout

---

## Lecciones aprendidas

### ✅ Qué funcionó bien
- Seguir el flujo de tráfico de afuera hacia adentro
- Validar la app desde dentro del pod
- No asumir que el problema estaba “en AWS” solo por el síntoma

### ⬜ Action items

| Acción | Owner | Estado |
|--------|-------|--------|
| Estandarizar `readinessProbe` y `healthcheck-path` en charts | Dev/SRE | ⬜ |
| Agregar checklist de puertos al proceso de deploy | DevOps | ⬜ |
| Crear alarma CloudWatch sobre Target Groups unhealthy | SRE | ⬜ |
| Documentar SG rules necesarios entre ALB y pods | DevOps | ⬜ |

---

## Cómo contarlo en entrevista (STAR)

**Situation:** LibreChat corriendo en EKS con ALB, pero el Target Group mostraba
targets `unhealthy` y los usuarios recibían `502`.

**Task:** Identificar en qué capa del stack estaba el problema real.

**Action:** Tracé el flujo completo de tráfico: revisé el Target Group en AWS,
las annotations del Ingress, el selector y targetPort del Service, los endpoints,
el estado de readiness de los pods, y finalmente hice un `curl` directo desde
dentro del pod para confirmar el comportamiento real de la app.

**Result:** Identifiqué la desalineación entre el `healthcheck-path` del ALB,
el `targetPort` del Service y la `readinessProbe`. Después de alinear estas tres
capas, los targets pasaron a `healthy` y el tráfico se normalizó.

---

> **Frase clave para entrevista:**
> *"When debugging unhealthy ALB targets in EKS, I trace the full request path
> layer by layer — from the load balancer down to the pod — validating ingress
> annotations, service ports, endpoints, readiness probes, and application
> behavior, to isolate the issue quickly instead of guessing."*

---

## Documentación relacionada

- [01-librechat-ingress.md](./01-librechat-ingress.md)
- [docs/01-eks-ingress-alb.md](../docs/01-eks-ingress-alb.md)
- [AWS Load Balancer Controller Annotations](https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/ingress/annotations/)