#!/usr/bin/env bash
# =============================================================================
# Lab 01 - VPC desde cero con AWS CLI
# Espeja exactamente la arquitectura del terraform/ de este mismo lab.
#
# Arquitectura:
#   VPC 10.0.0.0/16
#   |-- Subnet publica  us-east-1a  10.0.1.0/24  -> IGW
#   |-- Subnet publica  us-east-1b  10.0.2.0/24  -> IGW
#   |-- Subnet privada  us-east-1a  10.0.11.0/24 -> NAT GW
#   +-- Subnet privada  us-east-1b  10.0.12.0/24 -> NAT GW
#
# Uso:
#   # Paso a paso (recomendado para aprender):
#   source commands.sh   # carga las funciones sin ejecutar
#   step_01_vpc
#   step_02_subnets
#   step_03_igw
#   step_04_nat          # tarda ~90s
#   step_05_routes
#   step_06_sg
#   # step_06b_ssm_iam  # opcional: solo rol + instance profile SSM (sin EC2)
#   # step_07_ec2       # opcional: EC2 privada t2.micro + IAM para Session Manager
#   verify
#
#   # Todo de una vez (solo red, sin EC2):
#   bash commands.sh
#
#   # Cleanup al terminar:
#   cleanup
#
# Pre-requisitos:
#   aws configure  (o AWS_PROFILE exportado)
#   aws --version >= 2.x
#   Para step_07_ec2 / step_06b_ssm_iam: permisos IAM (create-role, create-instance-profile, etc.)
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# VARIABLES - ajusta region y nombre si lo necesitas
# ---------------------------------------------------------------------------
REGION="us-east-1"
PROJECT="epam-lab"

VPC_CIDR="10.0.0.0/16"
PUB_CIDR_1="10.0.1.0/24"
PUB_CIDR_2="10.0.2.0/24"
PRIV_CIDR_1="10.0.11.0/24"
PRIV_CIDR_2="10.0.12.0/24"
AZ1="us-east-1a"
AZ2="us-east-1b"

# IDs - se van llenando conforme avanzas
VPC_ID=""
SUBNET_PUB_1=""
SUBNET_PUB_2=""
SUBNET_PRIV_1=""
SUBNET_PRIV_2=""
IGW_ID=""
EIP_ALLOC=""
NAT_ID=""
RT_PUB=""
RT_PRIV=""
SG_ID=""
INSTANCE_ID=""
WEB_INSTANCE_ID=""
SG_WEB=""
# Rol + instance profile para SSM (creados en paso 7 o step_06b_ssm_iam)
SSM_ROLE_NAME="${PROJECT}-private-ec2-ssm"
SSM_INSTANCE_PROFILE_NAME="${PROJECT}-private-ec2-ssm"

# Archivo de estado local (mini .tfstate casero)
STATE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.lab-state"

# ---------------------------------------------------------------------------
# HELPERS
# ---------------------------------------------------------------------------
log() { echo -e "\n>>> $*"; }
ok()  { echo "    OK: $*"; }

# ---------------------------------------------------------------------------
# ESTADO - guardar y recuperar IDs (solucion al problema de variables perdidas)
# Concepto: esto es exactamente lo que Terraform hace con .tfstate
#           pero en version minima. Sin esto, al cerrar la terminal
#           pierdes todos los IDs y cleanup no puede borrar nada.
# ---------------------------------------------------------------------------
save_state() {
  cat > "$STATE_FILE" <<EOF
VPC_ID=$VPC_ID
SUBNET_PUB_1=$SUBNET_PUB_1
SUBNET_PUB_2=$SUBNET_PUB_2
SUBNET_PRIV_1=$SUBNET_PRIV_1
SUBNET_PRIV_2=$SUBNET_PRIV_2
IGW_ID=$IGW_ID
EIP_ALLOC=$EIP_ALLOC
NAT_ID=$NAT_ID
RT_PUB=$RT_PUB
RT_PRIV=$RT_PRIV
SG_ID=$SG_ID
INSTANCE_ID=$INSTANCE_ID
WEB_INSTANCE_ID=$WEB_INSTANCE_ID
SG_WEB=$SG_WEB
EOF
  ok "Estado guardado en $STATE_FILE"
}

load_state() {
  if [[ -f "$STATE_FILE" ]]; then
    source "$STATE_FILE"
    ok "Estado cargado desde $STATE_FILE"
  else
    log "No se encontro archivo de estado, intentando recuperar por tags..."
    recover_state_from_aws
  fi
}

# ---------------------------------------------------------------------------
# RECUPERAR ESTADO DESDE AWS (fallback si no hay archivo .lab-state)
# Busca recursos por tags Name=epam-lab-* y rellena las variables.
# ---------------------------------------------------------------------------
recover_state_from_aws() {
  log "Recuperando IDs desde AWS por tags (Name=${PROJECT}-*)..."

  VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=tag:Name,Values=${PROJECT}-vpc" \
    --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
  [[ "$VPC_ID" == "None" ]] && VPC_ID=""

  SUBNET_PUB_1=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=${PROJECT}-public-${AZ1}" \
    --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
  [[ "$SUBNET_PUB_1" == "None" ]] && SUBNET_PUB_1=""

  SUBNET_PUB_2=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=${PROJECT}-public-${AZ2}" \
    --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
  [[ "$SUBNET_PUB_2" == "None" ]] && SUBNET_PUB_2=""

  SUBNET_PRIV_1=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=${PROJECT}-private-${AZ1}" \
    --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
  [[ "$SUBNET_PRIV_1" == "None" ]] && SUBNET_PRIV_1=""

  SUBNET_PRIV_2=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=${PROJECT}-private-${AZ2}" \
    --query 'Subnets[0].SubnetId' --output text 2>/dev/null || echo "")
  [[ "$SUBNET_PRIV_2" == "None" ]] && SUBNET_PRIV_2=""

  IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=tag:Name,Values=${PROJECT}-igw" \
    --query 'InternetGateways[0].InternetGatewayId' --output text 2>/dev/null || echo "")
  [[ "$IGW_ID" == "None" ]] && IGW_ID=""

  NAT_ID=$(aws ec2 describe-nat-gateways \
    --filter "Name=tag:Name,Values=${PROJECT}-nat-gw" "Name=state,Values=available" \
    --query 'NatGateways[0].NatGatewayId' --output text 2>/dev/null || echo "")
  [[ "$NAT_ID" == "None" ]] && NAT_ID=""

  # EIP: buscar la que esta asociada al NAT, o cualquier EIP sin asociar del lab
  if [[ -n "$NAT_ID" ]]; then
    EIP_ALLOC=$(aws ec2 describe-nat-gateways \
      --nat-gateway-ids "$NAT_ID" \
      --query 'NatGateways[0].NatGatewayAddresses[0].AllocationId' --output text 2>/dev/null || echo "")
    [[ "$EIP_ALLOC" == "None" ]] && EIP_ALLOC=""
  fi

  RT_PUB=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=${PROJECT}-public-rt" \
    --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || echo "")
  [[ "$RT_PUB" == "None" ]] && RT_PUB=""

  RT_PRIV=$(aws ec2 describe-route-tables \
    --filters "Name=tag:Name,Values=${PROJECT}-private-rt" \
    --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null || echo "")
  [[ "$RT_PRIV" == "None" ]] && RT_PRIV=""

  SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=tag:Name,Values=${PROJECT}-private-ec2-sg" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
  [[ "$SG_ID" == "None" ]] && SG_ID=""

  SG_WEB=$(aws ec2 describe-security-groups \
    --filters "Name=tag:Name,Values=${PROJECT}-web-sg" \
    --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || echo "")
  [[ "$SG_WEB" == "None" ]] && SG_WEB=""

  INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${PROJECT}-private-ec2" "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "")
  [[ "$INSTANCE_ID" == "None" ]] && INSTANCE_ID=""

  WEB_INSTANCE_ID=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=${PROJECT}-web-ec2" "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null || echo "")
  [[ "$WEB_INSTANCE_ID" == "None" ]] && WEB_INSTANCE_ID=""

  ok "Recuperado: VPC=$VPC_ID IGW=$IGW_ID NAT=$NAT_ID"
  ok "Recuperado: PUB1=$SUBNET_PUB_1 PUB2=$SUBNET_PUB_2"
  ok "Recuperado: PRIV1=$SUBNET_PRIV_1 PRIV2=$SUBNET_PRIV_2"
  ok "Recuperado: RT_PUB=$RT_PUB RT_PRIV=$RT_PRIV"
  ok "Recuperado: SG=$SG_ID SG_WEB=$SG_WEB"
  ok "Recuperado: EC2=$INSTANCE_ID WEB=$WEB_INSTANCE_ID"
}

# ---------------------------------------------------------------------------
# PASO 1 - VPC
# Concepto: contenedor de red aislado. Sin esto no hay nada.
# ---------------------------------------------------------------------------
step_01_vpc() {
  log "PASO 1: Crear VPC ($VPC_CIDR)"

  VPC_ID=$(aws ec2 create-vpc \
    --cidr-block "$VPC_CIDR" \
    --region "$REGION" \
    --query 'Vpc.VpcId' \
    --output text)

  # Habilitar DNS hostnames (necesario para SSM y EKS)
  aws ec2 modify-vpc-attribute \
    --vpc-id "$VPC_ID" \
    --enable-dns-hostnames '{"Value":true}'

  aws ec2 modify-vpc-attribute \
    --vpc-id "$VPC_ID" \
    --enable-dns-support '{"Value":true}'

  aws ec2 create-tags \
    --resources "$VPC_ID" \
    --tags "Key=Name,Value=${PROJECT}-vpc" "Key=ManagedBy,Value=cli-lab"

  ok "VPC creada: $VPC_ID"
  save_state
}

# ---------------------------------------------------------------------------
# PASO 2 - Subnets
# Concepto: publica = ruta al IGW + IP publica asignada automaticamente
#           privada = ruta al NAT GW, sin IP publica directa
# ---------------------------------------------------------------------------
step_02_subnets() {
  log "PASO 2: Crear subnets (2 publicas + 2 privadas)"

  # Publica AZ1
  SUBNET_PUB_1=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$PUB_CIDR_1" \
    --availability-zone "$AZ1" \
    --query 'Subnet.SubnetId' --output text)
  aws ec2 modify-subnet-attribute \
    --subnet-id "$SUBNET_PUB_1" \
    --map-public-ip-on-launch
  aws ec2 create-tags --resources "$SUBNET_PUB_1" \
    --tags "Key=Name,Value=${PROJECT}-public-${AZ1}" "Key=Tier,Value=public"
  ok "Subnet publica AZ1: $SUBNET_PUB_1"

  # Publica AZ2
  SUBNET_PUB_2=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$PUB_CIDR_2" \
    --availability-zone "$AZ2" \
    --query 'Subnet.SubnetId' --output text)
  aws ec2 modify-subnet-attribute \
    --subnet-id "$SUBNET_PUB_2" \
    --map-public-ip-on-launch
  aws ec2 create-tags --resources "$SUBNET_PUB_2" \
    --tags "Key=Name,Value=${PROJECT}-public-${AZ2}" "Key=Tier,Value=public"
  ok "Subnet publica AZ2: $SUBNET_PUB_2"

  # Privada AZ1
  SUBNET_PRIV_1=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$PRIV_CIDR_1" \
    --availability-zone "$AZ1" \
    --query 'Subnet.SubnetId' --output text)
  aws ec2 create-tags --resources "$SUBNET_PRIV_1" \
    --tags "Key=Name,Value=${PROJECT}-private-${AZ1}" "Key=Tier,Value=private"
  ok "Subnet privada AZ1: $SUBNET_PRIV_1"

  # Privada AZ2
  SUBNET_PRIV_2=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block "$PRIV_CIDR_2" \
    --availability-zone "$AZ2" \
    --query 'Subnet.SubnetId' --output text)
  aws ec2 create-tags --resources "$SUBNET_PRIV_2" \
    --tags "Key=Name,Value=${PROJECT}-private-${AZ2}" "Key=Tier,Value=private"
  ok "Subnet privada AZ2: $SUBNET_PRIV_2"

  save_state
}

# ---------------------------------------------------------------------------
# PASO 3 - Internet Gateway
# Concepto: puerta de salida/entrada para las subnets PUBLICAS.
#           Sin esto las subnets publicas no tienen internet.
#           Diferencia clave vs NAT: IGW es bidireccional (entra y sale).
# ---------------------------------------------------------------------------
step_03_igw() {
  log "PASO 3: Crear y adjuntar Internet Gateway"

  IGW_ID=$(aws ec2 create-internet-gateway \
    --query 'InternetGateway.InternetGatewayId' --output text)
  aws ec2 create-tags --resources "$IGW_ID" \
    --tags "Key=Name,Value=${PROJECT}-igw"

  aws ec2 attach-internet-gateway \
    --internet-gateway-id "$IGW_ID" \
    --vpc-id "$VPC_ID"

  ok "IGW creado y adjuntado: $IGW_ID"
  save_state
}

# ---------------------------------------------------------------------------
# PASO 4 - Elastic IP + NAT Gateway
# Concepto: NAT GW permite que las subnets PRIVADAS salgan a internet
#           (para instalar paquetes) SIN tener IP publica propia.
#           Solo salida - el trafico de entrada no puede iniciar desde fuera.
#           El NAT GW vive en subnet PUBLICA (necesita IGW para salir).
# Nota: tarda ~2 minutos en quedar disponible.
# ---------------------------------------------------------------------------
step_04_nat() {
  log "PASO 4: Crear Elastic IP y NAT Gateway (va en subnet PUBLICA)"

  EIP_ALLOC=$(aws ec2 allocate-address \
    --domain vpc \
    --query 'AllocationId' --output text)
  ok "EIP alocada: $EIP_ALLOC"

  NAT_ID=$(aws ec2 create-nat-gateway \
    --subnet-id "$SUBNET_PUB_1" \
    --allocation-id "$EIP_ALLOC" \
    --query 'NatGateway.NatGatewayId' --output text)

  log "Esperando NAT Gateway disponible (~90s)..."
  aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID"

  aws ec2 create-tags --resources "$NAT_ID" \
    --tags "Key=Name,Value=${PROJECT}-nat-gw" 2>/dev/null || true

  ok "NAT Gateway disponible: $NAT_ID"
  save_state
}

# ---------------------------------------------------------------------------
# PASO 5 - Route Tables
# Concepto: tabla publica  -> default route al IGW (0.0.0.0/0 -> igw-xxx)
#           tabla privada  -> default route al NAT GW (0.0.0.0/0 -> nat-xxx)
#           Cada subnet se asocia a UNA route table.
#           La VPC tiene una Main RT por default - no la usamos directamente.
# ---------------------------------------------------------------------------
step_05_routes() {
  log "PASO 5: Crear Route Tables y asociar subnets"

  # Route Table PUBLICA -> IGW
  RT_PUB=$(aws ec2 create-route-table \
    --vpc-id "$VPC_ID" \
    --query 'RouteTable.RouteTableId' --output text)
  aws ec2 create-tags --resources "$RT_PUB" \
    --tags "Key=Name,Value=${PROJECT}-public-rt"

  aws ec2 create-route \
    --route-table-id "$RT_PUB" \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id "$IGW_ID"

  aws ec2 associate-route-table --route-table-id "$RT_PUB" --subnet-id "$SUBNET_PUB_1"
  aws ec2 associate-route-table --route-table-id "$RT_PUB" --subnet-id "$SUBNET_PUB_2"
  ok "Route Table publica: $RT_PUB -> $IGW_ID"

  # Route Table PRIVADA -> NAT GW
  RT_PRIV=$(aws ec2 create-route-table \
    --vpc-id "$VPC_ID" \
    --query 'RouteTable.RouteTableId' --output text)
  aws ec2 create-tags --resources "$RT_PRIV" \
    --tags "Key=Name,Value=${PROJECT}-private-rt"

  aws ec2 create-route \
    --route-table-id "$RT_PRIV" \
    --destination-cidr-block "0.0.0.0/0" \
    --nat-gateway-id "$NAT_ID"

  aws ec2 associate-route-table --route-table-id "$RT_PRIV" --subnet-id "$SUBNET_PRIV_1"
  aws ec2 associate-route-table --route-table-id "$RT_PRIV" --subnet-id "$SUBNET_PRIV_2"
  ok "Route Table privada: $RT_PRIV -> $NAT_ID"

  save_state
}

# ---------------------------------------------------------------------------
# PASO 6 - Security Group
# Concepto: firewall stateful a nivel de instancia (no de subnet).
#           Solo egress abierto: instancia privada, acceso por SSM.
#           SSM no necesita inbound SSH (puerto 22).
# ---------------------------------------------------------------------------
step_06_sg() {
  log "PASO 6: Crear Security Group para EC2 privada"

  SG_ID=$(aws ec2 create-security-group \
    --group-name "${PROJECT}-private-ec2-sg" \
    --description "SG para EC2 en subnet privada (solo egress)" \
    --vpc-id "$VPC_ID" \
    --query 'GroupId' --output text)
  aws ec2 create-tags --resources "$SG_ID" \
    --tags "Key=Name,Value=${PROJECT}-private-ec2-sg"

  # Solo egress: SSM no necesita inbound
  # El inbound ya esta denegado por default (no agregamos reglas ingress)
  ok "Security Group: $SG_ID (solo egress abierto)"
  save_state
}

# ---------------------------------------------------------------------------
# IAM para Session Manager (EC2)
# Crea rol de confianza ec2.amazonaws.com + AmazonSSMManagedInstanceCore
# y un instance profile con el mismo prefijo ${PROJECT}-private-ec2-ssm.
# Idempotente: si ya existen, no falla.
# ---------------------------------------------------------------------------
ensure_ssm_ec2_role_and_profile() {
  log "IAM: Rol + instance profile para SSM (AmazonSSMManagedInstanceCore)"
  local policy_arn="arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

  if aws iam get-role --role-name "$SSM_ROLE_NAME" &>/dev/null; then
    ok "Rol ya existe: $SSM_ROLE_NAME"
  else
    aws iam create-role \
      --role-name "$SSM_ROLE_NAME" \
      --description "Lab 01 VPC - EC2 Session Manager" \
      --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam attach-role-policy \
      --role-name "$SSM_ROLE_NAME" \
      --policy-arn "$policy_arn"
    ok "Rol creado: $SSM_ROLE_NAME + AmazonSSMManagedInstanceCore"
  fi

  if ! aws iam list-attached-role-policies --role-name "$SSM_ROLE_NAME" --output json |
    grep -q 'AmazonSSMManagedInstanceCore'; then
    aws iam attach-role-policy \
      --role-name "$SSM_ROLE_NAME" \
      --policy-arn "$policy_arn"
    ok "Politica AmazonSSMManagedInstanceCore adjuntada al rol"
  fi

  if aws iam get-instance-profile --instance-profile-name "$SSM_INSTANCE_PROFILE_NAME" &>/dev/null; then
    ok "Instance profile ya existe: $SSM_INSTANCE_PROFILE_NAME"
  else
    aws iam create-instance-profile --instance-profile-name "$SSM_INSTANCE_PROFILE_NAME"
    aws iam add-role-to-instance-profile \
      --instance-profile-name "$SSM_INSTANCE_PROFILE_NAME" \
      --role-name "$SSM_ROLE_NAME"
    ok "Instance profile creado: $SSM_INSTANCE_PROFILE_NAME"
  fi

  # Propagacion IAM antes de asociar a una nueva EC2
  log "Esperando propagacion IAM (~10s)..."
  sleep 10
}

# Opcional: crear solo el rol/perfil SSM (sin lanzar EC2)
step_06b_ssm_iam() {
  ensure_ssm_ec2_role_and_profile
}

# ---------------------------------------------------------------------------
# PASO 7 - EC2 privada (opcional)
# Concepto: lanzar una t2.micro barata en la subnet privada 1.
#           Crea (si hace falta) rol IAM + instance profile para Session Manager.
# ---------------------------------------------------------------------------
step_07_ec2() {
  log "PASO 7: Lanzar EC2 t2.micro en subnet privada (IAM para SSM)"

  ensure_ssm_ec2_role_and_profile

  # Buscar la ultima Amazon Linux 2 disponible en la region
  local ami_id
  ami_id=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text \
    --region "$REGION")

  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$ami_id" \
    --instance-type t2.micro \
    --subnet-id "$SUBNET_PRIV_1" \
    --security-group-ids "$SG_ID" \
    --iam-instance-profile "Name=$SSM_INSTANCE_PROFILE_NAME" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${PROJECT}-private-ec2}]" \
    --query 'Instances[0].InstanceId' \
    --output text \
    --region "$REGION")

  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

  ok "EC2 privada lanzada: $INSTANCE_ID (t2.micro, Amazon Linux 2, SSM: $SSM_INSTANCE_PROFILE_NAME)"
  log "Conectar con: aws ssm start-session --target $INSTANCE_ID"
  save_state
}

# ---------------------------------------------------------------------------
# VERIFICACION - resumen de recursos y validacion de rutas
# ---------------------------------------------------------------------------
verify() {
  # Intentar cargar estado si las variables estan vacias
  [[ -z "$VPC_ID" ]] && load_state

  log "VERIFICACION: Resumen de recursos creados"
  echo ""
  echo "  VPC:              ${VPC_ID:-(no creada)}"
  echo "  Subnet publica 1: ${SUBNET_PUB_1:-(no creada)}  ($PUB_CIDR_1 / $AZ1)"
  echo "  Subnet publica 2: ${SUBNET_PUB_2:-(no creada)}  ($PUB_CIDR_2 / $AZ2)"
  echo "  Subnet privada 1: ${SUBNET_PRIV_1:-(no creada)} ($PRIV_CIDR_1 / $AZ1)"
  echo "  Subnet privada 2: ${SUBNET_PRIV_2:-(no creada)} ($PRIV_CIDR_2 / $AZ2)"
  echo "  IGW:              ${IGW_ID:-(no creado)}"
  echo "  EIP Alloc:        ${EIP_ALLOC:-(no creada)}"
  echo "  NAT Gateway:      ${NAT_ID:-(no creado)}"
  echo "  RT Publica:       ${RT_PUB:-(no creada)}"
  echo "  RT Privada:       ${RT_PRIV:-(no creada)}"
  echo "  Security Group:   ${SG_ID:-(no creado)}"
  [[ -n "$INSTANCE_ID" ]] && echo "  EC2 privada:      $INSTANCE_ID"
  [[ -n "$WEB_INSTANCE_ID" ]] && echo "  EC2 web:          $WEB_INSTANCE_ID"
  [[ -n "$SG_WEB" ]] && echo "  SG Web:           $SG_WEB"
  echo "  IAM SSM profile:  $SSM_INSTANCE_PROFILE_NAME"
  echo ""

  if [[ -n "$RT_PRIV" ]]; then
    echo "  Rutas en RT privada:"
    aws ec2 describe-route-tables \
      --route-table-ids "$RT_PRIV" \
      --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,NatGatewayId,State]' \
      --output table
  fi
}

# ---------------------------------------------------------------------------
# RUN ALL - ejecuta todos los pasos en orden (solo red, sin EC2)
# ---------------------------------------------------------------------------
run_all() {
  step_01_vpc
  step_02_subnets
  step_03_igw
  step_04_nat
  step_05_routes
  step_06_sg
  verify
  log "Lab 01 VPC completo via CLI."
  log "Estado guardado en: $STATE_FILE"
  log "Para destruir ejecuta: cleanup"
}

# ---------------------------------------------------------------------------
# CLEANUP - borra todo en orden inverso (dependencias inversas)
# IMPORTANTE: el NAT GW y la EIP generan costo si los dejas corriendo.
# ---------------------------------------------------------------------------
cleanup() {
  log "CLEANUP: Eliminando recursos del Lab 01 VPC"

  # Cargar estado si las variables estan vacias
  [[ -z "$VPC_ID" ]] && load_state

  # EC2 web publica (si existe)
  if [[ -n "$WEB_INSTANCE_ID" ]]; then
    aws ec2 terminate-instances --instance-ids "$WEB_INSTANCE_ID"
    aws ec2 wait instance-terminated --instance-ids "$WEB_INSTANCE_ID"
    ok "EC2 web terminada: $WEB_INSTANCE_ID"
  fi

  # Instancia EC2 privada (si existe)
  if [[ -n "$INSTANCE_ID" ]]; then
    aws ec2 terminate-instances --instance-ids "$INSTANCE_ID"
    aws ec2 wait instance-terminated --instance-ids "$INSTANCE_ID"
    ok "EC2 privada terminada: $INSTANCE_ID"
  fi

  # IAM: instance profile + rol SSM del lab (solo si existen)
  if aws iam get-instance-profile --instance-profile-name "$SSM_INSTANCE_PROFILE_NAME" &>/dev/null; then
    aws iam remove-role-from-instance-profile \
      --instance-profile-name "$SSM_INSTANCE_PROFILE_NAME" \
      --role-name "$SSM_ROLE_NAME" 2>/dev/null || true
    aws iam delete-instance-profile \
      --instance-profile-name "$SSM_INSTANCE_PROFILE_NAME" && ok "Instance profile SSM eliminado: $SSM_INSTANCE_PROFILE_NAME"
  fi
  if aws iam get-role --role-name "$SSM_ROLE_NAME" &>/dev/null; then
    aws iam detach-role-policy \
      --role-name "$SSM_ROLE_NAME" \
      --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
    aws iam delete-role --role-name "$SSM_ROLE_NAME" && ok "Rol SSM eliminado: $SSM_ROLE_NAME"
  fi

  # SG web (si existe)
  [[ -n "$SG_WEB" ]] && \
    aws ec2 delete-security-group --group-id "$SG_WEB" && ok "SG Web eliminado"

  # SG privado
  [[ -n "$SG_ID" ]] && \
    aws ec2 delete-security-group --group-id "$SG_ID" && ok "SG eliminado"

  # Route Tables (desasociar primero, luego eliminar)
  for RT in "$RT_PUB" "$RT_PRIV"; do
    if [[ -n "$RT" ]]; then
      ASSOC_IDS=$(aws ec2 describe-route-tables \
        --route-table-ids "$RT" \
        --query 'RouteTables[0].Associations[?Main==`false`].RouteTableAssociationId' \
        --output text 2>/dev/null || echo "")
      for id in $ASSOC_IDS; do
        [[ "$id" != "None" ]] && aws ec2 disassociate-route-table --association-id "$id"
      done
      aws ec2 delete-route-table --route-table-id "$RT" && ok "RT eliminada: $RT"
    fi
  done

  # NAT Gateway (tarda ~1 min en eliminarse)
  if [[ -n "$NAT_ID" ]]; then
    aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID"
    log "Esperando que NAT Gateway se elimine (~60s)..."
    aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID"
    ok "NAT Gateway eliminado"
  fi

  # EIP (liberar despues del NAT GW)
  [[ -n "$EIP_ALLOC" ]] && \
    aws ec2 release-address --allocation-id "$EIP_ALLOC" && ok "EIP liberada"

  # IGW (detach antes de delete)
  if [[ -n "$IGW_ID" && -n "$VPC_ID" ]]; then
    aws ec2 detach-internet-gateway \
      --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID"
    aws ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID"
    ok "IGW eliminado"
  fi

  # Subnets
  for sn in "$SUBNET_PUB_1" "$SUBNET_PUB_2" "$SUBNET_PRIV_1" "$SUBNET_PRIV_2"; do
    [[ -n "$sn" ]] && aws ec2 delete-subnet --subnet-id "$sn" && ok "Subnet eliminada: $sn"
  done

  # VPC al final (cuando ya no tiene dependencias)
  [[ -n "$VPC_ID" ]] && \
    aws ec2 delete-vpc --vpc-id "$VPC_ID" && ok "VPC eliminada"

  # Limpiar archivo de estado
  [[ -f "$STATE_FILE" ]] && rm -f "$STATE_FILE" && ok "Archivo de estado eliminado"

  log "Cleanup completo. Sin recursos huerfanos."
}

# ---------------------------------------------------------------------------
# ENTRY POINT
# Si ejecutas el script directamente: bash commands.sh -> corre todo
# Si lo sourceas: source commands.sh -> puedes llamar cada funcion sola
# ---------------------------------------------------------------------------
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  run_all
fi