variable "harvester_kubeconfig_path" {
  description = "Path to the kubeconfig containing the Harvester context"
  type        = string
  default     = "~/.kube/config"
}

variable "harvester_kubeconfig_context" {
  description = "Kubeconfig context for the Harvester host cluster"
  type        = string
  default     = "sharvester"
}

variable "golden_image_build_timeout_seconds" {
  description = "Maximum time to wait for a golden-image builder VM to stop"
  type        = number
  default     = 3600
}
