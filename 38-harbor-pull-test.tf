resource "kubernetes_namespace_v1" "harbor_test" {
  provider = kubernetes.main

  metadata {
    name = "harbor-test"

    labels = {
      name = "harbor-test"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations
    ]
  }
}


resource "kubernetes_secret_v1" "runner_test_runtime_db" {
  provider = kubernetes.main

  metadata {
    name      = "runner-test-db"
    namespace = kubernetes_namespace_v1.harbor_test.metadata[0].name
  }

  type = "Opaque"

  data = {
    username = "runner_test"
    password = random_password.runner_test_db.result
  }
}

resource "kubernetes_secret_v1" "harbor_pull" {
  provider = kubernetes.main

  metadata {
    name      = "harbor-pull"
    namespace = kubernetes_namespace_v1.harbor_test.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "harbor.lab.harald-hiergeist.de" = {
          username = harbor_robot_account.kubernetes_pull.full_name
          password = random_password.harbor_robot_kubernetes_pull.result
          auth = base64encode(
            "${harbor_robot_account.kubernetes_pull.full_name}:${random_password.harbor_robot_kubernetes_pull.result}"
          )
        }
      }
    })
  }
}

