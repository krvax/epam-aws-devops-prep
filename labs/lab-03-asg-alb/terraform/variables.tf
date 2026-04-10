variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "lab"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "asg_min" {
  description = "Mínimo de instancias"
  type        = number
  default     = 2
}

variable "asg_max" {
  description = "Máximo de instancias"
  type        = number
  default     = 5
}

variable "asg_desired" {
  description = "Instancias deseadas"
  type        = number
  default     = 2
}

variable "cpu_target" {
  description = "CPU target para scaling policy (%)"
  type        = number
  default     = 60
}
