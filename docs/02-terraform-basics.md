# Terraform Basics — Conceptos Clave

## CLI vs Terraform

```text
AWS CLI                          Terraform
─────────                        ─────────
Imperativo                       Declarativo
"Crea esto, luego esto"          "Quiero que exista esto"
No guarda estado                 Guarda estado (terraform.tfstate)
Difícil de reproducir            100% reproducible
Limpieza: ~20 comandos           terraform destroy
```

## Flujo de trabajo

```text
┌──────────────┐     terraform plan      ┌─────────────┐
│  .tf files   │ ──────────────────────→ │  Plan       │
│  (tu código) │                          │  (preview)  │
└──────────────┘                          └──────┬──────┘
                                                  │
                      terraform apply             │
                 ┌────────────────────────────────┘
                 ▼
        ┌──────────────┐
        │    AWS       │   Crea/modifica/elimina recursos
        └──────────────┘
                 │
                 ▼
        ┌──────────────┐
        │  .tfstate    │   Guarda qué existe actualmente
        └──────────────┘
```

## Comandos esenciales

```bash
terraform init      # Descarga providers
terraform plan      # Preview de cambios
terraform apply     # Aplica cambios
terraform destroy   # Destruye TODO
terraform output    # Muestra outputs
terraform state list # Lista recursos en el state
```

## Estructura típica de un módulo

```
lab/
├── providers.tf     ← Configuración del provider AWS
├── variables.tf     ← Variables de entrada
├── main.tf          ← Recursos principales
├── outputs.tf       ← Valores de salida
└── terraform.tfvars ← Valores de las variables
```

## Conceptos clave para entrevista

**State remoto** — Guardar el tfstate en S3 + DynamoDB para trabajo en equipo:
```hcl
backend "s3" {
  bucket         = "mi-tfstate-bucket"
  key            = "lab/terraform.tfstate"
  region         = "us-east-1"
  dynamodb_table = "terraform-locks"
}
```

**`count` vs `for_each`** — Para crear múltiples recursos:
```hcl
# count: cuando son idénticos o una lista simple
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)
  cidr_block = var.public_subnet_cidrs[count.index]
}

# for_each: cuando necesitas keys únicos
resource "aws_subnet" "public" {
  for_each   = toset(var.public_subnet_cidrs)
  cidr_block = each.value
}
```

**`depends_on`** — Dependencias explícitas:
```hcl
resource "aws_nat_gateway" "main" {
  depends_on = [aws_internet_gateway.main]
}
```

**`data` sources** — Leer recursos existentes sin crearlos:
```hcl
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}
```

**`lifecycle`** — Comportamiento en cambios:
```hcl
lifecycle {
  create_before_destroy = true  # Para zero-downtime updates
  prevent_destroy       = true  # Proteger recursos críticos
}
```

---

> 🏷️ Tags: `terraform` `iac` `aws` `state` `modules`

*Para profundizar en estos conceptos con contexto de entrevista: [03-terraform-concepts.md](03-terraform-concepts.md)*