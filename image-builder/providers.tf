terraform {
  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = "1.8.2"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.1"
    }
  }
}

provider "harvester" {
  kubeconfig  = pathexpand(var.harvester_kubeconfig_path)
  kubecontext = var.harvester_kubeconfig_context
}

provider "kubernetes" {
  config_path    = pathexpand(var.harvester_kubeconfig_path)
  config_context = var.harvester_kubeconfig_context
}
