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
  name     = "craftista/${each.value}"
  image_tag_mutability = "MUTABLE"
}
