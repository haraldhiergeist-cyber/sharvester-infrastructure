resource "harbor_project" "sharvester" {
  name                   = "sharvester"
  public                 = false
  vulnerability_scanning = true

  depends_on = [
    helm_release.harbor
  ]
}

resource "random_password" "harbor_robot_gitlab_ci" {
  length  = 40
  special = false
}

resource "random_password" "harbor_robot_kubernetes_pull" {
  length  = 40
  special = false
}

resource "harbor_robot_account" "gitlab_ci" {
  name              = "gitlab-ci"
  description       = "GitLab CI push/pull access"
  level             = "project"
  secret_wo         = random_password.harbor_robot_gitlab_ci.result
  secret_wo_version = 1

  permissions {
    access {
      action   = "pull"
      resource = "repository"
    }

    access {
      action   = "push"
      resource = "repository"
    }

    kind      = "project"
    namespace = harbor_project.sharvester.name
  }
}

resource "harbor_robot_account" "kubernetes_pull" {
  name              = "kubernetes-pull"
  description       = "Kubernetes read-only image pull access"
  level             = "project"
  secret_wo         = random_password.harbor_robot_kubernetes_pull.result
  secret_wo_version = 1

  permissions {
    access {
      action   = "pull"
      resource = "repository"
    }

    kind      = "project"
    namespace = harbor_project.sharvester.name
  }
}
