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

# Security Group for ECS
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

# ALB Target Groups (one per service)
resource "aws_lb_target_group" "frontend_tg" {
  name        = "frontend-tg"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}

resource "aws_lb_target_group" "catalogue_tg" {
  name        = "catalogue-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}

resource "aws_lb_target_group" "recommendation_tg" {
  name        = "recommendation-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}

resource "aws_lb_target_group" "voting_tg" {
  name        = "voting-tg"
  port        = 8081
  protocol    = "HTTP"
  vpc_id      = data.aws_vpc.default.id
  target_type = "ip"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 10
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

# Path-based rules
resource "aws_lb_listener_rule" "catalogue_rule" {
  listener_arn = aws_lb_listener.main.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.catalogue_tg.arn
  }

  condition {
    path_pattern {
      values = ["/catalogue*"]
    }
  }
}

resource "aws_lb_listener_rule" "recommendation_rule" {
  listener_arn = aws_lb_listener.main.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.recommendation_tg.arn
  }

  condition {
    path_pattern {
      values = ["/recommendation*"]
    }
  }
}

resource "aws_lb_listener_rule" "voting_rule" {
  listener_arn = aws_lb_listener.main.arn
  priority     = 30

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.voting_tg.arn
  }

  condition {
    path_pattern {
      values = ["/voting*"]
    }
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

# CloudWatch Log Group
resource "aws_cloudwatch_log_group" "ecs_log_group" {
  name              = "/ecs/craftista-service"
  retention_in_days = 7
}

# ECS Task Definition
resource "aws_ecs_task_definition" "craftista_task" {
  family                   = "craftista-task"
  cpu                      = "2048"
  memory                   = "4096"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name         = "frontend"
      image        = "${aws_ecr_repository.repos["frontend"].repository_url}:${var.image_tag}"
      essential    = true
      portMappings = [{ containerPort = 3000, hostPort = 3000 }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "frontend"
        }
      }
    },
    {
      name         = "catalogue"
      image        = "${aws_ecr_repository.repos["catalogue"].repository_url}:${var.image_tag}"
      essential    = true
      portMappings = [{ containerPort = 5000, hostPort = 5000 }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "catalogue"
        }
      }
    },
    {
      name         = "catalogue-db"
      image        = "postgres:16.2-alpine3.19"
      essential    = true
      environment = [
        { name = "POSTGRES_USER", value = "devops" },
        { name = "POSTGRES_PASSWORD", value = "devops" },
        { name = "POSTGRES_DB", value = "catalogue" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "catalogue-db"
        }
      }
    },
    {
      name         = "recommendation"
      image        = "${aws_ecr_repository.repos["recommendation"].repository_url}:${var.image_tag}"
      essential    = true
      portMappings = [{ containerPort = 8080, hostPort = 8080 }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "recommendation"
        }
      }
    },
    {
      name         = "voting"
      image        = "${aws_ecr_repository.repos["voting"].repository_url}:${var.image_tag}"
      essential    = true
      portMappings = [{ containerPort = 8081, hostPort = 8081 }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs_log_group.name
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "voting"
        }
      }
    }
  ])
}

# ECS Service
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
