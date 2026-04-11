terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────
# IAM Role para EC2 con acceso a S3 (read-only)
# ─────────────────────────────────────────
resource "aws_iam_role" "ec2_s3_reader" {
  name        = "${var.project}-ec2-s3-reader"
  description = "Allows EC2 instances to read from S3 - no static keys needed"

  # Trust Policy: solo EC2 puede asumir este rol
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowEC2AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

# Inline policy: acceso S3 de solo lectura a un bucket específico
resource "aws_iam_role_policy" "s3_read" {
  name = "s3-read-specific-bucket"
  role = aws_iam_role.ec2_s3_reader.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ListBuckets"
        Effect = "Allow"
        Action = ["s3:ListAllMyBuckets", "s3:GetBucketLocation"]
        Resource = "*"
      },
      {
        Sid    = "ReadSpecificBucket"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      }
    ]
  })
}

# Instance Profile (necesario para asociar el role a EC2)
resource "aws_iam_instance_profile" "ec2_s3_reader" {
  name = "${var.project}-ec2-s3-reader-profile"
  role = aws_iam_role.ec2_s3_reader.name
  tags = var.common_tags
}

# SSM tambien necesario para acceder sin SSH
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_s3_reader.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
