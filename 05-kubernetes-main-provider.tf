provider "kubernetes" {
  alias = "main"

  config_path    = pathexpand("~/.kube/config")
  config_context = "main-direct"
}
