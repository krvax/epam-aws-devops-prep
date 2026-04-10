# Lab 02 — IAM Roles con Terraform

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

- IAM Role `lab-cross-role` con Trust Policy (same-account)
- Inline policy: solo S3 read en buckets `lab-test-*`
- S3 bucket de prueba con un objeto de test
- ExternalId para seguridad extra (previene confused deputy)

## Ejecutar

```bash
cd labs/lab-02-iam/terraform

terraform init
terraform plan
terraform apply

# Ver los comandos para probar assume role
terraform output assume_role_command

# Copiar y ejecutar los comandos que aparecen en el output
# Limpiar
terraform destroy
```

## Variables

| Variable | Default | Descripción |
|----------|---------|-------------|
| `aws_region` | `us-east-1` | Región AWS |
| `project_name` | `lab` | Prefijo para nombres |
| `external_id` | `lab-external-id-12345` | ExternalId para assume role |

## Qué verifica el lab

```bash
# ✅ Debe funcionar (permisos S3)
aws s3 ls
aws s3 cp s3://<bucket>/test.txt -

# ❌ Debe fallar (sin permisos EC2)
aws ec2 describe-instances
# Error: UnauthorizedOperation
```

## Pregunta de entrevista

> "¿Qué es el ExternalId en assume role?"

Respuesta: Es una condición adicional en la Trust Policy que previene el *confused deputy attack* — situación donde un servicio de terceros podría asumir un rol en tu cuenta usando sus propios permisos. El ExternalId actúa como un secreto compartido entre tú y quien asume el rol.

---

> 🏷️ Tags: `terraform` `iam` `assume-role` `least-privilege` `s3`
