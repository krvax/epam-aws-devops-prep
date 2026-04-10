#!/bin/bash
yum update -y
amazon-linux-extras install nginx1 -y
amazon-linux-extras install epel -y
yum install stress -y

systemctl start nginx
systemctl enable nginx

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

cat > /usr/share/nginx/html/index.html <<HTML
<html>
<head><title>Lab 1.3 - ASG</title></head>
<body>
  <h1>🖥️ Auto Scaling Group Lab</h1>
  <p><strong>Instance ID:</strong> ${INSTANCE_ID}</p>
  <p><strong>Availability Zone:</strong> ${AZ}</p>
  <p><strong>Timestamp:</strong> $(date)</p>
</body>
</html>
HTML

mkdir -p /usr/share/nginx/html/health
echo "OK" > /usr/share/nginx/html/health/index.html
