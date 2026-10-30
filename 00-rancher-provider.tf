# Rancher 2.14 provider configuration.
# IMPORTANT: do not add a second terraform { required_providers { ... } } block here.
# The existing required_providers block in main.tf must contain:
#
# rancher2 = {
#   source  = "rancher/rancher2"
#   version = "~> 14.0"
# }

variable "rancher_token" {
  description = "Rancher API bearer token. Supply via TF_VAR_rancher_token; never commit it."
  type        = string
  sensitive   = true
}

provider "rancher2" {
  api_url   = "https://rancher.lab.harald-hiergeist.de"
  token_key = var.rancher_token
}
