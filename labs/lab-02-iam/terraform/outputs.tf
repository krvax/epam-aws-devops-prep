output "role_arn" {
  description = "ARN del rol para asumir"
  value       = aws_iam_role.cross_role.arn
}

output "test_bucket" {
  description = "Bucket de prueba"
  value       = aws_s3_bucket.test.id
}

output "assume_role_command" {
  description = "Comandos para probar el assume role"
  value       = <<-EOT

    # 1. Asumir el rol
    CREDENTIALS=$(aws sts assume-role \
      --role-arn ${aws_iam_role.cross_role.arn} \
      --role-session-name test-session \
      --external-id ${var.external_id} \
      --query 'Credentials' \
      --output json)

    # 2. Exportar credenciales temporales
    export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')

    # 3. Verificar identidad
    aws sts get-caller-identity

    # 4. Probar S3 (debe funcionar ✅)
    aws s3 ls
    aws s3 cp s3://${aws_s3_bucket.test.id}/test.txt -

    # 5. Probar EC2 (debe FALLAR ❌)
    aws ec2 describe-instances

    # 6. Volver a tu identidad original
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  EOT
}
