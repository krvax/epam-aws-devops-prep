output "instance_id" {
  description = "ID de la EC2 loggen"
  value       = aws_instance.loggen.id
}

output "log_group_name" {
  description = "CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.app.name
}

output "sns_topic_arn" {
  description = "ARN del SNS topic de alertas"
  value       = aws_sns_topic.alerts.arn
}

output "alarm_app_errors" {
  description = "Nombre del alarm de errores 5xx"
  value       = aws_cloudwatch_metric_alarm.app_errors.alarm_name
}

output "tail_logs_command" {
  description = "Comando para seguir los logs en tiempo real"
  value       = "aws logs tail ${var.log_group_name} --follow"
}
