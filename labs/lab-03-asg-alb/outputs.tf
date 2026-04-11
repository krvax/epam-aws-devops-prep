output "alb_dns_name" {
  description = "ALB DNS name - use with: curl http://<this>"
  value       = aws_lb.main.dns_name
}

output "alb_arn" {
  value = aws_lb.main.arn
}

output "target_group_arn" {
  value = aws_lb_target_group.main.arn
}

output "asg_name" {
  description = "ASG name for CLI monitoring"
  value       = aws_autoscaling_group.main.name
}
