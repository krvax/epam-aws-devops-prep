# Lab 06 — GitLab CI/CD Pipeline: ECR + EKS

**Bloque:** 4 — CI/CD

**Objetivo:** Construir un pipeline GitLab CI/CD completo que compila una imagen Docker, la publica en ECR y despliega en EKS usando OIDC (sin access keys estáticas).

---

## Prerequisitos

- Lab 04 completado (cluster EKS corriendo)
- ECR repository creado
- GitLab Runner disponible (shared o self-hosted)
- IAM Role con OIDC trust para GitLab configurado

---

## Arquitectura del pipeline

```
git push (main)
    │
    └─→ GitLab CI/CD
          ├─→ validate    ← lint Dockerfile, terraform validate
          ├─→ build       ← docker build + push a ECR (via OIDC)
          ├─→ deploy      ← kubectl set image en EKS
          └─→ verify      ← health check post-deploy + rollback si falla
```

---

## Estructura del lab

```
lab-06-gitlab-cicd/
├── Readme.md
├── .gitlab-ci.yml          ← pipeline principal
├── terraform/
│   ├── main.tf             ← ECR repository + IAM Role para OIDC
│   ├── variables.tf
└──   └── outputs.tf
```

---

## Variables de GitLab requeridas

Configurar en **GitLab → Settings → CI/CD → Variables**:

| Variable | Tipo | Descripción |
|----------|------|-------------|
| `AWS_ROLE_ARN` | Variable | ARN del IAM Role con OIDC trust |
| `AWS_REGION` | Variable | `us-east-1` |
| `ECR_REGISTRY` | Variable | `<account>.dkr.ecr.us-east-1.amazonaws.com` |
| `ECR_REPO` | Variable | Nombre del repositorio ECR |
| `EKS_CLUSTER_NAME` | Variable | Nombre del cluster EKS |
| `K8S_NAMESPACE` | Variable | Namespace donde corre la app |

> **Nunca** guardar `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` como variables.
> El pipeline usa OIDC para obtener credenciales temporales.

---

## Paso a paso

### 1. Crear el IAM Role con OIDC trust para GitLab

```bash
# Obtener el OIDC thumbprint de GitLab
curl -s https://gitlab.com/.well-known/openid-configuration | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['jwks_uri'])"

# El trust policy del IAM Role debe permitir:
# - Principal: oidc-provider/gitlab.com
# - Condition: sub == project_path:<group>/<repo>:ref_type:branch:ref:main
```

```hcl
# En terraform/main.tf
data "aws_iam_openid_connect_provider" "gitlab" {
  url = "https://gitlab.com"
}

resource "aws_iam_role" "gitlab_ci" {
  name = "gitlab-ci-epam-prep"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.gitlab.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "gitlab.com:sub" = "project_path:<GROUP>/<REPO>:ref_type:branch:ref:main"
        }
      }
    }]
  })
}
```

### 2. Correr el pipeline

```bash
git add .gitlab-ci.yml
git commit -m "ci: add GitLab CI/CD pipeline"
git push origin main
# → El pipeline se dispara automáticamente
```

### 3. Verificar el deploy

```bash
# Ver el rollout
kubectl rollout status deployment/app -n <namespace>

# Ver la imagen deployada
kubectl get deployment app -n <namespace> \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

## Preguntas de entrevista

**"¿Por qué OIDC en vez de access keys en el pipeline?"**

Respuesta: Las access keys son credenciales de larga duración que si se filtran en logs o en el repo, exponen la cuenta permanentemente. Con OIDC, GitLab obtiene un JWT firmado por su identity provider, lo intercambia por credenciales temporales de AWS STS (15 min a 1 hora), y esas credenciales expiran solas. Si se filtran en un log, son inútiles pasado el TTL.

**"¿Cómo haces rollback automático si el deploy falla?"**

Respuesta: El stage `verify` del pipeline hace un health check con `kubectl rollout status --timeout`. Si el timeout se cumple sin que el rollout complete, ejecuta `kubectl rollout undo` y falla el pipeline, dejando el estado anterior corriendo.

**"¿Qué diferencia hay entre un GitLab Runner shared y self-hosted?"**

Respuesta: El runner shared lo provee GitLab.com y comparte capacidad con todos los proyectos de la instancia. El self-hosted lo controlas tú, corre dentro de tu VPC, tiene acceso directo a recursos privados (ECR, EKS, RDS) sin exponer endpoints al internet, y puedes darle el IAM Role necesario directamente via Instance Profile o IRSA si corre en K8s.

---

## Documentación relacionada

- [Lab 04 — EKS Cluster](../lab-04-eks-cluster/Readme.md)
- [Lab 05 — Remote State](../lab-05-remote-state/Readme.md)
- [GitLab CI/CD con OIDC en AWS](https://docs.gitlab.com/ee/ci/cloud_services/aws/)
