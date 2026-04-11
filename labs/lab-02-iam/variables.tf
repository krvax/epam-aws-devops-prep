variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project prefix"
  type        = string
  default     = "lab-02"
}

variable "s3_bucket_name" {
  description = "Name of the S3 bucket the EC2 role can read from"
  type        = string
  default     = "my-lab-bucket-replace-me"
}

variable "common_tags" {
  type = map(string)
  default = {
    Project     = "epam-aws-devops-prep"
    Lab         = "lab-02-iam"
    Environment = "lab"
    ManagedBy   = "terraform"
  }
}
