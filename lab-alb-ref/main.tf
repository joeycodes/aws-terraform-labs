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
  public_key = file("${path.module}/my-key.pub") # 读取当前目录的公钥文件

  tags = {
    Name = "myTestKeyPair"
  }
}


# ===========================================
# 1. Reference existing VPC
# ===========================================
data "aws_vpc" "demo" {
  tags = {
    Name = "my-demo-vpc"
  }
}

# ===========================================
# 2. Reference existing Internet Gateway
# ===========================================
data "aws_internet_gateway" "demo" {
  tags = {
    Name = "my-demo-igw"
  }
}

# ===========================================
# 3. Reference existing subnets
# ===========================================
data "aws_subnet" "demo01" {
  vpc_id = data.aws_vpc.demo.id

  tags = {
    Name = "my-demo-subnet-01"
  }
}

data "aws_subnet" "demo02" {
  vpc_id = data.aws_vpc.demo.id

  tags = {
    Name = "my-demo-subnet-02"
  }
}

# ===========================================
# 4. Reference existing route table
# ===========================================
data "aws_route_table" "demo" {
  vpc_id = data.aws_vpc.demo.id

  tags = {
    Name = "my-demo-rt-01"
  }
}

# ===========================================
# Create a new route in an existing route table.
# ===========================================

resource "aws_route" "demo_route" {
  route_table_id         = data.aws_route_table.demo.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = data.aws_internet_gateway.demo.id
}

# ===========================================
# 5. 把路由表关联到子网
# ===========================================
# resource "aws_route_table_association" "public" {
#   subnet_id      = data.aws_subnet.demo01.id
#   route_table_id = data.aws_route_table.demo.id
# }

# ===========================================
# 6. 创建 Security Group(允许 SSH 和 HTTP)
# ===========================================
resource "aws_security_group" "demo_alb" {
  name        = "my-demo-sg-alb"
  description = "Allow HTTP"
  vpc_id      = data.aws_vpc.demo.id

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
    Name = "my-demo-sg"
  }
}

resource "aws_security_group" "demo_ec2" {
  name        = "my-demo-sg-ec2"
  description = "Allow HTTP"
  vpc_id      = data.aws_vpc.demo.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    # 允许 ALB 的安全组访问 EC2 的 80 端口
    security_groups = [aws_security_group.demo_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # all protocols
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ===========================================
# 7. 启动2台 EC2
# ===========================================
locals {
  instances = {
    "01" = data.aws_subnet.demo01.id
    "02" = data.aws_subnet.demo02.id
  }
}

resource "aws_instance" "web" {
  for_each = local.instances

  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = each.value
  vpc_security_group_ids = [aws_security_group.demo_ec2.id]
  key_name               = aws_key_pair.demo.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    yum update -y
    yum install -y httpd
    systemctl start httpd
    systemctl enable httpd
    echo "<h1>Hello from Terraform - ${each.key}!</h1>" > /var/www/html/index.html
  EOF

  tags = {
    Name = "my-demo-web-${each.key}"
  }
}

# ===========================================
# 8. Create an Application Load Balancer
# ===========================================

resource "aws_lb" "demo" {
  name               = "my-demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.demo_alb.id]
  subnets            = [data.aws_subnet.demo01.id, data.aws_subnet.demo02.id]

  tags = {
    Name = "my-demo-alb"
  }
}

resource "aws_lb_target_group" "demo" {
  name     = "my-demo-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.demo.id
}

resource "aws_lb_listener" "demo" {
  load_balancer_arn = aws_lb.demo.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo.arn
  }
}

resource "aws_lb_target_group_attachment" "demo" {
  for_each         = aws_instance.web
  target_group_arn = aws_lb_target_group.demo.arn
  target_id        = each.value.id
  port             = 80
}



# ===========================================
# 8. 输出关键信息
# ===========================================
output "vpc_id" {
  value = data.aws_vpc.demo.id
}

output "alb_dns_name" {
  value = aws_lb.demo.dns_name
}