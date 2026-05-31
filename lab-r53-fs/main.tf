### Upload public key for EC2 instance access (replace with your own public key)
resource "aws_key_pair" "canada" {
  provider   = aws.canada
  key_name   = "my-demo-key"
  public_key = file("${path.module}/id_ed25519.pub")
}

resource "aws_key_pair" "japan" {
  provider   = aws.japan
  key_name   = "my-demo-key"
  public_key = file("${path.module}/id_ed25519.pub")
}

resource "aws_key_pair" "europe" {
  provider   = aws.europe
  key_name   = "my-demo-key"
  public_key = file("${path.module}/id_ed25519.pub")
}

# ----------------------------------------------------------------------------
# Data sources: Create infrastructure (read-only, not created)
# ----------------------------------------------------------------------------

# Create VPC, looked up by its Name tag - Canada
resource "aws_vpc" "canada" {
  provider = aws.canada

  cidr_block = "10.168.0.0/16"

  tags = {
    Name = "my-demo-vpc"
  }
}

# Create subnet for region canada, scoped to the VPC above and matched by Name tag
resource "aws_subnet" "canada" {
  provider                = aws.canada
  vpc_id                  = aws_vpc.canada.id
  cidr_block              = "10.168.1.0/24"
  availability_zone       = "ca-central-1a" # change to your AZ
  map_public_ip_on_launch = true            # auto-assign public IPs to instances in this subnet

  tags = {
    Name = "my-demo-subnet"
  }
}

# Create VPC, looked up by its Name tag - Japan
resource "aws_vpc" "japan" {
  provider = aws.japan

  cidr_block = "10.169.0.0/16"

  tags = {
    Name = "my-demo-vpc"
  }
}

# Create subnet for region japan, scoped to the VPC above and matched by Name tag
resource "aws_subnet" "japan" {
  provider                = aws.japan
  vpc_id                  = aws_vpc.japan.id
  cidr_block              = "10.169.1.0/24"
  availability_zone       = "ap-northeast-1a" # change to your AZ
  map_public_ip_on_launch = true              # auto-assign public IPs to instances in this subnet

  tags = {
    Name = "my-demo-subnet"
  }
}

# Create VPC, looked up by its Name tag - Europe
resource "aws_vpc" "europe" {
  provider = aws.europe

  cidr_block = "10.170.0.0/16"

  tags = {
    Name = "my-demo-vpc"
  }
}

# Create subnet 01, scoped to the VPC above and matched by Name tag
resource "aws_subnet" "europe" {
  provider                = aws.europe
  vpc_id                  = aws_vpc.europe.id
  cidr_block              = "10.170.1.0/24"
  availability_zone       = "eu-central-1a" # change to your AZ
  map_public_ip_on_launch = true            # auto-assign public IPs to instances in this subnet

  tags = {
    Name = "my-demo-subnet"
  }
}


# ----------------------------------------------------------------------------
# Create IGW and route table, and associate them with the subnets
# ----------------------------------------------------------------------------

resource "aws_internet_gateway" "canada" {
  provider = aws.canada
  vpc_id   = aws_vpc.canada.id

  tags = {
    Name = "my-demo-igw"
  }
}

resource "aws_route_table" "canada" {
  provider = aws.canada
  vpc_id   = aws_vpc.canada.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.canada.id
  }
}

resource "aws_route_table_association" "canada" {
  provider       = aws.canada
  subnet_id      = aws_subnet.canada.id
  route_table_id = aws_route_table.canada.id
}

##  For region japan

resource "aws_internet_gateway" "japan" {
  provider = aws.japan
  vpc_id   = aws_vpc.japan.id

  tags = {
    Name = "my-demo-igw"
  }
}

resource "aws_route_table" "japan" {
  provider = aws.japan
  vpc_id   = aws_vpc.japan.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.japan.id
  }
}

resource "aws_route_table_association" "japan" {
  provider       = aws.japan
  subnet_id      = aws_subnet.japan.id
  route_table_id = aws_route_table.japan.id
}

## For region europe
resource "aws_internet_gateway" "europe" {
  provider = aws.europe
  vpc_id   = aws_vpc.europe.id

  tags = {
    Name = "my-demo-igw"
  }
}

resource "aws_route_table" "europe" {
  provider = aws.europe
  vpc_id   = aws_vpc.europe.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.europe.id
  }
}

resource "aws_route_table_association" "europe" {
  provider       = aws.europe
  subnet_id      = aws_subnet.europe.id
  route_table_id = aws_route_table.europe.id
}

# ----------------------------------------------------------------------------
# Create NACL and associate it with the subnets
# ----------------------------------------------------------------------------

resource "aws_network_acl" "canada" {
  provider = aws.canada
  vpc_id   = aws_vpc.canada.id

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

resource "aws_network_acl_association" "canada" {
  provider       = aws.canada
  subnet_id      = aws_subnet.canada.id
  network_acl_id = aws_network_acl.canada.id
}

## For region japan
resource "aws_network_acl" "japan" {
  provider = aws.japan
  vpc_id   = aws_vpc.japan.id

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

resource "aws_network_acl_association" "japan" {
  provider       = aws.japan
  subnet_id      = aws_subnet.japan.id
  network_acl_id = aws_network_acl.japan.id
}

## For region europe
resource "aws_network_acl" "europe" {
  provider = aws.europe
  vpc_id   = aws_vpc.europe.id

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

resource "aws_network_acl_association" "europe" {
  provider       = aws.europe
  subnet_id      = aws_subnet.europe.id
  network_acl_id = aws_network_acl.europe.id
}


# ----------------------------------------------------------------------------
# Security groups
# ----------------------------------------------------------------------------


### For the instances
resource "aws_security_group" "canada_sg" {
  name        = "my-demo-instance-sg"
  description = "Allow traffic from anywhere to instances"
  vpc_id      = aws_vpc.canada.id
  provider    = aws.canada

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

## For region japan
resource "aws_security_group" "japan_sg" {
  name        = "my-demo-instance-sg"
  description = "Allow traffic from anywhere to instances"
  vpc_id      = aws_vpc.japan.id
  provider    = aws.japan

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

## For region europe
resource "aws_security_group" "europe_sg" {
  name        = "my-demo-instance-sg"
  description = "Allow traffic from anywhere to instances"
  vpc_id      = aws_vpc.europe.id
  provider    = aws.europe

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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

data "aws_ami" "canada_amazon_linux" {
  provider    = aws.canada
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "canada" {
  provider                    = aws.canada
  ami                         = data.aws_ami.canada_amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.canada.id
  vpc_security_group_ids      = [aws_security_group.canada_sg.id]
  key_name                    = aws_key_pair.canada.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
        #!/bin/bash
        yum install -y httpd
        systemctl start httpd
        echo "<h1>Hello from Canada </h1>" > /var/www/html/index.html
    EOF

  tags = {
    Name = "my-demo-instance"
  }
}

## For region japan
data "aws_ami" "japan_amazon_linux" {
  provider    = aws.japan
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "japan" {
  provider                    = aws.japan
  ami                         = data.aws_ami.japan_amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.japan.id
  vpc_security_group_ids      = [aws_security_group.japan_sg.id]
  key_name                    = aws_key_pair.japan.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
        #!/bin/bash
        yum install -y httpd
        systemctl start httpd
        echo "<h1>Hello from Japan </h1>" > /var/www/html/index.html
    EOF

  tags = {
    Name = "my-demo-instance"
  }
}

## For region europe
data "aws_ami" "europe_amazon_linux" {
  provider    = aws.europe
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

resource "aws_instance" "europe" {
  provider                    = aws.europe
  ami                         = data.aws_ami.europe_amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.europe.id
  vpc_security_group_ids      = [aws_security_group.europe_sg.id]
  key_name                    = aws_key_pair.europe.key_name
  associate_public_ip_address = true

  user_data = <<-EOF
        #!/bin/bash
        yum install -y httpd
        systemctl start httpd
        echo "<h1>Hello from Europe </h1>" > /var/www/html/index.html
    EOF

  tags = {
    Name = "my-demo-instance"
  }
}

# ----------------------------------------------------------------------------
# Route 53
# ----------------------------------------------------------------------------
resource "aws_route53_zone" "demo" {
  name = "mylab.click"
}

resource "aws_route53_record" "canada" {
  zone_id        = aws_route53_zone.demo.zone_id
  name           = "app.mylab.click"
  type           = "A"
  ttl            = 60
  set_identifier = "canada" 

  latency_routing_policy {
    region = "ca-central-1"
  }

# Enable for both latency and failover routing policies.
#   health_check_id = aws_route53_health_check.primary.id
  records = [aws_instance.canada.public_ip]
}

resource "aws_route53_record" "japan" {
  zone_id        = aws_route53_zone.demo.zone_id
  name           = "app.mylab.click"
  type           = "A"
  ttl            = 60
  set_identifier = "japan"
  latency_routing_policy {
    region = "ap-northeast-1"
  }

# Enable for both latency and failover routing policies.
#   health_check_id = aws_route53_health_check.secondary.id
  records = [aws_instance.japan.public_ip]
}

resource "aws_route53_record" "europe" {
  zone_id        = aws_route53_zone.demo.zone_id
  name           = "app.mylab.click"
  type           = "A"
  ttl            = 60
  set_identifier = "europe"
  latency_routing_policy {
    region = "eu-central-1"
  }
  
# Enable for both latency and failover routing policies.
# health_check_id = aws_route53_health_check.tertiary.id
  records = [aws_instance.europe.public_ip]
}

# ----------------------------------------------------------------------------
## Health check for Route 53
# ----------------------------------------------------------------------------
resource "aws_route53_health_check" "primary" {
#   fqdn              = "app.mylab.click"
  ip_address        = aws_instance.canada.public_ip
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name = "primary-health-check"
  }
}

resource "aws_route53_health_check" "secondary" {
    ip_address        = aws_instance.japan.public_ip
    port              = 80
    type              = "HTTP"
    resource_path     = "/"
    failure_threshold = 3
    request_interval  = 30

  tags = {
    Name = "secondary-health-check"
  }
}

# resource "aws_route53_health_check" "tertiary" {
#     ip_address        = aws_instance.europe.public_ip
#     port              = 80
#     type              = "HTTP"
#     resource_path     = "/"
#     failure_threshold = 3
#     request_interval  = 30

#   tags = {
#     Name = "tertiary-health-check"
#   }
# }

resource "aws_route53_record" "failover_primary" {
  zone_id        = aws_route53_zone.demo.zone_id
  name           = "ha.mylab.click"
  type           = "A"
  ttl            = 60
  set_identifier = "primary" 
  failover_routing_policy {
        type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary.id
  records = [aws_instance.canada.public_ip]
}

resource "aws_route53_record" "failover_secondary" {
  zone_id        = aws_route53_zone.demo.zone_id
  name           = "ha.mylab.click"
  type           = "A"
  ttl            = 60
  set_identifier = "secondary"
  failover_routing_policy {
    type = "SECONDARY"
  }
  health_check_id = aws_route53_health_check.secondary.id
  records = [aws_instance.japan.public_ip]
}


# ----------------------------------------------------------------------------
# Outputs
# ----------------------------------------------------------------------------

output "instance_ips" {
  value = {
    canada = aws_instance.canada.public_ip
    japan  = aws_instance.japan.public_ip
    europe = aws_instance.europe.public_ip
  }
}
