# CloudWatch Logs Insights — Queries de entrevista

Log Group: `/epam/lab/app`

Todas las queries asumen logs en formato JSON (producidos por `loggen.sh` o `generate_logs.py`).

---

## 1. Errores 5xx por tipo y endpoint

```sql
fields @timestamp, error, endpoint, status
| filter status >= 500
| stats count() as total_errors by error, endpoint
| sort total_errors desc
| limit 20
```

**Por qué importa en entrevista:** demuestra que sabes filtrar por campo JSON y agrupar — base del troubleshooting con Insights.

---

## 2. P95 y promedio de latencia por endpoint

```sql
fields endpoint, latency_ms
| stats
    pct(latency_ms, 95) as p95_ms,
    pct(latency_ms, 50) as p50_ms,
    avg(latency_ms)     as avg_ms,
    count()             as requests
  by endpoint
| sort p95_ms desc
```

**Por qué importa:** SLO/SLA — p95 es el KPI estándar de latencia. Pregunta frecuente en EPAM SRE.

---

## 3. Tasa de error por endpoint (error rate %)

```sql
fields endpoint, status
| stats
    count(status)                                    as total,
    count_distinct(request_id)                       as unique_reqs,
    sum(status >= 500)                               as errors_5xx
  by endpoint
| sort errors_5xx desc
```

> Nota: Insights no tiene división nativa; calcula el % mentalmente o exporta y procesas con Python.

---

## 4. Top 10 usuarios por número de requests

```sql
fields user
| stats count() as requests by user
| sort requests desc
| limit 10
```

---

## 5. Volumen de requests por minuto (serie de tiempo)

```sql
fields @timestamp
| stats count() as requests by bin(1m)
| sort @timestamp asc
```

**Por qué importa:** detecta spikes de tráfico — base de cualquier runbook de incidente.

---

## 6. Errores por minuto (para correlacionar con alarma)

```sql
fields @timestamp, level
| filter level = "ERROR"
| stats count() as errors by bin(1m)
| sort @timestamp asc
```

Esta query visualiza exactamente lo que dispara la **CloudWatch Alarm** del lab.

---

## 7. Requests lentos: latencia > 1500ms

```sql
fields @timestamp, endpoint, latency_ms, user, status
| filter latency_ms > 1500
| sort latency_ms desc
| limit 20
```

---

## 8. Correlación por request_id (tracing manual)

```sql
fields @timestamp, level, endpoint, status, latency_ms, error
| filter request_id = "PEGA-AQUI-UN-UUID"
| sort @timestamp asc
```

**Por qué importa:** sin X-Ray, esta es la forma de rastrear una petición completa — pregunta clásica de troubleshooting en entrevista.

---

## 9. Distribución de status codes

```sql
fields status
| stats count() as total by status
| sort total desc
```

---

## 10. Resumen ejecutivo (query de cierre de entrevista)

```sql
fields level, status, latency_ms
| stats
    count()                  as total_requests,
    count(level = "ERROR")   as errors,
    count(level = "WARN")    as warnings,
    avg(latency_ms)          as avg_latency,
    pct(latency_ms, 95)      as p95_latency
```

Esta query en 10 segundos da una foto completa del sistema — muy buena para cerrar una demostración en entrevista.

---

## Cómo usarlas

1. AWS Console → CloudWatch → Logs Insights
2. Selecciona Log Group: `/epam/lab/app`
3. Ajusta el rango de tiempo (last 30 min mientras corre el generador)
4. Pega la query → Run

## Desde CLI (alternativa pro)

```bash
aws logs start-query \\
  --log-group-name /epam/lab/app \\
  --start-time $(date -d '1 hour ago' +%s) \\
  --end-time $(date +%s) \\
  --query-string 'fields @timestamp, level | filter level="ERROR" | stats count() by bin(1m)'
```
