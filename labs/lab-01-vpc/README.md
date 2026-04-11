# Lab 01 — VPC desde cero

**Objetivo:** Crear una VPC con subnets públicas y privadas, Internet Gateway, NAT Gateway y verificar conectividad desde una EC2 en subnet privada.

## Prerequisitos

- AWS CLI configurado (`aws configure` o variables de entorno)
- Terraform >= 1.5
- Permisos IAM: `ec2:*`, `ssm:*`

## Estructura

```
lab-01-vpc/
├── main.tf          # VPC, subnets, IGW, NAT GW, route tables
├── ec2.tf           # EC2 en subnet privada con SSM access
├── variables.tf     # Variables configurables
├── outputs.tf       # IDs útiles para labs siguientes
└── README.md
```

## Uso

```bash
cd labs/lab-01-vpc
terraform init
terraform plan
terraform apply

# Conectarte a la EC2 privada via SSM (sin SSH abierto)
aws ssm start-session --target $(terraform output -raw instance_id)

# Verificar salida a internet desde la instancia privada
curl -s https://checkip.amazonaws.com

# Limpiar
terraform destroy
```

## Arquitectura

```
VPC 10.0.0.0/16
├── Public Subnet A  10.0.1.0/24  (us-east-1a)  → Internet Gateway
├── Public Subnet B  10.0.2.0/24  (us-east-1b)  → Internet Gateway
├── Private Subnet A 10.0.3.0/24  (us-east-1a)  → NAT Gateway
└── Private Subnet B 10.0.4.0/24  (us-east-1b)  → NAT Gateway

NAT Gateway → en Public Subnet A (con Elastic IP)
EC2 t3.micro → en Private Subnet A (acceso via SSM)
```

## Preguntas de entrevista

- ¿Cuál es la diferencia entre Security Group y NACL?
- ¿Cuándo necesitas un NAT Gateway vs un NAT Instance?
- ¿Qué pasa si el NAT Gateway falla? ¿Cómo lo haces resiliente?
- ¿Por qué poner la EC2 en subnet privada y no pública?
