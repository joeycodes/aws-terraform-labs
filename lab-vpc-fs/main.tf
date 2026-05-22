# ===========================================
# Provider 配置:告诉 Terraform 用 AWS
# ===========================================
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ca-central-1"
}

# 添加在 provider 块下面
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ===========================================
# Key Pair:把本地的公钥上传到 AWS
# ===========================================
resource "aws_key_pair" "demo" {
  key_name   = "myTestKeyPair"
  public_key = file("${path.module}/my-key.pub")  # 读取当前目录的公钥文件

  tags = {
    Name = "myTestKeyPair"
  }
}


# ===========================================
# 1. 创建 VPC
# ===========================================
resource "aws_vpc" "main" {
  cidr_block           = "192.168.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "myTestVPC"
  }
}

# ===========================================
# 2. 创建 Internet Gateway
# ===========================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "myTestIGW01"
  }
}

# ===========================================
# 3. 创建公有子网
# ===========================================
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "192.168.234.0/24"
  availability_zone       = "ca-central-1a"
  map_public_ip_on_launch = true # ← 自动分配公网 IP

  tags = {
    Name = "myTestPublicSubnet"
  }
}

# ===========================================
# 4. 创建路由表 + 添加 IGW 路由
# ===========================================
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "myTestPublicRT"
  }
}

# ===========================================
# 5. 把路由表关联到子网
# ===========================================
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ===========================================
# 6. 创建 Security Group(允许 SSH 和 HTTP)
# ===========================================
resource "aws_security_group" "web" {
  name        = "myTestWebSG"
  description = "Allow SSH and HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # ⚠️ 学习用,生产应限制 IP
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "myTestWebSG"
  }
}

# ===========================================
# 7. 启动一台 EC2
# ===========================================
resource "aws_instance" "web" {
  ami                    = data.aws_ami.amazon_linux_2023.id # Amazon Linux 2023 in ca-central-1
  instance_type          = "t3.micro"                        # Free Tier
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = aws_key_pair.demo.key_name

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Hello from Terraform!</h1>" > /var/www/html/index.html
  EOF

  tags = {
    Name = "myTestWebServer"
  }
}

# ===========================================
# 8. 输出关键信息
# ===========================================
output "vpc_id" {
  value = aws_vpc.main.id
}

output "instance_public_ip" {
  value = aws_instance.web.public_ip
}

output "ssh_command" {
  value = "ssh -i ./my-key ec2-user@${aws_instance.web.public_ip}"
}

output "web_url" {
  value = "http://${aws_instance.web.public_ip}"
}