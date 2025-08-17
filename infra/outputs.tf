# infra/outputs.tf

# Main website URL
output "website_url" {
  description = "Main website URL"
  value       = "http://${aws_lb.main.dns_name}"
}

# Load balancer details
output "load_balancer_dns" {
  description = "DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "load_balancer_zone_id" {
  description = "Zone ID of the load balancer"
  value       = aws_lb.main.zone_id
}

# Service endpoints
output "service_endpoints" {
  description = "API endpoints for each service"
  value = {
    frontend       = "http://${aws_lb.main.dns_name}/"
    catalogue      = "http://${aws_lb.main.dns_name}/api/catalogue"
    recommendation = "http://${aws_lb.main.dns_name}/api/recommendation"
    voting         = "http://${aws_lb.main.dns_name}/api/voting"
  }
}

# ECS Cluster information
output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.cluster.name
}

# ECR Repository URIs
output "ecr_repo_uris" {
  description = "ECR repository URIs"
  value       = { for s, r in aws_ecr_repository.repos : s => r.repository_url }
}

# CloudWatch Log Groups
output "log_groups" {
  description = "CloudWatch log group names for each service"
  value = {
    for service in var.services : service => aws_cloudwatch_log_group.ecs_logs[service].name
  }
}

# Useful AWS Console Links
output "aws_console_links" {
  description = "Useful AWS console links"
  value = {
    ecs_cluster = "https://console.aws.amazon.com/ecs/home?region=${var.region}#/clusters/${aws_ecs_cluster.cluster.name}/services"
    load_balancer = "https://console.aws.amazon.com/ec2/v2/home?region=${var.region}#LoadBalancers:search=${aws_lb.main.name}"
    cloudwatch_logs = "https://console.aws.amazon.com/cloudwatch/home?region=${var.region}#logsV2:log-groups"
  }
}