resource "kubernetes_secret_v1" "fleet_main_gitops_ssh" {
  provider = kubernetes.rancher_vcluster

  metadata {
    name      = "main-gitops-ssh"
    namespace = "fleet-default"
  }

  type = "kubernetes.io/ssh-auth"

  data = {
    ssh-privatekey = file(pathexpand("~/.ssh/fleet-main-gitops"))
    known_hosts    = file(pathexpand("~/.ssh/fleet-main-gitops.known_hosts"))
  }
}

resource "kubernetes_manifest" "fleet_main_gitops" {
  provider = kubernetes.rancher_vcluster

  manifest = {
    apiVersion = "fleet.cattle.io/v1alpha1"
    kind       = "GitRepo"

    metadata = {
      name      = "main-gitops"
      namespace = "fleet-default"
    }

    spec = {
      repo             = "git@gitlab.lab.harald-hiergeist.de:harald-lab/main-gitops.git"
      branch           = "main"
      clientSecretName = kubernetes_secret_v1.fleet_main_gitops_ssh.metadata[0].name

      paths = [
        "apps"
      ]

      targets = [
        {
          name        = "main"
          clusterName = "main"
        }
      ]
    }
  }

  depends_on = [
    kubernetes_secret_v1.fleet_main_gitops_ssh
  ]
}
