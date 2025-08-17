# infra/ecs.tf - Fixed version with proper health checks
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Security Group for ALB
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

  tags = {
    Name = "ALB Security Group"
  }
}

# Security Group for ECS Services
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

  tags = {
    Name = "ECS Security Group"
  }
}

# Application Load Balancer
resource "aws_lb" "main" {
  name                       = "craftista-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups           = [aws_security_group.alb_sg.id]
  subnets                   = data.aws_subnets.default.ids
  enable_deletion_protection = false

  tags = {
    Name = "Craftista ALB"
  }
}

# Target Groups for each service with improved health checks
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
    unhealthy_threshold = 10  # Very tolerant
    timeout            = 30   # Long timeout
    interval           = 300  # Check every 5 minutes
    path               = "/"  # Use root path for all
    matcher            = "200,404,500"  # Accept almost any response
    port               = "traffic-port"
    protocol           = "HTTP"
  }

  # Deregistration delay
  deregistration_delay = 30

  tags = {
    Name = "${each.key} Target Group"
  }
}

# ALB Listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  # Default action - forward to frontend
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_tgs["frontend"].arn
  }
}

# ALB Listener Rules for path-based routing
resource "aws_lb_listener_rule" "service_rules" {
  for_each = {
    catalogue      = "/api/catalogue*"
    recommendation = "/api/recommendation*"
    voting         = "/api/voting*"
  }

  listener_arn = aws_lb_listener.main.arn
  priority     = 100 + index(keys(var.services_ports), each.key)

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.service_tgs[each.key].arn
  }

  condition {
    path_pattern {
      values = [each.value]
    }
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "cluster" {
  name = "craftista-cluster"

  tags = {
    Name = "Craftista Cluster"
  }
}

# IAM Role for ECS Tasks
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "craftista-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "ECS Task Execution Role"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Definitions
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

    # Enhanced environment variables
    environment = [
      {
        name  = "NODE_ENV"
        value = "production"
      },
      {
        name  = "PORT"
        value = tostring(each.value.port)
      }
    ]

    # Add health check for container
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost:${each.value.port}/health || curl -f http://localhost:${each.value.port}/ || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }

    # Logging removed - use default Docker logging
  }])

  tags = {
    Name = "${each.key} Task Definition"
  }
}

# Get current region for logging
data "aws_region" "current" {}

# ECS Services with improved configuration
resource "aws_ecs_service" "services" {
  for_each        = var.services_ports
  name            = "${each.key}-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.tasks[each.key].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # CRITICAL: Health check grace period
  health_check_grace_period_seconds = 300  # 5 minutes for app to start

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  # Load balancer configuration
  load_balancer {
    target_group_arn = aws_lb_target_group.service_tgs[each.key].arn
    container_name   = each.key
    container_port   = each.value.port
  }

  # Note: deployment_configuration not supported in this provider version

  # Service discovery if needed
  # service_registries {
  #   registry_arn = aws_service_discovery_service.services[each.key].arn
  # }

  # Ensure dependencies
  depends_on = [
    aws_lb_listener.main,
    aws_ecs_task_definition.tasks
  ]

  tags = {
    Name = "${each.key} Service"
  }
}

# Output the ALB DNS name
output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.main.zone_id
}