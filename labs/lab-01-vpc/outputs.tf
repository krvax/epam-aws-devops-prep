output "vpc_id" {
  description = "VPC ID — used by subsequent labs"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = [for s in aws_subnet.private : s.id]
}

output "instance_id" {
  description = "EC2 instance ID — use with: aws ssm start-session --target <id>"
  value       = aws_instance.private.id
}

output "nat_gateway_ip" {
  description = "Elastic IP of the NAT Gateway"
  value       = aws_eip.nat.public_ip
}
