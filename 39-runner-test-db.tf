resource "random_password" "runner_test_db" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "runner_test_db" {
  provider = kubernetes.main

  metadata {
    name      = "runner-test-db-credentials"
    namespace = kubernetes_namespace_v1.database.metadata[0].name

    labels = {
      "cnpg.io/reload" = "true"
    }
  }

  type = "kubernetes.io/basic-auth"

  data = {
    username = "runner_test"
    password = random_password.runner_test_db.result
  }
}

resource "kubernetes_manifest" "runner_test_db_role" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "DatabaseRole"

    metadata = {
      name      = "runner-test"
      namespace = kubernetes_namespace_v1.database.metadata[0].name
    }

    spec = {
      cluster = {
        name = "platform-postgres"
      }

      name        = "runner_test"
      login       = true
      superuser   = false
      createdb    = false
      createrole  = false
      replication = false

      databaseRoleReclaimPolicy = "retain"

      passwordSecret = {
        name = kubernetes_secret_v1.runner_test_db.metadata[0].name
      }
    }
  }

  depends_on = [
    kubernetes_manifest.platform_postgres,
    kubernetes_secret_v1.runner_test_db
  ]
}

resource "kubernetes_manifest" "runner_test_database" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"

    metadata = {
      name      = "runner-test"
      namespace = kubernetes_namespace_v1.database.metadata[0].name
    }

    spec = {
      cluster = {
        name = "platform-postgres"
      }

      name                  = "runner_test"
      owner                 = "runner_test"
      databaseReclaimPolicy = "retain"
    }
  }

  depends_on = [
    kubernetes_manifest.runner_test_db_role
  ]
}
