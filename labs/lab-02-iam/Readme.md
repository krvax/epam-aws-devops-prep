# Lab 1.2 — IAM Roles y Assume Role

## Concepto visual

```text
👤 Tu usuario (Cuenta A)
    │
    │  aws sts assume-role
    │
    ▼
🎭 Rol: lab-cross-role
    │
    │  Trust Policy:       "¿Quién puede asumir este rol?"
    │  Permissions Policy: "¿Qué puede hacer este rol?"
    │
    ▼
📦 Credenciales temporales
    ├── AccessKeyId
    ├── SecretAccessKey
    ├── SessionToken
    └── Expiration (1 hora por defecto)
```

---

## Paso 1: Crear el rol con trust policy

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

aws iam create-role \
  --role-name lab-cross-role \
  --assume-role-policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Effect\": \"Allow\",
        \"Principal\": {
          \"AWS\": \"arn:aws:iam::${ACCOUNT_ID}:root\"
        },
        \"Action\": \"sts:AssumeRole\",
        \"Condition\": {
          \"StringEquals\": {
            \"sts:ExternalId\": \"lab-external-id-12345\"
          }
        }
      }
    ]
  }"
```

> 💡 **Trust Policy** = "¿QUIÉN puede asumir este rol?"
> El `ExternalId` es una capa de seguridad extra (previene confused deputy attack).

---

## Paso 2: Adjuntar permisos mínimos (Least Privilege)

```bash
aws iam put-role-policy \
  --role-name lab-cross-role \
  --policy-name lab-s3-readonly \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": ["s3:ListAllMyBuckets", "s3:GetBucketLocation"],
        "Resource": "arn:aws:s3:::*"
      },
      {
        "Effect": "Allow",
        "Action": ["s3:GetObject", "s3:ListBucket"],
        "Resource": [
          "arn:aws:s3:::lab-test-bucket-*",
          "arn:aws:s3:::lab-test-bucket-*/*"
        ]
      }
    ]
  }'
```

> 💡 **Least Privilege** = Solo los permisos que necesita, nada más. Nota cómo limitamos a buckets que empiecen con `lab-test-bucket-`.

---

## Paso 3: Asumir el rol

```bash
CREDENTIALS=$(aws sts assume-role \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/lab-cross-role \
  --role-session-name lab-test-session \
  --external-id lab-external-id-12345 \
  --duration-seconds 900 \
  --query 'Credentials' \
  --output json)

echo $CREDENTIALS | jq .

# Exportar credenciales temporales
export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')

# Verificar identidad actual
aws sts get-caller-identity
# Arn: arn:aws:sts::123456789012:assumed-role/lab-cross-role/lab-test-session
```

---

## Paso 4: Verificar permisos y expiración

```bash
# ✅ Esto DEBERÍA funcionar (S3 read)
aws s3 ls

# ❌ Esto DEBERÍA fallar (sin permisos EC2)
aws ec2 describe-instances
# Error: UnauthorizedOperation

# Ver expiración
echo $CREDENTIALS | jq '.Expiration'

# Volver a tu identidad original
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

---

## 📚 Pregunta de entrevista: EC2 a S3 sin access keys

```text
┌──────────┐      ┌──────────────────┐      ┌──────────┐
│   EC2    │ ──── │ Instance Profile  │ ──── │ IAM Role │
│          │      │ (IAM Role)        │      │          │
│ aws s3 ls│      │ Credenciales      │      │ S3 perms │
│          │      │ temporales auto   │      │          │
└──────────┘      └──────────────────┘      └──────────┘
```

> "Se usa un **IAM Instance Profile** que contiene un IAM Role. El metadata service (`169.254.169.254`) provee credenciales temporales automáticas que se rotan antes de expirar. Los SDKs de AWS las usan automáticamente. **Nunca deberías poner access keys en una EC2.**"

```bash
# Crear rol para EC2
aws iam create-role --role-name ec2-s3-role \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

aws iam attach-role-policy --role-name ec2-s3-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess

aws iam create-instance-profile --instance-profile-name ec2-s3-profile
aws iam add-role-to-instance-profile \
  --instance-profile-name ec2-s3-profile \
  --role-name ec2-s3-role

aws ec2 associate-iam-instance-profile \
  --instance-id i-xxxxx \
  --iam-instance-profile Name=ec2-s3-profile
```

---

## 🧹 Limpieza

```bash
aws iam delete-role-policy --role-name lab-cross-role --policy-name lab-s3-readonly
aws iam delete-role --role-name lab-cross-role
echo "Lab 1.2 limpio ✅"
```

---

> 🏷️ Tags: `aws` `iam` `assume-role` `least-privilege` `credentials` `instance-profile`