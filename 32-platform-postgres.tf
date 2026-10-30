resource "kubernetes_namespace_v1" "database" {
  provider = kubernetes.main

  metadata {
    name = "database"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations
    ]
  }
}

resource "kubernetes_manifest" "platform_postgres" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Cluster"

    metadata = {
      name      = "platform-postgres"
      namespace = kubernetes_namespace_v1.database.metadata[0].name
    }

    spec = {
      instances = 3

      imageName = "ghcr.io/cloudnative-pg/postgresql:17.11-standard-trixie"

      bootstrap = {
        initdb = {
          database      = "platform"
          owner         = "platform"
          dataChecksums = true
        }
      }

      storage = {
        storageClass = kubernetes_storage_class_v1.main_longhorn.metadata[0].name
        size         = "20Gi"
      }

      affinity = {
        enablePodAntiAffinity = true
        topologyKey           = "kubernetes.io/hostname"
        podAntiAffinityType   = "required"
      }

      resources = {
        requests = {
          cpu    = "250m"
          memory = "512Mi"
        }
      }

      enableSuperuserAccess = false
    }
  }

  depends_on = [
    helm_release.cloudnative_pg,
    kubernetes_namespace_v1.database
  ]
}
