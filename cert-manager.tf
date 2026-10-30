resource "helm_release" "cert_manager" {
  name      = "cert-manager"
  namespace = "cert-manager"

  repository = "oci://quay.io/jetstack/charts"
  chart      = "cert-manager"
  version    = "v1.21.2"

  create_namespace = true

  set = [
    {
      name  = "crds.enabled"
      value = "true"
    }
  ]

  wait    = true
  timeout = 600
}
