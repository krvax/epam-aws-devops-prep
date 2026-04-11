# ─────────────────────────────────────────
# Security Group — EC2 privada
# Solo permite tráfico de salida; SSM no necesita ingress
# ─────────────────────────────────────────
resource "aws_security_group" "private_ec2" {
  name        = "${var.project}-private-ec2-sg"
  description = "SG for private EC2 - SSM access only"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.project}-private-ec2-sg" })
}

# ─────────────────────────────────────────
# IAM Role para SSM (sin SSH)
# ─────────────────────────────────────────
resource "aws_iam_role" "ec2_ssm" {
  name = "${var.project}-ec2-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "${var.project}-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name
}

# ─────────────────────────────────────────
# EC2 en subnet privada
# ─────────────────────────────────────────
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_instance" "private" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private["a"].id
  vpc_security_group_ids = [aws_security_group.private_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_ssm.name

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y curl
  EOF

  tags = merge(var.common_tags, { Name = "${var.project}-private-ec2" })
}
