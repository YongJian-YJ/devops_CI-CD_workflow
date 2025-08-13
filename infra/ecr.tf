provider "aws" {
  region = "us-east-1"
}

variable "services" {
  type    = list(string)
  default = ["frontend", "catalogue", "recco", "voting"]
}

# Create ECR repositories dynamically
resource "aws_ecr_repository" "repos" {
  for_each = toset(var.services)
  name     = each.value
  image_tag_mutability = "MUTABLE"
}

# Output the repository URIs in a map for Jenkins
output "ecr_repo_uris" {
  value = { for s, r in aws_ecr_repository.repos : s => r.repository_url }
}
