# Lab 1.3 — Auto Scaling Group con ALB

## Arquitectura

```text
        🌐 Internet
            │
            ▼
    ┌──────────────┐
    │     ALB      │
    │  :80 → TG    │
    └──────┬───────┘
           │
    ┌──────┴───────┐
    │ Target Group │
    │  /health     │
    └──────┬───────┘
           │
     ┌─────┼─────┐
     ▼     ▼     ▼
   ┌───┐ ┌───┐ ┌───┐
   │EC2│ │EC2│ │EC2│    ← Auto Scaling Group
   │ 1 │ │ 2 │ │ 3 │       min=2, max=5
   └───┘ └───┘ └───┘
    AZ-a  AZ-b  AZ-a

   CPU > 60% → Scale Out
   CPU < 30% → Scale In
```

---

## Prerequisitos

```bash
# Usar VPC default si limpiaste la del Lab 1.1
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=isDefault,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text)

SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[*].SubnetId' \
  --output text)

PUBLIC_SUBNET_1=$(echo $SUBNETS | awk '{print $1}')
PUBLIC_SUBNET_2=$(echo $SUBNETS | awk '{print $2}')

echo "VPC: $VPC_ID | Subnet1: $PUBLIC_SUBNET_1 | Subnet2: $PUBLIC_SUBNET_2"
```

---

## Paso 1: Crear Launch Template con user-data

```bash
INSTANCE_SG=$(aws ec2 create-security-group \
  --group-name lab-asg-instance-sg \
  --description "SG para instancias del ASG" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $INSTANCE_SG \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

USER_DATA=$(cat <<'EOF' | base64 -w 0
#!/bin/bash
yum update -y
amazon-linux-extras install nginx1 -y
systemctl start nginx
systemctl enable nginx

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /usr/share/nginx/html/index.html <<HTML
<html><body>
<h1>Lab 1.3 - Auto Scaling Group</h1>
<p><strong>Instance ID:</strong> ${INSTANCE_ID}</p>
<p><strong>Availability Zone:</strong> ${AZ}</p>
</body></html>
HTML

echo "OK" > /usr/share/nginx/html/health
EOF
)

AMI_ID=$(aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
  --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
  --output text)

LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template \
  --launch-template-name lab-asg-template \
  --version-description "v1-nginx" \
  --launch-template-data "{
    \"ImageId\": \"${AMI_ID}\",
    \"InstanceType\": \"t2.micro\",
    \"SecurityGroupIds\": [\"${INSTANCE_SG}\"],
    \"UserData\": \"${USER_DATA}\",
    \"TagSpecifications\": [{
      \"ResourceType\": \"instance\",
      \"Tags\": [{\"Key\": \"Name\", \"Value\": \"lab-asg-instance\"}]
    }]
  }" \
  --query 'LaunchTemplate.LaunchTemplateId' \
  --output text)

echo "Launch Template: $LAUNCH_TEMPLATE_ID ✅"
```

---

## Paso 2: Crear ALB con Target Group

```bash
ALB_SG=$(aws ec2 create-security-group \
  --group-name lab-alb-sg \
  --description "SG para el ALB" \
  --vpc-id $VPC_ID \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG --protocol tcp --port 80 --cidr 0.0.0.0/0

# Instancias solo aceptan tráfico del ALB
aws ec2 revoke-security-group-ingress \
  --group-id $INSTANCE_SG --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress \
  --group-id $INSTANCE_SG --protocol tcp --port 80 --source-group $ALB_SG

ALB_ARN=$(aws elbv2 create-load-balancer \
  --name lab-alb \
  --subnets $PUBLIC_SUBNET_1 $PUBLIC_SUBNET_2 \
  --security-groups $ALB_SG \
  --scheme internet-facing --type application \
  --query 'LoadBalancers[0].LoadBalancerArn' \
  --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns $ALB_ARN \
  --query 'LoadBalancers[0].DNSName' \
  --output text)

echo "ALB DNS: $ALB_DNS"

TG_ARN=$(aws elbv2 create-target-group \
  --name lab-tg \
  --protocol HTTP --port 80 \
  --vpc-id $VPC_ID \
  --health-check-path /health \
  --health-check-interval-seconds 15 \
  --health-check-timeout-seconds 5 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --target-type instance \
  --query 'TargetGroups[0].TargetGroupArn' \
  --output text)

aws elbv2 create-listener \
  --load-balancer-arn $ALB_ARN \
  --protocol HTTP --port 80 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN

echo "ALB + Target Group listos ✅"
```

---

## Paso 3: Crear Auto Scaling Group

```bash
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name lab-asg \
  --launch-template LaunchTemplateId=$LAUNCH_TEMPLATE_ID,Version='$Latest' \
  --min-size 2 --max-size 5 --desired-capacity 2 \
  --vpc-zone-identifier "$PUBLIC_SUBNET_1,$PUBLIC_SUBNET_2" \
  --target-group-arns $TG_ARN \
  --health-check-type ELB \
  --health-check-grace-period 120 \
  --tags "Key=Name,Value=lab-asg-instance,PropagateAtLaunch=true"

echo "ASG creado ✅"

aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names lab-asg \
  --query 'AutoScalingGroups[0].Instances[*].[InstanceId,LifecycleState,HealthStatus]' \
  --output table
```

---

## Paso 4: Crear Scaling Policy (CPU Target Tracking)

```bash
aws autoscaling put-scaling-policy \
  --auto-scaling-group-name lab-asg \
  --policy-name lab-cpu-target-tracking \
  --policy-type TargetTrackingScaling \
  --target-tracking-configuration '{
    "PredefinedMetricSpecification": {
      "PredefinedMetricType": "ASGAverageCPUUtilization"
    },
    "TargetValue": 60.0,
    "ScaleInCooldown": 120,
    "ScaleOutCooldown": 60
  }'

echo "Scaling policy creada ✅"
```

> 💡 **Target Tracking**: le dices "mantén el CPU en 60%" y AWS crea las alarmas de CloudWatch automáticamente.

---

## Paso 5: Probar y simular carga

```bash
sleep 120
curl http://$ALB_DNS

# Verificar load balancing entre instancias
for i in {1..10}; do
  curl -s http://$ALB_DNS | grep "Instance ID"
  sleep 1
done

# Simular carga CPU vía SSM
INSTANCE_ID=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names lab-asg \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
  --output text)

aws ssm send-command \
  --instance-ids $INSTANCE_ID \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["amazon-linux-extras install epel -y","yum install stress -y","stress --cpu 4 --timeout 300"]'

# Observar el escalado en tiempo real
watch -n 10 "aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names lab-asg \
  --query 'AutoScalingGroups[0].[DesiredCapacity,Instances[*].InstanceId]' \
  --output text"
```

---

## 📚 Pregunta de entrevista: Scale Out vs Scale In

```text
┌──────────────────┬───────────────────────────┐
│    SCALE OUT     │       SCALE IN            │
├──────────────────┼───────────────────────────┤
│ Agregar instancias│ Quitar instancias        │
│ CPU > 60%        │ CPU < 30%                 │
│ 2 → 3 → 4 → 5   │ 5 → 4 → 3 → 2            │
│ Cooldown corto   │ Cooldown largo            │
│ (proteger UX)    │ (evitar flapping)         │
└──────────────────┴───────────────────────────┘
```

> "Scale Out es agregar instancias cuando sube la demanda. Scale In es removerlas cuando baja. El Scale Out se configura más agresivo para proteger la experiencia del usuario, mientras que el Scale In es más conservador para evitar *flapping*. Las **termination policies** definen qué instancia se elimina primero (`OldestInstance`, `NewestInstance`, etc.)."

---

## 🧹 Limpieza

```bash
aws autoscaling delete-auto-scaling-group --auto-scaling-group-name lab-asg --force-delete
sleep 120

LISTENER_ARN=$(aws elbv2 describe-listeners \
  --load-balancer-arn $ALB_ARN \
  --query 'Listeners[0].ListenerArn' --output text)
aws elbv2 delete-listener --listener-arn $LISTENER_ARN
aws elbv2 delete-target-group --target-group-arn $TG_ARN
aws elbv2 delete-load-balancer --load-balancer-arn $ALB_ARN
sleep 30

aws ec2 delete-launch-template --launch-template-id $LAUNCH_TEMPLATE_ID
aws ec2 delete-security-group --group-id $ALB_SG
aws ec2 delete-security-group --group-id $INSTANCE_SG

echo "Lab 1.3 limpio ✅"
```

---

> 🏷️ Tags: `aws` `asg` `alb` `auto-scaling` `target-group` `launch-template` `scaling-policy`