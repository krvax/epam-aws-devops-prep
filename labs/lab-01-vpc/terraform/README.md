# Lab 01 — VPC con Terraform

## Archivos

```
terraform/
├── providers.tf
├── variables.tf
├── main.tf
├── outputs.tf
└── terraform.tfvars
```

## Recursos que crea

- VPC `10.0.0.0/16` con DNS habilitado
- 2 subnets públicas (us-east-1a, us-east-1b)
- 2 subnets privadas (us-east-1a, us-east-1b)
- Internet Gateway
- NAT Gateway + Elastic IP
- Route tables (pública → IGW, privada → NAT GW)
- EC2 en subnet privada con IAM Role para SSM
- Security Group sin ingress (solo egress)

## Ejecutar

```bash
cd labs/lab-01-vpc/terraform

terraform init
terraform plan
terraform apply

# Conectarse a la EC2 privada vía SSM
aws ssm start-session --target $(terraform output -raw test_instance_id)

# Verificar salida a internet (debe mostrar IP del NAT GW)
curl https://ifconfig.me

# Limpiar
terraform destroy
```

## Variables

| Variable | Default | Descripción |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | Región AWS |
| `project_name` | `lab` | Prefijo para nombres |
| `vpc_cidr` | `10.0.0.0/16` | CIDR de la VPC |
| `availability_zones` | `[us-east-1a, us-east-1b]` | AZs a usar |
| `public_subnet_cidrs` | `[10.0.1.0/24, 10.0.2.0/24]` | CIDRs públicos |
| `private_subnet_cidrs` | `[10.0.3.0/24, 10.0.4.0/24]` | CIDRs privados |

## CLI vs Terraform

```text
CLI: ~50 comandos + copiar variables manualmente
Terraform: terraform apply (1 comando, ~2 min)
```

## Pregunta de entrevista

> "¿Cómo estructuras Terraform para multi-environment?"

Respuesta: root module + módulos reutilizables + `terraform.tfvars` por entorno (dev/stage/prod). State separado por entorno usando workspaces o backends distintos.

---

> 🏷️ Tags: `terraform` `vpc` `networking` `nat-gateway` `igw`
