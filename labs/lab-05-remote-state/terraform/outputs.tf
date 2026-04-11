output "state_bucket_name" {
  description = "Nombre del bucket S3 para Terraform state"
  value       = aws_s3_bucket.tf_state.id
}

output "state_bucket_arn" {
  description = "ARN del bucket — usar en IAM policies de otros labs"
  value       = aws_s3_bucket.tf_state.arn
}

output "backend_config" {
  description = "Bloque backend listo para copiar en otros labs"
  value = <<-EOT
    terraform {
      backend "s3" {
        bucket       = "${aws_s3_bucket.tf_state.id}"
        key          = "<LAB_NAME>/terraform.tfstate"
        region       = "${var.aws_region}"
        encrypt      = true
        use_lockfile = true
      }
    }
  EOT
}
