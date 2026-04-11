# =============================================================================
# backend.tf — Configuración del backend remoto S3
# =============================================================================
# PASO 2: Una vez creado el bucket con main.tf (state local),
# descomentar este bloque y correr: terraform init -migrate-state
# =============================================================================

terraform {
  backend "s3" {
    bucket = "epam-prep-tf-state-<YOUR_ACCOUNT_ID>" # reemplazar con output del apply
    key    = "lab-05/terraform.tfstate"
    region = "us-east-1"
    encrypt      = true
    use_lockfile = true # Terraform 1.10+ — locking nativo sin DynamoDB
  }
}

# -----------------------------------------------------------------------------
# ¿Por qué use_lockfile en vez de dynamodb_table?
# -----------------------------------------------------------------------------
# Terraform 1.10 introdujo locking nativo en S3 usando conditional writes.
# Al hacer terraform apply:
#   1. Terraform crea terraform.tfstate.tflock en S3 (If-None-Match header)
#   2. Si el archivo ya existe → otro proceso tiene el lock → falla limpiamente
#   3. Al terminar, Terraform borra el .tflock
#
# Ventajas vs DynamoDB:
#   - Sin recursos extra que mantener
#   - Sin costo adicional de DynamoDB
#   - Misma protección contra apply concurrentes
# -----------------------------------------------------------------------------
