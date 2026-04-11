#!/usr/bin/env bash
# parse_logs.sh — Ejercicios de scripting sobre /var/log/app/app.jsonl
# Requiere: jq
# Uso: bash parse_logs.sh [LOG_FILE]
#
# Cubre los ejercicios de entrevista EPAM:
#   1. Conteo de requests por endpoint y status
#   2. Top 5 endpoints con más errores 5xx
#   3. Detección de spikes de errores por minuto
#   4. Requests de usuario con mayor latencia
#   5. Tasa de disponibilidad (non-5xx / total)

set -euo pipefail

LOG_FILE="${1:-/var/log/app/app.jsonl}"

if [[ ! -f "$LOG_FILE" ]]; then
  echo "ERROR: No se encontró el archivo: $LOG_FILE"
  echo "Uso: bash parse_logs.sh [ruta/al/app.jsonl]"
  exit 1
fi

echo "========================================="
echo " Log: $LOG_FILE"
echo " Total líneas: $(wc -l < "$LOG_FILE")"
echo "========================================="

# ---------------------------------------------------------------------------
# 1) Conteo por endpoint + status
# ---------------------------------------------------------------------------
echo ""
echo "── 1) Requests por endpoint y status ──────────────────"
jq -r '[.endpoint, (.status|tostring)] | @tsv' "$LOG_FILE" \
  | awk '{k=$1" "$2; c[k]++} END{for (k in c) print c[k], k}' \
  | sort -nr \
  | head -20

# ---------------------------------------------------------------------------
# 2) Top 5 endpoints con más errores 5xx
# ---------------------------------------------------------------------------
echo ""
echo "── 2) Top 5 endpoints con errores 5xx ─────────────────"
jq -r 'select(.status >= 500) | .endpoint' "$LOG_FILE" \
  | sort | uniq -c | sort -nr | head -5

# ---------------------------------------------------------------------------
# 3) Spikes de errores ERROR por minuto (minuto = primeros 16 chars del ts)
# ---------------------------------------------------------------------------
echo ""
echo "── 3) Errores ERROR por minuto ─────────────────────────"
jq -r 'select(.level == "ERROR") | .ts[0:16]' "$LOG_FILE" \
  | sort | uniq -c | sort -nr | head -10

# ---------------------------------------------------------------------------
# 4) Top 5 requests más lentos (usuario + endpoint + latencia)
# ---------------------------------------------------------------------------
echo ""
echo "── 4) Top 5 requests más lentos ────────────────────────"
jq -r '[.latency_ms, .user, .endpoint, .status] | @tsv' "$LOG_FILE" \
  | sort -nr | head -5 \
  | awk '{printf "%s ms\t user=%-10s endpoint=%-25s status=%s\n", $1,$2,$3,$4}'

# ---------------------------------------------------------------------------
# 5) Disponibilidad: (total - 5xx) / total * 100
# ---------------------------------------------------------------------------
echo ""
echo "── 5) Disponibilidad ───────────────────────────────────"
total=$(wc -l < "$LOG_FILE")
five_xx=$(jq -r 'select(.status >= 500) | .status' "$LOG_FILE" | wc -l)
awk -v t="$total" -v e="$five_xx" 'BEGIN {
  avail = (t - e) * 100.0 / t
  printf "Total: %d  Errores 5xx: %d  Disponibilidad: %.2f%%\n", t, e, avail
}'

echo ""
echo "✅ Análisis completado."
