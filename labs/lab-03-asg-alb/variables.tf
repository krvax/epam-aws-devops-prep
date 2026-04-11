variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "lab-03"
}

variable "vpc_id" {
  description = "VPC ID from lab-01 output"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs from lab-01 (for ALB)"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs from lab-01 (for EC2 instances)"
  type        = list(string)
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "asg_min" {
  type    = number
  default = 2
}

variable "asg_max" {
  type    = number
  default = 5
}

variable "asg_desired" {
  type    = number
  default = 2
}

variable "scale_out_cpu_threshold" {
  description = "CPU % to trigger scale out"
  type        = number
  default     = 60
}

variable "common_tags" {
  type = map(string)
  default = {
    Project     = "epam-aws-devops-prep"
    Lab         = "lab-03-asg-alb"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}
