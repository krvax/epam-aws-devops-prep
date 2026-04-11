# 05 — Observabilidad & Monitoreo

> Stack cubierto: Splunk (primario), CloudWatch, Datadog, New Relic.
> Enfocado en los conceptos que EPAM pregunta y en cómo conectar
> tu experiencia real con el lenguaje de la entrevista.

---

## Índice

1. [Los 3 pilares de la observabilidad](#1-los-3-pilares-de-la-observabilidad)
2. [Splunk — tu herramienta principal](#2-splunk)
3. [CloudWatch — el stack nativo de AWS](#3-cloudwatch)
4. [Datadog — observabilidad unificada](#4-datadog)
5. [New Relic — APM y full-stack](#5-new-relic)
6. [Tabla comparativa: cuándo usar cuál](#6-tabla-comparativa)
7. [SLIs, SLOs y Error Budget](#7-slis-slos-y-error-budget)
8. [Alertas: cómo diseñarlas bien](#8-alertas-cómo-diseñarlas-bien)
9. [Preguntas de entrevista con esquema de respuesta](#9-preguntas-de-entrevista)

---

## 1. Los 3 pilares de la observabilidad

Antes de hablar de herramientas, este es el marco conceptual que debes manejar
en la entrevista. Todo lo que hacen Splunk, Datadog, CloudWatch y New Relic
encaja en estos tres pilares:

```
┌─────────────────────────────────────────────────────────┐
│                  OBSERVABILIDAD                         │
├───────────────┬──────────────────┬──────────────────────┤
│   MÉTRICAS    │      LOGS        │       TRAZAS         │
│               │                  │                      │
│ ¿Qué tan sano │ ¿Qué pasó        │ ¿Por qué tardó       │
│ está el        │ exactamente y    │ tanto esta           │
│ sistema?       │ cuándo?          │ request?             │
│               │                  │                      │
│ CPU, mem,     │ Eventos,         │ Request de extremo   │
│ error rate,   │ errores,         │ a extremo a través   │
│ latencia p99  │ auditoría        │ de microservicios    │
│               │                  │                      │
│ Splunk ITSI   │ Splunk Core      │ Splunk APM           │
│ CloudWatch    │ CloudWatch Logs  │ New Relic APM        │
│ Datadog       │ Datadog Logs     │ Datadog APM          │
│ New Relic     │ New Relic Logs   │ AWS X-Ray            │
└───────────────┴──────────────────┴──────────────────────┘
```

**Los 4 golden signals** (Google SRE Book) — lo que siempre debes monitorear:

| Signal | Qué mide | Ejemplo de alerta |
|--------|----------|-------------------|
| **Latency** | Tiempo de respuesta (p50, p95, p99) | p99 > 500ms por 5 min |
| **Traffic** | Volumen de requests | Caída > 50% vs baseline |
| **Errors** | Tasa de errores (5xx, excepciones) | Error rate > 1% por 2 min |
| **Saturation** | Qué tan lleno está el sistema | CPU > 85% por 10 min |

> 💡 **En la entrevista**: cuando te pregunten qué monitorearías para un servicio,
> responde con los 4 golden signals. Es la respuesta que esperan los ingenieros senior.

---

## 2. Splunk

### Por qué Splunk es tu ventaja en esta entrevista

Splunk es el estándar en empresas enterprise para log management y SIEM.
El hecho de que lo hayas usado en producción (dashboards, alertas, logs, APM)
te pone por encima de la mayoría de candidatos que solo conocen CloudWatch.

**Cómo presentarlo en la entrevista**:
> *"My primary observability platform has been Splunk. I've built dashboards for
> golden signals monitoring, written SPL queries for incident investigation,
> configured alerts with on-call routing, and used Splunk APM for distributed
> tracing across microservices."*

---

### Arquitectura de Splunk (para explicarla en entrevista)

```
Tus apps / servidores
        │
        │  (Universal Forwarder — agente ligero)
        ▼
  Heavy Forwarder          ← parsea, filtra, enruta
        │
        ▼
   Indexer(s)              ← almacena e indexa los datos
        │
        ▼
  Search Head(s)           ← donde tú haces las búsquedas y dashboards
```

En cloud (Splunk Cloud): la arquitectura es la misma pero gestionada por Splunk.
En EKS: el Universal Forwarder corre como DaemonSet (un pod por nodo).

---

### SPL — Search Processing Language

SPL es el lenguaje de consulta de Splunk. Funciona como un pipeline de Unix:
cada `|` pasa el resultado al siguiente comando.

```splunk
"Mostrar error rate de la API de pagos en los últimos 15 minutos"

index=prod sourcetype=app_logs service=payments
| eval is_error = if(status_code >= 500, 1, 0)
| stats count as total, sum(is_error) as errors by _time span=1m
| eval error_rate = round((errors/total)*100, 2)
| timechart span=1m avg(error_rate) as "Error Rate %"
```

```splunk
"Top 10 endpoints más lentos (p95 de latencia)"

index=prod sourcetype=nginx_access
| eval latency_ms = response_time * 1000
| stats perc95(latency_ms) as p95_latency by uri_path
| sort -p95_latency
| head 10
| rename uri_path as "Endpoint", p95_latency as "p95 Latency (ms)"
```

```splunk
"Detectar anomalías: hosts con errores fuera de lo normal"

index=prod sourcetype=app_logs level=ERROR
| stats count as error_count by host, _time span=5m
| streamstats avg(error_count) as avg_errors stdev(error_count) as std_errors by host
| eval anomaly = if(error_count > avg_errors + (2 * std_errors), "YES", "NO")
| where anomaly="YES"
```

```splunk
"Correlacionar deploys con picos de error (para post-mortem)"

(index=prod sourcetype=app_logs level=ERROR)
OR
(index=ops sourcetype=deploy_events)
| eval event_type = if(sourcetype="deploy_events", "DEPLOY", "ERROR")
| timechart span=5m count(eval(event_type="ERROR")) as errors,
            count(eval(event_type="DEPLOY")) as deploys
```

### Alertas en Splunk

```
Tipos de alert en Splunk:
1. Scheduled Alert  → corre una búsqueda cada X tiempo, alerta si el resultado cumple condición
2. Real-time Alert  → monitoreo continuo, más costoso en recursos

Ejemplo de alerta bien configurada:
- Búsqueda: error rate > 1% en ventana de 5 minutos
- Schedule: cada 5 minutos
- Trigger condition: "Number of results > 0"
- Throttle: no alertar más de 1 vez cada 30 minutos (evitar alert fatigue)
- Action: PagerDuty webhook → on-call engineer
```

### Splunk APM (trazas distribuidas)

```
Splunk APM usa OpenTelemetry para instrumentar las apps.

Lo que ves en APM:
- Flame graph: visualización de cuánto tiempo tomó cada parte de la request
- Service map: qué servicios llaman a qué otros servicios
- Error traces: las trazas específicas que terminaron en error

Ejemplo de lo que puedes explicar en entrevista:
"Teníamos un timeout intermitente en el checkout. Con Splunk APM encontré que
el 95% del tiempo de la request se iba en una llamada al servicio de inventario.
El flame graph mostró que era una query SQL sin índice. Lo resolvimos en 20 minutos
gracias a la traza — sin APM habría tomado horas de debugging manual."
```

---

## 3. CloudWatch

### Por qué importa aunque uses Splunk

CloudWatch es el sistema de observabilidad **nativo de AWS**. Incluso si usas Splunk
o Datadog como plataforma principal, CloudWatch sigue siendo importante porque:
- Es donde llegan por defecto los logs de Lambda, ECS, EKS
- Las alarmas de Auto Scaling usan métricas de CloudWatch
- CloudTrail → CloudWatch Logs es el estándar de auditoría en AWS
- No requiere agente para métricas de EC2, RDS, ALB, etc.

### Componentes clave

```
CloudWatch
├── Metrics          → series de tiempo (CPU, memoria, custom metrics)
├── Logs             → grupos y streams de logs
│   └── Logs Insights → queries sobre logs (como SPL pero más limitado)
├── Alarms           → alertas sobre métricas
├── Dashboards       → visualización
└── Container Insights → métricas y logs de EKS/ECS automáticamente
```

### Métricas y Namespaces

```bash
# Ver métricas disponibles de un servicio
aws cloudwatch list-metrics --namespace AWS/EC2

# Namespaces importantes:
# AWS/EC2          → CPU, NetworkIn/Out, DiskRead/Write
# AWS/RDS          → DatabaseConnections, FreeStorageSpace, ReadLatency
# AWS/ApplicationELB → RequestCount, HTTPCode_Target_5XX_Count, TargetResponseTime
# AWS/EKS          → (básico, usar Container Insights para detalle)
# ContainerInsights → pod_cpu_utilization, pod_memory_utilization
```

### CloudWatch Logs Insights — queries básicos

```sql
-- Error rate en los últimos 30 minutos
fields @timestamp, @message
| filter @message like /ERROR/
| stats count(*) as error_count by bin(5m)
| sort @timestamp desc

-- Top IPs con más requests (nginx)
fields @timestamp, remoteAddr, request
| stats count(*) as request_count by remoteAddr
| sort request_count desc
| limit 20

-- Latencia promedio por endpoint (API Gateway)
fields @timestamp, resourcePath, responseLatency
| stats avg(responseLatency) as avg_latency,
        percentile(responseLatency, 95) as p95_latency
        by resourcePath
| sort p95_latency desc
```

### Alarmas: anatomía

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "api-high-error-rate" \
  --metric-name HTTPCode_Target_5XX_Count \
  --namespace AWS/ApplicationELB \
  --dimensions Name=LoadBalancer,Value=app/mi-alb/abc123 \
  --statistic Sum \
  --period 60 \           # ventana de evaluación: 1 minuto
  --evaluation-periods 3 \  # evaluar 3 períodos consecutivos
  --threshold 10 \          # si suma > 10 errores en 3 minutos seguidos
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-east-1:123:mi-alerta \
  --ok-actions arn:aws:sns:us-east-1:123:mi-alerta    # notificar cuando se resuelve
```

### Container Insights en EKS

```bash
# Habilitar Container Insights
aws eks create-addon \
  --cluster-name mi-cluster \
  --addon-name amazon-cloudwatch-observability

# Métricas disponibles automáticamente:
# - pod_cpu_utilization       → CPU por pod
# - pod_memory_utilization    → Memoria por pod
# - pod_network_rx_bytes      → Network ingress por pod
# - node_cpu_utilization      → CPU por nodo
# - cluster_failed_node_count → nodos caídos en el cluster
```

---

## 4. Datadog

### Arquitectura en EKS

```
EKS Cluster
├── Datadog Agent (DaemonSet — un pod por nodo)
│   ├── Recoge métricas del nodo (CPU, memoria, disco, red)
│   ├── Recoge métricas de los pods (via kubelet)
│   ├── Tail de logs de contenedores
│   └── APM traces (si la app está instrumentada)
└── Cluster Agent (Deployment — 1 réplica)
    ├── Métricas del cluster (eventos, estado de deployments)
    └── Autodiscovery (detecta servicios automáticamente)
```

```bash
# Instalar Datadog con Helm
helm repo add datadog https://helm.datadoghq.com
helm install datadog-agent datadog/datadog \
  --namespace datadog \
  --create-namespace \
  --set datadog.apiKey=$DD_API_KEY \
  --set datadog.logs.enabled=true \
  --set datadog.apm.enabled=true \
  --set datadog.clusterAgent.enabled=true
```

### Conceptos clave de Datadog

**Tags**: la base de todo en Datadog. Cada métrica, log y traza tiene tags.
```
host:web-01
env:production
service:payments
version:1.2.3
region:us-east-1
```

Con estos tags puedes filtrar cualquier dato: *"muéstrame el error rate del
servicio payments en producción"* sin escribir una query compleja.

**Monitors** (alertas en Datadog):
```
Threshold Monitor  → alerta si métrica supera un valor fijo
Anomaly Monitor    → alerta si la métrica se desvía del comportamiento histórico
Forecast Monitor   → alerta si la métrica va a superar un threshold en X horas
Composite Monitor  → combina múltiples monitors (alerta si A y B son verdad)
```

**APM en Datadog**:
```
Service Map     → visualización de dependencias entre servicios
Flame Graph     → desglose del tiempo dentro de una request
Error Tracking  → agrupa errores similares, muestra tendencia
Continuous Profiler → CPU/memoria a nivel de función de código
```

**Dashboards**: Datadog tiene dashboards prediseñados para EKS, RDS, ALB, etc.
Se pueden importar con un clic desde el catálogo de integraciones.

---

## 5. New Relic

### Diferenciador principal

New Relic se posiciona en **APM y full-stack observability**.
Su agente es fácil de instalar y da visibilidad profunda de la aplicación
(transacciones, queries SQL, llamadas externas) con mínima configuración.

### Conceptos clave

**New Relic APM**:
```
Transactions    → tiempo de respuesta por endpoint/método
Error rate      → % de transacciones con error por servicio
Throughput      → requests por minuto
Apdex score     → métrica de satisfacción (0-1): qué % de requests
                  fueron "satisfactorias" (< T ms), "tolerables" (< 4T) o "frustrantes"
Distributed tracing → request de extremo a extremo entre servicios
```

**NRQL** — New Relic Query Language (similar a SQL):
```sql
-- Error rate del servicio de pagos en la última hora
SELECT percentage(count(*), WHERE error IS true) as 'Error Rate'
FROM Transaction
WHERE appName = 'payments-service'
SINCE 1 hour ago
TIMESERIES 5 minutes

-- p95 de latencia por endpoint
SELECT percentile(duration, 95) as 'p95 Latency'
FROM Transaction
WHERE appName = 'api-gateway'
FACET request.uri
SINCE 30 minutes ago
LIMIT 20
```

**New Relic Alerts**:
```
Alert Policy  → agrupa condiciones de alerta relacionadas
Condition     → define cuándo se dispara (threshold, anomaly, NRQL)
Notification  → a dónde va la alerta (PagerDuty, Slack, email)
```

---

## 6. Tabla comparativa

| | Splunk | CloudWatch | Datadog | New Relic |
|--|---|---|---|---|
| **Fortaleza** | Log analytics, SIEM, compliance | Nativo AWS, sin fricción | Todo en uno, UX excelente | APM, instrumentación fácil |
| **Logs** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Métricas** | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **APM / Trazas** | ⭐⭐⭐⭐ | ⭐⭐ (X-Ray) | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Alertas** | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Costo** | Alto | Pay-per-use | Alto | Alto |
| **Curva de aprendizaje** | Alta (SPL) | Media | Media | Baja |
| **Ideal en** | Enterprise, compliance | Proyectos 100% AWS | Startups, SaaS, K8s | Apps con APM crítico |

**Cuándo recomendar cuál en entrevista**:
```
"Para un proyecto 100% AWS sin budget para herramientas externas" → CloudWatch
"Para una empresa con compliance estricto (fintech, salud, gobierno)" → Splunk
"Para un equipo que quiere todo en una sola plataforma con buena UX" → Datadog
"Para un equipo que necesita APM profundo con mínima configuración" → New Relic
"En la práctica: CloudWatch para métricas de infraestructura AWS +
 Splunk/Datadog/New Relic para observabilidad de aplicación" → respuesta más realista
```

---

## 7. SLIs, SLOs y Error Budget

### Definiciones

```
SLI (Service Level Indicator)
→ La métrica que mides. Un número.
→ Ejemplo: "% de requests que retornan 2xx en menos de 300ms"

SLO (Service Level Objective)
→ El objetivo que te pones sobre ese SLI. Un compromiso interno.
→ Ejemplo: "El 99.9% de las requests deben cumplir el SLI anterior"

SLA (Service Level Agreement)
→ El contrato con el cliente. Consecuencias si no se cumple.
→ Ejemplo: "Si disponibilidad < 99.5%, el cliente recibe crédito"

Error Budget
→ Cuánto puedes fallar antes de romper el SLO.
→ Ejemplo: SLO 99.9% → puedes fallar el 0.1% = 43.8 min/mes
```

### Cálculo de Error Budget

```
Período: 30 días = 43,200 minutos

SLO 99.9%:
  Error budget = 0.1% × 43,200 = 43.2 minutos/mes de downtime permitido

SLO 99.5%:
  Error budget = 0.5% × 43,200 = 216 minutos/mes (~3.6 horas)

SLO 99.99% ("four nines"):
  Error budget = 0.01% × 43,200 = 4.32 minutos/mes
  (casi imposible de sostener sin automatización total)
```

### SLIs buenos vs malos

```
❌ SLI malo: "El servidor está up" (binario, no refleja experiencia del usuario)
❌ SLI malo: "CPU < 80%" (métrica de recurso, no de experiencia)

✅ SLI bueno: "% de requests con status 2xx o 3xx"
✅ SLI bueno: "% de requests completadas en < 500ms (medido en el cliente)"
✅ SLI bueno: "% de jobs de procesamiento completados exitosamente"
✅ SLI bueno: "% de transacciones de pago procesadas sin error"
```

### Burn Rate: qué es y cómo alertar

```
Burn rate = velocidad a la que consumes el error budget

Burn rate 1 = consumes el budget exactamente al ritmo del período
  → En 30 días agotarás el budget justo al día 30

Burn rate 14.4 = consumes 14.4x más rápido de lo normal
  → Agotarás el budget mensual en 2 días (30 / 14.4 = 2.08)

Estrategia de alertas de burn rate (Google SRE):

┌─────────────────┬──────────────┬──────────────┬────────────────┐
│ Alerta          │ Burn rate    │ Ventana      │ Budget consumido│
├─────────────────┼──────────────┼──────────────┼────────────────┤
│ Page (crítico)  │ > 14.4x      │ 1 hora       │ 2% en 1 hora   │
│ Page (crítico)  │ > 6x         │ 6 horas      │ 5% en 6 horas  │
│ Ticket (aviso)  │ > 3x         │ 3 días       │ 10% en 3 días  │
│ Ticket (aviso)  │ > 1x         │ 7 días       │ 10% en 7 días  │
└─────────────────┴──────────────┴──────────────┴────────────────┘
```

### Qué hacer cuando se agota el error budget

```
1. Congelar todos los deployments de features nuevas
   → Solo se permiten fixes de estabilidad y reliability

2. El equipo de producto y el equipo técnico se alinean:
   → El error budget es la razón objetiva (no opinión) para parar features

3. Investigar qué consumió el budget:
   → ¿Fue un incidente? → Post-mortem + action items
   → ¿Fue acumulación de pequeños problemas? → Reducir toil, mejorar tests

4. Revisar si el SLO es realista:
   → Si siempre se agota, quizás el SLO es demasiado agresivo para
     la arquitectura actual

5. Documentar en el Error Budget Policy (documento del equipo):
   → Qué pasa cuando se consume el X% del budget
   → Quién toma la decisión de congelar features
```

---

## 8. Alertas: cómo diseñarlas bien

### Alert fatigue: el enemigo principal

```
Alert fatigue: cuando hay tantas alertas (muchas falsas) que el equipo
empieza a ignorarlas o a silenciarlas automáticamente.

Consecuencia: cuando llega una alerta real crítica, nadie la atiende.

Señales de alert fatigue en un equipo:
- Las alertas se "acostumbran" a estar disparadas
- Los engineers silencian alertas sin investigar
- Hay más alertas en un turno de on-call que incidentes reales
- Nadie recuerda por qué existe cierta alerta
```

### Principios para alertas bien diseñadas

```
1. ACCIONABLE: cada alerta debe tener una acción clara
   ❌ Alerta: "CPU alta en algún nodo"
   ✅ Alerta: "Nodo web-03 CPU > 90% por 10 min — revisar runbook K8s-NODE-CPU"

2. URGENTE: solo alertar de lo que necesita atención inmediata
   ❌ Alerta a las 3am: "Disk usage > 70%"
   ✅ Alerta a las 3am: "Disk usage > 95% — sistema puede quedarse sin espacio en < 2h"

3. CON CONTEXTO: incluir en la alerta toda la info para empezar a investigar
   - Qué métrica, qué valor, qué threshold
   - Link al dashboard relevante
   - Link al runbook
   - Severidad y tiempo de respuesta esperado

4. SIN DUPLICADOS: si 5 pods crashean, 1 alerta de "deployment degradado",
   no 5 alertas de "pod crashed"
   → Usar agrupación en PagerDuty / OpsGenie

5. CON THROTTLE: no alertar más de 1 vez cada N minutos por el mismo problema
   → Splunk: throttle setting en la alerta
   → Datadog: re-notify settings
```

### Severidades (estándar común)

| SEV | Descripción | Tiempo de respuesta | Ejemplo |
|-----|-------------|---------------------|---------|
| SEV1 | Impacto total a producción, usuarios afectados | Inmediato, 24/7 | API caída, 100% error rate |
| SEV2 | Impacto parcial o degradación severa | < 30 min, 24/7 | Error rate 10%, latencia 5x |
| SEV3 | Degradación menor, workaround disponible | Horario laboral | Job fallido, alerta de capacidad |
| SEV4 | Informativo, sin impacto actual | Próximo sprint | Disco al 70%, cert expira en 30d |

---

## 9. Preguntas de entrevista

**"¿Qué son los 4 golden signals y por qué importan?"**

```
Los 4 golden signals son el framework mínimo de monitoreo para cualquier servicio,
definido por el Google SRE Book:

1. Latency: cuánto tarda en responder. No solo el promedio — el p99 es más
   representativo porque muestra la experiencia del 1% más lento de usuarios.

2. Traffic: cuántas requests está procesando. Una caída repentina es tan
   alarmante como un spike — puede indicar que los usuarios no pueden llegar.

3. Errors: qué % de requests fallan. Monitorear solo 5xx no es suficiente —
   también hay errores "silenciosos" (respuesta 200 con error en el body).

4. Saturation: qué tan cerca está el sistema de su límite. CPU, memoria,
   conexiones de DB, tamaño de cola. Predice problemas antes de que ocurran.

Por qué importan: son agnósticos a la tecnología. Los mismos 4 aplican a una
API REST, un job de procesamiento, una base de datos o un servicio de streaming.
Son el lenguaje común entre SRE, DevOps y desarrollo.
```

---

**"¿Cómo investigas un aumento repentino de latencia en producción?"**

```
Proceso estructurado (lo que hago con Splunk o cualquier herramienta):

1. SCOPE: ¿es global o parcial?
   → ¿Todos los endpoints o solo uno?
   → ¿Todos los usuarios o solo una región/ISP?
   → ¿Todos los nodos o solo algunos?

   En Splunk:
   index=prod sourcetype=access_log
   | stats avg(response_time) by uri_path, datacenter
   | sort -avg(response_time)

2. CORRELACIÓN TEMPORAL: ¿cuándo empezó exactamente?
   → ¿Coincide con un deploy? (buscar eventos de deploy en el mismo timerange)
   → ¿Coincide con un pico de tráfico?
   → ¿Coincide con un cambio de configuración?

3. DOWNSTREAM: ¿el problema es interno o una dependencia?
   → APM / trazas: ¿qué parte de la request tardó más?
   → Flame graph: ¿fue la DB? ¿una llamada externa? ¿serialización?

4. RECURSOS: ¿hay saturación?
   → CPU, memoria, conexiones de DB, thread pool exhaustion
   → En EKS: kubectl top pods, kubectl describe nodes

5. MITIGAR antes de root cause:
   → Si hay un servicio degradado que puedo reiniciar o escalar, lo hago
   → La investigación profunda viene después del servicio restaurado
```

---

**"¿Cómo defines un SLO para un servicio nuevo?"**

```
Proceso de 4 pasos:

1. Entender la experiencia del usuario:
   "¿Qué hace que este servicio sea considerado 'funcionando' para el usuario?"
   Para un API de pagos: que procese la transacción correctamente en tiempo razonable.

2. Definir el SLI (qué medir):
   - Disponibilidad: % de requests con respuesta 2xx o 3xx
   - Latencia: % de requests respondidas en < 500ms
   - Correctness: % de transacciones procesadas sin error de negocio

3. Establecer el objetivo (SLO) basado en datos históricos:
   "Si no tenemos histórico, empezar conservador (99%) y ajustar con el tiempo"
   "Si tenemos histórico, el SLO debe ser alcanzable pero retador"
   Nunca comprometer más de lo que la arquitectura actual puede sostener.

4. Calcular el error budget y establecer la política:
   SLO 99.5% → 3.6 horas de error budget/mes
   "Si consumimos > 50% del budget en la primera semana, paramos features"

Tip de entrevista: mencionar que el SLO se negocia con producto,
no lo define el equipo técnico solo. Es una conversación sobre
qué nivel de confiabilidad vale el costo de ingeniería para lograrlo.
```

---

**"¿Cómo reduces alert fatigue en un equipo con muchas alertas ruidosas?"**

```
Experiencia real que puedes contar:

1. Auditoría: revisar cuántas alertas del último mes tuvieron acción real.
   Si > 50% no requirieron acción → son ruido, eliminarlas o bajarlas de SEV.

2. Agrupar: en vez de una alerta por pod caído, una alerta por deployment
   degradado. PagerDuty / OpsGenie tienen grouping automático.

3. Ajustar thresholds: muchas alertas están configuradas con thresholds
   demasiado sensibles. Añadir evaluation periods (3 períodos consecutivos
   en vez de 1) elimina falsos positivos por spikes breves.

4. Añadir throttle: si ya alerté por este problema, no volver a alertar
   por 30 minutos a menos que se resuelva y reaparezca.

5. Runbooks para cada alerta: si una alerta no tiene runbook, no debería
   existir. El runbook define qué hacer y, si la respuesta es "no hacer nada",
   la alerta no es necesaria.

6. Revisión periódica: reunión mensual de 30 minutos donde el equipo revisa
   las alertas que más se dispararon y decide si ajustar, eliminar o mantener.
```

---

*Anterior: [04-cicd-concepts.md](04-cicd-concepts.md)*  
*Volver al inicio: [00-concepts-overview.md](00-concepts-overview.md)*