# Lab 1.1 — VPC desde cero

## Arquitectura que vamos a construir

```text
┌─────────────────── VPC 10.0.0.0/16 ───────────────────┐
│                                                         │
│  ┌─── AZ us-east-1a ───┐  ┌─── AZ us-east-1b ───┐    │
│  │                      │  │                      │    │
│  │  ┌──────────────┐   │  │  ┌──────────────┐   │    │
│  │  │  Public Sub  │   │  │  │  Public Sub  │   │    │
│  │  │ 10.0.1.0/24  │   │  │  │ 10.0.2.0/24  │   │    │
│  │  │  [NAT GW]    │   │  │  │              │   │    │
│  │  └──────────────┘   │  │  └──────────────┘   │    │
│  │                      │  │                      │    │
│  │  ┌──────────────┐   │  │  ┌──────────────┐   │    │
│  │  │ Private Sub  │   │  │  │ Private Sub  │   │    │
│  │  │ 10.0.3.0/24  │   │  │  │ 10.0.4.0/24  │   │    │
│  │  │   [EC2]      │   │  │  │              │   │    │
│  │  └──────────────┘   │  │  └──────────────┘   │    │
│  └──────────────────────┘  └──────────────────────┘    │
│                                                         │
│                    [Internet Gateway]                    │
└─────────────────────────────────────────────────────────┘
                         │
                      🌐 Internet
```

---

## Paso 1: Crear la VPC

```bash
export AWS_REGION=us-east-1

VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-vpc}]' \
  --query 'Vpc.VpcId' \
  --output text)

echo "VPC creada: $VPC_ID"

aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames '{"Value": true}'
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support '{"Value": true}'
```

> 💡 **¿Por qué /16?** Nos da 65,536 IPs. Suficiente para dividir en muchas subnets.

---

## Paso 2: Crear las 4 Subnets

```bash
# Pública 1 - AZ a
PUBLIC_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.1.0/24 \
  --availability-zone ${AWS_REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-public-1a}]' \
  --query 'Subnet.SubnetId' \
  --output text)

# Pública 2 - AZ b
PUBLIC_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.2.0/24 \
  --availability-zone ${AWS_REGION}b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-public-1b}]' \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_1 --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id $PUBLIC_SUBNET_2 --map-public-ip-on-launch

# Privada 1 - AZ a
PRIVATE_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.3.0/24 \
  --availability-zone ${AWS_REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-private-1a}]' \
  --query 'Subnet.SubnetId' \
  --output text)

# Privada 2 - AZ b
PRIVATE_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $VPC_ID \
  --cidr-block 10.0.4.0/24 \
  --availability-zone ${AWS_REGION}b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-private-1b}]' \
  --query 'Subnet.SubnetId' \
  --output text)

echo "Subnets creadas ✅"
```

> 💡 **¿Por qué 2 AZs?** Alta disponibilidad. Si `us-east-1a` se cae, `us-east-1b` sigue funcionando.

---

## Paso 3: Crear Internet Gateway

```bash
IGW_ID=$(aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=lab-igw}]' \
  --query 'InternetGateway.InternetGatewayId' \
  --output text)

aws ec2 attach-internet-gateway \
  --internet-gateway-id $IGW_ID \
  --vpc-id $VPC_ID

echo "IGW creado y asociado: $IGW_ID"
```

> 💡 **¿Qué es el IGW?** Es la puerta de salida a internet de tu VPC. Sin IGW, nada sale ni entra.

---

## Paso 4: Crear NAT Gateway

```bash
EIP_ALLOC=$(aws ec2 allocate-address \
  --domain vpc \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Name,Value=lab-nat-eip}]' \
  --query 'AllocationId' \
  --output text)

NAT_GW_ID=$(aws ec2 create-nat-gateway \
  --subnet-id $PUBLIC_SUBNET_1 \
  --allocation-id $EIP_ALLOC \
  --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=lab-nat-gw}]' \
  --query 'NatGateway.NatGatewayId' \
  --output text)

echo "Esperando NAT Gateway..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID
echo "NAT Gateway listo ✅"
```

> ⚠️ **El NAT Gateway va en la subnet PÚBLICA** porque necesita salida a internet (vía IGW) para traducir las peticiones de las subnets privadas.

```text
Pod en subnet privada → NAT GW (subnet pública) → IGW → Internet
```

---

## Paso 5: Configurar Route Tables

```bash
# Route Table PÚBLICA → IGW
PUBLIC_RT=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=lab-public-rt}]' \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route --route-table-id $PUBLIC_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_1
aws ec2 associate-route-table --route-table-id $PUBLIC_RT --subnet-id $PUBLIC_SUBNET_2

# Route Table PRIVADA → NAT GW
PRIVATE_RT=$(aws ec2 create-route-table \
  --vpc-id $VPC_ID \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=lab-private-rt}]' \
  --query 'RouteTable.RouteTableId' \
  --output text)

aws ec2 create-route --route-table-id $PRIVATE_RT --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID
aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $PRIVATE_SUBNET_1
aws ec2 associate-route-table --route-table-id $PRIVATE_RT --subnet-id $PRIVATE_SUBNET_2

echo "Route tables configuradas ✅"
```

```text
Route Table PÚBLICA:   0.0.0.0/0 → IGW
Route Table PRIVADA:   0.0.0.0/0 → NAT GW
```

---

## Paso 6: Lanzar EC2 en subnet privada y verificar

```bash
SG_ID=$(aws ec2 create-security-group \
  --group-name lab-private-sg \
  --description "SG para EC2 en subnet privada" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text)

INSTANCE_ID=$(aws ec2 run-instances \
  --image-id $AMI_ID \
  --instance-type t2.micro \
  --subnet-id $PRIVATE_SUBNET_1 \
  --security-group-ids $SG_ID \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=lab-private-ec2}]' \
  --query 'Instances[0].InstanceId' \
  --output text)

aws ec2 wait instance-running --instance-ids $INSTANCE_ID
echo "EC2 running: $INSTANCE_ID ✅"

# Conectarse vía SSM y verificar salida a internet
aws ssm start-session --target $INSTANCE_ID
# curl -s https://ifconfig.me  → debe mostrar la IP del NAT Gateway
```

---

## 📚 Pregunta de entrevista: Security Group vs NACL

```text
┌──────────────────────┬──────────────────────────────────────┐
│    Security Group    │              NACL                     │
├──────────────────────┼──────────────────────────────────────┤
│ Nivel INSTANCIA(ENI) │ Nivel SUBNET                         │
│ STATEFUL             │ STATELESS                            │
│ Solo reglas ALLOW    │ Reglas ALLOW y DENY                  │
│ Evalúa TODAS         │ Evalúa en ORDEN numérico             │
└──────────────────────┴──────────────────────────────────────┘
```

> "El Security Group es stateful a nivel de instancia — si permites entrada, la salida es automática. El NACL es stateless a nivel de subnet — debes definir entrada Y salida explícitamente, soporta ALLOW y DENY, y evalúa reglas en orden numérico."

---

## 🧹 Limpieza

```bash
aws ec2 terminate-instances --instance-ids $INSTANCE_ID
aws ec2 wait instance-terminated --instance-ids $INSTANCE_ID
aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GW_ID
sleep 60
aws ec2 release-address --allocation-id $EIP_ALLOC
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID
aws ec2 delete-subnet --subnet-id $PUBLIC_SUBNET_1
aws ec2 delete-subnet --subnet-id $PUBLIC_SUBNET_2
aws ec2 delete-subnet --subnet-id $PRIVATE_SUBNET_1
aws ec2 delete-subnet --subnet-id $PRIVATE_SUBNET_2
aws ec2 delete-route-table --route-table-id $PUBLIC_RT
aws ec2 delete-route-table --route-table-id $PRIVATE_RT
aws ec2 delete-security-group --group-id $SG_ID
aws ec2 delete-vpc --vpc-id $VPC_ID
echo "Lab 1.1 limpio ✅"
```

---

> 🏷️ Tags: `aws` `vpc` `networking` `nat-gateway` `igw` `subnets` `route-tables`