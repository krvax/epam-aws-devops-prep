# ---------------------------------------------------------------------------
# IAM Role para la EC2 — permisos mínimos para CloudWatch Agent
# ---------------------------------------------------------------------------

resource "aws_iam_role" "cw_agent" {
  name = "${var.prefix}-cw-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.cw_agent.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "cw_agent" {
  name = "${var.prefix}-cw-agent-profile"
  role = aws_iam_role.cw_agent.name
}

# ---------------------------------------------------------------------------
# EC2
# ---------------------------------------------------------------------------

resource "aws_instance" "loggen" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.public.ids[0]
  vpc_security_group_ids = [aws_security_group.loggen.id]
  iam_instance_profile   = aws_iam_instance_profile.cw_agent.name

  user_data = base64encode(templatefile("${path.module}/scripts/user_data.sh", {
    log_group = var.log_group_name
    region    = var.aws_region
  }))

  tags = merge(var.tags, { Name = "${var.prefix}-loggen" })
}
