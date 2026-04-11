#!/usr/bin/env python3
"""
log_analyzer_cw.py

Análisis de logs desde DOS fuentes:
  --source local  : lee un archivo local .jsonl (igual que log_analyzer.py)
  --source cw     : consulta CloudWatch Logs via AWS SDK (boto3)

Métricas que calcula:
  - Conteo por nivel (INFO / WARN / ERROR)
  - Conteo y tasa de error por endpoint
  - Distribución de latencia: avg, p50, p95, p99
  - Top errores por tipo
  - Disponibilidad (non-5xx %)
  - Spikes: minutos con más de N errores

Uso:
  # Archivo local (para practicar scripting sin AWS):
  python log_analyzer_cw.py --source local --file app.jsonl

  # CloudWatch Logs (lab activo en AWS):
  python log_analyzer_cw.py --source cw \\
      --log-group /epam/lab/app \\
      --hours 1 \\
      --region us-east-1

Dependencias:
  pip install boto3   # solo necesario para --source cw
"""

import argparse
import json
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone, timedelta


# ---------------------------------------------------------------------------
# Lectura de fuentes
# ---------------------------------------------------------------------------

def load_local(file_path: str) -> list[dict]:
    records = []
    with open(file_path) as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError as e:
                print(f"  ⚠️  Línea {i} inválida (skip): {e}", file=sys.stderr)
    return records


def load_cloudwatch(log_group: str, hours: int, region: str) -> list[dict]:
    try:
        import boto3
    except ImportError:
        sys.exit("ERROR: boto3 no instalado. Ejecuta: pip install boto3")

    client = boto3.client("logs", region_name=region)
    end_ms   = int(datetime.now(timezone.utc).timestamp() * 1000)
    start_ms = int((datetime.now(timezone.utc) - timedelta(hours=hours)).timestamp() * 1000)

    records = []
    kwargs = {
        "logGroupName": log_group,
        "startTime":    start_ms,
        "endTime":      end_ms,
    }

    print(f"📡 Consultando CloudWatch Logs: {log_group} (últimas {hours}h)...")
    while True:
        resp = client.filter_log_events(**kwargs)
        for event in resp.get("events", []):
            try:
                records.append(json.loads(event["message"]))
            except json.JSONDecodeError:
                pass
        next_token = resp.get("nextToken")
        if not next_token:
            break
        kwargs["nextToken"] = next_token

    print(f"   → {len(records)} eventos descargados.")
    return records


# ---------------------------------------------------------------------------
# Análisis
# ---------------------------------------------------------------------------

def percentile(sorted_list: list, p: float) -> float:
    if not sorted_list:
        return 0.0
    idx = int(len(sorted_list) * p / 100)
    return sorted_list[min(idx, len(sorted_list) - 1)]


def analyze(records: list[dict]):
    if not records:
        print("⚠️  Sin registros para analizar.")
        return

    total = len(records)
    levels    = Counter(r.get("level", "UNKNOWN") for r in records)
    statuses  = Counter(r.get("status", 0)         for r in records)
    errors    = Counter(r.get("error", "")          for r in records if r.get("error"))
    latencies = sorted(r.get("latency_ms", 0)       for r in records)

    # errores por endpoint
    ep_total  = Counter(r.get("endpoint") for r in records)
    ep_errors = Counter(r.get("endpoint") for r in records if r.get("status", 0) >= 500)

    # spikes: minutos con > 3 errores
    minute_errors = Counter(
        r["ts"][:16] for r in records
        if r.get("level") == "ERROR" and "ts" in r
    )
    spikes = {m: c for m, c in minute_errors.items() if c > 3}

    five_xx = sum(v for k, v in statuses.items() if k >= 500)
    avail   = (total - five_xx) * 100.0 / total

    # --------------- Reporte ---------------
    sep = "─" * 50

    print(f"\n{sep}")
    print(f" REPORTE DE LOGS — {total} registros")
    print(sep)

    print("\n📊 Niveles:")
    for lvl in ("INFO", "WARN", "ERROR"):
        print(f"   {lvl:<6} {levels.get(lvl, 0):>6}  ({levels.get(lvl,0)*100/total:.1f}%)")

    print("\n⏱  Latencia (ms):")
    avg = sum(latencies) // len(latencies) if latencies else 0
    print(f"   avg={avg}  p50={percentile(latencies,50)}  "
          f"p95={percentile(latencies,95)}  p99={percentile(latencies,99)}")

    print("\n🔴 Top errores por tipo:")
    for err, cnt in errors.most_common(5):
        print(f"   {err:<20} {cnt}")

    print("\n📍 Top endpoints con más 5xx:")
    for ep, cnt in ep_errors.most_common(5):
        rate = cnt * 100.0 / ep_total[ep] if ep_total[ep] else 0
        print(f"   {ep:<28} {cnt:>4} errores  ({rate:.1f}% error rate)")

    print(f"\n✅ Disponibilidad: {avail:.2f}%  "
          f"(5xx={five_xx} / total={total})")

    if spikes:
        print(f"\n⚡ Spikes detectados (>3 errores/min):")
        for m, c in sorted(spikes.items(), key=lambda x: -x[1])[:10]:
            print(f"   {m}  →  {c} errores")
    else:
        print("\n✅ Sin spikes detectados (ningún minuto superó 3 errores).")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Analiza logs de app desde archivo local o CloudWatch Logs"
    )
    parser.add_argument("--source",    choices=["local", "cw"], default="local")
    parser.add_argument("--file",      default="app.jsonl",     help="Archivo local .jsonl")
    parser.add_argument("--log-group", default="/epam/lab/app", help="CW Log Group name")
    parser.add_argument("--hours",     type=int, default=1,     help="Ventana de tiempo (horas)")
    parser.add_argument("--region",    default="us-east-1",     help="AWS region")
    args = parser.parse_args()

    if args.source == "local":
        records = load_local(args.file)
    else:
        records = load_cloudwatch(args.log_group, args.hours, args.region)

    analyze(records)


if __name__ == "__main__":
    main()
