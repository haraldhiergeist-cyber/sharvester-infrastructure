resource "kubernetes_storage_class_v1" "main_longhorn" {
  provider = kubernetes.main

  metadata {
    name = "main-longhorn"
  }

  storage_provisioner    = "driver.longhorn.io"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    numberOfReplicas    = "3"
    staleReplicaTimeout = "30"
    fsType              = "ext4"
  }
}
