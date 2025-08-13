provider "aws" {
  region = "us-east-1"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "default" {
  vpc_id = data.aws_vpc.default.id
}

# Security Group
resource "aws_security_group" "ecs_sg" {
  name        = "ecs_sg"
  description = "Allow HTTP inbound"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8080
    to_port     = 8081
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

# ECS Cluster
resource "aws_ecs_cluster" "cluster" {
  name = "craftista-cluster"
}

# IAM Role for ECS Tasks
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

variable "services_ports" {
  type = map(object({ port: number }))
  default = {
    frontend  = { port = 3000 }
    catalogue = { port = 5000 }
    recco     = { port = 8080 }
    voting    = { port = 8081 }
  }
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
}

# Pass in ECR repository URIs from ecr.tf output
variable "ecr_repo_uris" {
  description = "Map of service -> ECR repository URI"
  type        = map(string)
}

# ECS Task Definitions
resource "aws_ecs_task_definition" "tasks" {
  for_each = var.services_ports

  family                   = "${each.key}-task"
  cpu                      = "256"
  memory                   = "512"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = each.key
    image     = "${var.ecr_repo_uris[each.key]}:${var.image_tag}"
    essential = true
    portMappings = [{ containerPort = each.value.port, hostPort = each.value.port, protocol = "tcp" }]
  }])
}

# ECS Services
resource "aws_ecs_service" "services" {
  for_each = aws_ecs_task_definition.tasks

  name            = "${each.key}-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = each.value.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = data.aws_subnet_ids.default.ids
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  depends_on = [aws_iam_role_policy_attachment.ecs_task_execution_role_policy]
}
