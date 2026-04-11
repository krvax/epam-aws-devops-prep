# Lab 08 — Secrets Manager + Secrets Store CSI Driver en EKS

**Bloque:** 8 — Seguridad en AWS

**Objetivo:** Montar secrets de AWS Secrets Manager como volúmenes en pods de EKS usando el Secrets Store CSI Driver con IRSA, sin variables de entorno con valores hardcodeados.

---

## Prerequisitos

- Lab 04 completado (cluster EKS con OIDC Provider habilitado)
- Lab 02 completado (conocimiento de IAM)
- Helm 3 instalado

---

## ¿Por qué no usar variables de entorno para secrets?

```
Env vars en K8s → visible en:
  - kubectl describe pod
  - /proc/<pid>/environ dentro del container
  - logs accidentales
  - etcd (si el Secret de K8s no está cifrado)

Secrets Store CSI Driver →:
  - El secret vive en AWS Secrets Manager (cifrado con KMS)
  - Se monta como archivo en un path dentro del pod
  - IRSA controla quién puede acceder — solo el ServiceAccount correcto
  - La rotación en AWS SM se propaga automáticamente al pod
```

---

## Arquitectura

```
AWS Secrets Manager
  └─→ secret: /epam-prep/db-password
        │
        └─→ IAM Role (IRSA)
              └─→ ServiceAccount: app-sa (namespace: default)
                    └─→ Secrets Store CSI Driver
                          └─→ SecretProviderClass (CRD)
                                └─→ Volume montado en /mnt/secrets/
                                      └─→ Pod lee el archivo
```

---

## Estructura del lab

```
lab-08-secrets-manager/
├── Readme.md
├── k8s/
│   ├── secret-provider-class.yaml  ← CRD que define qué secret montar
│   ├── service-account.yaml        ← SA con anotó IRSA
│   └── pod-test.yaml               ← pod de prueba con el volumen
└── terraform/
    ├── main.tf                     ← Secret en AWS SM + IAM Role IRSA
    ├── variables.tf
    └── outputs.tf
```

---

## Paso a paso

### 1. Instalar Secrets Store CSI Driver + AWS Provider

```bash
# CSI Driver
helm repo add secrets-store-csi-driver \
  https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm install csi-secrets-store \
  secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace kube-system \
  --set syncSecret.enabled=true  # permite sincronizar como K8s Secret también

# AWS Provider
kubectl apply -f \
  https://raw.githubusercontent.com/aws/secrets-store-csi-driver-provider-aws/main/deployment/aws-provider-installer.yaml

# Verificar
kubectl get pods -n kube-system | grep secrets-store
```

### 2. Crear el secret en AWS Secrets Manager

```bash
aws secretsmanager create-secret \
  --name /epam-prep/db-password \
  --secret-string '{"username":"admin","password":"supersecret123"}' \
  --region us-east-1
```

### 3. Crear IAM Role con IRSA

```bash
# Crear service account con IRSA via eksctl
eksctl create iamserviceaccount \
  --name app-sa \
  --namespace default \
  --cluster epam-prep \
  --attach-policy-arn arn:aws:iam::aws:policy/SecretsManagerReadWrite \
  --approve

# O usando el terraform/ de este lab
cd terraform/ && terraform apply
```

### 4. Crear el SecretProviderClass

```bash
kubectl apply -f k8s/secret-provider-class.yaml
kubectl apply -f k8s/pod-test.yaml
```

### 5. Verificar que el secret está montado

```bash
# Ver el contenido del secret dentro del pod
kubectl exec -it pod-test -- cat /mnt/secrets/db-password
# → {"username":"admin","password":"supersecret123"}

# Verificar que NO está como env var
kubectl exec -it pod-test -- env | grep -i password
# → (sin output)
```

---

## Preguntas de entrevista

**"¿Por qué no poner secrets en variables de entorno en K8s?"**

Respuesta: Las env vars son visibles en `kubectl describe pod`, en `/proc/<pid>/environ` dentro del container, y pueden aparecer en logs accidentalmente. Los K8s Secrets están codificados en base64 (no cifrados) en etcd por defecto. Con Secrets Store CSI Driver + AWS Secrets Manager, el valor nunca entra al cluster — se monta directamente desde AWS con credenciales temporales de IRSA.

**"¿Cuál es la diferencia entre Secrets Manager y Parameter Store?"**

Respuesta: Secrets Manager está diseñado para secrets sensibles con rotación automática (RDS, API keys). Tiene costo por secret/mes. Parameter Store es más barato (tier gratuito) y sirve para configuración que no es secret estricto (feature flags, endpoints). Para credenciales de base de datos o API keys externas, Secrets Manager es la elección correcta.

**"¿Cómo funciona IRSA para acceder a Secrets Manager?"**

Respuesta: El pod tiene un ServiceAccount con una annotation que apunta a un IAM Role. El CSI Driver usa el OIDC token del ServiceAccount para hacer `sts:AssumeRoleWithWebIdentity` y obtener credenciales temporales con los permisos del Role. Esas credenciales se usan para llamar a Secrets Manager y montar el secret. Sin IRSA, el pod no puede acceder al secret aunque el Driver esté instalado.

---

## Cleanup

```bash
kubectl delete -f k8s/
helm uninstall csi-secrets-store -n kube-system
aws secretsmanager delete-secret \
  --secret-id /epam-prep/db-password \
  --force-delete-without-recovery
```

---

## Documentación relacionada

- [Lab 04 — EKS Cluster + IRSA](../lab-04-eks-cluster/Readme.md)
- [AWS Secrets Store CSI Driver Provider](https://github.com/aws/secrets-store-csi-driver-provider-aws)
- [Secrets Store CSI Driver](https://secrets-store-csi-driver.sigs.k8s.io/)
