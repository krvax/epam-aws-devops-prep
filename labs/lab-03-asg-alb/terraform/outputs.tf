output "alb_dns_name" {
  description = "URL del ALB"
  value       = "http://${aws_lb.main.dns_name}"
}

output "asg_name" {
  description = "Nombre del ASG"
  value       = aws_autoscaling_group.main.name
}

output "test_commands" {
  description = "Comandos para probar el lab"
  value       = <<-EOT

    # Probar el ALB (esperar ~2 min)
    curl http://${aws_lb.main.dns_name}

    # Ver diferentes instancias respondiendo
    for i in {1..10}; do
      curl -s http://${aws_lb.main.dns_name} | grep "Instance ID"
      sleep 1
    done

    # Ver estado del ASG
    aws autoscaling describe-auto-scaling-groups \
      --auto-scaling-group-names ${aws_autoscaling_group.main.name} \
      --query 'AutoScalingGroups[0].[DesiredCapacity,Instances[*].[InstanceId,HealthStatus]]' \
      --output table
  EOT
}
