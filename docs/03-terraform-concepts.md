# 03 — Terraform & Terragrunt: Conceptos Clave

> Complemento amigable a los labs de Terraform.
> Si algo de state, módulos, workspaces o Terragrunt te suena confuso, empieza aquí.

---

## Índice

1. [La Gran Foto: qué problema resuelve Terraform](#1-la-gran-foto)
2. [Ciclo de vida básico](#2-ciclo-de-vida-básico)
3. [State: el corazón de Terraform](#3-state-el-corazón-de-terraform)
4. [Variables, Outputs y Locals](#4-variables-outputs-y-locals)
5. [Data Sources: leer sin crear](#5-data-sources-leer-sin-crear)
6. [Módulos: código reutilizable](#6-módulos-código-reutilizable)
7. [Patrones avanzados](#7-patrones-avanzados)
8. [Workspaces](#8-workspaces)
9. [Terraform con AWS: patrones reales](#9-terraform-con-aws-patrones-reales)
10. [Terragrunt: DRY para entornos](#10-terragrunt-dry-para-entornos)
11. [Preguntas de entrevista con esquema de respuesta](#11-preguntas-de-entrevista)

---

## 1. La Gran Foto

Terraform es una herramienta de **Infraestructura como Código (IaC)** que te permite
describir recursos de AWS (u otros providers) en archivos `.tf` y aplicar esos cambios
de forma repetible y predecible.

```
Tu código .tf
    │
    ▼
terraform plan    ← muestra qué va a cambiar (sin tocar nada)
    │
    ▼
terraform apply   ← crea/modifica/destruye recursos en AWS
    │
    ▼
terraform.tfstate ← guarda el estado actual de la infra
```

**El principio fundamental**: Terraform compara tu código (estado deseado) contra el
state (estado actual) y calcula el diff. Solo cambia lo que es diferente.

---

## 2. Ciclo de vida básico

```bash
# 1. Inicializar: descarga providers y módulos
terraform init

# 2. Formatear código (buena práctica antes de commit)
terraform fmt

# 3. Validar sintaxis
terraform validate

# 4. Ver qué cambiaría (nunca toca AWS)
terraform plan

# 5. Aplicar cambios
terraform apply

# 5b. Aplicar sin confirmación manual (para pipelines CI/CD)
terraform apply -auto-approve

# 6. Destruir todo (¡cuidado!)
terraform destroy
```

### Estructura mínima de un proyecto

```
mi-proyecto/
  main.tf         # recursos principales
  variables.tf    # declaración de variables
  outputs.tf      # valores que quieres exponer
  providers.tf    # configuración del provider (AWS, versión, región)
  terraform.tfvars # valores de las variables (no commitear si tiene secrets)
```

### providers.tf — siempre pin la versión

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"   # acepta 5.x pero no 6.x
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "terraform"
      Project     = var.project_name
    }
  }
}
```

> 💡 `default_tags` en el provider aplica esos tags a **todos** los recursos automáticamente.
> Es una best practice que muy pocos conocen y que EPAM valora.

---

## 3. State: el corazón de Terraform

### Qué es el state

`terraform.tfstate` es un archivo JSON que Terraform mantiene para saber qué recursos
existen en el mundo real y cuáles son sus atributos actuales.

**Sin state**: Terraform no puede saber si el recurso ya existe o si hay que crearlo.
**Con state corrupto o desincronizado**: Terraform puede crear recursos duplicados o
intentar destruir cosas que no debería.

### Remote State: obligatorio en equipos

Local state (`terraform.tfstate` en tu máquina) es solo para proyectos personales.
En equipos usas **remote state** en S3 + DynamoDB para locking.

```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "mi-empresa-terraform-state"
    key            = "proyectos/eks-cluster/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-state-locks"
    encrypt        = true
  }
}
```

```bash
# Crear el bucket y tabla ANTES de hacer terraform init
aws s3api create-bucket \
  --bucket mi-empresa-terraform-state \
  --region us-east-1

aws s3api put-bucket-versioning \
  --bucket mi-empresa-terraform-state \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name terraform-state-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST
```

### Por qué S3 + DynamoDB

| Componente | Para qué |
|---|---|
| S3 | Almacena el archivo de state |
| S3 Versioning | Permite recuperar versiones anteriores del state |
| DynamoDB | State locking — evita que dos `terraform apply` corran simultáneamente |
| S3 Encryption | El state puede contener secrets (passwords de RDS, etc.) |

### Comandos de manipulación de state

```bash
# Ver todos los recursos en el state
terraform state list

# Ver detalles de un recurso específico
terraform state show aws_instance.web

# Renombrar un recurso en el state (sin destruir el recurso real)
terraform state mv aws_instance.web aws_instance.web_server

# Eliminar un recurso del state (sin destruir el recurso real)
# Útil cuando quieres que Terraform deje de gestionar algo
terraform state rm aws_s3_bucket.legacy

# Importar un recurso existente en AWS al state
# (para recursos creados manualmente que quieres gestionar con TF)
terraform import aws_s3_bucket.mi-bucket nombre-del-bucket-en-aws
```

> ⚠️ `terraform state rm` + `terraform import` son los comandos más usados cuando
> alguien modificó un recurso manualmente en la consola de AWS y rompió el state.

---

## 4. Variables, Outputs y Locals

### Variables: inputs de tu módulo o proyecto

```hcl
# variables.tf
variable "environment" {
  description = "Entorno de despliegue"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "El entorno debe ser dev, staging o prod."
  }
}

variable "instance_count" {
  description = "Número de instancias EC2"
  type        = number
  default     = 2
}

variable "allowed_cidrs" {
  description = "CIDRs permitidos en el Security Group"
  type        = list(string)
  default     = ["10.0.0.0/8"]
}

variable "tags" {
  description = "Tags adicionales"
  type        = map(string)
  default     = {}
}
```

```hcl
# terraform.tfvars (valores concretos)
environment    = "prod"
instance_count = 3
allowed_cidrs  = ["10.0.0.0/8", "172.16.0.0/12"]
```

### Outputs: valores que expones

```hcl
# outputs.tf
output "vpc_id" {
  description = "ID de la VPC creada"
  value       = aws_vpc.main.id
}

output "rds_endpoint" {
  description = "Endpoint de la base de datos"
  value       = aws_db_instance.main.endpoint
  sensitive   = true   # no se muestra en logs de CI/CD
}
```

Los outputs de un módulo se consumen así:
```hcl
module.vpc.vpc_id
module.rds.rds_endpoint
```

### Locals: variables internas (no son inputs)

```hcl
locals {
  # Construir un nombre consistente para todos los recursos
  name_prefix = "${var.project}-${var.environment}"

  # Mergear tags por defecto con tags del usuario
  common_tags = merge(
    {
      Environment = var.environment
      ManagedBy   = "terraform"
    },
    var.tags
  )

  # Calcular algo basado en otras variables
  is_production = var.environment == "prod"
}

# Usar locals
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}
```

---

## 5. Data Sources: leer sin crear

Un data source **lee** información de recursos existentes sin crearlos.

```hcl
# Leer la última AMI de Amazon Linux 2 (sin hardcodear el ID)
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Leer una VPC existente por tag
data "aws_vpc" "existing" {
  filter {
    name   = "tag:Name"
    values = ["mi-vpc-de-produccion"]
  }
}

# Leer el account ID de AWS actual (muy útil para ARNs)
data "aws_caller_identity" "current" {}

# Usar los data sources
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id   # siempre la AMI más reciente
  subnet_id     = data.aws_vpc.existing.id
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}
```

---

## 6. Módulos: código reutilizable

### Qué es un módulo

Un módulo es simplemente **un directorio con archivos `.tf`**. Cualquier proyecto de
Terraform es técnicamente un módulo (el root module). Los módulos hijos son los que
reutilizas.

### Estructura de un módulo reutilizable

```
modules/
  vpc/
    main.tf        # recursos (aws_vpc, aws_subnet, etc.)
    variables.tf   # inputs del módulo
    outputs.tf     # valores que expone
    README.md      # documentación (obligatorio en equipos)
```

```hcl
# modules/vpc/variables.tf
variable "vpc_cidr"     { type = string }
variable "environment"  { type = string }
variable "azs"          { type = list(string) }
variable "public_subnets"  { type = list(string) }
variable "private_subnets" { type = list(string) }
```

```hcl
# modules/vpc/outputs.tf
output "vpc_id"          { value = aws_vpc.main.id }
output "public_subnets"  { value = aws_subnet.public[*].id }
output "private_subnets" { value = aws_subnet.private[*].id }
```

### Consumir un módulo

```hcl
# envs/prod/main.tf
module "vpc" {
  source = "../../modules/vpc"   # path relativo

  vpc_cidr        = "10.0.0.0/16"
  environment     = "prod"
  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}

# Usar outputs del módulo en otro recurso
module "eks" {
  source = "../../modules/eks"

  vpc_id     = module.vpc.vpc_id          # output del módulo vpc
  subnet_ids = module.vpc.private_subnets
}
```

### Módulos del registro público de Terraform

```hcl
# En vez de escribir el módulo desde cero, usar uno oficial
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"   # siempre pin la versión

  cluster_name    = "mi-cluster"
  cluster_version = "1.29"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets
}
```

> 💡 **Cómo versionar módulos internos en un equipo**: guárdalos en un repo de Git
> separado y referencialos por tag de Git:
> ```hcl
> source = "git::https://github.com/mi-empresa/terraform-modules.git//vpc?ref=v2.1.0"
> ```
> Así cada equipo puede actualizar a la versión del módulo cuando quiera, sin romper otros.

---

## 7. Patrones avanzados

### `count` vs `for_each`

```hcl
# count — útil para crear N copias idénticas
resource "aws_instance" "web" {
  count         = 3
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  tags = {
    Name = "web-${count.index}"   # web-0, web-1, web-2
  }
}

# Problema con count: si eliminas el índice 1, Terraform destruye y recrea el 2 y 3
# porque los identifica por posición en la lista.
```

```hcl
# for_each — mejor para recursos con identidad propia
locals {
  buckets = {
    logs    = { region = "us-east-1" }
    backups = { region = "us-west-2" }
    assets  = { region = "us-east-1" }
  }
}

resource "aws_s3_bucket" "this" {
  for_each = local.buckets

  bucket = "mi-empresa-${each.key}"

  tags = {
    Name    = each.key
    Region  = each.value.region
  }
}

# Ventaja: cada recurso se identifica por key ("logs", "backups", "assets")
# Si eliminas "backups", solo se destruye ese bucket, no los demás.
```

**Regla**: usa `for_each` casi siempre. Usa `count` solo para cosas verdaderamente
idénticas donde el índice no importa.

### `dynamic` blocks

Cuando un bloque dentro de un recurso necesita repetirse un número variable de veces:

```hcl
variable "ingress_rules" {
  default = [
    { port = 80,  cidr = "0.0.0.0/0" },
    { port = 443, cidr = "0.0.0.0/0" },
    { port = 8080, cidr = "10.0.0.0/8" },
  ]
}

resource "aws_security_group" "web" {
  name   = "web-sg"
  vpc_id = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = [ingress.value.cidr]
    }
  }
}
```

### `lifecycle` rules

```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  lifecycle {
    # Crear el nuevo recurso antes de destruir el viejo
    # Útil para recursos que no pueden tener downtime
    create_before_destroy = true

    # Nunca destruir este recurso (ej: base de datos de producción)
    prevent_destroy = true

    # Ignorar cambios en estos atributos (ej: si alguien cambia la AMI manualmente)
    ignore_changes = [ami, tags["LastDeployment"]]
  }
}
```

### `templatefile()`

```hcl
# Generar un script de user-data dinámicamente
resource "aws_launch_template" "web" {
  name_prefix   = "web-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  user_data = base64encode(templatefile("${path.module}/templates/user-data.sh.tpl", {
    environment    = var.environment
    app_version    = var.app_version
    db_endpoint    = module.rds.endpoint
  }))
}
```

```bash
# templates/user-data.sh.tpl
#!/bin/bash
export ENVIRONMENT="${environment}"
export APP_VERSION="${app_version}"
export DB_HOST="${db_endpoint}"

yum update -y
yum install -y docker
systemctl start docker
docker run -d \
  -e ENVIRONMENT=$ENVIRONMENT \
  -e DB_HOST=$DB_HOST \
  mi-empresa/mi-app:${app_version}
```

---

## 8. Workspaces

Los workspaces permiten tener **múltiples states** con el mismo código.

```bash
# Ver workspaces existentes
terraform workspace list

# Crear un workspace nuevo
terraform workspace new staging

# Cambiar de workspace
terraform workspace select prod

# Ver workspace actual
terraform workspace show
```

```hcl
# Usar el workspace en el código
locals {
  instance_type = terraform.workspace == "prod" ? "t3.large" : "t3.micro"
  replica_count = terraform.workspace == "prod" ? 3 : 1
}
```

### Workspaces vs directorios separados por entorno

| | Workspaces | Directorios separados |
|--|---|---|
| Código | Mismo código, distinto state | Código separado por entorno |
| Riesgo | Alto: `terraform destroy` en prod es fácil | Bajo: contexto claro |
| Flexibilidad | Limitada | Alta (configs muy distintas por entorno) |
| Recomendado para | Entornos muy similares | Entornos con diferencias significativas |

> 💡 **Opinión de la industria**: para entornos de producción real, la mayoría prefiere
> **directorios separados + Terragrunt** sobre workspaces. Los workspaces son útiles para
> feature branches o testing efímero.

---

## 9. Terraform con AWS: patrones reales

### Organización recomendada de un repo

```
infrastructure/
  modules/
    vpc/
    eks/
    rds/
    iam/
  envs/
    dev/
      main.tf
      terraform.tfvars
      backend.tf
    staging/
      main.tf
      terraform.tfvars
      backend.tf
    prod/
      main.tf
      terraform.tfvars
      backend.tf
```

### Gestionar EKS con Terraform

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${local.name_prefix}-eks"
  cluster_version = "1.29"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # Karpenter en vez de managed node groups
  # (necesita un node group mínimo para que Karpenter corra)
  eks_managed_node_groups = {
    karpenter = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 2
      desired_size   = 1

      taints = {
        addons = {
          key    = "CriticalAddonsOnly"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }

  # Acceso al cluster
  enable_cluster_creator_admin_permissions = true
}
```

### Gestionar IAM con Terraform (least privilege)

```hcl
# Política con mínimo privilegio para una app que solo lee de S3
data "aws_iam_policy_document" "app_s3_read" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.app_data.arn,
      "${aws_s3_bucket.app_data.arn}/*",
    ]
  }
}

resource "aws_iam_policy" "app_s3_read" {
  name   = "${local.name_prefix}-app-s3-read"
  policy = data.aws_iam_policy_document.app_s3_read.json
}
```

---

## 10. Terragrunt: DRY para entornos

### El problema que resuelve

Con Terraform puro, cuando tienes múltiples entornos repites mucho código:
- El bloque `backend` es casi idéntico en cada entorno (solo cambia el `key`)
- El bloque `provider` es igual en todos
- Las llamadas a módulos son iguales, solo cambian algunos valores

Terragrunt es un **wrapper** de Terraform que elimina esa repetición.

### Estructura con Terragrunt

```
infrastructure/
  terragrunt.hcl          ← configuración raíz (backend, provider)
  modules/
    vpc/
    eks/
  envs/
    dev/
      terragrunt.hcl      ← hereda del raíz + valores de dev
      vpc/
        terragrunt.hcl    ← llama al módulo vpc con valores de dev
      eks/
        terragrunt.hcl    ← llama al módulo eks con valores de dev
    prod/
      terragrunt.hcl
      vpc/
        terragrunt.hcl
      eks/
        terragrunt.hcl
```

### terragrunt.hcl raíz — backend dinámico

```hcl
# infrastructure/terragrunt.hcl

locals {
  # Extraer el entorno del path actual
  env = basename(dirname(find_in_parent_folders()))
}

# Backend configurado una sola vez para todos los módulos
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "mi-empresa-terraform-state"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
  }
}

# Provider generado automáticamente
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = {
      Environment = "${local.env}"
      ManagedBy   = "terragrunt"
    }
  }
}
EOF
}
```

### terragrunt.hcl por módulo — sin repetición

```hcl
# envs/prod/vpc/terragrunt.hcl

# Hereda toda la config del raíz (backend, provider)
include "root" {
  path = find_in_parent_folders()
}

# Apunta al módulo de Terraform
terraform {
  source = "../../../modules/vpc"
}

# Solo defines los valores específicos de este entorno
inputs = {
  vpc_cidr        = "10.0.0.0/16"
  environment     = "prod"
  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
}
```

```hcl
# envs/prod/eks/terragrunt.hcl

include "root" {
  path = find_in_parent_folders()
}

# Dependencia explícita: EKS necesita que VPC exista primero
dependency "vpc" {
  config_path = "../vpc"

  # Valores mock para poder hacer plan sin que VPC esté creada
  mock_outputs = {
    vpc_id          = "vpc-00000000"
    private_subnets = ["subnet-00000000", "subnet-11111111"]
  }
}

terraform {
  source = "../../../modules/eks"
}

inputs = {
  cluster_name    = "mi-empresa-prod"
  cluster_version = "1.29"
  vpc_id          = dependency.vpc.outputs.vpc_id
  subnet_ids      = dependency.vpc.outputs.private_subnets
}
```

### Comandos de Terragrunt

```bash
# Equivalentes a los comandos de Terraform
terragrunt init
terragrunt plan
terragrunt apply

# Lo más poderoso: aplicar TODOS los módulos de un entorno en orden
cd envs/prod
terragrunt run-all apply

# Plan de todo sin aplicar
terragrunt run-all plan

# Solo los módulos que cambiaron (Terragrunt detecta dependencias)
terragrunt run-all apply --terragrunt-include-dir vpc
```

### Terragrunt vs Workspaces vs directorios

| | Workspaces | Directorios | Terragrunt |
|--|---|---|---|
| Repetición de código | Baja | Alta | Muy baja |
| Claridad de entornos | Baja | Alta | Alta |
| Gestión de dependencias | Manual | Manual | Automática |
| Complejidad inicial | Baja | Media | Media-Alta |
| Recomendado para | Feature branches | Equipos pequeños | Equipos grandes, múltiples entornos |

---

## 11. Preguntas de entrevista

**"¿Qué pasa si dos personas hacen `terraform apply` al mismo tiempo?"**

```
Sin remote state locking:
- Los dos leen el mismo state
- Los dos calculan el diff sobre el mismo estado
- Los dos aplican cambios simultáneamente
- El state se corrompe: el último en escribir gana, el primero se pierde
- Resultado: recursos duplicados, state desincronizado, caos

Con S3 + DynamoDB locking:
- El primero en hacer apply adquiere el lock en DynamoDB
- El segundo ve un error: "state is locked by [user], started at [time]"
- El segundo espera o cancela
- Cuando el primero termina, libera el lock
- El segundo puede proceder con el state actualizado
```

---

**"¿Alguien modificó un recurso manualmente en AWS. ¿Qué pasa?"**

```
Terraform no detecta cambios en tiempo real — solo cuando haces plan/apply.

Cuando haces terraform plan:
- Terraform lee el state (lo que cree que existe)
- Terraform lee el estado real de AWS (API)
- Detecta la diferencia
- Muestra que quiere "revertir" el cambio manual

Opciones:
1. terraform apply → revierte el cambio manual (infra as code gana)
2. terraform import → importa el estado actual al state para adoptarlo
3. ignore_changes en lifecycle → Terraform ignora ese atributo para siempre

La respuesta correcta en entrevista: "Lo ideal es que nadie modifique manualmente.
Se establece una política: todos los cambios van por Terraform y PR review.
Para detectar drift, usamos terraform plan en el pipeline de CI que corre noche."
```

---

**"¿Cómo evitas duplicar código entre entornos en Terraform?"**

```
Tres niveles de respuesta (de menor a mayor madurez):

1. Módulos locales — extraes lógica común a modules/ y la llamas desde cada entorno.
   Elimina duplicación de lógica pero no del boilerplate (backend, provider).

2. Módulos + variables — usas un mismo módulo con terraform.tfvars distintos por entorno.
   Funciona bien para equipos pequeños.

3. Terragrunt — un terragrunt.hcl raíz define backend y provider una sola vez.
   Cada módulo hereda esa config y solo define sus inputs.
   Gestiona dependencias entre módulos automáticamente.
   Es el estándar en equipos grandes con muchos entornos.
```

---

**"¿Qué es `terraform import` y cuándo lo usas?"**

```
terraform import asocia un recurso existente en AWS con un bloque de código en Terraform.
Úsalo cuando:
- Alguien creó infraestructura manualmente y quieres empezar a gestionarla con TF
- Migraste de CloudFormation a Terraform
- El state se corrompió y perdiste el track de un recurso

Ejemplo:
# 1. Escribir el bloque resource en tu .tf (vacío está bien)
resource "aws_s3_bucket" "mi-bucket" {}

# 2. Importar
terraform import aws_s3_bucket.mi-bucket nombre-real-del-bucket-en-aws

# 3. Hacer plan para ver qué atributos faltan en tu código
terraform plan

# 4. Completar el código hasta que el plan muestre "No changes"

Desde Terraform 1.5+ también existe el bloque import{} en HCL que es más declarativo.
```

---

**"¿Cómo manejas secrets en Terraform?"**

```
Lo que NO hay que hacer:
- Hardcodear passwords en .tf o .tfvars (van a Git → filtración)
- Usar variables de entorno sin encriptar en CI/CD

Lo que SÍ se hace:

1. AWS Secrets Manager como fuente de verdad:
   data "aws_secretsmanager_secret_version" "db_password" {
     secret_id = "prod/rds/password"
   }
   # Terraform lee el secret en runtime, nunca lo guarda en código

2. State encryption:
   - El state puede contener valores sensibles (RDS passwords, etc.)
   - Usar encrypt = true en el backend S3
   - El bucket S3 debe tener acceso restringido solo al rol de CI/CD

3. sensitive = true en outputs:
   output "db_password" {
     value     = random_password.db.result
     sensitive = true   # no aparece en logs de CI/CD
   }

4. En pipelines CI/CD:
   - Secrets en GitHub Actions Secrets / AWS Parameter Store
   - Nunca en variables de entorno visibles en logs
```

---

**"¿Cómo haces upgrades de Kubernetes con Terraform?"**

```
El upgrade de EKS tiene orden obligatorio:

1. Actualizar el control plane primero (en el módulo EKS):
   cluster_version = "1.29"  →  "1.30"
   terraform apply
   # AWS actualiza el control plane sin downtime

2. Actualizar los add-ons del cluster (CoreDNS, kube-proxy, VPC CNI):
   aws eks update-addon --cluster-name mi-cluster --addon-name coredns --addon-version ...

3. Actualizar los node groups:
   # Cambiar la versión en el Launch Template
   # El node group hace rolling update (un nodo a la vez)

4. Verificar que los pods siguen corriendo:
   kubectl get pods -A

Riesgo: solo puedes saltar una versión menor a la vez (1.28 → 1.29, no 1.28 → 1.30).
Con Terraform, el cambio de cluster_version hace todo el paso 1 automáticamente.
```

---

> 💡 **Tip para la entrevista**: si te preguntan sobre Terraform y mencionas Terragrunt,
> espera follow-up questions. Solo úsalo si lo entiendes bien.
> Una respuesta honesta: *"En mi equipo usamos módulos con directorios separados por entorno.
> Conozco Terragrunt y entiendo el problema que resuelve, pero no lo he usado en producción."*

---

*Documento generado como complemento de la guía principal del repo.*  
*Anterior: [02-terraform-basics.md](02-terraform-basics.md)*  
*Volver al inicio: [00-concepts-overview.md](00-concepts-overview.md)*