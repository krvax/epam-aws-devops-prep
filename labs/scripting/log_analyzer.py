#!/usr/bin/env python3
"""
log_analyzer.py  —  Ejercicio 1 de la prueba de scripting EPAM

Lee un access.log en Combined Log Format y reporta:
  - Total de requests
  - Conteo por status code
  - Top 5 endpoints con más errores 5xx
  - Error rate global
  - Alerta si error rate supera un umbral (SLO check)

Relación con lab-07: este análisis es el equivalente en Python de la
query PromQL de error rate:
    rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

Uso:
    python log_analyzer.py                        # analiza access.log
    python log_analyzer.py --log /ruta/otro.log
    python log_analyzer.py --slo 99.9             # SLO objetivo (default: 99.5)
"""

import re
import argparse
from collections import defaultdict

# Regex para Combined Log Format
# Ejemplo: 10.0.1.5 - - [11/Apr/2026:10:00:01 +0000] "GET /health HTTP/1.1" 200 1234
LOG_PATTERN = re.compile(
    r'(?P<ip>[\d.]+) - - \[(?P<timestamp>[^\]]+)\] '
    r'"(?P<method>\S+) (?P<path>\S+) (?P<http_ver>[^"]+)" '
    r'(?P<status>\d{3}) (?P<size>\d+)'
)


def parse_log(log_path: str):
    """Parsea el log y retorna lista de dicts con los campos relevantes."""
    records = []
    errors = 0
    with open(log_path, "r") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            m = LOG_PATTERN.match(line)
            if m:
                records.append({
                    "ip":     m.group("ip"),
                    "method": m.group("method"),
                    "path":   m.group("path"),
                    "status": int(m.group("status")),
                    "size":   int(m.group("size")),
                })
            else:
                errors += 1
                print(f"  ⚠️  Línea {lineno} no coincide con el patrón, se omite.")
    if errors:
        print(f"  ⚠️  {errors} líneas no parseadas en total.\n")
    return records


def analyze(records: list, slo_target: float):
    total = len(records)
    if total == 0:
        print("❌  No se encontraron registros válidos.")
        return

    # ------------------------------------------------------------------ #
    # 1. Conteo por status code
    # ------------------------------------------------------------------ #
    status_counts = defaultdict(int)
    for r in records:
        status_counts[r["status"]] += 1

    # ------------------------------------------------------------------ #
    # 2. Top endpoints con errores 5xx
    # ------------------------------------------------------------------ #
    endpoint_5xx = defaultdict(int)
    for r in records:
        if 500 <= r["status"] < 600:
            key = f"{r['method']} {r['path']}"
            endpoint_5xx[key] += 1

    top_5xx = sorted(endpoint_5xx.items(), key=lambda x: x[1], reverse=True)[:5]

    # ------------------------------------------------------------------ #
    # 3. Error rate y SLO check
    # ------------------------------------------------------------------ #
    total_5xx = sum(v for k, v in status_counts.items() if 500 <= k < 600)
    total_errors = sum(v for k, v in status_counts.items() if k >= 400)
    error_rate_5xx = total_5xx / total * 100
    availability = (total - total_5xx) / total * 100
    slo_ok = availability >= slo_target

    # ------------------------------------------------------------------ #
    # Output
    # ------------------------------------------------------------------ #
    print("=" * 55)
    print("  📋  LOG ANALYZER — EPAM Scripting Exercise")
    print("=" * 55)
    print(f"  Archivo analizado : {args.log}")
    print(f"  Total de requests : {total:,}")
    print(f"  Errores 4xx       : {total_errors - total_5xx:,}")
    print(f"  Errores 5xx       : {total_5xx:,}")
    print(f"  Error rate (5xx)  : {error_rate_5xx:.2f}%")
    print(f"  Availability      : {availability:.3f}%")
    print()

    print("  📊  Status code breakdown:")
    for code in sorted(status_counts):
        count = status_counts[code]
        bar = "█" * (count * 30 // total)
        print(f"     {code}  {bar:<30} {count:>5}")
    print()

    if top_5xx:
        print("  🔴  Top endpoints con errores 5xx:")
        for endpoint, count in top_5xx:
            print(f"     {count:>5}x  {endpoint}")
        print()

    # SLO check — mismo concepto que burn rate alert del lab-07
    slo_icon = "✅" if slo_ok else "🚨"
    slo_msg  = "CUMPLIDO" if slo_ok else "VIOLADO — error budget agotado"
    print(f"  {slo_icon}  SLO {slo_target}% availability: {slo_msg}")
    if not slo_ok:
        deficit = slo_target - availability
        print(f"     Déficit: {deficit:.3f}% por debajo del objetivo")
        print(f"     → En producción esto dispararía una alerta de burn rate")
    print("=" * 55)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Analiza access.log y reporta métricas de error")
    parser.add_argument("--log", type=str, default="access.log", help="Ruta al log (default: access.log)")
    parser.add_argument("--slo", type=float, default=99.5, help="SLO objetivo de availability %% (default: 99.5)")
    args = parser.parse_args()

    try:
        records = parse_log(args.log)
        analyze(records, args.slo)
    except FileNotFoundError:
        print(f"❌  No se encontró el archivo '{args.log}'")
        print(f"   Genera uno primero con: python generate_logs.py")
