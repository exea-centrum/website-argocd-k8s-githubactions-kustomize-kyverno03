terraform {
  required_providers {
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
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

resource "github_branch_default" "main" {
  repository = github_repository.website.name
  branch     = "main"
}
