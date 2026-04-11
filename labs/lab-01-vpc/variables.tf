variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "lab-01"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Map of public subnets"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    a = { cidr = "10.0.1.0/24", az = "us-east-1a" }
    b = { cidr = "10.0.2.0/24", az = "us-east-1b" }
  }
}

variable "private_subnets" {
  description = "Map of private subnets"
  type = map(object({
    cidr = string
    az   = string
  }))
  default = {
    a = { cidr = "10.0.3.0/24", az = "us-east-1a" }
    b = { cidr = "10.0.4.0/24", az = "us-east-1b" }
  }
}

variable "common_tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Project     = "epam-aws-devops-prep"
    Lab         = "lab-01-vpc"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}
