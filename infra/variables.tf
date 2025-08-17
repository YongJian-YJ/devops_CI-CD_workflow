# infra/variables.tf - Enhanced version with corrected ports
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
}

variable "services" {
  description = "List of services to deploy"
  type        = list(string)
  default     = ["frontend", "catalogue", "recommendation", "voting"]
}

variable "services_ports" {
  description = "Map of services to container ports and configurations"
  type = map(object({
    port = number
  }))
  default = {
    frontend = {
      port = 3000  # From docker-compose: 80:3000
    }
    catalogue = {
      port = 5000  # From docker-compose: 5000:5000
    }
    recommendation = {
      port = 8080  # From docker-compose: 8080:8080
    }
    voting = {
      port = 8080  # From docker-compose: 8081:8080 (container port is 8080)
    }
  }
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Name of the project"
  type        = string
  default     = "craftista"
}