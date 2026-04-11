variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cluster_name" {
  type    = string
  default = "epam-prep-eks"
}

variable "kubernetes_version" {
  type    = string
  default = "1.30"
}

variable "vpc_id" {
  description = "VPC ID from lab-01"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for node group"
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Public subnets for ALB"
  type        = list(string)
}

variable "node_instance_type" {
  type    = string
  default = "t3.medium"
}

variable "node_min" {
  type    = number
  default = 1
}

variable "node_max" {
  type    = number
  default = 3
}

variable "node_desired" {
  type    = number
  default = 2
}

variable "common_tags" {
  type = map(string)
  default = {
    Project     = "epam-aws-devops-prep"
    Lab         = "lab-04-eks-cluster"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}
