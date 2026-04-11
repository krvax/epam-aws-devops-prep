# =============================================================================
# Lab 05 — Remote State: S3 Bucket para Terraform State
# =============================================================================
# Crea el bucket S3 que almacena el estado de Terraform.
# IMPORTANTE: Este archivo se aplica con state LOCAL primero (bootstrap),
# luego se migra al backend remoto con terraform init -migrate-state
# =============================================================================

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Lab         = "lab-05-remote-state"
    }
  }
}

# -----------------------------------------------------------------------------
# S3 Bucket — almacén del estado
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "tf_state" {
  bucket = "${var.project_name}-tf-state-${data.aws_caller_identity.current.account_id}"

  # Prevenir borrado accidental del bucket de estado
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "Terraform State Bucket"
  }
}

# Habilitar versioning — requerido para use_lockfile y para recovery de estado
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Encryption en reposo con AES256
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bloquear acceso público — el estado nunca debe ser público
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Data source para obtener el Account ID dinámicamente
data "aws_caller_identity" "current" {}
