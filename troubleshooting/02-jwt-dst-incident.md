# 🚨 Incident: JWT TokenExpiredError por cambio de horario (DST)

> **Tipo:** Post-mortem / Incident Review
> **Severidad:** P2
> **Área:** Integración con sistema externo — validación de JWT en EKS

---

## Resumen ejecutivo

| Campo | Detalle |
|-------|---------|
| **Severidad** | P2 |
| **Servicio afectado** | API de procesamiento de archivos en EKS |
| **Síntoma visible** | Archivos JSON rechazados como inválidos |
| **Error real** | `TokenExpiredError: jwt expired` en la validación del token |
| **Causa raíz** | Sistema externo genera tokens con `exp` en timezone local; API en EKS valida en UTC |
| **Trigger** | Cambio de horario (DST) creó desfase de 1 hora entre el `exp` generado y el `exp` esperado |
| **Detectado por** | PagerDuty → New Relic (APM) + Datadog (Logs) |

---

## Timeline

```text
[HH:MM] 🔔 PagerDuty dispara P2: "API receiving invalid files — high error rate"
[HH:MM] 🔍 New Relic APM: spike de errores → TokenExpiredError: jwt expired
[HH:MM] 🔍 Datadog Logs: los errores empiezan exactamente al cambio de horario DST
[HH:MM] 🧠 Causa raíz identificada: desfase UTC vs timezone local en el claim exp
[HH:MM] 🔧 Coordinación con equipo del sistema externo para mitigación
[HH:MM] ✅ Error rate vuelve a cero, archivos procesados normalmente
```

---

## ¿Qué estaba pasando?

### Flujo normal

```text
Sistema externo                     API en EKS
──────────────                      ──────────
Genera JWT:
  exp = now() + 3600          ──→   Valida: exp > now() ✅
  (en timezone LOCAL)               (en UTC)
```

### Lo que pasó con DST

```text
=== Antes del cambio DST ===
Sistema externo (America/New_York):
  Hora local: 1:30 AM EST → exp = 2:30 AM EST → en UTC: 7:30 AM UTC ✅

=== Cambio DST: 2:00 AM → retrocede a 1:00 AM ===
Sistema externo:
  Reloj retrocede, sigue calculando exp con hora LOCAL
  exp calculado no coincide con UTC

API en EKS (UTC):
  Recibe token con exp en hora local del sistema externo
  exp < now() (en UTC) → TokenExpiredError ❌
  Rechaza el archivo como "invalid file"
```

### El problema de fondo

El sistema externo usaba `new Date()` con el timezone del sistema operativo
(America/New_York) en vez de UTC para calcular `exp`. Al cambiar el horario,
el desfase entre los dos sistemas superó el margen de tolerancia de la validación.

> ⚠️ Los archivos JSON eran **válidos**. El problema era el token adjunto,
> generado por un sistema fuera de nuestro control directo.

---

## Diagnóstico

### Paso 1 — Acknowledge en PagerDuty y abrir el incidente

```text
🔔 Alert: "API receiving invalid files — high error rate"
Acción: Acknowledge → avisar al equipo → abrir canal de incidente
```

### Paso 2 — New Relic APM

```text
APM → [servicio] → Errors
  ├── Error rate: spike claro a partir de [HH:MM]
  ├── Error más frecuente: "TokenExpiredError: jwt expired"
  └── Stack trace: apunta al middleware de validación JWT
```

Query NRQL útil:

```sql
SELECT count(*)
FROM TransactionError
WHERE appName = 'api-files-processor'
  AND error.message LIKE '%TokenExpired%'
SINCE 3 hours ago
TIMESERIES 5 minutes
```

### Paso 3 — Datadog Logs

```text
Filtro: service:api-files-processor status:error "TokenExpiredError"

Hallazgo clave:
  Los errores empiezan exactamente al momento del cambio de horario DST
  Los pods en EKS están healthy — CPU/Memory normales
  El problema no es de infraestructura nuestra
```

### Paso 4 — Correlación y causa raíz

| Fuente | Qué nos dijo |
|--------|-------------|
| New Relic | **Qué** fallaba: validación JWT, error 401 |
| Datadog | **Cuándo** empezó: exacto al cambio DST |
| Combinación | **Por qué**: sistema externo usa timezone local, nosotros UTC |

---

## Fix y mitigación

### Fix permanente (sistema externo — requiere coordinación)

```text
Solicitar al equipo responsable:
1. Configurar el servidor generador de tokens en UTC (TZ=UTC)
2. Usar Date.now() / 1000 para el campo exp — nunca depender del TZ del OS
3. Documentar el contrato: exp DEBE ser timestamp Unix UTC
```

### Mitigación temporal (nuestra API)

```javascript
const jwt = require('jsonwebtoken');

jwt.verify(token, secret, {
  clockTolerance: 300
});
```

> ⚠️ `clockTolerance` de 300s no cubre 1 hora de desfase DST.
> Es solo un buffer para pequeñas derivas de reloj entre sistemas.
> El fix real debe venir del sistema externo.

### Contrato de integración documentado

```text
📋 Contrato JWT entre sistemas

- El campo exp DEBE ser timestamp Unix UTC
- Se calcula como: Math.floor(Date.now() / 1000) + <segundos de validez>
- El servidor generador de tokens DEBE correr en UTC (TZ=UTC)
- Desviaciones de este contrato causarán rechazos de validación
```

---

## Verificación de recuperación

```bash
# New Relic: error rate volvió a 0%
# Datadog: sin logs de TokenExpiredError
# PagerDuty: alerta resuelta
# Archivos: procesándose normalmente
```

---

## Cómo contarlo en entrevista (STAR)

**Situation:** Teníamos una API en EKS que empezó a rechazar archivos JSON como
inválidos justo al cambio de horario de DST. PagerDuty nos alertó con un P2.

**Task:** Diagnosticar la causa del spike de errores sin contexto previo,
en el menor tiempo posible.

**Action:** Empecé con New Relic para identificar el tipo de error
(`TokenExpiredError`), luego fui a Datadog para correlacionar el timestamp
de inicio con el cambio de horario. Eso me llevó a revisar cómo el sistema
externo generaba el campo `exp` del JWT — encontramos que usaba timezone local
en vez de UTC.

**Result:** Identificamos la causa raíz sin tocar nuestro código ni reiniciar
pods. Coordinamos el fix con el equipo externo y documentamos el contrato de
integración para prevenir la recurrencia.

---

> **Frase clave para entrevista:**
> *"The symptom was in our API, but the root cause was in a system we didn't own.
> The key was not assuming the problem was ours — we used New Relic to identify
> what was failing and Datadog to pinpoint when it started, which pointed
> directly at the DST change and the timezone mismatch."*

---

## Lecciones aprendidas

**✅ Qué funcionó bien**
- PagerDuty detectó el problema antes de que llegaran quejas de usuarios
- Tener New Relic + Datadog permitió correlacionar QUÉ y CUÁNDO rápidamente
- No hicimos cambios apresurados antes de entender la causa

**⬜ Action items**

| Acción | Owner | Estado |
|--------|-------|--------|
| Solicitar fix al equipo del sistema externo (TZ=UTC en generador de tokens) | SRE/PM | ⬜ |
| Documentar contrato de integración JWT entre sistemas | Dev | ⬜ |
| Crear alerta específica para `TokenExpiredError` (no solo "invalid files") | SRE | ⬜ |
| Evaluar `clockTolerance` como mitigación mientras llega el fix | Dev | ⬜ |
| Agregar test de integración con tokens de sistema externo | Dev | ⬜ |
| Escribir runbook para incidentes con dependencias externas | SRE | ⬜ |

---

## Referencias

- [JWT RFC 7519 — exp claim](https://tools.ietf.org/html/rfc7519#section-4.1.4)
- [jsonwebtoken clockTolerance](https://github.com/auth0/node-jsonwebtoken#jwtverifytoken-secretorpublickey-options-callback)
- [DST y sistemas distribuidos](https://codeblog.jonskeet.uk/2019/03/27/storing-utc-is-not-a-silver-bullet/)