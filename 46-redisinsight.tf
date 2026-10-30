resource "random_password" "redisinsight_encryption_key" {
  length  = 64
  special = false
}

resource "kubernetes_secret_v1" "redisinsight" {
  provider = kubernetes.main

  metadata {
    name      = "redisinsight"
    namespace = "redis"
  }

  data = {
    encryption-key = random_password.redisinsight_encryption_key.result
  }

  type = "Opaque"
}

resource "kubernetes_persistent_volume_claim_v1" "redisinsight" {
  provider = kubernetes.main

  metadata {
    name      = "redisinsight-data"
    namespace = "redis"
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "main-longhorn"

    resources {
      requests = {
        storage = "2Gi"
      }
    }
  }
}

resource "kubernetes_deployment_v1" "redisinsight" {
  provider = kubernetes.main

  metadata {
    name      = "redisinsight"
    namespace = "redis"

    labels = {
      app = "redisinsight"
    }
  }

  spec {
    replicas = 1

    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "redisinsight"
      }
    }

    template {
      metadata {
        labels = {
          app = "redisinsight"
        }
      }

      spec {
        security_context {
          fs_group = 1000

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        init_container {
          name  = "init-data"
          image = "busybox:1.36"

          command = [
            "sh",
            "-c",
            "chown -R 1000:1000 /data"
          ]

          security_context {
            run_as_user = 0
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        container {
          name  = "redisinsight"
          image = "redis/redisinsight:3.8.0"

          port {
            name           = "http"
            container_port = 5540
          }

          env {
            name  = "RI_APP_HOST"
            value = "0.0.0.0"
          }

          env {
            name  = "RI_APP_PORT"
            value = "5540"
          }

          env {
            name  = "RI_REDIS_HOST"
            value = "redis.redis.svc.cluster.local"
          }

          env {
            name  = "RI_REDIS_PORT"
            value = "6379"
          }

          env {
            name  = "RI_REDIS_ALIAS"
            value = "platform-redis"
          }

          env {
            name  = "RI_REDIS_USERNAME"
            value = "default"
          }

          env {
            name = "RI_REDIS_PASSWORD"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.redis_auth.metadata[0].name
                key  = "password"
              }
            }
          }

          env {
            name = "RI_ENCRYPTION_KEY"

            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.redisinsight.metadata[0].name
                key  = "encryption-key"
              }
            }
          }

          readiness_probe {
            http_get {
              path = "/api/health/"
              port = 5540
            }

            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/api/health/"
              port = 5540
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
              cpu    = "1"
              memory = "1Gi"
            }
          }

          security_context {
            run_as_non_root            = true
            run_as_user                = 1000
            run_as_group               = 1000
            allow_privilege_escalation = false

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
            claim_name = kubernetes_persistent_volume_claim_v1.redisinsight.metadata[0].name
          }
        }
      }
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["field.cattle.io/publicEndpoints"]
    ]
  }
}

resource "kubernetes_service_v1" "redisinsight" {
  provider = kubernetes.main

  metadata {
    name      = "redisinsight"
    namespace = "redis"
  }

  spec {
    selector = {
      app = "redisinsight"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 5540
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "redisinsight" {
  provider = kubernetes.main

  metadata {
    name      = "redisinsight"
    namespace = "redis"

    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-production"
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "redisinsight.lab.harald-hiergeist.de"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.redisinsight.metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }

    tls {
      hosts = [
        "redisinsight.lab.harald-hiergeist.de"
      ]

      secret_name = "redisinsight-tls"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["field.cattle.io/publicEndpoints"]
    ]
  }
}
