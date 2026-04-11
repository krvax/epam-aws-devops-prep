# Lab: Scripting & Coding Prep

> Ejercicios prácticos para la prueba de scripting de EPAM.  
> Los logs simulados usan los mismos endpoints y patrones de error del **lab-07-monitoring** (Prometheus + Grafana en EKS).

---

## Flujo

```
lab-07 (Prometheus scrape HTTP metrics)
         ↓
    generate_logs.py   ← simula access.log realista con endpoints EKS
         ↓
    log_analyzer.py    ← ejercicio 1: parsea y reporta métricas (entrevista)
         ↓
    s3_janitor.py      ← ejercicio 2: boto3 + moto (próximamente)
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
# 500 líneas (default)
python generate_logs.py

# 2000 líneas para análisis más realista
python generate_logs.py --lines 2000

# Output personalizado
python generate_logs.py --lines 1000 --out /tmp/test.log
```

### Paso 2: Analiza el log

```bash
# Analiza access.log con SLO default (99.5%)
python log_analyzer.py

# SLO más estricto (99.9% — típico de producción)
python log_analyzer.py --slo 99.9

# Contra un log específico
python log_analyzer.py --log /tmp/test.log --slo 99.9
```

### Output esperado

```
=======================================================
  📋  LOG ANALYZER — EPAM Scripting Exercise
=======================================================
  Archivo analizado : access.log
  Total de requests : 500
  Errores 4xx       : 42
  Errores 5xx       : 31
  Error rate (5xx)  : 6.20%
  Availability      : 93.800%

  📊  Status code breakdown:
     200  ██████████████████████         350
     ...

  🔴  Top endpoints con errores 5xx:
     12x  POST /api/v1/payments
     ...

  🚨  SLO 99.9% availability: VIOLADO — error budget agotado
=======================================================
```

---

## Relación con lab-07-monitoring

El reporte de `log_analyzer.py` es el equivalente en Python de esta query PromQL del lab-07:

```promql
# Error rate
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# Availability (SLO check)
1 - (
  rate(http_requests_total{status=~"5.."}[5m]) /
  rate(http_requests_total[5m])
)
```

En la entrevista puedes mencionar esta conexión — demuestra que entiendes el concepto de error rate más allá del código.

---

## Archivos

| Archivo | Descripción |
|---|---|
| `generate_logs.py` | Generador de `access.log` con endpoints reales de EKS |
| `log_analyzer.py` | Ejercicio 1: análisis de logs con Python |
| `s3_janitor.py` | Ejercicio 2: boto3 + moto (próximamente) |
| `access.log` | Generado localmente — en `.gitignore` |

> ⚠️ `access.log` no se commitea al repo. Agrégalo al `.gitignore` del repo raíz si no está.
