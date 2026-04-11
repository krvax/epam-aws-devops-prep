# Lab 03 — Auto Scaling Group + Application Load Balancer

**Objetivo:** Desplegar una aplicación en un ASG con ALB frontal, configurar health checks y simular escalado por CPU.

## Prerequisitos

- Lab 01 aplicado (VPC y subnets)
- Terraform >= 1.5

## Estructura

```
lab-03-asg-alb/
├── main.tf          # ALB, Target Group, Listener
├── asg.tf           # Launch Template, ASG, Scaling Policies
├── sg.tf            # Security Groups para ALB y EC2
├── variables.tf
├── outputs.tf
└── README.md
```

## Uso

```bash
cd labs/lab-03-asg-alb

# Pasar los outputs del lab-01
terraform init
terraform apply \
  -var="vpc_id=<vpc_id del lab-01>" \
  -var='public_subnet_ids=["subnet-aaa","subnet-bbb"]' \
  -var='private_subnet_ids=["subnet-ccc","subnet-ddd"]'

# Probar el endpoint
curl http://$(terraform output -raw alb_dns_name)

# Simular carga para disparar scale out
ALB=$(terraform output -raw alb_dns_name)
for i in {1..1000}; do curl -s $ALB > /dev/null & done

# Observar scaling en tiempo real
watch -n5 'aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names lab-03-asg \
  --query "AutoScalingGroups[0].Instances[*].InstanceId"'

# Limpiar
terraform destroy
```

## Arquitectura

```
Internet
    ↓
ALB (public subnets, SG: 80 desde 0.0.0.0/0)
    ↓  HTTP:80
Target Group (health check: GET / → 200)
    ↓
ASG (private subnets, min=2 max=5)
    ├─ EC2 (nginx, SG: 80 desde ALB SG)
    ├─ EC2 (nginx, SG: 80 desde ALB SG)
    └─ EC2 (scale out cuando CPU > 60%)
```

## Preguntas de entrevista

- ¿Cuál es la diferencia entre Scale In y Scale Out policy?
- ¿Qué pasa si todos los instances del ASG están unhealthy?
- ¿Cómo el ALB sabe a cuál instancia mandar el tráfico?
- ¿Por qué poner las EC2 en subnets privadas si sirven tráfico público?
