resource "kubernetes_namespace_v1" "cnpg_system" {
  provider = kubernetes.main

  metadata {
    name = "cnpg-system"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations
    ]
  }
}

resource "helm_release" "cloudnative_pg" {
  provider = helm.main

  name       = "cloudnative-pg"
  namespace  = kubernetes_namespace_v1.cnpg_system.metadata[0].name
  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  version    = "0.29.1"

  create_namespace = false

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true
  timeout         = 600

  values = [
    yamlencode({
      crds = {
        create = true
      }

      config = {
        clusterWide = true
      }

      monitoring = {
        podMonitorEnabled = false
      }
    })
  ]

  depends_on = [
    kubernetes_namespace_v1.cnpg_system
  ]
}
