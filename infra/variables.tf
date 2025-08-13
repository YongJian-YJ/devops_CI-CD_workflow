variable "region" {
  description = "AWS region"
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
  description = "Map of services to container ports"
  type = map(object({ port: number }))
  default = {
    frontend  = { port = 3000 }
    catalogue = { port = 5000 }
    recommendation     = { port = 8080 }
    voting    = { port = 8081 }
  }
}
