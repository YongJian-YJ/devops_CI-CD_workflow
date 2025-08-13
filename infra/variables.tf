variable "region" {
  default = "us-east-1"
}

variable "image_tag" {
  description = "Docker image tag to deploy"
  type        = string
}
