# ============================================
# LAUNCH TEMPLATE
# ============================================
resource "aws_launch_template" "main" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.amazon_linux_2.id
  instance_type = var.instance_type

  vpc_security_group_ids = [aws_security_group.instances.id]

  user_data = base64encode(file("${path.module}/templates/user-data.sh"))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project_name}-asg-instance" }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================
# AUTO SCALING GROUP
# ============================================
resource "aws_autoscaling_group" "main" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = aws_subnet.public[*].id
  target_group_arns   = [aws_lb_target_group.main.arn]

  min_size         = var.asg_min
  max_size         = var.asg_max
  desired_capacity = var.asg_desired

  health_check_type         = "ELB"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }

  wait_for_capacity_timeout = "5m"
}

# ============================================
# SCALING POLICY: Target Tracking (CPU 60%)
# ============================================
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                   = "${var.project_name}-cpu-tracking"
  autoscaling_group_name = aws_autoscaling_group.main.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value       = var.cpu_target
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}
