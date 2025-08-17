# Create ECR repositories dynamically
resource "aws_ecr_repository" "repos" {
  for_each             = toset(var.services)
  name                 = each.value
  # force_delete         = true
  image_tag_mutability = "MUTABLE"
}

# Output repository URIs for ECS
output "ecr_repo_uris" {
  value = { for s, r in aws_ecr_repository.repos : s => r.repository_url }
}