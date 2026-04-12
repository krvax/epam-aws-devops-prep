# 🚀 EPAM DevOps Cloud Engineer — AWS Interview Prep

> Plan de estudio con labs prácticos basado en los temas reales de entrevistas EPAM.
> Marca cada sección con `[x]` conforme avances.

---

## 📋 Índice

1. [Proceso de entrevista EPAM](#1-proceso-de-entrevista-epam)
2. [Bloque 1 — AWS Core](#2-bloque-1--aws-core)
3. [Bloque 2 — Kubernetes / EKS](#3-bloque-2--kubernetes--eks)
4. [Bloque 3 — Infraestructura como Código (Terraform)](#4-bloque-3--infraestructura-como-código-terraform)
5. [Bloque 4 — CI/CD](#5-bloque-4--cicd)
6. [Bloque 5 — Observabilidad & Monitoreo](#6-bloque-5--observabilidad--monitoreo)
7. [Bloque 6 — SRE: SLIs, SLOs & Incident Management](#7-bloque-6--sre-slis-slos--incident-management)
8. [Bloque 7 — Linux & Networking](#8-bloque-7--linux--networking)
9. [Bloque 8 — Seguridad en AWS](#9-bloque-8--seguridad-en-aws)
10. [Preguntas frecuentes de entrevista EPAM](#10-preguntas-frecuentes-de-entrevista-epam)
11. [Recursos & Certificaciones](#11-recursos--certificaciones)
12. [Labs prácticos](#12-labs-prácticos)
13. [Troubleshooting & Incident Reviews](#13-troubleshooting--incident-reviews)

---

## 1. Proceso de entrevista EPAM

| Ronda | Qué evalúan | Tips |
|-------|-------------|------|
| HR Screen | Background, inglés, expectativas | Prepara tu pitch en inglés: "Tell me about yourself" enfocado en SRE/DevOps |
| English Assessment | Comprensión y speaking técnico | Practica explicar arquitecturas y post-mortems en inglés |
| Technical Interview (1.5h) | Profundidad técnica, escenarios reales | Usa el framework STAR para incidentes |
| Managerial Round | Cultura, soft skills, liderazgo técnico | Prepara ejemplos de mejoras que propusiste |

> ⚠️ **Tip EPAM**: Si tienes certificaciones (AWS, CKA, etc.), prepárate para preguntas MUY detalladas sobre los temas del examen. No las menciones si no las dominas.

---

## 2. Bloque 1 — AWS Core

### Temas a dominar

- [ ] **Compute**: EC2 (tipos, AMIs, Auto Scaling Groups, Launch Templates), Lambda, ECS vs EKS
- [ ] **Networking**: VPC, subnets, route tables, Security Groups vs NACLs, VPC Peering, Transit Gateway
- [ ] **Storage**: S3 (lifecycle, versioning, replication), EBS (tipos, snapshots), EFS, Glacier
- [ ] **IAM**: Roles, policies (inline vs managed), SCP, assume role, instance profiles
- [ ] **Load Balancing**: ALB vs NLB vs CLB, target groups, health checks, path-based routing
- [ ] **DNS & CDN**: Route53 (routing policies), CloudFront (origins, behaviors, cache)
- [ ] **Databases**: RDS (Multi-AZ vs Read Replicas), Aurora, ElastiCache, DynamoDB basics

### 🧪 Labs

> **Carpetas en el repo:** [lab-01-vpc](./labs/lab-01-vpc/Readme.md) · [lab-02-iam](./labs/lab-02-iam/Readme.md) · [lab-03-asg-alb](./labs/lab-03-asg-alb/Readme.md) · Índice completo: [§12 Labs prácticos](#12-labs-prácticos).

#### [Lab 1.1 — VPC desde cero](./labs/lab-01-vpc/Readme.md)
```
Objetivo: Crear una VPC con subnets públicas y privadas, NAT Gateway, y verificar conectividad.

Pasos:
1. Crear VPC (CIDR: 10.0.0.0/16)
2. Crear 2 subnets públicas y 2 privadas en distintas AZs
3. Crear Internet Gateway y asociarlo a la VPC
4. Crear NAT Gateway en subnet pública
5. Configurar route tables (pública → IGW, privada → NAT GW)
6. Lanzar EC2 en subnet privada y verificar salida a internet

Pregunta de entrevista: "¿Cuál es la diferencia entre Security Group y NACL?"
```

#### [Lab 1.2 — IAM Roles y Assume Role](./labs/lab-02-iam/Readme.md)
```
Objetivo: Crear un rol cross-account y asumir el rol desde otra cuenta/servicio.

Pasos:
1. Crear rol con trust policy hacia tu cuenta
2. Adjuntar política con permisos mínimos (least privilege)
3. Usar AWS CLI: aws sts assume-role --role-arn ... --role-session-name test
4. Verificar credenciales temporales y expiración

Pregunta de entrevista: "¿Cómo das acceso a una EC2 a S3 sin usar access keys?"
```

#### [Lab 1.3 — Auto Scaling Group con ALB](./labs/lab-03-asg-alb/Readme.md)
```
Objetivo: Configurar ASG que escale basado en CPU y distribuya tráfico con ALB.

Pasos:
1. Crear Launch Template con user-data que instale nginx
2. Crear ALB con target group (health check: /health)
3. Crear ASG asociado al ALB, min=2, max=5
4. Crear scaling policy: CPU > 60% → scale out
5. Simular carga con stress tool y observar escalado

Pregunta de entrevista: "¿Cuál es la diferencia entre Scale In y Scale Out policy?"
```

---

## 3. Bloque 2 — Kubernetes / EKS

### Temas a dominar

- [ ] **Arquitectura**: Control plane vs data plane, etcd, API server, scheduler, kubelet
- [ ] **Objetos core**: Pod, Deployment, ReplicaSet, StatefulSet, DaemonSet, Job/CronJob
- [ ] **Networking**: Services (ClusterIP, NodePort, LoadBalancer), Ingress, Network Policies, CoreDNS
- [ ] **Storage**: PV, PVC, StorageClass, EBS CSI Driver en EKS
- [ ] **Config & Secrets**: ConfigMap, Secrets (base64 vs encriptados con KMS), External Secrets Operator
- [ ] **RBAC**: Role, ClusterRole, RoleBinding, ServiceAccounts
- [ ] **EKS específico**: Managed node groups vs self-managed vs Fargate, IRSA (IAM Roles for Service Accounts), eksctl, add-ons (CoreDNS, kube-proxy, VPC CNI)
- [ ] **Observabilidad K8s**: kubectl top, describe, logs, events; métricas con CloudWatch Container Insights
- [ ] **Troubleshooting**: Pod en CrashLoopBackOff, ImagePullBackOff, OOMKilled, Pending

### 🧪 Labs

> **Carpeta principal:** [lab-04-eks-cluster](./labs/lab-04-eks-cluster/Readme.md). Los Labs 2.2–2.4 (IRSA, troubleshooting, NetworkPolicy) se practican sobre ese cluster; el Readme del lab enlaza OIDC/IRSA y escenarios de diagnóstico.

#### [Lab 2.1 — Cluster EKS con eksctl](./labs/lab-04-eks-cluster/Readme.md)
```bash
# Objetivo: Crear cluster EKS básico y desplegar aplicación

eksctl create cluster \
  --name epam-prep \
  --region us-east-1 \
  --nodegroup-name standard-workers \
  --node-type t3.medium \
  --nodes 2 \
  --nodes-min 1 \
  --nodes-max 3 \
  --managed

# Verificar nodos
kubectl get nodes -o wide

# Desplegar nginx
kubectl create deployment nginx --image=nginx --replicas=2
kubectl expose deployment nginx --port=80 --type=LoadBalancer

# Pregunta: "¿Qué es IRSA y por qué es mejor que usar access keys en pods?"
```

#### [Lab 2.2 — IRSA (IAM Roles for Service Accounts)](./labs/lab-04-eks-cluster/Readme.md)
```bash
# Objetivo: Dar acceso a un pod a S3 sin access keys

# 1. Crear OIDC provider para el cluster
eksctl utils associate-iam-oidc-provider --cluster epam-prep --approve

# 2. Crear service account con rol IAM asociado
eksctl create iamserviceaccount \
  --name s3-reader \
  --namespace default \
  --cluster epam-prep \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
  --approve

# 3. Usar el service account en un pod
# En el deployment spec:
# serviceAccountName: s3-reader

# Pregunta: "¿Cuál es la diferencia entre usar kube2iam vs IRSA?"
```

#### [Lab 2.3 — Troubleshooting de pods](./labs/lab-04-eks-cluster/Readme.md)
```bash
# Escenarios a practicar:

# CrashLoopBackOff
kubectl logs <pod> --previous
kubectl describe pod <pod>

# OOMKilled — verificar limits
kubectl get pod <pod> -o jsonpath='{.spec.containers[*].resources}'

# ImagePullBackOff
kubectl describe pod <pod> | grep -A5 Events

# Pending — verificar recursos del nodo
kubectl describe node <node> | grep -A10 "Allocated resources"

# Pregunta: "Un pod está en Pending desde hace 10 minutos. ¿Cómo lo diagnosticas?"
```

#### [Lab 2.4 — Network Policies](./labs/lab-04-eks-cluster/Readme.md)
```yaml
# Objetivo: Aislar un namespace para que solo acepte tráfico interno

apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-external
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: production

# Pregunta: "¿Cómo verificas que una NetworkPolicy está funcionando?"
```

---

## 4. Bloque 3 — Infraestructura como Código (Terraform)

### Temas a dominar

- [ ] **Fundamentos**: providers, resources, variables, outputs, locals, data sources
- [ ] **State**: terraform.tfstate, remote state (S3 + DynamoDB locking), state mv, state rm
- [ ] **Módulos**: estructura, inputs/outputs, registro público vs privado
- [ ] **Workspaces**: uso para entornos (dev/staging/prod)
- [ ] **Ciclo de vida**: `create_before_destroy`, `prevent_destroy`, `ignore_changes`
- [ ] **Patrones avanzados**: `for_each` vs `count`, dynamic blocks, `templatefile()`
- [ ] **Terraform con AWS**: gestión de VPCs, EKS, IAM roles, S3 con Terraform

### 🧪 Labs

> **Carpetas:** [lab-05-remote-state](./labs/lab-05-remote-state/Readme.md) (remote state) · [lab-01-vpc/terraform](./labs/lab-01-vpc/terraform/README.md) (VPC con Terraform) · [lab-04-eks-cluster](./labs/lab-04-eks-cluster/) (EKS/IaC).

#### [Lab 3.1 — Remote State con S3 y DynamoDB](./labs/lab-05-remote-state/Readme.md)
```hcl
# backend.tf
terraform {
  backend "s3" {
    bucket         = "mi-terraform-state"
    key            = "epam-prep/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}

# Crear el bucket y tabla DynamoDB antes:
# aws s3 mb s3://mi-terraform-state
# aws dynamodb create-table \
#   --table-name terraform-locks \
#   --attribute-definitions AttributeName=LockID,AttributeType=S \
#   --key-schema AttributeName=LockID,KeyType=HASH \
#   --billing-mode PAY_PER_REQUEST

# Pregunta: "¿Qué pasa si dos personas hacen terraform apply al mismo tiempo sin locking?"
```

#### [Lab 3.2 — Módulo VPC reutilizable](./labs/lab-01-vpc/terraform/README.md)
```
Objetivo: Crear un módulo que cree una VPC completa y usarlo en 2 entornos.

Estructura:
modules/
  vpc/
    main.tf
    variables.tf
    outputs.tf
envs/
  dev/
    main.tf   ← llama al módulo con var dev
  prod/
    main.tf   ← llama al módulo con var prod

Pregunta: "¿Cómo versionas módulos de Terraform en un equipo?"
```

#### [Lab 3.3 — EKS con Terraform](./labs/lab-04-eks-cluster/)
```hcl
# Usar el módulo oficial de terraform-aws-modules/eks/aws
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "epam-prep"
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      min_size     = 1
      max_size     = 3
      desired_size = 2
      instance_types = ["t3.medium"]
    }
  }
}

# Pregunta: "¿Cómo manejas upgrades de versión de Kubernetes con Terraform?"
```

---

## 5. Bloque 4 — CI/CD

### Temas a dominar

- [ ] **AWS CodePipeline / CodeBuild / CodeDeploy**: stages, artifacts, buildspec.yml
- [ ] **GitLab CI/CD**: `.gitlab-ci.yml`, stages, jobs, variables, environments, runners, artifacts
- [ ] **Jenkins**: Jenkinsfile, declarative vs scripted, agentes, plugins
- [ ] **GitOps**: ArgoCD o Flux — concepto, ventajas vs CI tradicional
- [ ] **Estrategias de deployment**: Blue/Green, Canary, Rolling Update
- [ ] **Seguridad en pipelines**: escaneo de imágenes (Trivy), SAST, secrets management

### 🧪 Labs

> **Carpeta:** [lab-06-gitlab-cicd](./labs/lab-06-gitlab-cicd/Readme.md) (GitLab → ECR → EKS, OIDC).

#### [Lab 4.1 — Pipeline CI/CD con GitLab CI + EKS](./labs/lab-06-gitlab-cicd/Readme.md)
```yaml
# .gitlab-ci.yml
stages:
  - build
  - push
  - deploy

variables:
  AWS_REGION: us-east-1
  ECR_REPO: my-app
  EKS_CLUSTER: epam-prep

.aws_auth: &aws_auth
  before_script:
    - aws configure set region $AWS_REGION
    - aws ecr get-login-password | docker login --username AWS --password-stdin $ECR_REGISTRY

build:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  <<: *aws_auth
  script:
    - docker build -t $ECR_REGISTRY/$ECR_REPO:$CI_COMMIT_SHA .
  only:
    - main

push:
  stage: push
  image: docker:24
  services:
    - docker:24-dind
  <<: *aws_auth
  script:
    - docker push $ECR_REGISTRY/$ECR_REPO:$CI_COMMIT_SHA
    - docker tag $ECR_REGISTRY/$ECR_REPO:$CI_COMMIT_SHA $ECR_REGISTRY/$ECR_REPO:latest
    - docker push $ECR_REGISTRY/$ECR_REPO:latest
  only:
    - main

deploy:
  stage: deploy
  image: alpine/k8s:1.30.0
  script:
    - aws eks update-kubeconfig --name $EKS_CLUSTER --region $AWS_REGION
    - kubectl set image deployment/app app=$ECR_REGISTRY/$ECR_REPO:$CI_COMMIT_SHA
    - kubectl rollout status deployment/app --timeout=120s
  environment:
    name: production
  only:
    - main

# Variables a configurar en GitLab → Settings → CI/CD → Variables:
# AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY (o usar GitLab OIDC con IAM Role)
# ECR_REGISTRY: <account_id>.dkr.ecr.us-east-1.amazonaws.com

# Pregunta: "¿Cómo haces rollback automático si kubectl rollout status falla?"
```

#### [Lab 4.2 — GitLab CI con OIDC (sin access keys estáticas)](./labs/lab-06-gitlab-cicd/Readme.md)
```yaml
# Uso de OIDC para autenticarse con AWS sin AWS_ACCESS_KEY_ID
# Requiere configurar un IAM Identity Provider en AWS para GitLab

deploy_oidc:
  stage: deploy
  image: amazon/aws-cli:latest
  id_tokens:
    GITLAB_OIDC_TOKEN:
      aud: https://gitlab.com
  script:
    - >
      export $(printf "AWS_ACCESS_KEY_ID=%s AWS_SECRET_ACCESS_KEY=%s AWS_SESSION_TOKEN=%s"
      $(aws sts assume-role-with-web-identity
      --role-arn $AWS_ROLE_ARN
      --role-session-name gitlab-cicd
      --web-identity-token $GITLAB_OIDC_TOKEN
      --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]'
      --output text))
    - aws eks update-kubeconfig --name $EKS_CLUSTER --region $AWS_REGION
    - kubectl rollout status deployment/app

# Pregunta: "¿Qué ventaja tiene OIDC sobre access keys en un runner de GitLab?"
```

#### [Lab 4.3 — Blue/Green Deployment en EKS](./labs/lab-04-eks-cluster/Readme.md)
```
Objetivo: Implementar Blue/Green usando dos Deployments y cambiar el selector del Service.

Pasos:
1. Crear deployment "app-blue" con versión 1.0
2. Crear Service apuntando a selector: version=blue
3. Crear deployment "app-green" con versión 2.0
4. Probar app-green (port-forward)
5. Cambiar selector del Service a version=green
6. Verificar zero-downtime

Pregunta: "¿Cuándo usarías Canary vs Blue/Green?"
```

---

## 6. Bloque 5 — Observabilidad & Monitoreo

### Temas a dominar

- [ ] **Los 3 pilares**: Métricas, Logs, Trazas
- [ ] **AWS CloudWatch**: métricas, dashboards, alarms, Logs Insights, Container Insights
- [ ] **Datadog**: dashboards, monitors, APM, log management, synthetic monitoring
- [ ] **Splunk**: queries SPL básicas, dashboards, alertas
- [ ] **Prometheus + Grafana**: PromQL básico, scraping, alertmanager
- [ ] **OpenTelemetry**: concepto de instrumentación, collectors, exporters
- [ ] **Alert fatigue**: estrategias para reducirla (agrupación, supresión, severidades)
- [ ] **SLI/SLO dashboards**: cómo visualizarlos y qué mostrar en un burn rate alert

### 🧪 Labs

> **Carpeta:** [lab-07-monitoring](./labs/lab-07-monitoring/Readme.md) (Prometheus/Grafana; complementa métricas y alertas).

#### [Lab 5.1 — CloudWatch Container Insights en EKS](./labs/lab-07-monitoring/Readme.md)
```bash
# Habilitar Container Insights
aws eks create-addon \
  --cluster-name epam-prep \
  --addon-name amazon-cloudwatch-observability

# Explorar en la consola:
# CloudWatch → Container Insights → EKS Clusters
# Métricas: CPU/Memory por pod, namespace, nodo

# Crear alarma de CPU > 80% en un pod
aws cloudwatch put-metric-alarm \
  --alarm-name "high-cpu-pod" \
  --metric-name pod_cpu_utilization \
  --namespace ContainerInsights \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 2 \
  --period 60 \
  --statistic Average

# Pregunta: "¿Qué es el golden signals monitoring y qué métricas incluye?"
```

#### [Lab 5.2 — Prometheus + Grafana en EKS](./labs/lab-07-monitoring/Readme.md)
```bash
# Instalar con Helm
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

# Acceder a Grafana
kubectl port-forward svc/kube-prometheus-stack-grafana 3000:80 -n monitoring

# PromQL básico a practicar:
# CPU por pod:
rate(container_cpu_usage_seconds_total{namespace="default"}[5m])

# Memory usage:
container_memory_working_set_bytes{namespace="default"}

# HTTP error rate (si usas metrics):
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])

# Pregunta: "¿Cómo calculas un error budget burn rate en Prometheus?"
```

---

## 7. Bloque 6 — SRE: SLIs, SLOs & Incident Management

### Temas a dominar

- [ ] **SLI** (Service Level Indicator): qué medir (latencia, disponibilidad, error rate, throughput)
- [ ] **SLO** (Service Level Objective): cómo definirlos, negociación con producto
- [ ] **Error Budget**: cálculo, qué hacer cuando se agota, error budget policy
- [ ] **Toil**: definición, cómo medirlo, automatización
- [ ] **Incident Management**: severidades, roles (IC, comms lead), runbooks, escalation
- [ ] **Post-mortem**: estructura blameless, 5 whys, action items
- [ ] **Chaos Engineering**: concepto, herramientas (AWS FIS, Chaos Monkey)

### 📝 Conceptos clave

```
Disponibilidad = (tiempo_total - downtime) / tiempo_total

Error Budget = 1 - SLO
  Ejemplo: SLO 99.9% → Error Budget = 0.1% = 43.8 min/mes

Burn Rate = tasa a la que consumes el error budget
  Si burn rate = 1 → consumes justo a tiempo
  Si burn rate = 2 → agotarás el budget en la mitad del período

Fast burn alert: burn rate > 14.4 en 1h (consume 2% del budget mensual)
Slow burn alert: burn rate > 3 en 6h
```

### 🧪 Labs

> **Referencias:** ejercicios en este README; para práctica STAR/post-mortems usa [§13 Troubleshooting](#13-troubleshooting--incident-reviews).

#### Lab 6.1 — Definir SLIs/SLOs para un servicio real
```
Ejercicio (responde antes de la entrevista):

Servicio: API de pagos de una aseguradora

1. Define 3 SLIs apropiados:
   - Disponibilidad: % de requests que retornan 2xx o 3xx
   - Latencia: % de requests completados en < 500ms (p99)
   - Error rate: % de transacciones procesadas exitosamente

2. Define SLOs realistas:
   - Disponibilidad: 99.9% mensual
   - Latencia p99: 99% de requests < 500ms
   - Error rate: < 0.1% de transacciones fallidas

3. Calcula el error budget:
   - 99.9% → 43.8 min de downtime permitido/mes

Pregunta de entrevista: "El error budget se agotó el día 20 del mes. ¿Qué haces?"
```

#### [Lab 6.2 — Post-mortem template](#13-troubleshooting--incident-reviews)
```markdown
# Post-Mortem: [Título del incidente]

**Fecha**: YYYY-MM-DD
**Duración**: X horas Y minutos
**Severidad**: SEV1 / SEV2 / SEV3
**Impacto**: [usuarios afectados, revenue, SLO]

## Timeline
- HH:MM — Alerta disparada
- HH:MM — Incident Commander asignado
- HH:MM — Causa identificada
- HH:MM — Mitigación aplicada
- HH:MM — Servicio restaurado

## Root Cause
[Descripción técnica de la causa raíz]

## 5 Whys
1. ¿Por qué? →
2. ¿Por qué? →
3. ¿Por qué? →
4. ¿Por qué? →
5. ¿Por qué? →

## Qué salió bien
-

## Qué salió mal
-

## Action Items
| Acción | Owner | Due Date | P0/P1/P2 |
|--------|-------|----------|----------|
|        |       |          |          |

## Lecciones aprendidas
```

---

## 8. Bloque 7 — Linux & Networking

### Temas a dominar

- [ ] **Comandos esenciales**: top, htop, ps, netstat/ss, lsof, strace, tcpdump, curl, dig
- [ ] **File system**: inodes, permisos, ACLs, df vs du, /proc, /sys
- [ ] **Procesos**: signals, systemd, cgroups, namespaces (base de containers)
- [ ] **Networking**: TCP/IP stack, DNS resolution, iptables/nftables, routing
- [ ] **Performance troubleshooting**: CPU, Memory, Disk I/O, Network I/O

### 🧪 Preguntas típicas con respuesta

```bash
# "Explica el output de top"
# → Load average (1/5/15 min), CPU states (us/sy/id/wa), MEM usage

# "El servidor está lento. ¿Cómo diagnosticas?"
top                          # CPU, memoria, procesos top
iostat -x 1                  # Disk I/O (await, util%)
netstat -an | grep ESTABLISHED | wc -l  # Conexiones activas
vmstat 1 5                   # Memory, swap, I/O, CPU

# "¿Cómo ves qué proceso está usando el puerto 8080?"
ss -tlnp | grep 8080
lsof -i :8080

# "¿Cómo depuras un problema de DNS en un pod de K8s?"
kubectl exec -it <pod> -- nslookup kubernetes.default
kubectl exec -it <pod> -- cat /etc/resolv.conf
kubectl logs -n kube-system -l k8s-app=kube-dns
```

---

## 9. Bloque 8 — Seguridad en AWS

### Temas a dominar

- [ ] **IAM Best Practices**: least privilege, MFA, password policy, access keys rotation
- [ ] **KMS**: CMK vs AWS managed keys, envelope encryption, key policies
- [ ] **Secrets Manager vs Parameter Store**: cuándo usar cada uno
- [ ] **Security Groups & NACLs**: stateful vs stateless, reglas de entrada/salida
- [ ] **AWS Config & CloudTrail**: auditoría, compliance, detective controls
- [ ] **GuardDuty**: threat detection, findings, integración con Security Hub
- [ ] **Container security**: image scanning (ECR), Pod Security Standards, Falco

### 🧪 Labs

> **Carpeta:** [lab-08-secrets-manager](./labs/lab-08-secrets-manager/Readme.md).

#### [Lab 8.1 — Secrets en EKS con Secrets Manager](./labs/lab-08-secrets-manager/Readme.md)
```bash
# Objetivo: Montar un secret de AWS Secrets Manager como volumen en un pod

# 1. Instalar AWS Secrets Store CSI Driver
helm repo add secrets-store-csi-driver \
  https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install csi-secrets-store \
  secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system

# 2. Instalar AWS provider
kubectl apply -f https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

# 3. Crear SecretProviderClass
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: aws-secrets
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "my-db-password"
        objectType: "secretsmanager"

# Pregunta: "¿Por qué NO deberías poner secrets en variables de entorno directamente?"
```

---

## 10. Preguntas frecuentes de entrevista EPAM

### Escenarios de incident management (preparar respuesta STAR)

```
1. "Production está caído. Los usuarios no pueden hacer login. ¿Qué haces?"
   → Respuesta estructurada: Detect → Mitigate → Investigate → Communicate → Post-mortem

2. "Un pod está consumiendo 100% de CPU y está afectando otros pods del nodo. ¿Cómo actúas?"
   → kubectl top pods → identificar pod → revisar limits → cordon nodo si es necesario

3. "El deployment nuevo está causando errores. ¿Cómo haces rollback?"
   → kubectl rollout undo deployment/app
   → kubectl rollout status deployment/app
   → Revisar por qué falló antes de re-deployar

4. "¿Cómo mejorarías la resiliencia de este sistema?"
   → Multi-AZ, health checks, circuit breakers, retry logic, graceful degradation
```

### Preguntas técnicas directas

```
AWS:
- ¿Diferencia entre ALB y NLB?
- ¿Cómo funciona el auto scaling de EKS Fargate vs managed node groups?
- ¿Cómo reduces costos en AWS sin sacrificar disponibilidad?
- ¿Qué es un NAT Gateway y cuándo no lo necesitas?

Kubernetes:
- ¿Qué pasa cuando haces kubectl apply?
- ¿Diferencia entre Deployment y StatefulSet?
- ¿Cómo funciona el scheduler de K8s?
- ¿Qué es un PodDisruptionBudget y cuándo lo usas?

Terraform:
- ¿Qué es terraform import y cuándo lo usas?
- ¿Cómo evitas duplicar código entre entornos?
- ¿Qué pasa si alguien modifica un recurso manualmente en AWS?

CI/CD (GitLab):
- ¿Cuál es la diferencia entre un GitLab Runner shared vs specific?
- ¿Cómo proteges secrets en un pipeline de GitLab?
- ¿Qué es GitLab OIDC y por qué es mejor que access keys estáticas?
- ¿Cómo implementas ambientes protegidos (protected environments) en GitLab?

SRE:
- ¿Cómo defines qué SLO poner a un servicio nuevo?
- ¿Qué haces cuando el error budget se agota?
- ¿Cuál es la diferencia entre MTTD, MTTI, MTTR y MTTF?
```

---

## 11. Recursos & Certificaciones

### 📚 Gratuitos

| Recurso | URL | Para qué |
|---------|-----|----------|
| Google SRE Book | sre.google/sre-book | SLOs, incident management, toil |
| AWS Workshop Studio | workshops.aws | Labs prácticos AWS |
| Kubernetes the Hard Way | github.com/kelseyhightower/kubernetes-the-hard-way | Entender K8s a fondo |
| killer.sh | killer.sh | Simulador CKA/CKAD |
| HashiCorp Learn | developer.hashicorp.com/terraform/tutorials | Terraform |
| AWS Skill Builder (free tier) | skillbuilder.aws | Cursos AWS oficiales |
| GitLab CI/CD Docs | docs.gitlab.com/ee/ci | Referencia oficial GitLab CI |

### 🎓 Certificaciones recomendadas (en orden)

1. **AWS Solutions Architect Associate (SAA-C03)** — base sólida de AWS
2. **CKA — Certified Kubernetes Administrator** — muy valorada en EPAM
3. **AWS DevOps Engineer Professional (DOP-C02)** — CI/CD, IaC, monitoreo
4. **Terraform Associate** — validar conocimientos de IaC

### ⏱️ Plan de estudio sugerido (6 semanas)

| Semana | Bloques | Meta |
|--------|---------|------|
| 1 | AWS Core (Bloque 1) | Labs VPC, IAM, ASG |
| 2 | Kubernetes / EKS (Bloque 2) | Cluster funcionando, troubleshooting |
| 3 | Terraform + CI/CD (Bloques 3-4) | Pipeline GitLab → ECR → EKS |
| 4 | Observabilidad (Bloque 5) | Dashboards + alertas |
| 5 | SRE + Seguridad (Bloques 6 + 8) | SLOs definidos, secrets en K8s |
| 6 | Linux + Mock interviews (Bloques 7 + 10) | Practicar respuestas en inglés |

---

> 💡 **Tip final**: En la entrevista EPAM, si no sabes algo, no lo inventes. Di: *"I haven't worked with that specific tool, but I'm familiar with the concept and I've used X which solves a similar problem."* Eso demuestra honestidad y capacidad de aprendizaje, que EPAM valora mucho.

---

## 12. Labs prácticos

| Lab | Descripción | Archivos |
|-----|-------------|----------|
| [lab-01-vpc](./labs/lab-01-vpc/) | VPC con subnets públicas/privadas, IGW, NAT GW | ✅ Terraform |
| [lab-02-iam](./labs/lab-02-iam/) | IAM Roles, Policies, Assume Role | ✅ Terraform |
| [lab-03-asg-alb](./labs/lab-03-asg-alb/) | Auto Scaling Group + Application Load Balancer | ✅ Terraform |
| [lab-04-eks-cluster](./labs/lab-04-eks-cluster/) | EKS Cluster + Managed Node Group + IRSA + LBC | ✅ Terraform |
| [lab-05-remote-state](./labs/lab-05-remote-state/) | S3 backend + use_lockfile (sin DynamoDB) | ✅ Readme |
| [lab-06-gitlab-cicd](./labs/lab-06-gitlab-cicd/) | Pipeline GitLab CI → ECR → EKS con OIDC | ✅ Readme |
| [lab-07-monitoring](./labs/lab-07-monitoring/) | Prometheus + Grafana en EKS con Helm | ✅ Readme |
| [lab-08-secrets-manager](./labs/lab-08-secrets-manager/) | Secrets Store CSI Driver + Secrets Manager en EKS | ✅ Readme |
| lab-09-librechat-ec2 | LibreChat + Docker Compose + Bedrock via IAM Role | 🔜 Pendiente |

---

## 13. Troubleshooting & Incident Reviews

Runbooks y post-mortems basados en incidentes reales en EKS.
Cada documento incluye diagnóstico paso a paso y formato STAR para entrevista.

| Documento | Tipo | Descripción |
|-----------|------|-------------|
| [01-librechat-ingress](./troubleshooting/01-librechat-ingress.md) | Runbook | Ingress no genera ALB — annotations ausentes en `values.yaml` |
| [02-jwt-dst-incident](./troubleshooting/02-jwt-dst-incident.md) | Post-mortem | `TokenExpiredError` por timezone mismatch en cambio DST |
| [03-eks-target-group-unhealthy](./troubleshooting/03-eks-target-group-unhealthy.md) | Runbook | ALB existe pero Target Group muestra targets `unhealthy` |
| [04-akamai-tls-handshake-5xx](./troubleshooting/04-akamai-tls-handshake-5xx.md) | Post-mortem | Akamai cert pinning mismatch → 5xx tras rotación de certificado en origin (AEM/Konector) |
