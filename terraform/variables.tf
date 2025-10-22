variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  type        = string
  default     = "my-cluster"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"
}
