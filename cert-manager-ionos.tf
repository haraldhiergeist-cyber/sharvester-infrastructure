resource "helm_release" "cert_manager_ionos_webhook" {
  name      = "cert-manager-webhook-ionos"
  namespace = "cert-manager"

  repository = "https://fabmade.github.io/cert-manager-webhook-ionos"
  chart      = "cert-manager-webhook-ionos"

  wait    = true
  timeout = 300

  depends_on = [
    helm_release.cert_manager
  ]
}


resource "kubernetes_manifest" "letsencrypt_production" {
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
          }
        ]
      }
    }
  }

  depends_on = [
    helm_release.cert_manager_ionos_webhook
  ]
}

resource "kubernetes_manifest" "lab_wildcard_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"

    metadata = {
      name      = "lab-wildcard"
      namespace = "cert-manager"
    }

    spec = {
      secretName = "lab-wildcard-tls"

      dnsNames = [
        "*.lab.harald-hiergeist.de",
        "lab.harald-hiergeist.de"
      ]

      issuerRef = {
        name = "letsencrypt-production"
        kind = "ClusterIssuer"
      }
    }
  }

  depends_on = [
    kubernetes_manifest.letsencrypt_production
  ]
}
