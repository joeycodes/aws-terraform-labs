###############################################################################
# PrivateLink Lab - 基础配置
#
# 这份配置搭好:
#   Provider VPC (10.0.0.0/16):  1x EC2(Nginx) + Internal NLB + Endpoint Service
#   Consumer VPC (10.1.0.0/16):  1x 测试 EC2
#
# 两台 EC2 都有公网 IP + SSH,方便你直接进去操作(不折腾 SSM)。
#
# 需要你在 CONSOLE 手动完成的部分(故意留白给你练手):
#   在 Consumer VPC 里创建 Interface Endpoint,指向 output 里给出的
#   endpoint_service_name,然后 curl 验证。
###############################################################################

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ca-west-1" # change to your region
}

### Upload public key for EC2 instance access (replace with your own public key)
resource "aws_key_pair" "lab" {
  key_name   = "my-demo-key"
  public_key = file("${path.module}/id_ed25519_private_link.pub")
}


###############################################################################
# 最新 Amazon Linux 2023 AMI
###############################################################################
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}


###############################################################################
# ============ PROVIDER VPC ============
###############################################################################
resource "aws_vpc" "provider" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "pl-provider-vpc" }
}

resource "aws_internet_gateway" "provider" {
  vpc_id = aws_vpc.provider.id
  tags   = { Name = "pl-provider-igw" }
}

# 两个子网(不同 AZ),NLB 要求至少覆盖服务所在 AZ
resource "aws_subnet" "provider_a" {
  vpc_id                  = aws_vpc.provider.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "pl-provider-subnet-a" }
}

resource "aws_subnet" "provider_b" {
  vpc_id                  = aws_vpc.provider.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags                    = { Name = "pl-provider-subnet-b" }
}

resource "aws_route_table" "provider" {
  vpc_id = aws_vpc.provider.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.provider.id
  }
  tags = { Name = "pl-provider-rt" }
}

resource "aws_route_table_association" "provider_a" {
  subnet_id      = aws_subnet.provider_a.id
  route_table_id = aws_route_table.provider.id
}

resource "aws_route_table_association" "provider_b" {
  subnet_id      = aws_subnet.provider_b.id
  route_table_id = aws_route_table.provider.id
}

# 后端 EC2 的安全组:允许 SSH(你的IP) + 80(VPC内网,给NLB探活/转发)
resource "aws_security_group" "provider_ec2" {
  name        = "pl-provider-ec2-sg"
  description = "Provider backend EC2"
  vpc_id      = aws_vpc.provider.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP from within provider VPC (NLB)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.provider.cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "pl-provider-ec2-sg" }
}

# 后端服务:一个返回主机名的 Nginx
resource "aws_instance" "provider_backend" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.provider_a.id
  vpc_security_group_ids = [aws_security_group.provider_ec2.id]
  key_name               = aws_key_pair.lab.key_name

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    echo "Hello from Provider via PrivateLink! host=$(hostname -i)" > /usr/share/nginx/html/index.html
    systemctl enable --now nginx
  EOF

  tags = { Name = "pl-provider-backend" }
}

# Internal NLB
resource "aws_lb" "provider" {
  name               = "pl-provider-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = [aws_subnet.provider_a.id, aws_subnet.provider_b.id]
  tags               = { Name = "pl-provider-nlb" }
}

resource "aws_lb_target_group" "provider" {
  name        = "pl-provider-tg"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.provider.id
  target_type = "instance"

  health_check {
    protocol = "TCP"
    port     = "80"
  }
  tags = { Name = "pl-provider-tg" }
}

resource "aws_lb_target_group_attachment" "provider" {
  target_group_arn = aws_lb_target_group.provider.arn
  target_id        = aws_instance.provider_backend.id
  port             = 80
}

resource "aws_lb_listener" "provider" {
  load_balancer_arn = aws_lb.provider.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.provider.arn
  }
}

# # ===== Endpoint Service(PrivateLink 的核心)=====
# resource "aws_vpc_endpoint_service" "provider" {
#   acceptance_required        = true          # 实验里手动 accept,看清流程
#   network_load_balancer_arns = [aws_lb.provider.arn]
#   tags                       = { Name = "pl-endpoint-service" }
# }

# # 允许当前账号自己连接(同账号实验必需,否则默认只允许服务owner)
# data "aws_caller_identity" "current" {}

# resource "aws_vpc_endpoint_service_allowed_principal" "self" {
#   vpc_endpoint_service_id = aws_vpc_endpoint_service.provider.id
#   principal_arn           = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
# }

###############################################################################
# ============ CONSUMER VPC ============
###############################################################################
resource "aws_vpc" "consumer" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "pl-consumer-vpc" }
}

resource "aws_internet_gateway" "consumer" {
  vpc_id = aws_vpc.consumer.id
  tags   = { Name = "pl-consumer-igw" }
}

resource "aws_subnet" "consumer" {
  vpc_id                  = aws_vpc.consumer.id
  cidr_block              = "10.1.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "pl-consumer-subnet" }
}

resource "aws_route_table" "consumer" {
  vpc_id = aws_vpc.consumer.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.consumer.id
  }
  tags = { Name = "pl-consumer-rt" }
}

resource "aws_route_table_association" "consumer" {
  subnet_id      = aws_subnet.consumer.id
  route_table_id = aws_route_table.consumer.id
}

# 测试机安全组:SSH(你的IP)。
# 注意:等你在 console 建好 Interface Endpoint 后,endpoint 的安全组
# 需要放行来自这个测试机的 443,那部分你在 console 里配。
resource "aws_security_group" "consumer_ec2" {
  name        = "pl-consumer-ec2-sg"
  description = "Consumer test EC2"
  vpc_id      = aws_vpc.consumer.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "pl-consumer-ec2-sg" }
}

resource "aws_instance" "consumer_test" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.consumer.id
  vpc_security_group_ids = [aws_security_group.consumer_ec2.id]
  key_name               = aws_key_pair.lab.key_name
  tags                   = { Name = "pl-consumer-test" }
}

###############################################################################
# Consumer 侧:Interface Endpoint(PrivateLink 消费端)
###############################################################################

resource "aws_security_group" "consumer_endpoint" {
  name        = "pl-consumer-endpoint-sg"
  description = "For interface endpoint ENI"
  vpc_id      = aws_vpc.consumer.id

  ingress {
    description = "HTTP for interface endpoint (PrivateLink)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.consumer.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "pl-consumer-endpoint-sg" }
}

resource "aws_vpc_endpoint_service" "provider" {
  acceptance_required        = true # ← 改成 false,连接自动接受
  network_load_balancer_arns = [aws_lb.provider.arn]
  tags                       = { Name = "pl-endpoint-service" }
}

# Interface Endpoint 本体
resource "aws_vpc_endpoint" "consumer" {
  vpc_id              = aws_vpc.consumer.id
  service_name        = aws_vpc_endpoint_service.provider.service_name # 引用你的 endpoint service
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.consumer.id]
  security_group_ids  = [aws_security_group.consumer_endpoint.id]
  private_dns_enabled = false # 自建服务没有默认域名,保持 false(和你 console 里看到的 No 一致)

  tags = { Name = "my-lab-private-link-01" }
}

