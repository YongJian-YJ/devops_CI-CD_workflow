# infra/ecs.tf - ECS + ALB + Service Discovery setup

# ----------------------------
# VPC & Subnets
# ----------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ----------------------------
# Security Groups
# ----------------------------
resource "aws_security_group" "alb_sg" {
  name        = "alb-security-group"
  description = "Security group for ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "ALB Security Group" }
}

resource "aws_security_group" "ecs_sg" {
  name        = "ecs-security-group"
  description = "Security group for ECS services"
  vpc_id      = data.aws_vpc.default.id

  # Allow traffic from ALB
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Allow inter-service communication
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "ECS Security Group" }
}

# ----------------------------
# ALB
# ----------------------------
resource "aws_lb" "main" {
  name               = "craftista-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
  enable_deletion_protection = false
  tags = { Name = "Craftista ALB" }
}

# ----------------------------
# Service Discovery Namespace
# ----------------------------
resource "aws_service_discovery_private_dns_namespace" "namespace" {
  name        = "craftista.local"
  vpc         = data.aws_vpc.default.id
  description = "Private namespace for Craftista services"
}

# ----------------------------
# Service Discovery Services
# ----------------------------
resource "aws_service_discovery_service" "sd_services" {
  for_each = var.services_ports
  name     = each.key
  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.namespace.id
    routing_policy = "MULTIVALUE"
    dns_records {
      type = "A"
      ttl  = 10
    }
  }
}

# ----------------------------
# Health Check Paths
# ----------------------------
locals {
  health_check_paths = {
    frontend       = "/"
    catalogue      = "/api/products"
    recommendation = "/api/recommendation-status"
    voting         = "/api/origamis"
  }
}

# ----------------------------
# Target Groups
# ----------------------------
resource "aws_lb_target_group" "service_tgs" {
  for_each    = var.services_ports
  name        = "${each.key}-tg"
  port        = each.value.port
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 10
    interval            = 30
    path                = lookup(local.health_check_paths, each.key, "/")
    matcher             = "200-399"
  }

  deregistration_delay = 30
  tags                 = { Name = "${each.key} Target Group" }
}

# ----------------------------
# ALB Listener & Rules
# ----------------------------
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_tgs["frontend"].arn
  }
}

resource "aws_lb_listener_rule" "service_rules" {
  for_each = {
    catalogue      = "/api/products*"
    recommendation = "/api/recommendation*"
    voting         = "/api/origamis*"
  }

  listener_arn = aws_lb_listener.main.arn
  priority     = 100 + index(keys(var.services_ports), each.key)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_tgs[each.key].arn
  }

  condition {
    path_pattern { values = [each.value] }
  }
}

# ----------------------------
# ECS Cluster
# ----------------------------
resource "aws_ecs_cluster" "cluster" {
  name = "craftista-cluster"
  tags = { Name = "Craftista Cluster" }
}

# ----------------------------
# IAM Role
# ----------------------------
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "craftista-ecs-task-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "ECS Task Execution Role" }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ----------------------------
# ECS Task Definitions
# ----------------------------
resource "aws_ecs_task_definition" "tasks" {
  for_each                 = var.services_ports
  family                   = "${each.key}-task"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = each.key
    image     = "${aws_ecr_repository.repos[each.key].repository_url}:${var.image_tag}"
    essential = true

    portMappings = [{
      containerPort = each.value.port
      hostPort      = each.value.port
      protocol      = "tcp"
    }]

    environment = [
      { name = "PORT", value = tostring(each.value.port) }
    ]

    # ✅ Health check mimicking Docker Compose
    healthCheck = {
      command = [
        "CMD-SHELL",
        "curl -f http://localhost:${each.value.port}${lookup(local.health_check_paths, each.key, '/')} || curl -f http://localhost:${each.value.port}/ || exit 1"
      ]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
  }])

  tags = { Name = "${each.key} Task Definition" }
}

# ----------------------------
# ECS Services
# ----------------------------
resource "aws_ecs_service" "services" {
  for_each        = var.services_ports
  name            = "${each.key}-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.tasks[each.key].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = 120

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  # ✅ Service Discovery registration
  service_registries {
    registry_arn = aws_service_discovery_service.sd_services[each.key].arn
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.service_tgs[each.key].arn
    container_name   = each.key
    container_port   = each.value.port
  }

  depends_on = [
    aws_lb_listener.main,
    aws_ecs_task_definition.tasks
  ]

  tags = { Name = "${each.key} Service" }
}

# ----------------------------
# Outputs
# ----------------------------
output "load_balancer_dns" {
  value       = aws_lb.main.dns_name
  description = "DNS name of the ALB"
}

output "load_balancer_zone_id" {
  value       = aws_lb.main.zone_id
  description = "Zone ID of the ALB"
}

output "service_discovery_namespace" {
  value       = aws_service_discovery_private_dns_namespace.namespace.name
  description = "Private DNS namespace for ECS services"
}
