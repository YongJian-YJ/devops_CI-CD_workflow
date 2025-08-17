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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for ECS Task
resource "aws_security_group" "ecs_sg" {
  name        = "ecs-security-group"
  description = "Security group for ECS services"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

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
}

# Application Load Balancer
resource "aws_lb" "main" {
  name               = "craftista-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

# Target Group for frontend
resource "aws_lb_target_group" "frontend_tg" {
  name        = "frontend-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"  # Remove 404
    protocol            = "HTTP"
  }
}

# ALB Listener
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_tg.arn
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "cluster" {
  name = "craftista-cluster"
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
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Single ECS Task Definition for all services
resource "aws_ecs_task_definition" "craftista_task" {
  family                   = "craftista-task"
  cpu                      = "1024"
  memory                   = "2048"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "frontend"
      image     = "${aws_ecr_repository.repos["frontend"].repository_url}:${var.image_tag}"
      essential = true
      portMappings = [{ containerPort = 3000, protocol = "tcp" }]
      environment  = [{ name = "PORT", value = "3000" }]
    },
    {
      name      = "catalogue"
      image     = "${aws_ecr_repository.repos["catalogue"].repository_url}:${var.image_tag}"
      essential = true
      portMappings = [{ containerPort = 5000, protocol = "tcp" }]
      environment  = [{ name = "PORT", value = "5000" }]
    },
    {
      name      = "catalogue-db"
      image     = "postgres:16.2-alpine3.19"
      essential = true
      environment = [
        { name = "POSTGRES_USER", value = "devops" },
        { name = "POSTGRES_PASSWORD", value = "devops" },
        { name = "POSTGRES_DB", value = "catalogue" }
      ]
    },
    {
      name      = "recommendation"
      image     = "${aws_ecr_repository.repos["recommendation"].repository_url}:${var.image_tag}"
      essential = true
      portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    },
    {
      name      = "voting"
      image     = "${aws_ecr_repository.repos["voting"].repository_url}:${var.image_tag}"
      essential = true
      portMappings = [{ containerPort = 8081, protocol = "tcp" }]
    }
  ])
}

# Single ECS Service
resource "aws_ecs_service" "craftista_service" {
  name            = "craftista-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.craftista_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = data.aws_subnets.default.ids
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend_tg.arn
    container_name   = "frontend"
    container_port   = 3000
  }

  health_check_grace_period_seconds = 120
}

# Output ALB DNS
output "load_balancer_dns" {
  value = aws_lb.main.dns_name
}
