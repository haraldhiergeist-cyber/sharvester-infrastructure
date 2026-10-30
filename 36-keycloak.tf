resource "kubernetes_namespace_v1" "keycloak" {
  provider = kubernetes.main

  metadata {
    name = "keycloak"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations
    ]
  }
}

resource "random_password" "keycloak_admin" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "keycloak_admin" {
  provider = kubernetes.main

  metadata {
    name      = "keycloak-admin"
    namespace = kubernetes_namespace_v1.keycloak.metadata[0].name
  }

  type = "Opaque"

  data = {
    username = "admin"
    password = random_password.keycloak_admin.result
  }
}

resource "kubernetes_secret_v1" "keycloak_db_runtime" {
  provider = kubernetes.main

  metadata {
    name      = "keycloak-db-credentials"
    namespace = kubernetes_namespace_v1.keycloak.metadata[0].name
  }

  type = "Opaque"

  data = {
    username = "keycloak"
    password = random_password.keycloak_db.result
  }
}

resource "kubernetes_deployment_v1" "keycloak" {
  provider = kubernetes.main

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["field.cattle.io/publicEndpoints"]
    ]
  }

  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.keycloak.metadata[0].name

    labels = {
      app = "keycloak"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "keycloak"
      }
    }

    template {
      metadata {
        labels = {
          app = "keycloak"
        }
      }

      spec {
        node_selector = {
          "node-role.kubernetes.io/worker" = "true"
        }

        affinity {
          pod_anti_affinity {
            required_during_scheduling_ignored_during_execution {
              topology_key = "kubernetes.io/hostname"

              label_selector {
                match_expressions {
                  key      = "app"
                  operator = "In"
                  values   = ["keycloak"]
                }
              }
            }
          }
        }

        container {
          name  = "keycloak"
          image = "quay.io/keycloak/keycloak:26.8.1"

          command = [
            "/opt/keycloak/bin/kc.sh"
          ]

          args = [
            "start"
          ]

          port {
            name           = "http"
            container_port = 8080
          }

          port {
            name           = "jgroups"
            container_port = 7800
          }

          env {
            name  = "KC_DB"
            value = "postgres"
          }

          env {
            name  = "KC_DB_URL"
            value = "jdbc:postgresql://platform-postgres-rw.database.svc.cluster.local:5432/keycloak?sslmode=require"
          }

          env {
            name = "KC_DB_USERNAME"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.keycloak_db_runtime.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "KC_DB_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.keycloak_db_runtime.metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name = "KC_BOOTSTRAP_ADMIN_USERNAME"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.keycloak_admin.metadata[0].name
                key  = "username"
              }
            }
          }

          env {
            name = "KC_BOOTSTRAP_ADMIN_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.keycloak_admin.metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name  = "KC_HOSTNAME"
            value = "https://keycloak.lab.harald-hiergeist.de"
          }

          env {
            name  = "KC_HTTP_ENABLED"
            value = "true"
          }

          env {
            name  = "KC_PROXY_HEADERS"
            value = "xforwarded"
          }

          env {
            name  = "KC_CACHE"
            value = "ispn"
          }

          env {
            name  = "KC_CACHE_STACK"
            value = "jdbc-ping"
          }

          startup_probe {
            tcp_socket {
              port = "http"
            }

            period_seconds    = 5
            failure_threshold = 60
          }

          readiness_probe {
            tcp_socket {
              port = "http"
            }

            period_seconds = 10
          }

          liveness_probe {
            tcp_socket {
              port = "http"
            }

            initial_delay_seconds = 30
            period_seconds        = 20
          }

          resources {
            requests = {
              cpu    = "250m"
              memory = "768Mi"
            }

            limits = {
              memory = "1536Mi"
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_manifest.keycloak_database,
    kubernetes_secret_v1.keycloak_db_runtime
  ]
}

resource "kubernetes_service_v1" "keycloak" {
  provider = kubernetes.main

  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.keycloak.metadata[0].name
  }

  spec {
    selector = {
      app = "keycloak"
    }

    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "keycloak" {
  provider = kubernetes.main

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["field.cattle.io/publicEndpoints"]
    ]
  }

  metadata {
    name      = "keycloak"
    namespace = kubernetes_namespace_v1.keycloak.metadata[0].name

    annotations = {
      "cert-manager.io/cluster-issuer"                   = "letsencrypt-production"
      "traefik.ingress.kubernetes.io/router.entrypoints" = "websecure"
    }
  }

  spec {
    ingress_class_name = "traefik"

    tls {
      hosts = [
        "keycloak.lab.harald-hiergeist.de"
      ]

      secret_name = "keycloak-tls"
    }

    rule {
      host = "keycloak.lab.harald-hiergeist.de"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.keycloak.metadata[0].name

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
