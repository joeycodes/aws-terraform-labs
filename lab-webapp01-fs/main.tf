### Upload public key for EC2 instance access (replace with your own public key)
resource "aws_key_pair" "demo" {
  key_name   = "my-demo-key"
  public_key = file("${path.module}/id_ed25519.pub")
}

# ----------------------------------------------------------------------------
# Data sources: Create infrastructure (read-only, not created)
# ----------------------------------------------------------------------------

# Create VPC, looked up by its Name tag - Canada
resource "aws_vpc" "demo" {
  cidr_block = "10.168.0.0/16"

  tags = {
    Name = "my-demo-vpc"
  }
}

# Create subnet, scoped to the VPC above and matched by Name tag
resource "aws_subnet" "demo01" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.168.1.0/24"
  availability_zone       = "ca-west-1a" # change to your AZ
  map_public_ip_on_launch = true            # auto-assign public IPs to instances in this subnet

  tags = {
    Name = "my-demo-subnet-01"
  }
}

resource "aws_subnet" "demo02" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.168.2.0/24"
  availability_zone       = "ca-west-1b" # change to your AZ
  map_public_ip_on_launch = true            # auto-assign public IPs to instances in this subnet

  tags = {
    Name = "my-demo-subnet-02"
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


### For the instances
resource "aws_security_group" "demo_instance" {
  name        = "my-demo-instance-sg"
  description = "Allow traffic from anywhere to instances"
  vpc_id      = aws_vpc.demo.id

  ingress {
    from_port = 80
    to_port   = 80
    protocol  = "tcp"
    ## only allow HTTP traffic from the ALB security group
    security_groups = [aws_security_group.demo_alb.id]
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

## For the ALB
resource "aws_security_group" "demo_alb" {
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
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ----------------------------------------------------------------------------
# Create ALB, and associate them with the subnets
# ----------------------------------------------------------------------------

### Create ALB itself
resource "aws_lb" "demo" {
  name               = "my-demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.demo_alb.id] # add security group IDs here if needed
  subnets            = [aws_subnet.demo01.id, aws_subnet.demo02.id]

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

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    matcher             = "200"
  }
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

# ----------------------------------------------------------------------------
# Create ASG and associate it with the target group
# ----------------------------------------------------------------------------

resource "aws_autoscaling_group" "demo" {
  name                = "my-demo-asg"
  max_size            = 4
  min_size            = 2
  desired_capacity    = 2
  vpc_zone_identifier = [aws_subnet.demo01.id, aws_subnet.demo02.id]
  launch_template {
    id      = aws_launch_template.demo.id
    version = "$Latest"
  }
  target_group_arns = [aws_lb_target_group.demo.arn]

  ## Health check settings (optional, but recommended for better integration with ALB)
  health_check_type         = "ELB"
  health_check_grace_period = 300

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

data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_launch_template" "demo" {
  name_prefix   = "my-demo-lt-"
  image_id      = data.aws_ssm_parameter.al2023.value
  instance_type = "t3.micro"
  key_name      = aws_key_pair.demo.key_name

  network_interfaces {
    security_groups             = [aws_security_group.demo_instance.id]
    associate_public_ip_address = true
  }

  user_data = base64encode(<<-EOF
            #!/bin/bash
            dnf update -y
            dnf install -y httpd
            systemctl start httpd
            systemctl enable httpd
            echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html
            EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "my-demo-asg-instance"
    }
  }
}


# ----------------------------------------------------------------------------
# Route 53
# ----------------------------------------------------------------------------
resource "aws_route53_zone" "demo" {
  name = "mylab.click"
}

resource "aws_route53_record" "demo" {
  zone_id = aws_route53_zone.demo.zone_id
  name    = "app.mylab.click"
  type    = "A"

  alias {
    name                   = aws_lb.demo.dns_name
    zone_id                = aws_lb.demo.zone_id
    evaluate_target_health = true
  }
}


# ----------------------------------------------------------------------------
# Outputs
# ----------------------------------------------------------------------------

output "alb_dns_name" {
  value       = aws_lb.demo.dns_name
  description = "The DNS name of the ALB"
}
