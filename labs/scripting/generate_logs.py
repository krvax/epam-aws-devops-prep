#!/usr/bin/env python3
"""
generate_logs.py

Simula el app.log de una EC2 con CloudWatch Agent (lab-09-cloudwatch-logs).
Formato JSON estructurado — idéntico al que produce loggen.sh en la EC2.
Incluy e request_id, latency_ms, user, endpoint — útil para:
  - CloudWatch Logs Insights queries
  - Ejercicios de scripting (jq, python, bash)
  - Correlación por request_id / trace_id

Uso:
    python generate_logs.py                   # 500 líneas -> app.log
    python generate_logs.py --lines 2000
    python generate_logs.py --out /tmp/app.log
"""

import argparse
import json
import random
import uuid
import datetime

# ---------------------------------------------------------------------------
# Config — mismos endpoints que loggen.sh (lab-09)
# ---------------------------------------------------------------------------

ENDPOINTS = [
    ("/health",          "GET",   18),
    ("/login",           "POST",   8),
    ("/logout",          "POST",   3),
    ("/checkout",        "POST",  10),
    ("/search",          "GET",   14),
    ("/items",           "GET",   12),
    ("/items/42",        "GET",    8),
    ("/api/v1/payments", "POST",  10),
    ("/api/v1/orders",   "GET",    9),
    ("/metrics",         "GET",    8),
]

USERS = ["alice", "bob", "carol", "dave", "erin", "svc-account"]

ERROR_MESSAGES = ["db_timeout", "null_pointer", "upstream_502"]


def weighted_endpoint():
    total = sum(w for _, _, w in ENDPOINTS)
    r = random.uniform(0, total)
    cumulative = 0
    for path, method, weight in ENDPOINTS:
        cumulative += weight
        if r <= cumulative:
            return path, method
    return ENDPOINTS[-1][0], ENDPOINTS[-1][1]


def make_record(ts: datetime.datetime) -> dict:
    path, method = weighted_endpoint()
    r = random.randint(0, 99)
    if r < 85:
        status, level = 200, "INFO"
    elif r < 93:
        status, level = 400, "WARN"
    else:
        status, level = 500, "ERROR"

    latency = random.randint(10, 1990)
    # latencia más alta en errores (realista)
    if status == 500:
        latency = random.randint(800, 2500)

    error = ""
    if status == 500:
        error = random.choice(ERROR_MESSAGES)

    return {
        "ts":         ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "level":      level,
        "request_id": str(uuid.uuid4()),
        "user":       random.choice(USERS),
        "method":     method,
        "endpoint":   path,
        "status":     status,
        "latency_ms": latency,
        "error":      error,
    }


def generate(n_lines: int, output_path: str):
    now = datetime.datetime.utcnow().replace(microsecond=0)
    ts  = now - datetime.timedelta(seconds=n_lines * 2)

    records = []
    for _ in range(n_lines):
        ts += datetime.timedelta(seconds=random.uniform(0.1, 0.4))  # ~0.2s entre requests
        records.append(make_record(ts))

    with open(output_path, "w") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")

    # Resumen
    from collections import Counter
    level_counts  = Counter(r["level"]  for r in records)
    status_counts = Counter(r["status"] for r in records)
    error_counts  = Counter(r["error"]  for r in records if r["error"])
    latencies     = [r["latency_ms"] for r in records]
    latencies.sort()
    p95 = latencies[int(len(latencies) * 0.95)]
    p99 = latencies[int(len(latencies) * 0.99)]

    print(f"\u2705  Generadas {n_lines} líneas en '{output_path}'")
    print(f"\n\ud83d\udcca  Niveles: " + "  ".join(f"{k}={v}" for k, v in sorted(level_counts.items())))
    print(f"\ud83d\udcca  Status:  " + "  ".join(f"{k}={v}" for k, v in sorted(status_counts.items())))
    if error_counts:
        print(f"\ud83d\udd34  Errores: " + "  ".join(f"{k}={v}" for k, v in error_counts.most_common()))
    print(f"\u23f1   Latencia: avg={sum(latencies)//len(latencies)}ms  p95={p95}ms  p99={p99}ms")
    fives = sum(v for k, v in status_counts.items() if str(k).startswith("5"))
    print(f"\ud83d\udfe1  Availability: {(n_lines - fives) * 100 / n_lines:.2f}%")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Genera app.log JSON para labs de scripting/observabilidad")
    parser.add_argument("--lines", type=int,  default=500,       help="Número de líneas (default: 500)")
    parser.add_argument("--out",   type=str,  default="app.log", help="Archivo de salida (default: app.log)")
    args = parser.parse_args()
    generate(args.lines, args.out)
