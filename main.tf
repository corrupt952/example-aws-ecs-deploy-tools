###
# Variables
variable "service" {
  default = "example"
}

###
# Data resoruces
data "aws_availability_zones" "available" {
  state = "available"
}

###
# VPC & Network resources
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = var.service
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_default_route_table" "main" {
  default_route_table_id = aws_vpc.main.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_subnet" "main" {
  count = length(data.aws_availability_zones.available.names)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.service}-subnet-${count.index}"
  }
}

resource "aws_security_group" "lb" {
  name   = "${var.service}-lb"
  vpc_id = aws_vpc.main.id

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

resource "aws_security_group" "ecs" {
  name   = "${var.service}-ecs"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###
# LB
resource "aws_alb" "main" {
  name            = var.service
  internal        = false
  security_groups = [aws_security_group.lb.id]
  subnets         = aws_subnet.main.*.id
}

resource "aws_lb_target_group" "main" {
  name        = var.service
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id
}

resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_alb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

###
# ECS resources
resource "aws_ecs_cluster" "main" {
  name = var.service
}

###
# IAM resources
resource "aws_iam_role" "main" {
  name = var.service

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = ""
        Effect = "ALlow"
        Action = "sts:AssumeRole"
        Principal = {
          "Service" : "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

###
# Output
output "subnets" {
  value = aws_subnet.main.*.id
}

output "security_group" {
  value = aws_security_group.ecs.id
}

output "target_group" {
  value = aws_lb_target_group.main.arn
}

output "aws_iam_role" {
  value = aws_iam_role.main.arn
}