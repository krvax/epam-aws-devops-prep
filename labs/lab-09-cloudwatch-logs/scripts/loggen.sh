#!/usr/bin/env bash
# loggen.sh — Generador de logs JSON tipo producción
# Mismo formato que generate_logs.py en labs/scripting/
# Se instala como servicio systemd via user_data.sh
set -euo pipefail

LOG_DIR="/var/log/app"
LOG_FILE="$LOG_DIR/app.log"
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

endpoints=("/login" "/checkout" "/search" "/health" "/items" "/items/42" "/api/v1/payments" "/api/v1/orders" "/metrics")
methods=(   "POST"   "POST"      "GET"     "GET"     "GET"    "GET"        "POST"             "GET"             "GET")
users=("alice" "bob" "carol" "dave" "erin" "svc-account")
error_types=("db_timeout" "null_pointer" "upstream_502")

echo "[loggen] Iniciando generador de logs en $LOG_FILE"

while true; do
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  request_id=$(cat /proc/sys/kernel/random/uuid)

  idx=$((RANDOM % ${#endpoints[@]}))
  endpoint=${endpoints[$idx]}
  method=${methods[$idx]}
  user=${users[$RANDOM % ${#users[@]}]}
  latency=$((10 + RANDOM % 1990))

  r=$((RANDOM % 100))
  if   (( r < 85 )); then status=200; level="INFO";  error=""
  elif (( r < 93 )); then status=400; level="WARN";  error=""
  else
    status=500; level="ERROR"
    latency=$((800 + RANDOM % 1700))  # errores son más lentos
    error=${error_types[$RANDOM % ${#error_types[@]}]}
  fi

  printf '{"ts":"%s","level":"%s","request_id":"%s","user":"%s","method":"%s","endpoint":"%s","status":%d,"latency_ms":%d,"error":"%s"}\n' \
    "$ts" "$level" "$request_id" "$user" "$method" "$endpoint" \
    "$status" "$latency" "$error" >> "$LOG_FILE"

  sleep 0.2
done
