#!/usr/bin/env python3
"""
log_analyzer.py  —  Ejercicio 1 de scripting EPAM

Lee app.log (JSON estructurado) y reporta:
  - Conteo por level / status code
  - Top 5 endpoints con más errores 5xx
  - Percentiles de latencia (p50, p95, p99)
  - Error rate y SLO check
  - Top errores por tipo (db_timeout, null_pointer, etc.)

Relación con labs:
  lab-07: equivalente Python de la query PromQL de error rate
  lab-09: analiza los mismos logs que CloudWatch Logs Insights procesa

CloudWatch Logs Insights equivalente:
    fields endpoint, status, latency_ms
    | filter status >= 500
    | stats count() as errors, pct(latency_ms, 95) as p95 by endpoint
    | sort errors desc

Uso:
    python log_analyzer.py                    # analiza app.log
    python log_analyzer.py --log /ruta/app.log
    python log_analyzer.py --slo 99.9
"""

import json
import argparse
from collections import defaultdict


def parse_log(log_path: str):
    records = []
    parse_errors = 0
    with open(log_path, "r") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                parse_errors += 1
                print(f"  \u26a0\ufe0f  Línea {lineno} no es JSON válido, se omite.")
    if parse_errors:
        print(f"  \u26a0\ufe0f  {parse_errors} líneas omitidas.\n")
    return records


def percentile(data: list, p: int) -> float:
    if not data:
        return 0.0
    s = sorted(data)
    idx = max(0, int(len(s) * p / 100) - 1)
    return s[idx]


def analyze(records: list, slo_target: float, log_path: str):
    total = len(records)
    if total == 0:
        print("\u274c  No se encontraron registros válidos.")
        return

    level_counts  = defaultdict(int)
    status_counts = defaultdict(int)
    endpoint_5xx  = defaultdict(int)
    error_types   = defaultdict(int)
    latencies     = []
    latencies_5xx = []

    for r in records:
        level_counts[r.get("level", "?")]  += 1
        status = r.get("status", 0)
        status_counts[status] += 1
        lat = r.get("latency_ms", 0)
        latencies.append(lat)

        if 500 <= status < 600:
            key = f"{r.get('method','?')} {r.get('endpoint','?')}"
            endpoint_5xx[key] += 1
            latencies_5xx.append(lat)
            err = r.get("error", "")
            if err:
                error_types[err] += 1

    total_5xx    = sum(v for k, v in status_counts.items() if 500 <= k < 600)
    total_4xx    = sum(v for k, v in status_counts.items() if 400 <= k < 500)
    availability = (total - total_5xx) / total * 100
    error_rate   = total_5xx / total * 100
    slo_ok       = availability >= slo_target

    p50  = percentile(latencies, 50)
    p95  = percentile(latencies, 95)
    p99  = percentile(latencies, 99)
    avg  = sum(latencies) // len(latencies) if latencies else 0

    top_5xx = sorted(endpoint_5xx.items(), key=lambda x: x[1], reverse=True)[:5]

    SEP = "=" * 58
    print(SEP)
    print("  \ud83d\udccb  LOG ANALYZER — EPAM Scripting Exercise")
    print(SEP)
    print(f"  Archivo        : {log_path}")
    print(f"  Total requests : {total:,}")
    print(f"  INFO / WARN / ERROR : "
          f"{level_counts['INFO']:,} / {level_counts['WARN']:,} / {level_counts['ERROR']:,}")
    print()

    print("  \ud83d\udcca  Status code breakdown:")
    for code in sorted(status_counts):
        count = status_counts[code]
        bar   = "\u2588" * (count * 28 // total)
        print(f"     {code}  {bar:<28} {count:>5}")
    print()

    print("  \u23f1   Latencia (todos los requests):")
    print(f"     avg={avg}ms   p50={p50}ms   p95={p95}ms   p99={p99}ms")
    if latencies_5xx:
        p95_err = percentile(latencies_5xx, 95)
        print(f"     p95 solo en 5xx: {p95_err}ms  (errores son más lentos)")
    print()

    if top_5xx:
        print("  \ud83d\udd34  Top endpoints con errores 5xx:")
        for endpoint, count in top_5xx:
            print(f"     {count:>5}x  {endpoint}")
        print()

    if error_types:
        print("  \ud83d\udd0d  Tipos de error:")
        for err, count in sorted(error_types.items(), key=lambda x: x[1], reverse=True):
            print(f"     {count:>5}x  {err}")
        print()

    # SLO check — mismo concepto que burn rate alert del lab-07/lab-09
    slo_icon = "\u2705" if slo_ok else "\ud83d\udea8"
    slo_msg  = "CUMPLIDO" if slo_ok else "VIOLADO — error budget agotado"
    print(f"  {slo_icon}  SLO {slo_target}% availability: {slo_msg}")
    print(f"     Error rate 5xx : {error_rate:.2f}%")
    print(f"     Availability   : {availability:.3f}%")
    if not slo_ok:
        deficit = slo_target - availability
        print(f"     Déficit        : {deficit:.3f}% bajo el objetivo")
        print(f"     \u2192 En producción dispara alerta de burn rate (lab-07/lab-09)")
    print(SEP)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Analiza app.log JSON y reporta métricas de error y latencia")
    parser.add_argument("--log", type=str,   default="app.log", help="Ruta al log (default: app.log)")
    parser.add_argument("--slo", type=float, default=99.5,      help="SLO objetivo %% availability (default: 99.5)")
    args = parser.parse_args()
    try:
        records = parse_log(args.log)
        analyze(records, args.slo, args.log)
    except FileNotFoundError:
        print(f"\u274c  No se encontró '{args.log}'")
        print(f"   Genera uno primero con: python generate_logs.py")
