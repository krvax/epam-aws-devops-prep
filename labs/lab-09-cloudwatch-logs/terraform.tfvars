aws_region         = "us-east-1"
prefix             = "epam-lab09"
vpc_name           = "epam-lab-vpc"
instance_type      = "t3.micro"
log_group_name     = "/epam/lab/app"
log_retention_days = 3
alert_email        = "krvajal@yahoo.com.mx"
ssh_cidr           = "0.0.0.0/0" # Restringe a tu IP antes de aplicar: x.x.x.x/32
