provider "helm" {
  alias = "main"

  kubernetes = {
    config_path    = pathexpand("~/.kube/config")
    config_context = "main-direct"
  }
}
