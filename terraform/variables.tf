variable "kube_config" {
  description = "Kubernetes configuration for GitHub Actions"
  type        = string
  sensitive   = true
}
