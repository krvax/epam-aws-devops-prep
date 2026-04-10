# Lab 03 — Auto Scaling Group + ALB con Terraform

## Archivos

```
terraform/
├── providers.tf
├── variables.tf
├── main.tf          ← VPC + Security Groups
├── alb.tf           ← ALB + Target Group + Listener
├── asg.tf           ← Launch Template + ASG + Scaling Policy
├── outputs.tf
├── terraform.tfvars
└── templates/
    └── user-data.sh
```

## Recursos que crea

- VPC + 2 subnets públicas + IGW + Route Table
- Security Groups (ALB y instancias separados)
- Application Load Balancer
- Target Group con health check en `/health/`
- Launch Template con nginx + página personalizada por instancia
- Auto Scaling Group (min=2, max=5, desired=2)
- Target Tracking Scaling Policy (CPU target 60%)

## Ejecutar

```bash
cd labs/lab-03-asg-alb/terraform

terraform init
terraform plan
terraform apply

# Ver comandos de prueba
terraform output test_commands

# Probar el ALB (esperar ~2 min después del apply)
curl $(terraform output -raw alb_dns_name)

# Limpiar
terraform destroy
```

## Variables

| Variable | Default | Descripción |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | Región AWS |
| `project_name` | `lab` | Prefijo para nombres |
| `instance_type` | `t2.micro` | Tipo de instancia |
| `asg_min` | `2` | Mínimo de instancias |
| `asg_max` | `5` | Máximo de instancias |
| `asg_desired` | `2` | Instancias deseadas |
| `cpu_target` | `60` | CPU% objetivo para scaling |

## Verificar load balancing

Al refrescar el ALB varias veces deberías ver diferentes Instance IDs respondiendo desde distintas AZs — eso confirma que el ALB está distribuyendo el tráfico correctamente.

## Simular carga para probar Scale Out

```bash
# Conectarse a una instancia vía SSM
aws ssm send-command \
  --instance-ids <INSTANCE_ID> \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["stress --cpu 4 --timeout 300"]'

# Observar escalado
watch -n 10 "aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names lab-asg \
  --query 'AutoScalingGroups[0].DesiredCapacity'"
```

## Pregunta de entrevista

> "¿Cuál es la diferencia entre Scale Out y Scale In?"

Scale Out = agregar instancias (cooldown corto, para proteger UX). Scale In = quitar instancias (cooldown largo, para evitar flapping). Las **termination policies** definen qué instancia se elimina primero.

---

> 🏷️ Tags: `terraform` `asg` `alb` `auto-scaling` `target-tracking`
