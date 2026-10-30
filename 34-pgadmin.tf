resource "random_password" "pgadmin_admin" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "pgadmin_admin" {
  provider = kubernetes.main

  metadata {
    name      = "pgadmin-admin"
    namespace = kubernetes_namespace_v1.database.metadata[0].name
  }

  type = "Opaque"

  data = {
    email    = "pgadmin@lab.harald-hiergeist.de"
    password = random_password.pgadmin_admin.result
  }
}

resource "kubernetes_config_map_v1" "pgadmin_servers" {
  provider = kubernetes.main

  metadata {
    name      = "pgadmin-servers"
    namespace = kubernetes_namespace_v1.database.metadata[0].name
  }

  data = {
    "servers.json" = jsonencode({
      Servers = {
        "1" = {
          Name          = "Platform PostgreSQL - Harbor"
          Group         = "Platform"
          Host          = "platform-postgres-rw.database.svc.cluster.local"
          Port          = 5432
          MaintenanceDB = "harbor"
          Username      = "harbor"

          ConnectionParameters = {
            sslmode         = "prefer"
            connect_timeout = 10
          }
        }

        "2" = {
          Name          = "Platform PostgreSQL - Keycloak"
          Group         = "Platform"
          Host          = "platform-postgres-rw.database.svc.cluster.local"
          Port          = 5432
          MaintenanceDB = "keycloak"
          Username      = "keycloak"

          ConnectionParameters = {
            sslmode         = "prefer"
            connect_timeout = 10
          }
        }
      }
    })
  }
}

resource "kubernetes_persistent_volume_claim_v1" "pgadmin" {
  provider = kubernetes.main

  metadata {
    name      = "pgadmin-data"
    namespace = kubernetes_namespace_v1.database.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = kubernetes_storage_class_v1.main_longhorn.metadata[0].name

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "pgadmin" {
  provider = kubernetes.main

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["field.cattle.io/publicEndpoints"]
    ]
  }

  metadata {
    name      = "pgadmin"
    namespace = kubernetes_namespace_v1.database.metadata[0].name

    labels = {
      app = "pgadmin"
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "pgadmin"
      }
    }

    template {
      metadata {
        labels = {
          app = "pgadmin"
        }
      }

      spec {
        security_context {
          fs_group               = 5050
          fs_group_change_policy = "OnRootMismatch"
        }

        container {
          name  = "pgadmin"
          image = "dpage/pgadmin4:9.18"

          security_context {
            run_as_non_root            = true
            run_as_user                = 5050
            run_as_group               = 5050
            allow_privilege_escalation = false

            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            name           = "http"
            container_port = 8080
          }

          env {
            name = "PGADMIN_DEFAULT_EMAIL"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.pgadmin_admin.metadata[0].name
                key  = "email"
              }
            }
          }

          env {
            name = "PGADMIN_DEFAULT_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.pgadmin_admin.metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name  = "PGADMIN_LISTEN_PORT"
            value = "8080"
          }

          env {
            name  = "PGADMIN_DISABLE_POSTFIX"
            value = "1"
          }

          env {
            name  = "PGADMIN_SERVER_JSON_FILE"
            value = "/pgadmin4/servers.json"
          }

          volume_mount {
            name       = "data"
            mount_path = "/var/lib/pgadmin"
          }

          volume_mount {
            name       = "servers"
            mount_path = "/pgadmin4/servers.json"
            sub_path   = "servers.json"
            read_only  = true
          }

          readiness_probe {
            http_get {
              path = "/misc/ping"
              port = "http"
            }

            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/misc/ping"
              port = "http"
            }

            initial_delay_seconds = 30
            period_seconds        = 20
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }

            limits = {
              memory = "1Gi"
            }
          }
        }

        volume {
          name = "data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.pgadmin.metadata[0].name
          }
        }

        volume {
          name = "servers"

          config_map {
            name = kubernetes_config_map_v1.pgadmin_servers.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_persistent_volume_claim_v1.pgadmin
  ]
}

resource "kubernetes_service_v1" "pgadmin" {
  provider = kubernetes.main

  metadata {
    name      = "pgadmin"
    namespace = kubernetes_namespace_v1.database.metadata[0].name
  }

  spec {
    selector = {
      app = "pgadmin"
    }

    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "pgadmin" {
  provider = kubernetes.main

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["field.cattle.io/publicEndpoints"]
    ]
  }

  metadata {
    name      = "pgadmin"
    namespace = kubernetes_namespace_v1.database.metadata[0].name

    annotations = {
      "cert-manager.io/cluster-issuer"                   = "letsencrypt-production"
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
    }
  }

  spec {
    ingress_class_name = "traefik"

    tls {
      hosts = [
        "pgadmin.lab.harald-hiergeist.de"
      ]

      secret_name = "pgadmin-tls"
    }

    rule {
      host = "pgadmin.lab.harald-hiergeist.de"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.pgadmin.metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
