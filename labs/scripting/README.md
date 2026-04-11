# Lab: Scripting & Coding Prep

> Ejercicios prácticos para la prueba de scripting de EPAM.  
> Los logs JSON usan el mismo formato que el `loggen.sh` del **lab-09-cloudwatch-logs**,
> y las métricas que reporta son equivalentes a las queries de **CloudWatch Logs Insights**
> y a las de **Prometheus** del lab-07.

---

## Flujo

```
[lab-09] EC2 + loggen.sh ──► CloudWatch Log Group /epam/lab/app
                 │
                 ▼  (mismo formato JSON)
         generate_logs.py   ◄── genera app.log local para practicar
                 │
                 ▼
         log_analyzer.py    ◄── Ejercicio 1: parseo, métricas, SLO check
                 │
                 ▼
         s3_janitor.py      ◄── Ejercicio 2: boto3 + moto (próximamente)
```

---

## Setup

```bash
# Desde la raíz del repo
python3 -m venv .venv
source .venv/bin/activate
pip install boto3 moto pytest

cd labs/scripting
```

---

## Ejercicio 1 — Log Analyzer

### Paso 1: Genera el log

```bash
python generate_logs.py              # 500 líneas -> app.log
python generate_logs.py --lines 2000 # más datos
python generate_logs.py --out /tmp/app.log
```

### Paso 2: Analiza

```bash
python log_analyzer.py               # SLO default 99.5%
python log_analyzer.py --slo 99.9    # SLO estricto de producción
python log_analyzer.py --log /tmp/app.log --slo 99.9
```

### Output esperado

```
==========================================================
  📋  LOG ANALYZER — EPAM Scripting Exercise
==========================================================
  Total requests : 2,000
  INFO / WARN / ERROR : 1,700 / 160 / 140

  📊  Status code breakdown:
     200  ███████████████████████      1700
     400  ███                160
     500  ██                  140

  ⏱   Latencia:
     avg=312ms  p50=290ms  p95=1820ms  p99=2380ms

  🔴  Top endpoints con errores 5xx:
     38x  POST /api/v1/payments
     ...

  ✅  SLO 99.5% availability: CUMPLIDO
==========================================================
```

---

## Equivalencias con otros labs

| Métrica de log_analyzer.py | CloudWatch Logs Insights (lab-09) | PromQL (lab-07) |
|---|---|---|
| Error rate 5xx | `filter status >= 500 \| stats count()` | `rate(http_requests_total{status=~"5.."}[5m])` |
| p95 latencia | `stats pct(latency_ms, 95) by endpoint` | `histogram_quantile(0.95, rate(http_duration_bucket[5m]))` |
| Top errores | `stats count() by error \| sort desc` | `topk(5, rate(errors_total[5m]))` |

---

## Ejercicios bonus con jq (bash)

```bash
# Top endpoints por requests
jq -r '.endpoint' app.log | sort | uniq -c | sort -nr | head

# Errores por tipo
jq -r 'select(.error != "") | .error' app.log | sort | uniq -c | sort -nr

# P95 de latencia sin numpy
jq -r '.latency_ms' app.log | sort -n | awk 'BEGIN{c=0} {lines[c++]=$0} END{print lines[int(c*0.95)]}'

# Requests de un usuario específico
jq 'select(.user == "alice")' app.log | jq -s 'length'

# Correlación: buscar request_id en el log
jq 'select(.request_id == "<uuid-aqui>")' app.log
```

---

## Archivos

| Archivo | Descripción |
|---|---|
| `generate_logs.py` | Genera `app.log` JSON — mismo formato que `loggen.sh` de lab-09 |
| `log_analyzer.py` | Ejercicio 1: análisis completo con SLO check |
| `s3_janitor.py` | Ejercicio 2: boto3 + moto (próximamente) |
| `app.log` | Generado localmente — en `.gitignore` |
