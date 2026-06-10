# ----------------------------------------------------------------------------
# VPC
# ----------------------------------------------------------------------------

# Create VPC, looked up by its Name tag - Canada
resource "aws_vpc" "demo" {
  cidr_block = "10.168.0.0/16"

  tags = {
    Name = "my-demo-vpc"
  }
}

# ----------------------------------------------------------------------------
# Subnets
# ----------------------------------------------------------------------------

# Create subnet, scoped to the VPC above and matched by Name tag
resource "aws_subnet" "demo01" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.168.1.0/24"
  availability_zone       = "ca-west-1a" # change to your AZ
  map_public_ip_on_launch = true         # auto-assign public IPs to instances in this subnet

  tags = {
    Name = "my-demo-subnet-01"
  }
}

resource "aws_subnet" "demo02" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.168.2.0/24"
  availability_zone       = "ca-west-1b" # change to your AZ
  map_public_ip_on_launch = true         # auto-assign public IPs to instances in this subnet

  tags = {
    Name = "my-demo-subnet-02"
  }
}

resource "aws_subnet" "demo03" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.168.3.0/24"
  availability_zone       = "ca-west-1c" # change to your AZ
  map_public_ip_on_launch = true         # auto-assign public IPs to instances in this subnet

  tags = {
    Name = "my-demo-subnet-03"
  }
}


# ----------------------------------------------------------------------------
# IGW and route table, and associate them with the subnets
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
# NACL and associate it with the subnets
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

resource "aws_network_acl_association" "demo03" {
  subnet_id      = aws_subnet.demo03.id
  network_acl_id = aws_network_acl.demo.id
}

# ----------------------------------------------------------------------------
# Create ALB, and associate them with the subnets
# ----------------------------------------------------------------------------

### Create ALB itself
resource "aws_lb" "demo" {
  name               = "my-demo-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.demo_ecs_alb.id] # add security group IDs here if needed
  subnets            = [aws_subnet.demo01.id, aws_subnet.demo02.id, aws_subnet.demo03.id]

  tags = {
    Name = "my-demo-ecs-alb"
  }
}

### Create a target group for the ALB
resource "aws_lb_target_group" "demo" {
  name        = "my-demo-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.demo.id
  target_type = "ip"

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
# ECS Cluster
# ----------------------------------------------------------------------------
resource "aws_ecs_cluster" "demo" {
  name = "${var.project}-cluster"

  # setting {
  #   name  = "containerInsights"
  #   value = "disabled"
  # }
}

# ----------------------------------------------------------------------------
# IAM Role
# ----------------------------------------------------------------------------
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "demo_task_execution" {
  name               = "${var.project}-task-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "demo_task_execution" {
  role       = aws_iam_role.demo_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}


# ----------------------------------------------------------------------------
# Security group
# ----------------------------------------------------------------------------
resource "aws_security_group" "demo_ecs_alb" {
  name        = "my-demo-ecs-alb-sg"
  description = "Allow traffic from anywhere to ECS ALB"
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

resource "aws_security_group" "demo_ecs_tasks" {
  name        = "my-demo-ecs-tasks-sg"
  description = "Allow traffic from ALB to ECS tasks"
  vpc_id      = aws_vpc.demo.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.demo_ecs_alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ----------------------------------------------------------------------------
# ECS Task Definition
# ----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "demo_fargate" {
  family                   = "${var.project}-fargate-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.demo_task_execution.arn

  cpu    = 256
  memory = 512

  container_definitions = jsonencode([{
    name  = "nginx-hello"
    image = "nginxdemos/hello"
    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]
  }])
}


# ----------------------------------------------------------------------------
# ECS Service
# ----------------------------------------------------------------------------
resource "aws_ecs_service" "fargate" {
  name            = "${var.project}-fargate-svc"
  cluster         = aws_ecs_cluster.demo.id
  task_definition = aws_ecs_task_definition.demo_fargate.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.demo01.id, aws_subnet.demo02.id, aws_subnet.demo03.id]
    security_groups  = [aws_security_group.demo_ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.demo.arn
    container_name   = "nginx-hello"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.demo]
}