#!/usr/bin/env python3
"""
generate_logs.py

Simula el access.log de un ALB/nginx frente a una app corriendo en EKS.
Los endpoints y patrones de error reflejan lo que Prometheus estaría
scrapeando en el lab-07-monitoring.

Uso:
    python generate_logs.py              # genera 500 líneas en access.log
    python generate_logs.py --lines 2000 # genera N líneas
    python generate_logs.py --out /tmp/access.log
"""

import argparse
import random
import datetime
import ipaddress

# ---------------------------------------------------------------------------
# Configuración — refleja los endpoints reales del lab-07 (EKS + Prometheus)
# ---------------------------------------------------------------------------

ENDPOINTS = [
    # (path, method, peso relativo, status_codes_posibles)
    ("/health",              "GET",    20, [200, 200, 200, 200, 503]),
    ("/metrics",             "GET",    15, [200, 200, 200, 500]),
    ("/api/v1/users",        "GET",    12, [200, 200, 200, 404, 500]),
    ("/api/v1/users",        "POST",    8, [201, 201, 400, 500]),
    ("/api/v1/payments",     "POST",   10, [201, 201, 201, 400, 500, 502]),
    ("/api/v1/payments",     "GET",     8, [200, 200, 404, 500]),
    ("/api/v1/orders",       "GET",    10, [200, 200, 200, 404]),
    ("/api/v1/orders",       "POST",    5, [201, 201, 400, 500, 503]),
    ("/login",               "POST",    6, [200, 200, 401, 429]),
    ("/logout",              "POST",    3, [200, 204]),
    ("/static/main.js",      "GET",     2, [200, 304]),
    ("/favicon.ico",         "GET",     1, [200, 404]),
]

HTTP_VERSIONS = ["HTTP/1.1", "HTTP/1.1", "HTTP/2.0"]

RESPONSE_SIZES = {
    200: (512,  8192),
    201: (256,  2048),
    204: (0,    0),
    304: (0,    0),
    400: (128,  512),
    401: (128,  256),
    404: (256,  512),
    429: (128,  256),
    500: (256,  1024),
    502: (256,  512),
    503: (256,  512),
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def random_ip():
    """Genera IPs de rangos privados (simula pods/clientes internos)."""
    ranges = [
        ("10.0.0.1",   "10.0.255.254"),
        ("172.16.0.1", "172.16.255.254"),
        ("192.168.1.1","192.168.10.254"),
    ]
    lo, hi = random.choice(ranges)
    lo_int = int(ipaddress.IPv4Address(lo))
    hi_int = int(ipaddress.IPv4Address(hi))
    return str(ipaddress.IPv4Address(random.randint(lo_int, hi_int)))


def random_timestamp(base: datetime.datetime, jitter_seconds: int = 1):
    """Avanza el timestamp con un pequeño jitter para simular tráfico real."""
    delta = datetime.timedelta(seconds=random.randint(0, jitter_seconds))
    return base + delta


def build_line(ts: datetime.datetime, ip: str, method: str, path: str,
               http_ver: str, status: int, size: int) -> str:
    """
    Formato Combined Log Format (igual al que usa nginx/ALB access logs):
    {ip} - - [{timestamp}] "{method} {path} {http_ver}" {status} {size}
    """
    ts_str = ts.strftime("%d/%b/%Y:%H:%M:%S +0000")
    return f'{ip} - - [{ts_str}] "{method} {path} {http_ver}" {status} {size}'


def weighted_choice(endpoints):
    """Selecciona un endpoint según su peso relativo."""
    total = sum(e[3] for e in [(p, m, w, sc) for p, m, w, sc in endpoints])
    r = random.uniform(0, total)
    cumulative = 0
    for path, method, weight, statuses in endpoints:
        cumulative += weight
        if r <= cumulative:
            return path, method, statuses
    return endpoints[-1][0], endpoints[-1][1], endpoints[-1][3]


# ---------------------------------------------------------------------------
# Generador principal
# ---------------------------------------------------------------------------

def generate(n_lines: int, output_path: str):
    now = datetime.datetime.utcnow().replace(microsecond=0)
    # El log arranca 'n_lines' segundos atrás para tener un rango de tiempo
    start = now - datetime.timedelta(seconds=n_lines)
    ts = start

    lines = []
    for _ in range(n_lines):
        path, method, statuses = weighted_choice(ENDPOINTS)
        status = random.choice(statuses)
        lo, hi = RESPONSE_SIZES.get(status, (256, 1024))
        size = random.randint(lo, hi) if hi > 0 else 0
        ip = random_ip()
        http_ver = random.choice(HTTP_VERSIONS)
        ts = random_timestamp(ts, jitter_seconds=2)
        lines.append(build_line(ts, ip, method, path, http_ver, status, size))

    with open(output_path, "w") as f:
        f.write("\n".join(lines) + "\n")

    # Resumen rápido
    from collections import Counter
    status_counts = Counter()
    for line in lines:
        code = int(line.split('" ')[1].split()[0])
        status_counts[code] += 1

    print(f"✅  Generadas {n_lines} líneas en '{output_path}'")
    print("\n📊  Distribución de status codes:")
    for code in sorted(status_counts):
        bar = "█" * (status_counts[code] * 40 // n_lines)
        pct = status_counts[code] * 100 / n_lines
        print(f"   {code}  {bar:<40} {status_counts[code]:>5}  ({pct:.1f}%)")
    fives = sum(v for k, v in status_counts.items() if str(k).startswith("5"))
    print(f"\n🔴  Total errores 5xx: {fives} ({fives*100/n_lines:.1f}%)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Genera access.log simulado para labs de scripting")
    parser.add_argument("--lines", type=int, default=500, help="Número de líneas a generar (default: 500)")
    parser.add_argument("--out", type=str, default="access.log", help="Archivo de salida (default: access.log)")
    args = parser.parse_args()
    generate(args.lines, args.out)
