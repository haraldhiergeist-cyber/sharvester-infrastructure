locals {
  main_metallb_version   = "0.16.1"
  main_metallb_pool_name = "main"
  main_metallb_pool      = "10.20.100.213-10.20.100.220"
  main_ingress_ip        = "10.20.100.213"
}

resource "kubernetes_namespace_v1" "main_metallb" {
  provider = kubernetes.main

  metadata {
    name = "metallb-system"

    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations
    ]
  }
}

resource "helm_release" "main_metallb" {
  provider = helm.main

  name       = "metallb"
  repository = "https://metallb.github.io/metallb"
  chart      = "metallb"
  version    = local.main_metallb_version
  namespace  = kubernetes_namespace_v1.main_metallb.metadata[0].name

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 600

  values = [
    yamlencode({
      speaker = {
        frr = {
          enabled = false
        }
      }
      frrk8s = {
        enabled = false
      }
    })
  ]
}

# First deployment: install helm_release.main_metallb first so the CRDs exist.
resource "kubernetes_manifest" "main_metallb_ip_pool" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"

    metadata = {
      name      = local.main_metallb_pool_name
      namespace = kubernetes_namespace_v1.main_metallb.metadata[0].name
    }

    spec = {
      addresses = [local.main_metallb_pool]
    }
  }

  depends_on = [helm_release.main_metallb]
}

resource "kubernetes_manifest" "main_metallb_l2_advertisement" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"

    metadata = {
      name      = "main"
      namespace = kubernetes_namespace_v1.main_metallb.metadata[0].name
    }

    spec = {
      ipAddressPools = [local.main_metallb_pool_name]
    }
  }

  depends_on = [
    helm_release.main_metallb,
    kubernetes_manifest.main_metallb_ip_pool,
  ]
}
