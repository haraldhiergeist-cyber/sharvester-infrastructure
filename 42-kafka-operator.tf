resource "kubernetes_storage_class_v1" "main_longhorn_single" {
  provider = kubernetes.main

  metadata {
    name = "main-longhorn-single"
  }

  storage_provisioner    = "driver.longhorn.io"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    numberOfReplicas    = "1"
    staleReplicaTimeout = "30"
    fsType              = "ext4"
  }
}

resource "kubernetes_namespace_v1" "kafka" {
  provider = kubernetes.main

  metadata {
    name = "kafka"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations
    ]
  }
}

resource "helm_release" "strimzi" {
  provider = helm.main

  name       = "strimzi-kafka-operator"
  repository = "oci://quay.io/strimzi-helm"
  chart      = "strimzi-kafka-operator"
  version    = "1.3.0"

  namespace        = kubernetes_namespace_v1.kafka.metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      replicas = 1

      watchNamespaces = [
        "kafka"
      ]
    })
  ]
}
