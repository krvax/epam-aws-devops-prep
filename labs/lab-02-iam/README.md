# Lab 02 — IAM Roles y Assume Role

**Objetivo:** Crear un IAM Role con least privilege, attached a una EC2, y practicar `sts:AssumeRole` desde CLI.

## Prerequisitos

- Lab 01 aplicado (usa los outputs de VPC)
- AWS CLI configurado
- Terraform >= 1.5

## Estructura

```
lab-02-iam/
├── main.tf          # Role, Policy, Instance Profile
├── assume_role.tf   # Role cross-account para practicar assume-role
├── variables.tf
├── outputs.tf
└── README.md
```

## Uso

```bash
cd labs/lab-02-iam
terraform init
terraform apply

# Practicar assume-role desde CLI
aws sts assume-role \
  --role-arn $(terraform output -raw assume_role_arn) \
  --role-session-name lab02-test

# Verificar identidad con credenciales temporales
export AWS_ACCESS_KEY_ID=<AccessKeyId del output>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey>
export AWS_SESSION_TOKEN=<SessionToken>
aws sts get-caller-identity

# Probar que el rol S3 ReadOnly funciona
aws s3 ls

# Probar que NO tiene permisos de escritura (debe fallar)
aws s3 mb s3://test-bucket-12345

# Limpiar
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
terraform destroy
```

## Conceptos clave

| Concepto | Descripción |
|----------|-------------|
| **Trust Policy** | Define QUIÉN puede asumir el rol (Principal) |
| **Permission Policy** | Define QUÉ puede hacer el rol |
| **Instance Profile** | Contenedor que asocia un Role a una EC2 |
| **STS AssumeRole** | API que entrega credenciales temporales |
| **Session Duration** | 1h por defecto, max 12h |

## Preguntas de entrevista

- ¿Cuál es la diferencia entre un IAM User, Role y Group?
- ¿Cómo das acceso a una Lambda a DynamoDB sin usar access keys?
- ¿Qué es una SCP y cómo interactúa con las IAM Policies?
- ¿Qué significa "least privilege" y cómo lo aplicas en la práctica?
