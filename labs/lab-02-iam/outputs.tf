output "ec2_role_arn" {
  description = "ARN of the EC2 IAM role"
  value       = aws_iam_role.ec2_s3_reader.arn
}

output "instance_profile_name" {
  description = "Instance profile name to use in EC2 launch configs"
  value       = aws_iam_instance_profile.ec2_s3_reader.name
}

output "assume_role_arn" {
  description = "ARN to use with: aws sts assume-role --role-arn <this>"
  value       = aws_iam_role.assumable.arn
}

output "assume_role_cli_command" {
  description = "Ready-to-run CLI command to test assume-role"
  value       = "aws sts assume-role --role-arn ${aws_iam_role.assumable.arn} --role-session-name lab02-test"
}
