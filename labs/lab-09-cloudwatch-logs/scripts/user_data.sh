#!/usr/bin/env bash
# user_data.sh — Bootstrap de la EC2
# Instala CloudWatch Agent + loggen.sh como servicio systemd
set -euo pipefail

LOG_GROUP="${log_group}"
REGION="${region}"

# 1. Instalar CloudWatch Agent
dnf install -y amazon-cloudwatch-agent

# 2. Escribir config del agente
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/app/app.log",
            "log_group_name": "$LOG_GROUP",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%dT%H:%M:%SZ"
          }
        ]
      }
    }
  }
}
CWCONFIG

# Reemplazar placeholder con valor real
sed -i "s|\$LOG_GROUP|$LOG_GROUP|g" \
  /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json

# 3. Iniciar CloudWatch Agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

# 4. Instalar loggen.sh
mkdir -p /opt/loggen
cat > /opt/loggen/loggen.sh << 'LOGGEN'
#!/usr/bin/env bash
set -euo pipefail
LOG_DIR="/var/log/app"
LOG_FILE="$LOG_DIR/app.log"
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
endpoints=("/login" "/checkout" "/search" "/health" "/items" "/items/42" "/api/v1/payments" "/api/v1/orders" "/metrics")
methods=("POST" "POST" "GET" "GET" "GET" "GET" "POST" "GET" "GET")
users=("alice" "bob" "carol" "dave" "erin" "svc-account")
error_types=("db_timeout" "null_pointer" "upstream_502")
while true; do
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  request_id=$(cat /proc/sys/kernel/random/uuid)
  idx=$((RANDOM % $${#endpoints[@]}))
  endpoint=$${endpoints[$idx]}
  method=$${methods[$idx]}
  user=$${users[$RANDOM % $${#users[@]}]}
  latency=$((10 + RANDOM % 1990))
  r=$((RANDOM % 100))
  if (( r < 85 )); then status=200; level="INFO"; error=""
  elif (( r < 93 )); then status=400; level="WARN"; error=""
  else
    status=500; level="ERROR"
    latency=$((800 + RANDOM % 1700))
    error=$${error_types[$RANDOM % $${#error_types[@]}]}
  fi
  printf '{"ts":"%s","level":"%s","request_id":"%s","user":"%s","method":"%s","endpoint":"%s","status":%d,"latency_ms":%d,"error":"%s"}\n' \
    "$ts" "$level" "$request_id" "$user" "$method" "$endpoint" \
    "$status" "$latency" "$error" >> "$LOG_FILE"
  sleep 0.2
done
LOGGEN
chmod +x /opt/loggen/loggen.sh

# 5. Crear servicio systemd
cat > /etc/systemd/system/loggen.service << 'SYSTEMD'
[Unit]
Description=App Log Generator
After=network.target

[Service]
ExecStart=/opt/loggen/loggen.sh
Restart=always
User=root
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
SYSTEMD

systemctl daemon-reload
systemctl enable --now loggen

echo "[user_data] Setup completo. Logs en /var/log/app/app.log"
