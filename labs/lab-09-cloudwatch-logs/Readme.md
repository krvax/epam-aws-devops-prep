# Lab 09 — CloudWatch Logs: Centralización, Métricas y Alarmas

**Bloque:** 5 — Observabilidad & Monitoreo

**Objetivo:** Desplegar una EC2 con un generador de logs JSON, enviar los logs a CloudWatch con el agente oficial, crear Metric Filters y Alarmas que demuestren el flujo completo de observabilidad en AWS.

> 🔗 **Relación con otros labs:**
> - Lab 07 — Prometheus/Grafana en EKS: cubre métricas de K8s
> - Lab 09 (este) — CloudWatch Logs: cubre logs y alertas en EC2/AWS
> - `labs/scripting/` — usa el mismo formato JSON para practicar scripting

---

## Arquitectura

```
EC2 (Amazon Linux 2023)
  └─► loggen.sh (systemd)     ← genera JSON logs cada ~200ms
       └─► /var/log/app/app.log
             └─► CloudWatch Agent
                   └─► Log Group: /epam/lab/app  (retención 3 días)
                         └─► Metric Filter: AppErrors (count status=500)
                               └─► CloudWatch Alarm
                                     └─► SNS Topic ─► Email
```

---

## Estructura del lab

```
lab-09-cloudwatch-logs/
├── Readme.md
├── main.tf          ← provider, data sources
├── ec2.tf           ← EC2 + IAM Role + Instance Profile
├── cloudwatch.tf    ← Log Group, Metric Filter, Alarm, SNS
├── sg.tf            ← Security Group (SSH opcional)
├── variables.tf
├── outputs.tf
└── scripts/
    ├── loggen.sh        ← generador de logs JSON (systemd service)
    └── cw-agent.json    ← config del CloudWatch Agent
```

---

## Prerrequisitos

- Terraform >= 1.6
- AWS CLI configurado con permisos suficientes
- Una VPC existente con al menos una subnet pública (puede ser la del lab-01)
- Email válido para las notificaciones SNS

---

## Paso a paso

### 1. Inicializar y planear

```bash
cd labs/lab-09-cloudwatch-logs
terraform init
terraform plan -var="alert_email=tu@email.com"
```

### 2. Aplicar

```bash
terraform apply -var="alert_email=tu@email.com"
# Confirmar la suscripción SNS en tu email
```

### 3. Verificar logs en CloudWatch

```bash
# Ver los últimos eventos del log stream
aws logs tail /epam/lab/app --follow

# Ver con filtro de errores
aws logs filter-log-events \
  --log-group-name /epam/lab/app \
  --filter-pattern '{ $.status = 500 }'
```

### 4. CloudWatch Logs Insights queries

En la consola: **CloudWatch → Logs Insights → Log group: `/epam/lab/app`**

#### Errores por tipo y endpoint
```sql
fields @timestamp, error, endpoint, status
| filter status >= 500
| stats count() as errors by error, endpoint
| sort errors desc
```

#### P95 de latencia por endpoint
```sql
fields endpoint, latency_ms
| stats pct(latency_ms, 95) as p95, avg(latency_ms) as avg_lat by endpoint
| sort p95 desc
```

#### Top usuarios por requests
```sql
fields user
| stats count() as requests by user
| sort requests desc
| limit 10
```

#### Spikes de errores por minuto
```sql
fields @timestamp, level
| filter level = "ERROR"
| stats count() as errors by bin(1m)
| sort @timestamp asc
```

#### Correlación por request_id
```sql
fields @timestamp, level, endpoint, status, latency_ms, error
| filter request_id = "<uuid-aqui>"
```

### 5. Verificar la alarma

```bash
# Ver estado de la alarma
aws cloudwatch describe-alarms --alarm-names "epam-lab-app-errors"

# Forzar estado ALARM para probar SNS (opcional)
aws cloudwatch set-alarm-state \
  --alarm-name "epam-lab-app-errors" \
  --state-value ALARM \
  --state-reason "Test manual"
```

---

## Preguntas de entrevista

**"¿Cuál es la diferencia entre CloudWatch Metrics y CloudWatch Logs?"**

Métricas son datos numéricos agregados (CPU, request count) almacenados como time series. Logs son registros textuales/JSON de eventos individuales. Los Metric Filters permiten derivar métricas desde logs — por ejemplo, contar líneas con `status=500` y convertirlo en una métrica `AppErrors` sobre la que puedes crear alarmas.

**"¿Cuándo usar CloudWatch vs Prometheus?"**

CloudWatch para infraestructura AWS nativa (EC2, RDS, ALB) y logs centralizados. Prometheus para métricas de aplicación en Kubernetes — PromQL es más expresivo para cálculos como SLOs y burn rates. En producción se usan ambos: Prometheus para K8s (lab-07), CloudWatch para EC2 y servicios managed.

**"¿Cómo reduces costos de CloudWatch Logs?"**

Reducing retention (este lab usa 3 días), filtrar qué logs se envían al agente, usar S3 para archivado long-term, y comprimir con gzip. También evitar logs muy verbosos (DEBUG) en producción.

---

## Cleanup

```bash
terraform destroy -var="alert_email=tu@email.com"
```

---

## Documentación relacionada

- [Lab 07 — Monitoring Prometheus/Grafana](../lab-07-monitoring/Readme.md)
- [Scripting Lab — log_analyzer.py](../../labs/scripting/README.md)
- [CloudWatch Agent docs](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Install-CloudWatch-Agent.html)
- [Logs Insights query syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
