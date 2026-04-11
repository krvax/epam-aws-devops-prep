# Lab 04 — EKS Cluster con Terraform

**Objetivo:** Crear un cluster EKS con managed node group, configurar `kubectl`, instalar el AWS Load Balancer Controller con IRSA y desplegar una app de prueba con Ingress.

## Prerequisitos

- Lab 01 aplicado (VPC, subnets con tags K8s)
- Terraform >= 1.5
- `kubectl` instalado
- `helm` >= 3.x instalado
- Permisos IAM: `eks:*`, `ec2:*`, `iam:*`

## Estructura

```
lab-04-eks-cluster/
├── main.tf          # EKS cluster + managed node group
├── irsa.tf          # OIDC provider + IAM role para LBC
├── variables.tf
├── outputs.tf
└── README.md
```

## Uso

```bash
cd labs/lab-04-eks-cluster
terraform init
terraform apply \
  -var="vpc_id=<vpc_id>" \
  -var='private_subnet_ids=["subnet-aaa","subnet-bbb"]' \
  -var='public_subnet_ids=["subnet-ccc","subnet-ddd"]'

# Configurar kubectl
aws eks update-kubeconfig \
  --name $(terraform output -raw cluster_name) \
  --region us-east-1

# Verificar nodos
kubectl get nodes -o wide

# Instalar AWS Load Balancer Controller con Helm
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$(terraform output -raw cluster_name) \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Desplegar app de prueba con Ingress
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-demo
  template:
    metadata:
      labels:
        app: nginx-demo
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-demo
spec:
  selector:
    app: nginx-demo
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: nginx-demo
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: nginx-demo
            port:
              number: 80
EOF

# Esperar el ADDRESS del Ingress
kubectl get ingress nginx-demo -w

# Limpiar
kubectl delete deployment,service,ingress nginx-demo
terraform destroy
```

## Arquitectura

```
EKS Control Plane (managed by AWS)
    │
    ├─ Managed Node Group (t3.medium x2, private subnets)
    │       ├─ aws-load-balancer-controller (kube-system)
    │       ├─ coredns
    │       └─ kube-proxy
    │
    └─ IRSA: LBC ServiceAccount → IAM Role → elasticloadbalancing:*

Ingress → ALB (public subnets) → Pod IPs (target-type: ip)
```

## Preguntas de entrevista

- ¿Qué es IRSA y por qué es mejor que kube2iam?
- ¿Cuál es la diferencia entre managed node groups y self-managed?
- ¿Cómo upgradeas la versión de Kubernetes en EKS sin downtime?
- ¿Qué add-ons son críticos en EKS y cuáles son opcionales?
