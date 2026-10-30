resource "random_password" "harbor_db" {
  length  = 32
  special = false
}

resource "random_password" "keycloak_db" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "harbor_db" {
  provider = kubernetes.main

  metadata {
    name      = "harbor-db-credentials"
    namespace = kubernetes_namespace_v1.database.metadata[0].name

    labels = {
      "cnpg.io/reload" = "true"
    }
  }

  type = "kubernetes.io/basic-auth"

  data = {
    username = "harbor"
    password = random_password.harbor_db.result
  }
}

resource "kubernetes_secret_v1" "keycloak_db" {
  provider = kubernetes.main

  metadata {
    name      = "keycloak-db-credentials"
    namespace = kubernetes_namespace_v1.database.metadata[0].name

    labels = {
      "cnpg.io/reload" = "true"
    }
  }

  type = "kubernetes.io/basic-auth"

  data = {
    username = "keycloak"
    password = random_password.keycloak_db.result
  }
}

resource "kubernetes_manifest" "harbor_db_role" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "DatabaseRole"

    metadata = {
      name      = "harbor"
      namespace = kubernetes_namespace_v1.database.metadata[0].name
    }

    spec = {
      cluster = {
        name = "platform-postgres"
      }

      name        = "harbor"
      login       = true
      superuser   = false
      createdb    = false
      createrole  = false
      replication = false

      databaseRoleReclaimPolicy = "retain"

      passwordSecret = {
        name = kubernetes_secret_v1.harbor_db.metadata[0].name
      }
    }
  }

  depends_on = [
    kubernetes_manifest.platform_postgres,
    kubernetes_secret_v1.harbor_db
  ]
}

resource "kubernetes_manifest" "keycloak_db_role" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "DatabaseRole"

    metadata = {
      name      = "keycloak"
      namespace = kubernetes_namespace_v1.database.metadata[0].name
    }

    spec = {
      cluster = {
        name = "platform-postgres"
      }

      name        = "keycloak"
      login       = true
      superuser   = false
      createdb    = false
      createrole  = false
      replication = false

      databaseRoleReclaimPolicy = "retain"

      passwordSecret = {
        name = kubernetes_secret_v1.keycloak_db.metadata[0].name
      }
    }
  }

  depends_on = [
    kubernetes_manifest.platform_postgres,
    kubernetes_secret_v1.keycloak_db
  ]
}

resource "kubernetes_manifest" "harbor_database" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"

    metadata = {
      name      = "harbor"
      namespace = kubernetes_namespace_v1.database.metadata[0].name
    }

    spec = {
      cluster = {
        name = "platform-postgres"
      }

      name                  = "harbor"
      owner                 = "harbor"
      databaseReclaimPolicy = "retain"
    }
  }

  depends_on = [
    kubernetes_manifest.harbor_db_role
  ]
}

resource "kubernetes_manifest" "keycloak_database" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "postgresql.cnpg.io/v1"
    kind       = "Database"

    metadata = {
      name      = "keycloak"
      namespace = kubernetes_namespace_v1.database.metadata[0].name
    }

    spec = {
      cluster = {
        name = "platform-postgres"
      }

      name                  = "keycloak"
      owner                 = "keycloak"
      databaseReclaimPolicy = "retain"
    }
  }

  depends_on = [
    kubernetes_manifest.keycloak_db_role
  ]
}
