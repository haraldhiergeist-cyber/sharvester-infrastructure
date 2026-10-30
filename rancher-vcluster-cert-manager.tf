resource "helm_release" "rancher_vcluster_ionos_webhook" {
  provider = helm.rancher_vcluster

  name       = "cert-manager-webhook-ionos"
  namespace  = "cert-manager"
  repository = "https://fabmade.github.io/cert-manager-webhook-ionos"
  chart      = "cert-manager-webhook-ionos"
  version    = "1.3.1"

  wait    = true
  timeout = 300
}

resource "kubernetes_manifest" "rancher_vcluster_letsencrypt_production" {
  provider = kubernetes.rancher_vcluster

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"

    metadata = {
      name = "letsencrypt-production"
    }

    spec = {
      acme = {
        email  = "harald.hiergeist@gmail.com"
        server = "https://acme-v02.api.letsencrypt.org/directory"

        privateKeySecretRef = {
          name = "letsencrypt-production-account-key"
        }

        solvers = [{
          selector = {
            dnsZones = [
              "harald-hiergeist.de"
            ]
          }

          dns01 = {
            webhook = {
              groupName  = "acme.fabmade.de"
              solverName = "ionos"

              config = {
                apiUrl = "https://api.hosting.ionos.com/dns/v1"

                publicKeySecretRef = {
                  name = "ionos-secret"
                  key  = "IONOS_PUBLIC_PREFIX"
                }

                secretKeySecretRef = {
                  name = "ionos-secret"
                  key  = "IONOS_SECRET"
                }
              }
            }
          }
        }]
      }
    }
  }

  depends_on = [
    helm_release.rancher_vcluster_ionos_webhook
  ]
}


resource "kubernetes_manifest" "rancher_vcluster_rancher_certificate" {
  provider = kubernetes.rancher_vcluster

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = "rancher-letsencrypt"
      namespace = "cattle-system"
    }

    spec = {
      secretName = "tls-rancher-ingress"

      dnsNames = [
        "*.lab.harald-hiergeist.de", "lab.harald-hiergeist.de"
      ]

      issuerRef = {
        name = "letsencrypt-production"
        kind = "ClusterIssuer"
      }
    }
  }

  depends_on = [
    kubernetes_manifest.rancher_vcluster_letsencrypt_production
  ]
}
