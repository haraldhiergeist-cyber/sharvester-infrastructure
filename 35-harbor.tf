resource "kubernetes_namespace_v1" "harbor" {
  provider = kubernetes.main

  metadata {
    name = "harbor"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations
    ]
  }
}

resource "random_password" "harbor_admin" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "harbor_admin" {
  provider = kubernetes.main

  metadata {
    name      = "harbor-admin"
    namespace = kubernetes_namespace_v1.harbor.metadata[0].name
  }

  type = "Opaque"

  data = {
    HARBOR_ADMIN_PASSWORD = random_password.harbor_admin.result
  }
}

# Das DB-Secret muss im selben Namespace wie Harbor liegen.
resource "kubernetes_secret_v1" "harbor_db_runtime" {
  provider = kubernetes.main

  metadata {
    name      = "harbor-db-credentials"
    namespace = kubernetes_namespace_v1.harbor.metadata[0].name
  }

  type = "Opaque"

  data = {
    password = random_password.harbor_db.result
  }
}

resource "helm_release" "harbor" {
  provider = helm.main

  name      = "harbor"
  namespace = kubernetes_namespace_v1.harbor.metadata[0].name

  repository = "https://helm.goharbor.io"
  chart      = "harbor"
  version    = "1.19.2"

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true
  timeout         = 1200

  values = [
    yamlencode({
      expose = {
        type = "ingress"

        tls = {
          enabled    = true
          certSource = "secret"

          secret = {
            secretName = "harbor-tls"
          }
        }

        ingress = {
          className = "traefik"

          hosts = {
            core = "harbor.lab.harald-hiergeist.de"
          }

          annotations = {
            "cert-manager.io/cluster-issuer"                   = "letsencrypt-production"
            "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
          }
        }
      }

      externalURL = "https://harbor.lab.harald-hiergeist.de"

      existingSecretAdminPassword    = kubernetes_secret_v1.harbor_admin.metadata[0].name
      existingSecretAdminPasswordKey = "HARBOR_ADMIN_PASSWORD"

      updateStrategy = {
        type = "Recreate"
      }

      persistence = {
        enabled        = true
        resourcePolicy = "keep"

        persistentVolumeClaim = {
          registry = {
            storageClass = kubernetes_storage_class_v1.main_longhorn.metadata[0].name
            accessMode   = "ReadWriteOnce"
            size         = "50Gi"
          }

          jobservice = {
            jobLog = {
              storageClass = kubernetes_storage_class_v1.main_longhorn.metadata[0].name
              accessMode   = "ReadWriteOnce"
              size         = "5Gi"
            }
          }

          redis = {
            storageClass = kubernetes_storage_class_v1.main_longhorn.metadata[0].name
            accessMode   = "ReadWriteOnce"
            size         = "5Gi"
          }

          trivy = {
            storageClass = kubernetes_storage_class_v1.main_longhorn.metadata[0].name
            accessMode   = "ReadWriteOnce"
            size         = "10Gi"
          }
        }

        imageChartStorage = {
          type = "filesystem"

          filesystem = {
            rootdirectory = "/storage"
          }
        }
      }

      database = {
        type = "external"

        external = {
          host           = "platform-postgres-rw.database.svc.cluster.local"
          port           = 5432
          username       = "harbor"
          coreDatabase   = "harbor"
          existingSecret = kubernetes_secret_v1.harbor_db_runtime.metadata[0].name
          sslmode        = "require"
        }
      }

      # Seit Harbor 2.15.2 verwendet das Chart intern Valkey.
      redis = {
        type = "internal"
      }

      trivy = {
        enabled = true
      }

      metrics = {
        enabled = false
      }
    })
  ]

  depends_on = [
    kubernetes_manifest.harbor_database,
    kubernetes_secret_v1.harbor_db_runtime,
    kubernetes_secret_v1.harbor_admin
  ]
}
