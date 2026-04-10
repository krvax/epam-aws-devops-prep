variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "lab"
}

variable "external_id" {
  description = "External ID para assume role (seguridad extra)"
  type        = string
  default     = "lab-external-id-12345"
  sensitive   = true
}
