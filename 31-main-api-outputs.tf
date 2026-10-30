output "main_api_vip" {
  description = "Direct highly available RKE2 Kubernetes API VIP"
  value       = local.main_kube_vip_address
}

output "main_api_endpoint" {
  description = "Direct highly available RKE2 Kubernetes API URL"
  value       = "https://${local.main_kube_vip_address}:6443"
}
