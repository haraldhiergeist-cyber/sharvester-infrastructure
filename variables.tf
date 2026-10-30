variable "ssh_public_key" {
  type        = string
  description = "SSH public key for VM access"
}

variable "harvester_kubeconfig_path" {
  description = "Path to the Harvester kubeconfig"
  type        = string
  default     = "~/.kube/config"
}
