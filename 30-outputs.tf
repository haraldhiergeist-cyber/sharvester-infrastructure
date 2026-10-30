output "main_cluster_id" {
  description = "Rancher cluster-v2 ID for main."
  value       = rancher2_cluster_v2.main.id
}

output "main_kube_vip" {
  description = "Stable API VIP to be used by kube-vip."
  value       = var.main_kube_vip
}

output "main_controlplane_image" {
  description = "Automated Harvester image used for control-plane/etcd nodes."
  value       = local.main_controlplane_image
}

output "main_worker_image" {
  description = "Automated Harvester image with Longhorn prerequisites used for worker nodes."
  value       = local.main_worker_image
}

output "main_vm_network" {
  description = "Harvester VM network for all DHCP-addressed nodes."
  value       = local.main_vm_network
}

output "main_vm_storage_class" {
  description = "Harvester storage class for VM disks."
  value       = local.main_target_storage_class
}

output "harbor_gitlab_robot_username" {
  value = harbor_robot_account.gitlab_ci.full_name
}

output "harbor_kubernetes_robot_username" {
  value = harbor_robot_account.kubernetes_pull.full_name
}
