resource "kubernetes_namespace_v1" "redis" {
  provider = kubernetes.main

  metadata {
    name = "redis"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations
    ]
  }
}

resource "random_password" "redis" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "redis_auth" {
  provider = kubernetes.main

  metadata {
    name      = "redis-auth"
    namespace = kubernetes_namespace_v1.redis.metadata[0].name
  }

  data = {
    password = random_password.redis.result
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim_v1" "redis_data" {
  provider = kubernetes.main

  metadata {
    name      = "redis-data"
    namespace = kubernetes_namespace_v1.redis.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "main-longhorn"

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "redis" {
  provider = kubernetes.main

  metadata {
    name      = "redis"
    namespace = kubernetes_namespace_v1.redis.metadata[0].name

    labels = {
      app = "redis"
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "redis"
      }
    }

    template {
      metadata {
        labels = {
          app = "redis"
        }
      }

      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = 999
          run_as_group    = 1000
          fs_group        = 1000

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "redis"
          image = "redis:8.2.10-alpine"

          command = [
            "sh",
            "-c"
          ]

          args = [
            <<-EOT
              exec redis-server \
                --bind 0.0.0.0 \
                --port 6379 \
                --appendonly yes \
                --appendfsync everysec \
                --requirepass "$REDIS_PASSWORD" \
                --dir /data
            EOT
          ]

          env {
            name = "REDIS_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.redis_auth.metadata[0].name
                key  = "password"
              }
            }
          }

          port {
            name           = "redis"
            container_port = 6379
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }

            limits = {
              cpu    = "1"
              memory = "1Gi"
            }
          }

          readiness_probe {
            exec {
              command = [
                "sh",
                "-c",
                "REDISCLI_AUTH=\"$REDIS_PASSWORD\" redis-cli ping | grep -q PONG"
              ]
            }

            initial_delay_seconds = 5
            period_seconds        = 10
          }

          liveness_probe {
            exec {
              command = [
                "sh",
                "-c",
                "REDISCLI_AUTH=\"$REDIS_PASSWORD\" redis-cli ping | grep -q PONG"
              ]
            }

            initial_delay_seconds = 15
            period_seconds        = 20
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true

            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        volume {
          name = "data"

          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.redis_data.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "redis" {
  provider = kubernetes.main

  metadata {
    name      = "redis"
    namespace = kubernetes_namespace_v1.redis.metadata[0].name
  }

  spec {
    selector = {
      app = "redis"
    }

    port {
      name        = "redis"
      port        = 6379
      target_port = 6379
    }

    type = "ClusterIP"
  }
}
