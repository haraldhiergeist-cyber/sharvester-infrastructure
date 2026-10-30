resource "kubernetes_manifest" "platform_kafka_nodepool" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "kafka.strimzi.io/v1"
    kind       = "KafkaNodePool"

    metadata = {
      name      = "mixed"
      namespace = kubernetes_namespace_v1.kafka.metadata[0].name

      labels = {
        "strimzi.io/cluster" = "platform-kafka"
      }
    }

    spec = {
      replicas = 3

      roles = [
        "controller",
        "broker"
      ]

      storage = {
        type = "jbod"

        volumes = [
          {
            id          = 0
            type        = "persistent-claim"
            size        = "20Gi"
            class       = kubernetes_storage_class_v1.main_longhorn_single.metadata[0].name
            deleteClaim = false
          }
        ]
      }

      resources = {
        requests = {
          cpu    = "500m"
          memory = "1Gi"
        }

        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
      }

      template = {
        pod = {
          affinity = {
            podAntiAffinity = {
              requiredDuringSchedulingIgnoredDuringExecution = [
                {
                  labelSelector = {
                    matchExpressions = [
                      {
                        key      = "strimzi.io/pool-name"
                        operator = "In"
                        values   = ["mixed"]
                      }
                    ]
                  }

                  topologyKey = "kubernetes.io/hostname"
                }
              ]
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_manifest" "platform_kafka" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "kafka.strimzi.io/v1"
    kind       = "Kafka"

    metadata = {
      name      = "platform-kafka"
      namespace = kubernetes_namespace_v1.kafka.metadata[0].name
    }

    spec = {
      kafka = {
        version         = "4.3.1"
        metadataVersion = "4.3-IV0"

        listeners = [
          {
            name = "plain"
            port = 9092
            type = "internal"
            tls  = false
          }
        ]

        config = {
          "offsets.topic.replication.factor"         = 3
          "transaction.state.log.replication.factor" = 3
          "transaction.state.log.min.isr"            = 2
          "default.replication.factor"               = 3
          "min.insync.replicas"                      = 2
          "num.partitions"                           = 3
        }
      }

      entityOperator = {
        topicOperator = {}
        userOperator  = {}
      }
    }
  }

  depends_on = [
    kubernetes_manifest.platform_kafka_nodepool
  ]
}
