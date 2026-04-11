# ---------------------------------------------------------------------------
# Log Group
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "app" {
  name              = var.log_group_name
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ---------------------------------------------------------------------------
# Metric Filter — cuenta cada línea con status=500
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "app_errors" {
  name           = "${var.prefix}-app-errors"
  log_group_name = aws_cloudwatch_log_group.app.name
  pattern        = "{ $.status = 500 }"

  metric_transformation {
    name      = "AppErrors"
    namespace = "EPAM/Lab"
    value     = "1"
    unit      = "Count"
  }
}

resource "aws_cloudwatch_log_metric_filter" "high_latency" {
  name           = "${var.prefix}-high-latency"
  log_group_name = aws_cloudwatch_log_group.app.name
  # Latencia > 1500ms
  pattern        = "{ $.latency_ms > 1500 }"

  metric_transformation {
    name      = "HighLatencyRequests"
    namespace = "EPAM/Lab"
    value     = "1"
    unit      = "Count"
  }
}

# ---------------------------------------------------------------------------
# SNS Topic para notificaciones
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${var.prefix}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# CloudWatch Alarms
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "app_errors" {
  alarm_name          = "${var.prefix}-app-errors"
  alarm_description   = "Demasiados errores 5xx en /epam/lab/app"
  namespace           = "EPAM/Lab"
  metric_name         = "AppErrors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "high_latency" {
  alarm_name          = "${var.prefix}-high-latency"
  alarm_description   = "Requests con latencia > 1500ms superaron el umbral"
  namespace           = "EPAM/Lab"
  metric_name         = "HighLatencyRequests"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}
