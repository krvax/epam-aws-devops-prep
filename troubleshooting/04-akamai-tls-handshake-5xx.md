# 04 — Akamai Certificate Pinning Failure → 5xx (T-Mobile Domain Management)

## Resumen
Un subdominio del portal de clientes de T-Mobile dejó de funcionar.
Usuarios y un third party recibían 5xx al intentar acceder a contenido
servido por AEM/Konector detrás de Akamai CDN. La causa fue una rotación
de certificado donde el origin ya presentaba el cert nuevo pero el
certificate pinning en la Akamai Property todavía apuntaba al cert viejo.
Resolví el incidente durante on-call actualizando el pin en Akamai
Property Manager para incluir ambos certificados (viejo y nuevo).

## Contexto
- **Empresa**: T-Mobile
- **Mi rol**: Domain Management team, on-call
- **Stack**:
  ```
  Usuarios / 3rd party
         ↓
      Akamai CDN
         ↓
    Property config (mapea subdominios)
         ↓                    ↓
    AEM (contenido)    Konector (contenido)
  ```
- **Severidad**: SEV1 — subdominio completamente inaccesible
- **Detección**: Reportes de usuarios + alertas de disponibilidad

## Qué es certificate pinning en Akamai
En Akamai Property Manager se puede configurar que la conexión al
origin solo se establezca si el certificado TLS presentado coincide
con un fingerprint (pin) previamente configurado. Esto previene
ataques MITM pero introduce un punto de fallo si el certificado
del origin cambia sin actualizar el pin.

## Qué pasó (secuencia real)

```
Paso 1: Se rota el certificado del subdominio
         └─ cert A (viejo, en producción)
         └─ cert B (nuevo, generado para la rotación)

Paso 2: El origin (AEM/Konector) ya presenta cert B
         └─ El cambio se propagó al origin ✅

Paso 3: Akamai Property todavía tiene pineado cert A ❌
         └─ No se actualizó el pin antes del cambio en origin

Paso 4: Akamai intenta TLS handshake con origin
         └─ Origin presenta cert B
         └─ Pin en Akamai espera cert A
         └─ MISMATCH → handshake failure → 5xx

Paso 5: Usuarios y 3rd party no pueden acceder al contenido
         └─ 100% de requests al subdominio fallan
```

## Síntomas iniciales
1. 5xx en el subdominio afectado — outage total para ese contenido
2. Akamai devolvía cadena de error de referencia:
   ```
   Reference #18.xxxxxxxx.xxxxxxxxxx.xxxxxxx
   ```
   Esta cadena es el identificador interno de Akamai que indica
   fallo en la conexión edge → origin
3. Otros subdominios en la misma Akamai config funcionaban normal
4. El origin respondía correctamente al consultarlo directo (bypass Akamai)
5. Logs del origin **no mostraban requests entrantes** — morían en
   el handshake antes de llegar

## Investigación (on-call)

### Paso 1 — Identificar que el problema era Akamai → Origin
```bash
# La cadena de referencia de Akamai indicaba connection failure
# No era problema de caché ni de routing
# Otros subdominios OK → problema específico de este subdominio/origin
```

### Paso 2 — Verificar el origin directamente
```bash
# Bypass Akamai, conectar directo al origin
openssl s_client -connect <origin-host>:443 -servername <subdominio>

# Resultado: handshake exitoso
# Pero el certificado presentado era DIFERENTE al que Akamai esperaba
```

### Paso 3 — Confirmar el mismatch de certificado
```bash
# Fingerprint del cert que presentaba el origin (cert B — nuevo)
openssl s_client -connect <origin-host>:443 -servername <subdominio> \
  2>/dev/null | openssl x509 -noout -fingerprint -sha256
# SHA256 Fingerprint = BB:BB:BB:... (cert B)

# Pin en Akamai Property Manager:
# SHA256 Fingerprint = AA:AA:AA:... (cert A — viejo)
# → MISMATCH confirmado
```

### Paso 4 — Correlacionar con la rotación de certificado
```bash
# Confirmé con el equipo:
# - Cert B fue generado como parte de rotación planificada
# - El origin ya lo tenía instalado
# - El pin en Akamai NO se actualizó antes del cambio
# → Causa raíz identificada
```

## Causa raíz
Durante una rotación de certificado, el origin (AEM/Konector) ya
presentaba el certificado nuevo, pero el certificate pinning en la
Akamai Property del subdominio no fue actualizado previamente.
Esto causó un TLS handshake failure en todas las conexiones de
Akamai al origin, resultando en 5xx para todos los usuarios y
el third party que accedían a ese subdominio.

## Resolución

### Fix en Akamai Property Manager
Actualicé el certificate pinning en la Property del subdominio
afectado para incluir **ambos certificados**:

```
Akamai Property Manager
  → Property del subdominio afectado
    → Origin Server configuration
      → Certificate Pinning

Pins configurados (post-fix):
  Pin 1: cert B (nuevo — el que el origin ya presentaba) ✅
  Pin 2: cert A (viejo — mantenido como fallback)        ✅
```

### Pasos exactos del fix
1. Accedí a Akamai Property Manager
2. Abrí la Property del subdominio afectado
3. En la configuración de Origin SSL, localicé el certificate pinning
4. Agregué el fingerprint del cert nuevo (cert B)
5. **Mantuve el cert viejo (cert A)** como segundo pin (transición segura)
6. Guardé y activé la nueva versión de la Property:
   - Primero en **staging** → validé que el handshake funcionara
   - Luego en **production**
7. Verifiqué que el subdominio respondiera correctamente
8. Monitoreé: 0 errores 5xx post-fix

### Por qué pinear ambos certs (no solo el nuevo)
- **Rollback safety**: si había que revertir al cert viejo en el
  origin por cualquier razón, Akamai seguiría conectando
- **Transición gradual**: permite validar el cert nuevo en producción
  antes de eliminar el pin viejo
- **Best practice**: siempre mantener al menos 2 pins activos para
  evitar outages durante rotaciones

## Timeline
| Tiempo  | Evento |
|---------|--------|
| T+0     | Alertas: 5xx en el subdominio, usuarios no pueden acceder |
| T+10m   | On-call (yo) confirma: outage total en ese subdominio |
| T+15m   | Verifico origin directo: responde OK → problema en Akamai→Origin |
| T+20m   | Identifico cadena de error Akamai (Reference #18...) |
| T+25m   | Comparo fingerprints: cert del origin ≠ pin en Akamai Property |
| T+30m   | Confirmo con equipo: rotación de cert sin actualizar pin |
| T+35m   | Agrego ambos pins en Akamai Property Manager |
| T+40m   | Activo en staging → valido handshake OK |
| T+45m   | Activo en producción |
| T+50m   | Subdominio restaurado, 0 errores |
| T+80m   | Monitoreo confirmado, incidente cerrado |

## Impacto
- **Duración**: ~50 minutos de outage
- **Afectados**: Todos los usuarios + third party que accedían al subdominio
- **Causa**: Falta de coordinación en el proceso de rotación de certificados

## 5 Whys
1. **¿Por qué los usuarios veían 5xx?**
   → Akamai no podía establecer conexión TLS con el origin

2. **¿Por qué fallaba la conexión TLS?**
   → Certificate pinning en la Akamai Property no coincidía con el
   cert que presentaba el origin

3. **¿Por qué no coincidía?**
   → El origin ya tenía el cert nuevo pero el pin en Akamai seguía
   apuntando al cert viejo

4. **¿Por qué no se actualizó el pin antes?**
   → No había un proceso definido que exigiera actualizar el pin
   en Akamai **antes** de instalar el cert nuevo en el origin

5. **¿Por qué no se detectó antes de que impactara usuarios?**
   → No había validación automatizada post-cambio de certificado
   que verificara el pinning de Akamai contra el cert del origin

## Action Items
| Acción | Owner | Prioridad |
|--------|-------|-----------|
| Definir runbook: "Rotación de certificados con Akamai pinning" | Domain Management | P0 |
| El pin en Akamai debe actualizarse ANTES de instalar cert en origin | Domain Management | P0 |
| Siempre mantener 2+ pins (current + next) durante rotaciones | Domain Management | P1 |
| Implementar monitoreo: comparar cert fingerprint del origin vs pin en Akamai | SRE / Monitoring | P1 |
| Agregar step de validación TLS en el checklist de cambios de dominio | Domain Management | P1 |
| Evaluar pinning por public key hash (más resiliente a rotaciones) | Security | P2 |

## Lecciones aprendidas
- En rotaciones de certificado con Akamai pinning, el orden importa:
  **primero** actualizar el pin, **después** cambiar el cert en el origin
- Mejor aún: agregar el pin del cert nuevo **antes** de la rotación,
  mantener ambos, y luego remover el viejo post-validación
- La cadena de error `Reference #18...` de Akamai indica fallo en
  la conexión edge→origin — no es un error de la aplicación
- Cuando el origin no muestra requests en sus logs pero hay 5xx,
  el problema está **antes** del origin (TLS, DNS, routing, CDN)

## Respuesta STAR para entrevista

**Situation**: En T-Mobile trabajaba en el equipo de Domain Management.
Gestionábamos subdominios del portal de clientes que pasaban por Akamai
CDN hacia origins en AEM y Konector. Durante una rotación de certificado
planificada, el subdominio dejó de funcionar — usuarios y un third party
recibían 5xx. Me tocó el incidente en on-call.

**Task**: Diagnosticar y resolver el outage del subdominio lo antes
posible. Era un SEV1, customer-facing, afectando a todos los usuarios
de ese contenido.

**Action**: Primero verifiqué que el origin respondía correctamente
conectándome directo con `openssl s_client`, lo que descartó un
problema en AEM. Luego revisé la cadena de error de Akamai
(`Reference #18...`) que indicaba fallo en la conexión al origin.
Comparé el fingerprint del certificado que presentaba el origin con
el pin configurado en la Akamai Property y confirmé el mismatch:
el origin ya tenía el cert nuevo pero Akamai seguía pineando el viejo.
Accedí a Akamai Property Manager y actualicé el certificate pinning
para incluir ambos certificados — el nuevo y el viejo como fallback.
Activé primero en staging, validé, y luego en producción.

**Result**: Servicio restaurado en aproximadamente 50 minutos.
Como mejora, establecí un runbook de rotación de certificados que
requiere actualizar el pin en Akamai **antes** de instalar el nuevo
cert en el origin, y adopté la práctica de siempre mantener al menos
dos pins activos durante transiciones.

## Comandos útiles (referencia rápida)

```bash
# Ver certificado actual del origin
openssl s_client -connect <origin>:443 -servername <subdominio> \
  2>/dev/null | openssl x509 -noout -text

# Obtener fingerprint SHA256 del origin
openssl s_client -connect <origin>:443 -servername <subdominio> \
  2>/dev/null | openssl x509 -noout -fingerprint -sha256

# Verificar fecha de expiración
openssl s_client -connect <origin>:443 -servername <subdominio> \
  2>/dev/null | openssl x509 -noout -dates

# Verificar cadena completa de certificados
openssl s_client -connect <origin>:443 -servername <subdominio> \
  -showcerts 2>/dev/null

# Simular handshake con cipher específico
openssl s_client -connect <origin>:443 -servername <subdominio> \
  -tls1_2 -cipher ECDHE-RSA-AES256-GCM-SHA384

# Ver subject y issuer rápido
openssl s_client -connect <origin>:443 -servername <subdominio> \
  2>/dev/null | openssl x509 -noout -subject -issuer
```

## Diagrama del incidente

```
                    ANTES (funcionaba)
                    ==================
Usuario/3rd party → Akamai CDN → Property (pin=certA)
                                      ↓ TLS handshake
                                 Origin AEM/Konector [certA] ✅


                    DURANTE EL OUTAGE
                    ==================
Usuario/3rd party → Akamai CDN → Property (pin=certA)
                                      ↓ TLS handshake
                                 Origin AEM/Konector [certB] ❌
                                 pin mismatch → 5xx


                    DESPUÉS DEL FIX
                    ================
Usuario/3rd party → Akamai CDN → Property (pin=certA + certB)
                                      ↓ TLS handshake
                                 Origin AEM/Konector [certB] ✅
```
