resource "random_password" "kafka_ui_admin" {
  length  = 32
  special = false
}

resource "kubernetes_deployment_v1" "kafka_console" {
  provider = kubernetes.main

  metadata {
    name      = "kafka-console"
    namespace = "kafka"

    labels = {
      app = "kafka-console"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "kafka-console"
      }
    }

    template {
      metadata {
        labels = {
          app = "kafka-console"
        }
      }

      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = 99
          run_as_group    = 99
          fs_group        = 99

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }


        container {
          name  = "kafka-console"
          image = "docker.redpanda.com/redpandadata/console:v3.12.0"

          env {
            name  = "KAFKA_BROKERS"
            value = "platform-kafka-kafka-bootstrap.kafka.svc.cluster.local:9092"
          }

          env {
            name  = "SERVER_LISTENPORT"
            value = "8080"
          }

          port {
            name           = "http"
            container_port = 8080
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }

            limits = {
              cpu    = "1"
              memory = "512Mi"
            }
          }

          # CONTAINER security context
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 99

            capabilities {
              drop = ["ALL"]
            }
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

resource "kubernetes_service_v1" "kafka_console" {
  provider = kubernetes.main

  metadata {
    name      = "kafka-console"
    namespace = "kafka"
  }

  spec {
    selector = {
      app = "kafka-console"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "kafka_console" {
  provider = kubernetes.main

  metadata {
    name      = "kafka-console"
    namespace = "kafka"

    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-production"
    }
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "kafka-ui.lab.harald-hiergeist.de"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.kafka_console.metadata[0].name

              port {
                number = 8080
              }
            }
          }
        }
      }
    }

    tls {
      hosts = [
        "kafka-ui.lab.harald-hiergeist.de"
      ]

      secret_name = "kafka-ui-tls"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["field.cattle.io/publicEndpoints"]
    ]
  }
}

output "kafka_ui_admin_password" {
  value     = random_password.kafka_ui_admin.result
  sensitive = true
}
