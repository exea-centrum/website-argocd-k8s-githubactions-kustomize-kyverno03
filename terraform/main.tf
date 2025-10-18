terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
  }
  backend "remote" {
    hostname = "app.terraform.io"
    organization = "davtro"
    workspaces {
      name = "github-actions-terraform"
    }
  }
}

provider "github" {
  owner = "exea-centrum"
}

resource "github_repository" "website" {
  name        = "website-argocd-k8s-githubactions-kustomize-kyverno03"
  description = "Davtro Website with ArgoCD, K8s, GitHub Actions, Kustomize, Kyverno"
  visibility  = "public"
  auto_init   = true
}

resource "github_actions_secret" "kube_config" {
  repository      = github_repository.website.name
  secret_name     = "KUBE_CONFIG"
  plaintext_value = var.kube_config
}

resource "github_branch_default" "main" {
  repository = github_repository.website.name
  branch     = "main"
}

variable "kube_config" {
  description = "Kubernetes configuration"
  type        = string
  sensitive   = true
}

output "repository_url" {
  value = github_repository.website.html_url
}
