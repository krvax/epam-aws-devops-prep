output "vpc_id" {
  description = "ID de la VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs de subnets públicas"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs de subnets privadas"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ip" {
  description = "IP pública del NAT Gateway"
  value       = aws_eip.nat.public_ip
}

output "test_instance_id" {
  description = "ID de la EC2 de prueba"
  value       = aws_instance.private_test.id
}

output "ssm_connect_command" {
  description = "Comando para conectarse a la EC2 vía SSM"
  value       = "aws ssm start-session --target ${aws_instance.private_test.id}"
}
