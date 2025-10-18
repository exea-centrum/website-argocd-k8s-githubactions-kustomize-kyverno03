terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig
}

resource "kubernetes_namespace" "davtro" {
  metadata {
    name = "davtrokyverno03"
  }
}

resource "kubernetes_secret" "davtro_db" {
  metadata {
    name = "davtro-db-secret"
    namespace = kubernetes_namespace.davtro.metadata[0].name
  }

  data = {
    database_url = var.database_url
  }
}
