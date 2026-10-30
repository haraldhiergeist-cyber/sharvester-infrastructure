locals {
  main_acme_dns_zone = "harald-hiergeist.de"
}

resource "kubernetes_manifest" "main_letsencrypt_production" {
  provider = kubernetes.main

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

        solvers = [
          {
            selector = {
              dnsZones = [
                local.main_acme_dns_zone
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
          }
        ]
      }
    }
  }

  depends_on = [
    helm_release.main_cert_manager,
    helm_release.main_ionos_webhook,
  ]
}
