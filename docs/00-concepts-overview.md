# 00 — Mapa de Conceptos: Léeme Primero

> Este documento es tu punto de entrada antes de tocar labs o checklists.
> Si algo de Kubernetes, EKS, Helm o Karpenter te suena confuso, empieza aquí.

---

## Índice

1. [La Gran Foto: cómo encaja todo](#1-la-gran-foto)
2. [Kubernetes desde cero (sin mentiras)](#2-kubernetes-desde-cero)
3. [Ingress: el portero inteligente](#3-ingress-el-portero-inteligente)
4. [Annotations: mensajes entre componentes](#4-annotations-mensajes-entre-componentes)
5. [Helm: el gestor de paquetes de K8s](#5-helm-el-gestor-de-paquetes-de-k8s)
6. [EKS: Kubernetes en AWS](#6-eks-kubernetes-en-aws)
7. [IRSA: permisos AWS para pods (sin access keys)](#7-irsa-permisos-aws-para-pods)
8. [Karpenter: el autoscaler moderno](#8-karpenter-el-autoscaler-moderno)
9. [EKS Blueprints: todo preconfigurado](#9-eks-blueprints-todo-preconfigurado)
10. [Flujo completo de una request HTTP](#10-flujo-completo-de-una-request-http)
11. [Preguntas de entrevista con esquema de respuesta](#11-preguntas-de-entrevista)

---

## 1. La Gran Foto

Antes de entrar al detalle, visualiza las capas:

```
Usuario
  │
  ▼
Internet / DNS (Route53)
  │
  ▼
AWS Load Balancer (ALB)          ← creado automáticamente por el AWS LB Controller
  │
  ▼
Ingress (objeto de K8s)          ← define las reglas de enrutamiento HTTP
  │
  ├─ /api   → Service "backend"
  └─ /app   → Service "frontend"
                │
                ▼
            Pods (los contenedores reales)
                │
                ▼
            AWS (S3, RDS, Secrets Manager...)  ← accedido via IRSA, sin access keys
```

**EKS** es el plano de control de Kubernetes corriendo en AWS.
**Karpenter** decide cuántos nodos (EC2) existen para correr esos pods.
**Helm** es cómo instalas todo esto sin escribir 500 líneas de YAML a mano.
**Terraform** es cómo creaste el cluster y sus componentes desde código.

---

## 2. Kubernetes desde cero

### La jerarquía de objetos (de menor a mayor)

```
Pod
 └─ Deployment (maneja réplicas del Pod)
      └─ Service (da IP estable al Deployment)
           └─ Ingress (enruta HTTP hacia Services)
```

### Pod

La unidad mínima. Uno o más contenedores que comparten red y storage.
En la práctica, casi nunca creas Pods directamente — creas Deployments.

```yaml
# No hagas esto en producción, solo para entender:
apiVersion: v1
kind: Pod
metadata:
  name: mi-app
spec:
  containers:
    - name: app
      image: nginx:1.25
```

### Deployment

Dice: *"quiero 3 réplicas de este Pod, siempre"*. Si un Pod muere, el Deployment crea otro.
También maneja rolling updates: reemplaza pods de a uno sin downtime.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mi-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: mi-app
  template:
    metadata:
      labels:
        app: mi-app
    spec:
      containers:
        - name: app
          image: nginx:1.25
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"
```

> ⚠️ **Siempre define `requests` y `limits`**. Sin ellos, un pod puede consumir todos
> los recursos del nodo y matar a los demás (OOMKilled).

### Service

Los Pods tienen IPs que cambian cada vez que mueren y renacen.
El Service da una IP fija (ClusterIP) que siempre apunta a los pods correctos usando **label selectors**.

| Tipo | Para qué |
|------|----------|
| `ClusterIP` | Tráfico interno dentro del cluster |
| `NodePort` | Expone un puerto en cada nodo (para testing) |
| `LoadBalancer` | Crea un ALB/NLB en AWS automáticamente |

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mi-app-svc
spec:
  selector:
    app: mi-app        # apunta a pods con este label
  ports:
    - port: 80
      targetPort: 8080
  type: ClusterIP
```

### StatefulSet vs Deployment

| | Deployment | StatefulSet |
|--|------------|-------------|
| Pods intercambiables | ✅ Sí | ❌ No, cada uno tiene identidad |
| Nombre de pods | aleatorio | ordenado (pod-0, pod-1...) |
| Storage compartido | No necesariamente | PVC propio por pod |
| Uso típico | APIs, web apps | bases de datos, Redis, Kafka |

### DaemonSet

Corre **exactamente un pod por nodo**. Útil para agentes de monitoring (Datadog, Fluentd) o CNI plugins.

### Job / CronJob

- **Job**: corre una tarea hasta que termina exitosamente (ej: migración de DB)
- **CronJob**: Job que se repite con schedule tipo cron

---

## 3. Ingress: el portero inteligente

### El problema que resuelve

Sin Ingress, para exponer 3 apps necesitas 3 LoadBalancers en AWS → caro.
Con Ingress, tienes **1 ALB** que enruta basado en path o dominio.

```
sin ingress:                    con ingress:
ALB-1 → app-frontend            ALB-1 → /app    → app-frontend
ALB-2 → app-backend                    /api    → app-backend
ALB-3 → app-admin                      /admin  → app-admin
```

### Cómo funciona (dos piezas)

1. **Ingress Controller**: un pod que corre en el cluster, escucha cambios en objetos Ingress y configura el ALB real en AWS. En EKS usamos el **AWS Load Balancer Controller**.

2. **Ingress object**: el YAML que tú escribes declarando las reglas de enrutamiento.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mi-ingress
  annotations:
    kubernetes.io/ingress.class: alb              # usa el AWS LB Controller
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
    - host: api.miempresa.com
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: backend-svc
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-svc
                port:
                  number: 80
```

> 💡 El AWS LB Controller ve este YAML → crea un ALB en AWS → configura listener rules
> con exactamente esas rutas. Es completamente automático.

---

## 4. Annotations: mensajes entre componentes

Las annotations son **metadata en forma de key-value** que los controladores externos leen
para saber cómo configurarse.

No las memorices todas. Entiende el patrón:

```
<prefijo-del-controlador>/<nombre>: <valor>
```

Ejemplos reales:

```yaml
annotations:
  # Le dice al AWS LB Controller que el ALB sea público
  alb.ingress.kubernetes.io/scheme: internet-facing

  # Le dice que use certificado de ACM (HTTPS)
  alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:...

  # Le dice al cluster autoscaler que no elimine este nodo
  cluster-autoscaler.kubernetes.io/safe-to-evict: "false"

  # Le dice a Prometheus cómo hacer scraping de métricas
  prometheus.io/scrape: "true"
  prometheus.io/port: "8080"
```

**Regla mental**: cuando veas una annotation, pregúntate *¿qué controlador la va a leer?*
Ese controlador es quien le da significado.

---

## 5. Helm: el gestor de paquetes de K8s

### La analogía

Helm es `apt` o `brew` para Kubernetes.
Un **chart** es el paquete. Contiene todos los YAMLs necesarios con **variables** (values).

```
sin Helm: escribes 15 archivos YAML a mano para instalar Prometheus
con Helm: helm install prometheus prometheus-community/kube-prometheus-stack
```

### Comandos esenciales

```bash
# Agregar repositorio de charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Ver qué charts hay en un repo
helm search repo prometheus-community

# Ver los valores configurables de un chart
helm show values prometheus-community/kube-prometheus-stack

# Instalar con valores customizados
helm install mi-release prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --set grafana.adminPassword=secreto \
  --values mis-valores.yaml

# Ver releases instalados
helm list -A

# Actualizar un release
helm upgrade mi-release prometheus-community/kube-prometheus-stack

# Desinstalar
helm uninstall mi-release -n monitoring
```

### values.yaml: cómo customizas un chart

```yaml
# mis-valores.yaml — solo sobreescribes lo que necesitas cambiar
grafana:
  adminPassword: "mi-password-seguro"
  service:
    type: LoadBalancer

prometheus:
  prometheusSpec:
    retention: 30d
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: gp3
          resources:
            requests:
              storage: 50Gi
```

### Estructura de un chart (si te preguntan)

```
mi-chart/
  Chart.yaml          # metadata (nombre, versión, descripción)
  values.yaml         # valores por defecto
  templates/          # YAMLs con placeholders {{ .Values.xxx }}
    deployment.yaml
    service.yaml
    ingress.yaml
    _helpers.tpl      # funciones reutilizables
```

---

## 6. EKS: Kubernetes en AWS

### Qué maneja AWS y qué manejas tú

| AWS gestiona | Tú gestionas |
|---|---|
| Control plane (API server, etcd, scheduler) | Node groups (EC2) |
| HA del control plane (multi-AZ automático) | Networking (VPC CNI) |
| Upgrades del control plane | Add-ons (CoreDNS, kube-proxy) |
| | Workloads (tus apps) |

### Tipos de compute en EKS

| Tipo | Qué es | Cuándo usarlo |
|---|---|---|
| Managed Node Groups | EC2 gestionadas por AWS | Mayoría de casos |
| Self-managed nodes | EC2 que tú controlas | Configuración muy específica |
| Fargate | Serverless, sin nodos | Workloads variables, sin gestión de nodos |
| Karpenter | EC2 gestionadas por Karpenter | Scaling eficiente y rápido |

### Add-ons críticos de EKS

```bash
# Ver add-ons instalados en tu cluster
aws eks list-addons --cluster-name mi-cluster

# Add-ons comunes:
# - vpc-cni          → networking de pods (IPs de la VPC)
# - coredns          → DNS interno del cluster
# - kube-proxy       → networking de Services
# - aws-ebs-csi-driver → storage (PVCs con EBS)
# - amazon-cloudwatch-observability → métricas y logs
```

### kubeconfig: cómo te conectas al cluster

```bash
# Configurar kubectl para apuntar a tu cluster EKS
aws eks update-kubeconfig \
  --name mi-cluster \
  --region us-east-1

# Verificar
kubectl cluster-info
kubectl get nodes
```

---

## 7. IRSA: Permisos AWS para Pods

### El problema

Tus pods necesitan acceder a S3, Secrets Manager, DynamoDB, etc.
La solución incorrecta: poner access keys en variables de entorno o en el código.
La solución correcta: **IRSA** (IAM Roles for Service Accounts).

### Cómo funciona (simplificado)

```
Pod → usa ServiceAccount → ServiceAccount tiene annotation con ARN del IAM Role
                                  ↓
                         AWS STS verifica el token OIDC del pod
                                  ↓
                         AWS entrega credenciales temporales al pod
                                  ↓
                         Pod accede a S3/DynamoDB/etc. con esas credenciales
```

Nunca hay un access key hardcodeado. Las credenciales son temporales y rotadas automáticamente.

### Setup paso a paso

```bash
# 1. Asociar OIDC provider al cluster (una sola vez)
eksctl utils associate-iam-oidc-provider \
  --cluster mi-cluster \
  --approve

# 2. Crear IAM Role + ServiceAccount (eksctl lo hace junto)
eksctl create iamserviceaccount \
  --name mi-app-sa \
  --namespace production \
  --cluster mi-cluster \
  --attach-policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
  --approve

# 3. En tu Deployment, referenciar el ServiceAccount
```

```yaml
spec:
  serviceAccountName: mi-app-sa   # ← esto es todo lo que necesitas en el pod
  containers:
    - name: app
      image: mi-app:latest
      # No hay ninguna variable AWS_ACCESS_KEY_ID aquí
```

---

## 8. Karpenter: el autoscaler moderno

### El problema que resuelve

El **Cluster Autoscaler** clásico es lento y rígido: trabaja con Node Groups pre-definidos
y tarda 3-5 minutos en agregar un nodo.

**Karpenter** es más inteligente:
- Mira qué pods están en `Pending` y qué recursos necesitan
- Elige el tipo de EC2 óptimo para esos pods (tamaño exacto, spot vs on-demand)
- Levanta el nodo en ~30-60 segundos
- Consolida nodos cuando hay poco uso (bin packing)

### Conceptos clave

**NodePool** (antes llamado Provisioner): define las reglas de qué nodos puede crear Karpenter.

```yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]    # prefiere spot, usa on-demand si no hay
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t3.medium", "t3.large", "m5.large"]
      nodeClassRef:
        name: default
  limits:
    cpu: 1000                              # límite total del cluster
  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 30s
```

**EC2NodeClass**: configuración específica de AWS (AMI, subnets, security groups).

```yaml
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2
  role: "KarpenterNodeRole-mi-cluster"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: mi-cluster
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: mi-cluster
```

### Karpenter vs Cluster Autoscaler

| | Cluster Autoscaler | Karpenter |
|--|---|---|
| Velocidad | ~3-5 min | ~30-60 seg |
| Selección de instancia | Fija por Node Group | Dinámica, elige la óptima |
| Consolidación | Limitada | Agresiva (bin packing) |
| Configuración | Node Groups en AWS | NodePool + EC2NodeClass en K8s |
| Spot handling | Manual por Node Group | Automático con fallback |

---

## 9. EKS Blueprints: todo preconfigurado

### Qué es

EKS Blueprints es un conjunto de **módulos de Terraform** (o CDK) que crea un cluster
EKS production-ready con todos los add-ons ya configurados.

En vez de:
1. Crear VPC con Terraform
2. Crear cluster EKS
3. Instalar AWS LB Controller con Helm
4. Configurar IRSA para el LB Controller
5. Instalar Karpenter
6. Configurar IRSA para Karpenter
7. Instalar CoreDNS, kube-proxy, VPC CNI
8. Instalar External Secrets Operator
9. ... (20 pasos más)

Con Blueprints:

```hcl
module "eks_blueprints" {
  source = "github.com/aws-ia/terraform-aws-eks-blueprints"

  cluster_name    = "mi-cluster"
  cluster_version = "1.29"
  vpc_id          = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnets

  # Add-ons con un flag
  enable_aws_load_balancer_controller = true
  enable_karpenter                    = true
  enable_metrics_server               = true
  enable_external_secrets             = true
}
```

**Para la entrevista**: EKS Blueprints no es magia, es Terraform + Helm + configuración
de IRSA automatizada. Si te preguntan, describe los componentes que instala, no lo trates
como una caja negra.

---

## 10. Flujo completo de una request HTTP

Trazar este flujo de memoria es una pregunta favorita de entrevistadores.

```
1. Usuario escribe: https://api.miempresa.com/users

2. DNS (Route53) resuelve api.miempresa.com → IP del ALB en AWS

3. ALB recibe la request en puerto 443
   └─ Termina TLS con certificado de ACM
   └─ Busca listener rule que coincida con /users

4. ALB forwardea a Target Group (pods del cluster)
   └─ El target type "ip" envía directo a la IP del pod (no al nodo)

5. La request llega al pod de la app
   └─ Pod procesa la request
   └─ Si necesita DB: llama a RDS en subnet privada
   └─ Si necesita secrets: llama a Secrets Manager via IRSA

6. Respuesta regresa por el mismo camino: Pod → ALB → Usuario
```

**Componentes K8s involucrados**:
- `Ingress` → definió la regla `/users → backend-svc`
- `Service (backend-svc)` → seleccionó los pods correctos
- `AWS LB Controller` → creó y configuró el ALB automáticamente
- `IRSA` → permitió al pod acceder a Secrets Manager sin access keys

---

## 11. Preguntas de entrevista

### K8s fundamentals

**"¿Qué pasa cuando haces `kubectl apply -f deployment.yaml`?"**

```
1. kubectl envía el YAML al API Server (HTTPS)
2. API Server autentica (tu kubeconfig) y autoriza (RBAC)
3. API Server valida el objeto y lo guarda en etcd
4. El Deployment Controller detecta el cambio en etcd
5. Crea un ReplicaSet con las especificaciones
6. El ReplicaSet crea los Pods
7. El Scheduler asigna cada Pod a un nodo disponible
8. El kubelet del nodo descarga la imagen y arranca el contenedor
```

---

**"Un pod lleva 10 minutos en `Pending`. ¿Cómo lo diagnosticas?"**

```bash
# Paso 1: ver el evento de error
kubectl describe pod <nombre> | grep -A20 Events

# Causas más comunes:
# - "Insufficient cpu/memory" → no hay nodo con recursos suficientes
#   → Solución: revisar requests del pod, agregar nodos, o bajar requests

# - "no nodes available to schedule" → todos los nodos tienen taints sin toleration
#   → kubectl describe nodes | grep Taint

# - "0/3 nodes are available: persistentvolumeclaim not bound"
#   → kubectl get pvc → ver si el PVC está en Pending también
#   → kubectl describe pvc → ver por qué no se provisionó el storage

# Paso 2: verificar recursos del cluster
kubectl top nodes
kubectl describe nodes | grep -A5 "Allocated resources"
```

---

**"¿Cuál es la diferencia entre Deployment y StatefulSet?"**

```
Deployment:
- Pods son idénticos e intercambiables
- Si un pod muere, el reemplazo puede ir a cualquier nodo
- Storage compartido o sin storage persistente
- Ej: una API REST, un servidor web

StatefulSet:
- Cada pod tiene identidad única (pod-0, pod-1, pod-2)
- Siempre se crean y destruyen en orden
- Cada pod tiene su propio PVC (storage independiente)
- El pod-0 siempre es el mismo pod (mismo nombre, mismo storage)
- Ej: PostgreSQL, Redis cluster, Kafka, Elasticsearch
```

---

**"¿Qué es un PodDisruptionBudget?"**

```
Define cuántos pods pueden estar no disponibles durante una disrupción voluntaria
(upgrade de nodo, drain, etc.).

Ejemplo: tengo 5 réplicas, quiero que siempre haya al menos 4 disponibles:

apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  minAvailable: 4
  selector:
    matchLabels:
      app: mi-app

Sin PDB: un kubectl drain podría matar todos los pods del nodo de golpe.
Con PDB: Kubernetes espera a que otro pod esté Ready antes de sacar el siguiente.
```

---

### EKS / AWS

**"¿Qué es IRSA y por qué es mejor que access keys en pods?"**

```
IRSA = IAM Roles for Service Accounts.

Problema con access keys:
- Se hardcodean en env vars o código → riesgo de filtración
- No rotan automáticamente
- Si el pod es comprometido, el atacante tiene acceso indefinido

IRSA soluciona esto:
- Credenciales temporales (expiran en horas)
- Rotación automática por AWS STS
- Principio de mínimo privilegio por pod (cada ServiceAccount tiene su propio rol)
- Si el pod es comprometido, las credenciales expiran solas
- Auditoria clara en CloudTrail: qué pod asumió qué rol
```

---

**"¿Cómo funciona el autoscaling en EKS?"**

```
Hay dos tipos de autoscaling independientes:

1. HPA (Horizontal Pod Autoscaler) — escala pods
   - Mide CPU/memoria (o métricas custom)
   - Agrega o quita réplicas del Deployment
   - Actúa en segundos

2. Karpenter (o Cluster Autoscaler) — escala nodos
   - Detecta pods en Pending por falta de recursos
   - Agrega nodos EC2 para que esos pods tengan dónde correr
   - Actúa en minutos (CA) o ~60 segundos (Karpenter)

Flujo típico:
Tráfico sube → HPA agrega pods → pods quedan en Pending (sin nodo)
→ Karpenter detecta Pending → crea EC2 → pods se schedulean → sistema estable
```

---

**"¿Qué harías si un deployment nuevo está causando errores en producción?"**

```bash
# Opción 1: rollback inmediato
kubectl rollout undo deployment/mi-app

# Verificar que el rollback progresó
kubectl rollout status deployment/mi-app

# Ver historial de versiones
kubectl rollout history deployment/mi-app

# Opción 2: si usas GitOps (ArgoCD)
# Revertir el commit en Git → ArgoCD detecta el cambio → hace rollback automático

# DESPUÉS del rollback: investigar qué falló
kubectl logs deployment/mi-app --previous
kubectl describe deployment/mi-app
# Revisar métricas en CloudWatch / Datadog del período del error
```

---

### Incident Management (respuesta STAR)

**"Production está caído. Usuarios no pueden hacer login. ¿Qué haces?"**

```
Estructura: Detect → Mitigate → Investigate → Communicate → Post-mortem

1. DETECT
   - Confirmar el incidente: ¿es real o falso positivo?
   - kubectl get pods -n production (¿hay pods caídos?)
   - Revisar dashboards: error rate, latencia, saturación

2. MITIGATE (primero, antes de investigar)
   - ¿El último deploy fue reciente? → kubectl rollout undo deployment/auth
   - ¿Es un problema de capacidad? → kubectl scale deployment/auth --replicas=5
   - El objetivo es restaurar servicio, no encontrar root cause todavía

3. INVESTIGATE
   - kubectl logs deployment/auth --previous
   - kubectl describe pods -n production
   - Revisar CloudTrail: ¿hubo cambios de IAM recientes?
   - Revisar RDS: ¿conexiones saturadas? ¿replication lag?

4. COMMUNICATE
   - Actualizar status page cada 15-20 minutos
   - Notificar a stakeholders: "Estamos investigando, ETA de resolución: X"

5. POST-MORTEM
   - Blameless, dentro de las 48h del incidente
   - 5 Whys para llegar a root cause
   - Action items con owner y fecha
```

---

> 💡 **Tip para la entrevista**: Cuando no sepas algo, usa esta frase:
> *"I haven't used that specific tool in production, but I'm familiar with the concept.
> In my experience I've solved a similar problem with X, which works by..."*
>
> Eso demuestra honestidad + capacidad de aprendizaje + que no te quedas paralizado.

---

*Documento generado como complemento de la guía principal del repo.*
*Siguiente paso recomendado: [01-eks-ingress-alb.md](01-eks-ingress-alb.md)*