resource "aws_security_group" "loggen" {
  name        = "${var.prefix}-loggen-sg"
  description = "SG para EC2 loggen — solo egress necesario para CW Agent"
  vpc_id      = data.aws_vpc.selected.id

  # SSH opcional — solo para debug, deshabilitar en prod
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  egress {
    description = "Allow all outbound (CW Agent + SSM)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.prefix}-loggen-sg" })
}
