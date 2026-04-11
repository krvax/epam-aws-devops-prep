variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "prefix" {
  description = "Prefijo para nombrar recursos"
  type        = string
  default     = "epam-lab09"
}

variable "vpc_name" {
  description = "Tag Name de la VPC a usar (la del lab-01 o cualquier existente)"
  type        = string
  default     = "epam-lab-vpc"
}

variable "instance_type" {
  description = "Tipo de instancia EC2"
  type        = string
  default     = "t3.micro"
}

variable "log_group_name" {
  description = "Nombre del CloudWatch Log Group"
  type        = string
  default     = "/epam/lab/app"
}

variable "log_retention_days" {
  description = "Días de retención de logs en CloudWatch"
  type        = number
  default     = 3
}

variable "alert_email" {
  description = "Email para notificaciones SNS"
  type        = string
}

variable "ssh_cidr" {
  description = "CIDR permitido para SSH (usa tu IP: x.x.x.x/32)"
  type        = string
  default     = "0.0.0.0/0"  # Restringe esto en uso real
}

variable "tags" {
  description = "Tags comunes para todos los recursos"
  type        = map(string)
  default = {
    Project     = "epam-aws-devops-prep"
    Lab         = "09-cloudwatch-logs"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}
