# ─────────────────────────────────────────
# Role para practicar AssumeRole desde CLI
# Este rol puede ser asumido por usuarios de tu propia cuenta
# ─────────────────────────────────────────
resource "aws_iam_role" "assumable" {
  name        = "${var.project}-assumable-role"
  description = "Role for practicing sts:AssumeRole from CLI"
  max_session_duration = 3600  # 1 hora

  # Trust Policy: cualquier IAM user/role en tu cuenta puede asumir este rol
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowSameAccountAssume"
      Effect = "Allow"
      Principal = {
        AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      }
      Action    = "sts:AssumeRole"
      Condition = {
        # Opcional: solo desde MFA
        # BoolIfExists = { "aws:MultiFactorAuthPresent" = "true" }
      }
    }]
  })

  tags = var.common_tags
}

# Permission Policy: S3 read-only (para demostrar least privilege)
resource "aws_iam_role_policy_attachment" "assumable_s3" {
  role       = aws_iam_role.assumable.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}
