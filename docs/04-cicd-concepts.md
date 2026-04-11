# 04 — CI/CD: Pipelines, GitOps & Deployment Strategies

> Cubre GitHub Actions, GitOps, ArgoCD, estrategias de deployment y seguridad en pipelines.
> Enfocado en los escenarios reales que EPAM pregunta en entrevista.

---

## Índice

1. [La Gran Foto: CI vs CD vs GitOps](#1-la-gran-foto)
2. [GitHub Actions: anatomía de un workflow](#2-github-actions)
3. [Buildspec: AWS CodeBuild](#3-buildspec-aws-codebuild)
4. [Docker en pipelines: build, tag, push](#4-docker-en-pipelines)
5. [Estrategias de deployment](#5-estrategias-de-deployment)
6. [GitOps con ArgoCD](#6-gitops-con-argocd)
7. [Seguridad en pipelines](#7-seguridad-en-pipelines)
8. [Rollback: manual y automático](#8-rollback-manual-y-automático)
9. [Preguntas de entrevista con esquema de respuesta](#9-preguntas-de-entrevista)

---

## 1. La Gran Foto

```
Desarrollador hace push
        │
        ▼
┌───────────────┐
│      CI       │  Continuous Integration
│               │  - Checkout del código
│               │  - Build de la imagen Docker
│               │  - Tests unitarios / integración
│               │  - Escaneo de seguridad (Trivy, SAST)
│               │  - Push a ECR / registry
└───────┬───────┘
        │ imagen tagged con SHA del commit
        ▼
┌───────────────┐
│      CD       │  Continuous Delivery / Deployment
│               │  - Actualizar el manifiesto de K8s
│               │  - Aplicar en cluster (kubectl / ArgoCD)
│               │  - Verificar health del deployment
│               │  - Rollback automático si falla
└───────────────┘
```

### CI vs CD vs GitOps

| | CI | CD tradicional | GitOps |
|--|---|---|---|
| Qué hace | Build + test + push imagen | Pipeline que hace `kubectl apply` | Git es la fuente de verdad; un agente sincroniza |
| Quién aplica cambios | Pipeline | Pipeline (push) | Agente en el cluster (pull) |
| Auditoría | Logs del pipeline | Logs del pipeline | Git history = historial completo |
| Rollback | Manual o script | Manual o script | `git revert` → automático |
| Ejemplo | GitHub Actions | CodePipeline + CodeDeploy | ArgoCD, Flux |

---

## 2. GitHub Actions

### Anatomía de un workflow

```yaml
# .github/workflows/ci-cd.yml

name: CI/CD Pipeline          # nombre visible en GitHub UI

on:                            # cuándo se dispara
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:           # disparo manual desde la UI

env:                           # variables globales del workflow
  AWS_REGION: us-east-1
  ECR_REPO: mi-empresa/mi-app

jobs:
  test:                        # job 1: tests
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run tests
        run: |
          npm install
          npm test

  build-and-push:              # job 2: build imagen
    needs: test                # espera a que "test" termine con éxito
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.meta.outputs.tags }}

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}   # OIDC, sin access keys
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build, tag & push
        id: meta
        env:
          REGISTRY: ${{ steps.login-ecr.outputs.registry }}
          IMAGE_TAG: ${{ github.sha }}
        run: |
          docker build -t $REGISTRY/$ECR_REPO:$IMAGE_TAG .
          docker push $REGISTRY/$ECR_REPO:$IMAGE_TAG
          echo "tags=$REGISTRY/$ECR_REPO:$IMAGE_TAG" >> $GITHUB_OUTPUT

  deploy:                      # job 3: deploy a EKS
    needs: build-and-push
    runs-on: ubuntu-latest
    environment: production    # requiere aprobación manual si está configurado

    steps:
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Update kubeconfig
        run: aws eks update-kubeconfig --name mi-cluster --region $AWS_REGION

      - name: Deploy to EKS
        env:
          IMAGE_TAG: ${{ needs.build-and-push.outputs.image-tag }}
        run: |
          kubectl set image deployment/mi-app app=$IMAGE_TAG
          kubectl rollout status deployment/mi-app --timeout=300s
```

### Conceptos clave de GitHub Actions

**Triggers (`on`)**:
```yaml
on:
  push:
    branches: [main, release/*]
    paths: ['src/**', 'Dockerfile']   # solo si cambian estos archivos
  schedule:
    - cron: '0 2 * * *'              # nightly build a las 2am
  workflow_dispatch:                  # manual
```

**Secrets y variables**:
```yaml
# Secrets: encriptados, nunca visibles en logs
${{ secrets.AWS_ROLE_ARN }}
${{ secrets.DB_PASSWORD }}

# Variables: visibles, para config no sensible
${{ vars.AWS_REGION }}
${{ vars.ECR_REPO }}

# Variables de contexto de GitHub (automáticas)
${{ github.sha }}          # SHA del commit
${{ github.ref_name }}     # nombre del branch
${{ github.actor }}        # usuario que hizo push
${{ github.repository }}   # org/repo
```

**Environments**: protegen deployments a producción.
```yaml
jobs:
  deploy-prod:
    environment: production   # bloquea hasta que un reviewer apruebe en GitHub UI
```

**Reusable workflows**: evitan duplicar pipelines entre repos.
```yaml
# Llamar a un workflow definido en otro repo o archivo
jobs:
  call-shared-pipeline:
    uses: mi-empresa/shared-workflows/.github/workflows/deploy.yml@main
    with:
      environment: production
      cluster-name: mi-cluster
    secrets: inherit
```

**Matrix strategy**: correr el mismo job con múltiples configuraciones.
```yaml
jobs:
  test:
    strategy:
      matrix:
        node-version: [18, 20, 22]
        os: [ubuntu-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/setup-node@v4
        with:
          node-version: ${{ matrix.node-version }}
      - run: npm test
```

---

## 3. Buildspec: AWS CodeBuild

Cuando usas AWS CodePipeline en vez de GitHub Actions, el build se define en `buildspec.yml`.

```yaml
# buildspec.yml (en la raíz del repo)
version: 0.2

env:
  variables:
    AWS_REGION: us-east-1
  parameter-store:               # leer secrets de Parameter Store
    DB_PASSWORD: /prod/db/password

phases:
  install:                       # instalar dependencias del build
    runtime-versions:
      nodejs: 20
    commands:
      - npm install -g yarn

  pre_build:                     # antes del build: login, setup
    commands:
      - echo Logging into ECR...
      - aws ecr get-login-password --region $AWS_REGION |
          docker login --username AWS --password-stdin $ECR_REGISTRY
      - IMAGE_TAG=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c1-7)

  build:                         # el build real
    commands:
      - echo Build started at $(date)
      - docker build -t $ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG .
      - docker push $ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG

  post_build:                    # después del build: notificaciones, artifacts
    commands:
      - echo Build completed
      - printf '[{"name":"mi-app","imageUri":"%s"}]'
          $ECR_REGISTRY/$ECR_REPO:$IMAGE_TAG > imagedefinitions.json

artifacts:                       # archivos que pasan al siguiente stage del pipeline
  files:
    - imagedefinitions.json
    - appspec.yml

cache:                           # cachear node_modules entre builds (más rápido)
  paths:
    - node_modules/**/*
```

---

## 4. Docker en pipelines

### Tag strategy: cómo nombrar imágenes

```bash
# Nunca usar solo :latest en producción — no sabes qué versión es

# ✅ Usar el SHA del commit (inmutable, trazable)
IMAGE_TAG=mi-app:abc1234

# ✅ O combinar con fecha para legibilidad
IMAGE_TAG=mi-app:2024-01-15-abc1234

# ✅ Para releases: usar el tag de Git
IMAGE_TAG=mi-app:v1.2.3

# El SHA garantiza:
# - Reproducibilidad: siempre sabes exactamente qué código está corriendo
# - Trazabilidad: del pod al commit en 2 pasos
# - Rollback exacto: kubectl set image ... mi-app:abc1232 (el commit anterior)
```

### Multi-stage build: imágenes más pequeñas y seguras

```dockerfile
# Stage 1: build (imagen grande, tiene compiladores, dev tools)
FROM node:20 AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build

# Stage 2: runtime (imagen mínima, solo lo necesario)
FROM node:20-alpine AS runtime
WORKDIR /app

# Solo copiar el resultado del build, no el código fuente
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules

# No correr como root
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

EXPOSE 3000
CMD ["node", "dist/server.js"]
```

> 💡 **Por qué importa en entrevista**: imagen más pequeña = menos superficie de ataque,
> menos tiempo de pull, menos costo de storage en ECR. El no correr como root es un
> requisito de Pod Security Standards en K8s.

---

## 5. Estrategias de deployment

### Rolling Update (default en K8s)

Reemplaza pods uno a uno. Sin downtime si tienes `minReadySeconds` y readiness probes.

```yaml
spec:
  replicas: 4
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1         # puede haber 1 pod extra durante el update
      maxUnavailable: 0   # nunca matar un pod antes de que el nuevo esté Ready
```

```
Antes:  [v1] [v1] [v1] [v1]
Step 1: [v1] [v1] [v1] [v2]   ← v2 levanta, pasa readiness probe
Step 2: [v1] [v1] [v2] [v2]   ← v1 se baja
Step 3: [v1] [v2] [v2] [v2]
Step 4: [v2] [v2] [v2] [v2]
```

**Cuándo usarlo**: la mayoría de casos. Versiones compatibles entre sí.
**Riesgo**: si v2 tiene un bug, hay un período donde corren v1 y v2 simultáneamente.

---

### Blue/Green

Dos entornos completos. Switch instantáneo de tráfico.

```
Blue (v1) ←── Service (selector: version=blue)    ACTIVO
Green (v2) ←── sin tráfico                        EN STANDBY

# Paso 1: desplegar green (sin tráfico)
kubectl apply -f deployment-green.yaml

# Paso 2: verificar que green está sano
kubectl rollout status deployment/app-green

# Paso 3: switch instantáneo
kubectl patch service mi-app -p '{"spec":{"selector":{"version":"green"}}}'

# Paso 4: si falla, revertir en segundos
kubectl patch service mi-app -p '{"spec":{"selector":{"version":"blue"}}}'
```

**Cuándo usarlo**: cambios de base de datos, cambios breaking de API, cuando necesitas
rollback instantáneo.  
**Costo**: necesitas el doble de recursos durante el switch.

---

### Canary

Envías un porcentaje pequeño del tráfico a la nueva versión. Monitoreas. Gradualmente aumentas.

```yaml
# Con Argo Rollouts (la forma más limpia en K8s)
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: mi-app
spec:
  replicas: 10
  strategy:
    canary:
      steps:
        - setWeight: 10        # 10% del tráfico a la nueva versión
        - pause: {duration: 5m}
        - setWeight: 30
        - pause: {duration: 5m}
        - analysis:             # análisis automático de métricas
            templates:
              - templateName: success-rate
        - setWeight: 100        # si el análisis pasó, 100%
```

```
Tráfico: 90% → [v1][v1][v1][v1][v1][v1][v1][v1][v1]
          10% → [v2]

Si métricas OK → 70/30 → 0/100
Si métricas malas → rollback automático a 100% v1
```

**Cuándo usarlo**: cuando quieres validar v2 con tráfico real antes de hacer el switch
completo. Ideal para features con impacto en conversión o performance.

---

### Comparativa para entrevista

| | Rolling | Blue/Green | Canary |
|--|---|---|---|
| Downtime | Ninguno | Ninguno | Ninguno |
| Rollback | Lento (re-roll) | Instantáneo | Automático si hay análisis |
| Recursos extra | Mínimos | 2x durante switch | Mínimos (solo % canary) |
| Complejidad | Baja | Media | Alta |
| Riesgo de versiones mixtas | Sí (transitorio) | No | Sí (intencional) |
| Ideal para | Mayoría de casos | Cambios críticos / DB | Validar con tráfico real |

---

## 6. GitOps con ArgoCD

### El problema que resuelve

En CD tradicional, el pipeline tiene acceso directo al cluster (`kubectl apply`).
Problemas:
- El pipeline necesita credenciales del cluster
- Si alguien hace `kubectl apply` manualmente, el estado del cluster diverge del repo
- No hay forma fácil de saber *qué* está corriendo vs *qué debería* estar corriendo

**GitOps**: Git es la única fuente de verdad. Un agente *dentro* del cluster sincroniza.

```
Developer → Git PR → merge → ArgoCD detecta cambio → aplica al cluster
                                      ↑
                              (pull, no push)
                              ArgoCD ya está dentro
                              No necesita credenciales externas
```

### Conceptos clave de ArgoCD

**Application**: el objeto principal de ArgoCD. Define qué sincronizar y dónde.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mi-app
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/mi-empresa/k8s-manifests
    targetRevision: main
    path: apps/mi-app/overlays/prod    # carpeta con los manifiestos

  destination:
    server: https://kubernetes.default.svc   # cluster local
    namespace: production

  syncPolicy:
    automated:
      prune: true      # elimina recursos que ya no están en Git
      selfHeal: true   # si alguien modifica manualmente, ArgoCD revierte
    syncOptions:
      - CreateNamespace=true
```

**Sync status**:
- `Synced`: cluster == Git ✅
- `OutOfSync`: alguien modificó algo manualmente o hay un cambio nuevo en Git
- `Degraded`: hay recursos con errores (pods crasheando, etc.)

**App of Apps pattern**: una Application que gestiona otras Applications.
```
argocd/
  app-of-apps.yaml          ← Application que apunta a apps/
  apps/
    frontend.yaml            ← Application para el frontend
    backend.yaml             ← Application para el backend
    monitoring.yaml          ← Application para el stack de monitoreo
```

### Flujo GitOps completo

```
1. Developer hace PR con cambio de imagen en deployment.yaml
   (image: mi-app:abc1234  →  mi-app:def5678)

2. PR review + merge a main

3. ArgoCD detecta el cambio en el repo (polling cada 3 min o webhook)

4. ArgoCD calcula el diff entre Git y el cluster

5. ArgoCD aplica el cambio (kubectl apply interno)

6. ArgoCD monitorea que el rollout sea exitoso

7. Si falla: ArgoCD puede hacer rollback automático al commit anterior

8. Git history = auditoría completa de quién cambió qué y cuándo
```

### Imagen promotion entre entornos

```
apps/
  mi-app/
    base/
      deployment.yaml    ← image: mi-app:PLACEHOLDER
    overlays/
      dev/
        kustomization.yaml  ← image: mi-app:abc1234  (actualizado por CI)
      staging/
        kustomization.yaml  ← image: mi-app:abc1234  (manual o auto)
      prod/
        kustomization.yaml  ← image: mi-app:v1.2.3   (solo releases aprobados)
```

El pipeline de CI actualiza automáticamente el overlay de `dev`.
La promoción a `staging` y `prod` es un PR — con review y aprobación.

---

## 7. Seguridad en pipelines

### No usar access keys — usar OIDC

```yaml
# MAL: access keys hardcodeadas en secrets de GitHub
AWS_ACCESS_KEY_ID: AKIA...
AWS_SECRET_ACCESS_KEY: ...
# Se rotan manualmente, si se filtran son válidas indefinidamente

# BIEN: OIDC — GitHub Actions asume un IAM Role directamente
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789:role/github-actions-role
    aws-region: us-east-1
# Credenciales temporales, rotación automática, sin secrets que gestionar
```

**Configurar OIDC en AWS**:
```hcl
# Terraform para crear el OIDC provider de GitHub en AWS
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions" {
  name = "github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" =
            "repo:mi-empresa/mi-repo:ref:refs/heads/main"
        }
      }
    }]
  })
}
```

### Escaneo de imágenes con Trivy

```yaml
- name: Scan image for vulnerabilities
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.ECR_REGISTRY }}/${{ env.ECR_REPO }}:${{ github.sha }}
    format: 'sarif'
    output: 'trivy-results.sarif'
    severity: 'CRITICAL,HIGH'
    exit-code: '1'     # falla el pipeline si encuentra CRITICAL o HIGH

- name: Upload scan results
  uses: github/codeql-action/upload-sarif@v3
  with:
    sarif_file: 'trivy-results.sarif'
```

### Secrets management en pipelines

```
Nunca en código:          DB_PASS="super-secret"  ❌
Nunca en .env en Git:     .env con passwords       ❌

Opciones correctas:
1. GitHub Actions Secrets  → para variables de CI (role ARNs, etc.)
2. AWS Secrets Manager     → para secrets de la aplicación en runtime
3. AWS Parameter Store     → para config y secrets menos críticos
4. External Secrets Op.    → sincroniza Secrets Manager → K8s Secrets automáticamente
```

---

## 8. Rollback: manual y automático

### Rollback manual en K8s

```bash
# Ver historial de versiones del deployment
kubectl rollout history deployment/mi-app

# Rollback a la versión anterior
kubectl rollout undo deployment/mi-app

# Rollback a una versión específica
kubectl rollout undo deployment/mi-app --to-revision=3

# Verificar que el rollback progresó
kubectl rollout status deployment/mi-app

# Ver qué imagen está corriendo ahora
kubectl get deployment mi-app -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Rollback automático en GitHub Actions

```yaml
- name: Deploy and verify
  run: |
    kubectl set image deployment/mi-app app=$IMAGE_TAG
    
    # Esperar hasta 5 minutos a que el rollout sea exitoso
    if ! kubectl rollout status deployment/mi-app --timeout=300s; then
      echo "Deployment failed — rolling back"
      kubectl rollout undo deployment/mi-app
      kubectl rollout status deployment/mi-app
      exit 1   # marcar el pipeline como fallido
    fi
```

### Rollback con ArgoCD (GitOps)

```bash
# Ver historial de syncs de ArgoCD
argocd app history mi-app

# Rollback al sync anterior (que apunta a un commit de Git)
argocd app rollback mi-app --revision 3

# O simplemente: hacer git revert + push → ArgoCD sincroniza automáticamente
git revert HEAD
git push origin main
# ArgoCD detecta el nuevo commit y aplica el revert
```

> 💡 **La respuesta correcta en entrevista**: en GitOps el rollback es un `git revert`.
> No es un comando de kubectl ni de ArgoCD — es una operación de Git que queda auditada.

---

## 9. Preguntas de entrevista

**"¿Cuál es la diferencia entre CI y CD?"**

```
CI (Continuous Integration):
- Se dispara en cada push o PR
- Valida que el código integra correctamente con el resto
- Build + test + análisis estático + escaneo de seguridad
- Produce un artefacto (imagen Docker) listo para deployar

CD (Continuous Delivery):
- Toma el artefacto de CI y lo despliega a un entorno
- Puede ser automático (Continuous Deployment) o requerir aprobación manual
- Verifica que el deployment fue exitoso
- Tiene rollback si algo falla

La diferencia clave: CI valida el código. CD lo despliega.
Puedes tener CI sin CD (construyes pero deployeas manualmente).
```

---

**"¿Cómo haces rollback automático si el deployment falla?"**

```
Hay tres capas de protección:

1. Readiness probe en K8s:
   - Si el pod nuevo no pasa la readiness probe, K8s no le manda tráfico
   - El rolling update se detiene automáticamente
   - Los pods viejos siguen activos

2. kubectl rollout status en el pipeline:
   if ! kubectl rollout status deployment/mi-app --timeout=300s; then
     kubectl rollout undo deployment/mi-app
     exit 1
   fi

3. Con ArgoCD + Argo Rollouts:
   - Análisis automático de métricas (error rate, latencia) durante el canary
   - Si las métricas superan el threshold → rollback automático sin intervención humana

El rollout status es el mínimo viable. En producción real, el análisis de métricas
es lo que da confianza real de que la nueva versión está sana.
```

---

**"¿Qué es GitOps y en qué se diferencia de un pipeline de CD tradicional?"**

```
CD tradicional (push):
- El pipeline tiene credenciales del cluster
- Hace kubectl apply directamente
- Si alguien modifica el cluster manualmente, el pipeline no lo sabe
- Auditoría: logs del pipeline (difícil de seguir)

GitOps (pull):
- Git es la fuente de verdad absoluta
- Un agente (ArgoCD) DENTRO del cluster hace pull de Git y aplica
- Si alguien modifica el cluster manualmente, ArgoCD lo detecta y revierte (selfHeal)
- Auditoría: Git history = quién cambió qué, cuándo, por qué (commit message + PR)
- Rollback = git revert (operación estándar, auditada)
- El cluster nunca está más adelante que Git

Ventajas clave de GitOps:
1. Security: no hay credenciales del cluster fuera del cluster
2. Consistency: el cluster siempre converge al estado de Git
3. Auditability: toda la historia está en Git
4. Disaster recovery: si pierdes el cluster, ArgoCD lo reconstruye desde Git
```

---

**"¿Cuándo usarías Canary vs Blue/Green?"**

```
Blue/Green cuando:
- El cambio es una migración de base de datos (necesitas switch limpio)
- Hay cambios breaking de API y necesitas rollback instantáneo
- Quieres validar en un entorno idéntico a producción antes del switch
- El tiempo de validación es corto (segundos o minutos)
Costo: doble de recursos durante el período de switch

Canary cuando:
- Quieres validar el impacto real con un subconjunto de usuarios
- El cambio afecta performance o comportamiento que solo ves con tráfico real
- Tienes métricas claras de éxito (error rate, latencia, conversion rate)
- Puedes tolerar que un % de usuarios experimente la nueva versión
Ventaja: detectas problemas antes de afectar a todos los usuarios
```

---

**"¿Cómo aseguras que los secrets no se filtren en el pipeline?"**

```
Cuatro niveles de protección:

1. Nunca en código ni en .env en Git (obvio pero el más común de los errores)

2. En GitHub Actions: usar OIDC en vez de access keys
   → No hay secrets de AWS que gestionar, las credenciales son temporales

3. En runtime (la app): usar AWS Secrets Manager + External Secrets Operator
   → Los secrets nunca pasan por el pipeline, van directo de AWS al pod

4. Escaneo de secrets en CI:
   - GitLeaks: detecta si alguien accidentalmente commitió un secret
   - git-secrets: hook pre-commit que bloquea el push si detecta patterns de AWS keys

5. Si un secret se filtra: rotarlo inmediatamente, auditar CloudTrail
   para ver si fue usado, revocar el token de GitHub si es necesario
```

---

**"Un deploy salió mal y hay usuarios afectados. ¿Qué haces?"**

```
Prioridad 1: mitigar (no investigar todavía)

1. ¿Cuándo fue el último deploy? 
   → Si fue reciente: kubectl rollout undo deployment/mi-app
   → Verificar: kubectl rollout status deployment/mi-app

2. ¿El rollback resolvió el problema?
   → Revisar dashboards: error rate, latencia
   → Confirmar con el equipo de soporte que usuarios pueden operar

3. Comunicar (mientras el técnico hace el rollback, otra persona comunica):
   → Status page: "Estamos investigando un problema, ETA 15 min"
   → Slack/Teams interno: situación actual, quién está trabajando en ello

Prioridad 2: investigar (DESPUÉS de mitigar)
   → kubectl logs deployment/mi-app --previous
   → Revisar métricas del período del incidente
   → Comparar qué cambió entre el commit anterior y el que falló (git diff)

Prioridad 3: post-mortem (dentro de 48h)
   → Blameless, 5 Whys, action items con owner y fecha
```

---

*Anterior: [03-terraform-concepts.md](03-terraform-concepts.md)*  
*Volver al inicio: [00-concepts-overview.md](00-concepts-overview.md)*