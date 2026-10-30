locals {
  # IONOS currently lists webhook v1.0.2 as compatible with cert-manager v1.21.1.
  main_cert_manager_version = "v1.21.1"
}

resource "kubernetes_namespace_v1" "main_cert_manager" {
  provider = kubernetes.main

  metadata {
    name = "cert-manager"
  }

  lifecycle {
    # Rancher adds its own namespace annotations.
    ignore_changes = [
      metadata[0].annotations,
      metadata[0].labels
    ]
  }
}

resource "helm_release" "main_cert_manager" {
  provider = helm.main

  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = local.main_cert_manager_version
  namespace  = kubernetes_namespace_v1.main_cert_manager.metadata[0].name

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  values = [
    yamlencode({
      crds = {
        enabled = true
      }

      # Avoid split-DNS/SOA surprises during DNS-01 self-checks.
      extraArgs = [
        "--dns01-recursive-nameservers-only",
        "--dns01-recursive-nameservers=1.1.1.1:53,8.8.8.8:53",
      ]
    })
  ]
}

resource "helm_release" "main_ionos_webhook" {
  provider = helm.main

  name       = "cert-manager-webhook-ionos"
  repository = "https://fabmade.github.io/cert-manager-webhook-ionos"
  chart      = "cert-manager-webhook-ionos"
  version    = "1.3.1"
  namespace  = kubernetes_namespace_v1.main_cert_manager.metadata[0].name

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  depends_on = [
    helm_release.main_cert_manager
  ]
}
