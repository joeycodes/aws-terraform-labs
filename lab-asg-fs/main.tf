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
  public_key = file("${path.module}/id_ed25519_lab_asg.pub")
}


# ----------------------------------------------------------------------------
# Create VPC, subnets, IGW, route table, and associate them
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

# Create subnet 03
resource "aws_subnet" "demo03" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.168.3.0/24"
  availability_zone       = "ca-central-1d" # change to your AZ
  map_public_ip_on_launch = true            # auto-assign public IPs to instances in this subnet

  tags = {
    Name = "my-demo-subnet-03"
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

resource "aws_route_table_association" "demo03" {
  subnet_id      = aws_subnet.demo03.id
  route_table_id = aws_route_table.demo.id
}

# ----------------------------------------------------------------------------
# Create ALB, and associate them with the subnets
# ----------------------------------------------------------------------------

### Create ALB itself
resource "aws_lb" "demo" {
  name               = "my-demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id] # add security group IDs here if needed
  subnets            = [aws_subnet.demo01.id, aws_subnet.demo02.id, aws_subnet.demo03.id]

  tags = {
    Name = "my-demo-alb"
  }
}

### Create a target group for the ALB
resource "aws_lb_target_group" "demo" {
  name     = "my-demo-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.demo.id
}

### Create a listener for the ALB that forwards to the target group
resource "aws_lb_listener" "demo" {
  load_balancer_arn = aws_lb.demo.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.demo.arn
  }

}


# ### Attach the EC2 instances to the target group (done after instance creation)
# resource "aws_lb_target_group_attachment" "demo01" {
#   target_group_arn = aws_lb_target_group.demo.arn
#   target_id        = aws_instance.demo01.id
#   port             = 80
# }

# resource "aws_lb_target_group_attachment" "demo02" {
#   target_group_arn = aws_lb_target_group.demo.arn
#   target_id        = aws_instance.demo02.id
#   port             = 80
# }

# resource "aws_lb_target_group_attachment" "demo03" {
#   target_group_arn = aws_lb_target_group.demo.arn
#   target_id        = aws_instance.demo03.id
#   port             = 80
# }


# ----------------------------------------------------------------------------
# Create NACL and associate it with the subnets
# ----------------------------------------------------------------------------

resource "aws_network_acl" "demo" {
  vpc_id = aws_vpc.demo.id

  tags = {
    Name = "my-demo-nacl"
  }

  # Ingress rule: allow ANY traffic from anywhere
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

resource "aws_network_acl_association" "demo03" {
  subnet_id      = aws_subnet.demo03.id
  network_acl_id = aws_network_acl.demo.id
}

# ----------------------------------------------------------------------------
# Security groups
# ----------------------------------------------------------------------------

### For the ALB
resource "aws_security_group" "alb_sg" {
  name        = "my-demo-alb-sg"
  description = "Allow HTTP traffic to ALB"
  vpc_id      = aws_vpc.demo.id

  ingress {
    from_port   = 80
    to_port     = 80
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

### For the instances
resource "aws_security_group" "instance_sg" {
  name        = "my-demo-instance-sg"
  description = "Allow traffic from ALB to instances"
  vpc_id      = aws_vpc.demo.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
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
# Create ASG and associate it with the target group
# ----------------------------------------------------------------------------

resource "aws_autoscaling_group" "demo" {
  name                = "my-demo-asg"
  max_size            = 3
  min_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = [aws_subnet.demo01.id, aws_subnet.demo02.id, aws_subnet.demo03.id]
  launch_template {
    id      = aws_launch_template.demo.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.demo.arn]

  ## Health check settings (optional, but recommended for better integration with ALB)
  health_check_type = "ELB"

}

### target tracking policy to keep 1 healthy instance running, and scale out if CPU > 40%
resource "aws_autoscaling_policy" "cpu_scale_out" {
  name                   = "my-demo-cpu-scale-out"
  autoscaling_group_name = aws_autoscaling_group.demo.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 40.0
  }
}

# ----------------------------------------------------------------------------
## Launch template for ASG
# ----------------------------------------------------------------------------

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_launch_template" "demo" {
  name_prefix   = "my-demo-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.demo.key_name

  network_interfaces {
    security_groups             = [aws_security_group.instance_sg.id]
    associate_public_ip_address = true
  }

  user_data = base64encode(<<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html
              EOF
  )

  tags = {
    Name = "my-demo-asg-instance"
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

output "subnet03" {
  description = "Details of my-demo-subnet-03"
  value = {
    id                = aws_subnet.demo03.id
    cidr_block        = aws_subnet.demo03.cidr_block
    availability_zone = aws_subnet.demo03.availability_zone
  }
}


output "all_subnet_ids" {
  description = "Every subnet ID in the VPC"
  value       = data.aws_subnets.all.ids
}

### Output ALB details
output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.demo.dns_name
}