terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = "labs-aws", Lab = "02-iam", ManagedBy = "terraform" }
  }
}

# ============================================
# DATA: Cuenta actual
# ============================================
data "aws_caller_identity" "current" {}

# ============================================
# IAM ROLE con Trust Policy
# ============================================
resource "aws_iam_role" "cross_role" {
  name                 = "${var.project_name}-cross-role"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "sts:ExternalId" = var.external_id }
      }
    }]
  })

  tags = { Name = "${var.project_name}-cross-role" }
}

# ============================================
# POLÍTICA: Least Privilege (solo S3 read)
# ============================================
resource "aws_iam_role_policy" "s3_readonly" {
  name = "${var.project_name}-s3-readonly"
  role = aws_iam_role.cross_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBuckets"
        Effect   = "Allow"
        Action   = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
        Resource = "arn:aws:s3:::*"
      },
      {
        Sid    = "ReadSpecificBuckets"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.project_name}-test-*",
          "arn:aws:s3:::${var.project_name}-test-*/*"
        ]
      }
    ]
  })
}

# ============================================
# S3 BUCKET DE PRUEBA
# ============================================
resource "aws_s3_bucket" "test" {
  bucket = "${var.project_name}-test-${data.aws_caller_identity.current.account_id}"
  tags   = { Name = "${var.project_name}-test-bucket" }
}

resource "aws_s3_object" "test_file" {
  bucket  = aws_s3_bucket.test.id
  key     = "test.txt"
  content = "Si puedes leer esto, el assume role funcionó correctamente ✅"
}
