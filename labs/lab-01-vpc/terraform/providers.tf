terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend remoto (descomentar para uso real)
  # backend "s3" {
  #   bucket         = "mi-tfstate-bucket"
  #   key            = "lab-01/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "labs-aws"
      Lab         = "01-vpc"
      ManagedBy   = "terraform"
      Environment = "lab"
    }
  }
}
