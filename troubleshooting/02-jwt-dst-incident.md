# 🚨 Incidente: JWT TokenExpiredError por cambio de horario (DST)

## Resumen ejecutivo

| Campo | Detalle |
|-------|---------|
| **Fecha** | [YYYY-MM-DD] |
| **Severity** | P2 |
| **Duración** | [X horas] |
| **Servicio afectado** | API en EKS |
| **Síntoma** | Archivos JSON rechazados como inválidos |
| **Causa raíz** | Tokens JWT generados por sistema externo con timezone local, validados en EKS con UTC |
| **Detectado por** | PagerDuty → New Relic / Datadog |

---

## Timeline del incidente

```text
[HH:MM] 🔔 PagerDuty alerta: "API receiving invalid files" (P2)
   │
   ├─→ SRE on-call recibe la alerta
   │
[HH:MM] 🔍 Revisión en New Relic
   │     → Error rate elevado en la API
   │     → Traces mostrando: TokenExpiredError: jwt expired
   │
[HH:MM] 🔍 Revisión en Datadog
   │     → Logs confirmando: "TokenExpiredError" en pods de EKS
   │     → Spike de errores 401 coincide exactamente con cambio de horario DST
   │
[HH:MM] 🧠 Identificación de causa raíz
   │     → El sistema externo que genera los tokens usa timezone LOCAL
   │     → Nuestra API en EKS valida usando UTC
   │     → El cambio DST creó un desfase en el claim "exp" del JWT
   │
[HH:MM] 🔧 Mitigación aplicada
   │     → [Coordinación con equipo externo / workaround temporal]
   │
[HH:MM] ✅ Servicio recuperado, error rate vuelve a normal
```

---

## ¿Qué estaba pasando?

### El flujo normal

```text
Sistema externo (fuera de EKS)         Nuestra API (EKS)
──────────────────────────────         ─────────────────
1. Genera JWT                       
   exp = now() + 1 hora             
   Token: { exp: 1699336800 }  ──→  2. Recibe archivo JSON + JWT
                                     3. Valida JWT:
                                        ¿exp > now()? ✅
                                     4. Procesa archivo
```

### Lo que pasó con DST

```text
=== ANTES DEL CAMBIO DST ===

Sistema externo (timezone: America/New_York)
  Hora local: 1:30 AM EST
  Genera token: exp = 2:30 AM EST (1 hora)
  En UTC: exp = 7:30 AM UTC ✅

=== CAMBIO DST: 2:00 AM → 1:00 AM ===

Sistema externo (timezone: America/New_York)
  El reloj retrocede a 1:00 AM
  Los tokens generados en ese rango tienen un "exp"
  calculado con hora local que ya no coincide con UTC

  Escenario A: token "del futuro"
  → Generado a las 1:30 AM (primera vez)
  → Reloj vuelve a 1:00 AM
  → El token parece válido por 1.5 horas más de lo esperado

  Escenario B: token ya expirado al llegar
  → Sistema externo calcula exp con hora local
  → Nuestra API valida con UTC
  → El cálculo no coincide → TokenExpiredError ❌

Nuestra API (EKS, usando UTC)
  Recibe token con exp calculado en hora local del sistema externo
  exp no coincide → TokenExpiredError
  Rechaza el archivo JSON como inválido → error reportado como "invalid file"
```

### El problema de fondo

```text
┌──────────────────────────────────────────────────────┐
│                                                        │
│  Sistema externo:  new Date() → hora LOCAL             │
│                    exp = localTime + 3600              │
│                                                        │
│  Nuestra API EKS:  new Date() → UTC                    │
│                    if (exp < Date.now()) → EXPIRED ❌  │
│                                                        │
│  EL PROBLEMA:                                          │
│  Mezclar timezones entre sistemas al calcular          │
│  la expiración del JWT                                 │
│                                                        │
└──────────────────────────────────────────────────────┘
```

> ⚠️ **Nota importante:** La causa estaba en el sistema externo, fuera de nuestro
> control directo. Los archivos JSON eran válidos; el problema era el token que
> los acompañaba.

---

## Paso a paso: Cómo lo diagnostiqué

### Paso 1: Recibí la alerta de PagerDuty

```text
🔔 PagerDuty Alert - P2
Service: api-files-processor
Alert: "High error rate - invalid files received"
Triggered at: [timestamp]
```

**Acción:** Acknowledge la alerta para que el equipo sepa que alguien está investigando.

### Paso 2: Fui a New Relic (APM)

```text
New Relic → APM → [nombre del servicio] → Errors

1. Error rate → Vi un spike claro
2. Click en el error más frecuente
3. Error message: "TokenExpiredError: jwt expired"
4. Stack trace → Apuntaba al middleware de validación JWT
5. Transactions → Las requests llegaban pero fallaban en la validación del token
```

**Query NRQL útil:**
```sql
SELECT count(*) 
FROM TransactionError 
WHERE appName = 'api-files-processor' 
AND error.message LIKE '%TokenExpired%' 
SINCE 3 hours ago 
TIMESERIES 5 minutes
```

### Paso 3: Fui a Datadog (Logs + Infra)

```text
Datadog → Logs → Filtrar:

1. service:api-files-processor status:error
2. Vi los logs con "TokenExpiredError: jwt expired"
3. El timestamp de los errores coincidía exactamente con el cambio de horario DST

Datadog → Infrastructure → Kubernetes:
4. Los pods estaban healthy (no era problema de infra nuestra)
5. CPU/Memory normales
6. El problema no era de recursos ni de código nuestro
```

**Query de logs útil:**
```
service:api-files-processor "TokenExpiredError"
```

### Paso 4: Correlacioné los datos

```text
New Relic me dijo  → QUÉ estaba fallando (JWT validation, 401s)
Datadog me dijo    → CUÁNDO empezó (exacto al cambio DST)
La combinación     → POR QUÉ: el sistema externo genera tokens con hora local,
                     nosotros validamos en UTC → desfase al cambio de horario
```

### Paso 5: Confirmé la causa raíz

```text
- El error TokenExpiredError solo aparece desde el cambio de horario
- Nuestra infraestructura y código están en UTC (correcto)
- La fuente del problema está en el sistema externo que genera los tokens
- Ese sistema usa timezone local (America/New_York) en vez de UTC
```

### Paso 6: Mitigación

```text
Dado que la causa está en el sistema externo:

Opción A (corto plazo):
  → Notificar al equipo/proveedor del sistema externo
  → Solicitarles que configuren TZ=UTC en su generador de tokens

Opción B (workaround temporal si aplica):
  → Ampliar la ventana de tolerancia en la validación del JWT
     (clock skew tolerance) para absorber el desfase de 1 hora
  → SOLO como medida temporal mientras se coordina el fix real

Opción C (largo plazo):
  → Agregar validación defensiva que detecte tokens con exp en hora local
  → Documentar el contrato: los tokens DEBEN usar UTC
```

### Paso 7: Verifiqué la recuperación

```text
1. New Relic → Error rate volvió a 0%
2. Datadog → No más logs de TokenExpiredError
3. PagerDuty → Resolví la alerta
4. Los archivos JSON se empezaron a procesar normalmente
```

---

## Causa raíz (Root Cause)

```text
El sistema externo que genera los JWT tokens usaba timezone local
(America/New_York) en vez de UTC para calcular el claim "exp".

Cuando ocurrió el cambio de horario (DST), el claim "exp" quedó
desfasado 1 hora respecto a lo que nuestra API en EKS esperaba (UTC).

Los archivos JSON que llegaban eran válidos, pero el token adjunto
no pasaba la validación de expiración → rechazado como "invalid file".
```

---

## Fix permanente

### En el sistema externo (coordinación requerida)

```text
Solicitar al equipo responsable del sistema externo que:
1. Configuren el servidor/proceso generador de tokens en UTC
2. Usen siempre Math.floor(Date.now() / 1000) para el campo exp
3. No dependan del timezone del sistema operativo para cálculos de JWT
```

### En nuestra API (defensa propia)

```javascript
// Agregar tolerancia a pequeños desfases de reloj (clock skew)
// Esto absorbe diferencias menores pero NO es el fix real

const jwt = require('jsonwebtoken');

jwt.verify(token, secret, {
  clockTolerance: 300  // 5 minutos de tolerancia (en segundos)
});

// Para DST (1 hora = 3600s), esto NO alcanza.
// El fix real debe venir del sistema externo.
```

### Contrato documentado entre sistemas

```text
📋 Contrato de integración: tokens JWT

- El campo "exp" DEBE ser un timestamp Unix en UTC
- Se calcula como: Math.floor(Date.now() / 1000) + <segundos de validez>
- El servidor que genera tokens DEBE correr en UTC (TZ=UTC)
- Cualquier desviación de este contrato causará rechazos en validación
```

---

## Lecciones aprendidas

### ✅ Qué hicimos bien
- PagerDuty detectó el problema rápidamente
- Teníamos observabilidad en New Relic y Datadog
- El diagnóstico fue metódico: descartamos infra propia antes de señalar al externo
- No hicimos cambios apresurados en nuestro código antes de entender la causa

### ❌ Qué debemos mejorar
1. **No había contrato documentado** con el sistema externo sobre timezones en JWT
2. **La alerta era genérica** ("invalid files") en vez de apuntar a JWT directamente
3. **No teníamos test de integración** que simulara tokens de sistemas externos
4. **Falta de runbook** para incidentes con dependencias externas

### 🛡️ Action items

| # | Acción | Owner | Estado |
|---|--------|-------|--------|
| 1 | Notificar al equipo del sistema externo y solicitar fix (TZ=UTC) | SRE / PM | ⬜ |
| 2 | Documentar contrato de integración JWT entre sistemas | Dev | ⬜ |
| 3 | Agregar alerta específica para TokenExpiredError (no solo "invalid files") | SRE | ⬜ |
| 4 | Evaluar clock skew tolerance como mitigación temporal | Dev | ⬜ |
| 5 | Agregar test de integración con tokens de sistema externo | Dev | ⬜ |
| 6 | Escribir runbook para incidentes con dependencias externas | SRE | ⬜ |

---

## Referencias

- [JWT RFC 7519 - exp claim](https://tools.ietf.org/html/rfc7519#section-4.1.4)
- [DST y sus problemas en sistemas distribuidos](https://codeblog.jonskeet.uk/2019/03/27/storing-utc-is-not-a-silver-bullet/)
- [jsonwebtoken clockTolerance option](https://github.com/auth0/node-jsonwebtoken#jwtverifytoken-secretorpublickey-options-callback)
