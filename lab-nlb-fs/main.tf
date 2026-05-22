# ----------------------------------------------------------------------------
# Provider
# ----------------------------------------------------------------------------
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
  region = "ca-central-1" # change to your region
}

### Upload public key for EC2 instance access (replace with your own public key)
resource "aws_key_pair" "demo" {
  key_name   = "my-demo-key"
  public_key = file("${path.module}/id_ed25519.pub")

  tags = {
    Name = "my-demo-key"
  }
}


# ----------------------------------------------------------------------------
# Data sources: Create infrastructure (read-only, not created)
# ----------------------------------------------------------------------------

# Create VPC, looked up by its Name tag
resource "aws_vpc" "demo" {

  cidr_block = "10.168.0.0/16"

  tags = {
    Name = "my-demo-vpc"
  }
}

# Create subnet 01, scoped to the VPC above and matched by Name tag
resource "aws_subnet" "demo01" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.168.1.0/24"
  availability_zone       = "ca-central-1a" # change to your AZ
  map_public_ip_on_launch = true            # auto-assign public IPs to instances in this subnet

  tags = {
    Name = "my-demo-subnet-01"
  }
}

# Create subnet 02
resource "aws_subnet" "demo02" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.168.2.0/24"
  availability_zone       = "ca-central-1b" # change to your AZ
  map_public_ip_on_launch = true            # auto-assign public IPs to instances in this subnet

  tags = {
    Name = "my-demo-subnet-02"
  }
}

# (Optional) Grab ALL subnets in the VPC at once — handy if you have many
data "aws_subnets" "all" {
  depends_on = [aws_vpc.demo]

  filter {
    name   = "vpc-id"
    values = [aws_vpc.demo.id]
  }
}

# ----------------------------------------------------------------------------
# Create IGW and route table, and associate them with the subnets
# ----------------------------------------------------------------------------

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id

  tags = {
    Name = "my-demo-igw"
  }
}

resource "aws_route_table" "demo" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }
}

resource "aws_route_table_association" "demo01" {
  subnet_id      = aws_subnet.demo01.id
  route_table_id = aws_route_table.demo.id
}

resource "aws_route_table_association" "demo02" {
  subnet_id      = aws_subnet.demo02.id
  route_table_id = aws_route_table.demo.id
}


# ----------------------------------------------------------------------------
# Create NLB, and associate them with the subnets
# ----------------------------------------------------------------------------

### Create NLB itself
resource "aws_lb" "demo" {
  name               = "my-demo-nlb"
  internal           = false
  load_balancer_type = "network"
#   security_groups    = [aws_security_group.nlb_sg.id] # add security group IDs here if needed
  subnets            = [aws_subnet.demo01.id, aws_subnet.demo02.id]

  tags = {
    Name = "my-demo-nlb"
  }
}

### Create a target group for the NLB
resource "aws_lb_target_group" "demo" {
  name     = "my-demo-tg"
  port     = 80
  protocol = "TCP"
  vpc_id   = aws_vpc.demo.id
}

### Create a listener for the NLB that forwards to the target group
resource "aws_lb_listener" "demo" {
  load_balancer_arn = aws_lb.demo.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo.arn
  }

}

## condition action for listener (optional, for more complex routing rules)
# resource "aws_lb_listener_rule" "error" {
#   listener_arn = aws_lb_listener.demo.arn
#   priority     = 10

#   action {
#     type             = "fixed-response"
#     fixed_response {
#       content_type = "text/plain"
#       message_body = "<h1>404 - Page Not Found</h1>"
#       status_code  = "404"
#     }
#   }

#   condition {
#     path_pattern {
#       values = ["/error"]
#     }
#   }
# }

### Attach the EC2 instances to the target group (done after instance creation)
resource "aws_lb_target_group_attachment" "demo01" {
  target_group_arn = aws_lb_target_group.demo.arn
  target_id        = aws_instance.demo01.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "demo02" {
  target_group_arn = aws_lb_target_group.demo.arn
  target_id        = aws_instance.demo02.id
  port             = 80
}


# ----------------------------------------------------------------------------
# Create NACL and associate it with the subnets
# ----------------------------------------------------------------------------

resource "aws_network_acl" "demo" {
  vpc_id = aws_vpc.demo.id

  tags = {
    Name = "my-demo-nacl"
  }

  # Ingress rule: allow HTTP traffic from anywhere
  ingress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    from_port  = 0
    to_port    = 0
    cidr_block = "0.0.0.0/0"
  }

  # Egress rule: allow all outbound traffic
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    from_port  = 0
    to_port    = 0
    cidr_block = "0.0.0.0/0"
  }
}

resource "aws_network_acl_association" "demo01" {
  subnet_id      = aws_subnet.demo01.id
  network_acl_id = aws_network_acl.demo.id
}

resource "aws_network_acl_association" "demo02" {
  subnet_id      = aws_subnet.demo02.id
  network_acl_id = aws_network_acl.demo.id
}

# ----------------------------------------------------------------------------
# Security groups
# ----------------------------------------------------------------------------

### For the NLB
# resource "aws_security_group" "nlb_sg" {
#   name        = "my-demo-nlb-sg"
#   description = "Allow HTTP traffic to NLB"
#   vpc_id      = aws_vpc.demo.id

#   ingress {
#     from_port   = 80
#     to_port     = 80
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#   }
# }

### For the instances
resource "aws_security_group" "instance_sg" {
  name        = "my-demo-instance-sg"
  description = "Allow traffic from NLB to instances"
  vpc_id      = aws_vpc.demo.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow from anywhere, or specify the NLB SG ID for tighter security
  }

  ingress {
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
}

# ----------------------------------------------------------------------------
# Create EC2 instances and register them with the target group
# ----------------------------------------------------------------------------

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "demo01" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.demo01.id
  vpc_security_group_ids      = [aws_security_group.instance_sg.id]
  key_name                    = aws_key_pair.demo.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from demo01</h1>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "my-demo-instance-01"
  }
}

resource "aws_instance" "demo02" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.demo02.id
  vpc_security_group_ids      = [aws_security_group.instance_sg.id]
  key_name                    = aws_key_pair.demo.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from demo02</h1>" > /var/www/html/index.html
              EOF

  tags = {
    Name = "my-demo-instance-02"
  }
}


# ----------------------------------------------------------------------------
# Outputs
# ----------------------------------------------------------------------------

output "vpc_id" {
  description = "ID of the existing VPC"
  value       = aws_vpc.demo.id
}

output "vpc_cidr" {
  description = "CIDR block of the existing VPC"
  value       = aws_vpc.demo.cidr_block
}

output "subnet01" {
  description = "Details of my-demo-subnet-01"
  value = {
    id                = aws_subnet.demo01.id
    cidr_block        = aws_subnet.demo01.cidr_block
    availability_zone = aws_subnet.demo01.availability_zone
  }
}

output "subnet02" {
  description = "Details of my-demo-subnet-02"
  value = {
    id                = aws_subnet.demo02.id
    cidr_block        = aws_subnet.demo02.cidr_block
    availability_zone = aws_subnet.demo02.availability_zone
  }
}

output "all_subnet_ids" {
  description = "Every subnet ID in the VPC"
  value       = data.aws_subnets.all.ids
}

### Output NLB details
output "nlb_dns_name" {
  description = "DNS name of the NLB"
  value       = aws_lb.demo.dns_name
}