resource "kubernetes_namespace_v1" "gitlab_proxy" {
  provider = kubernetes.main

  metadata {
    name = "gitlab-proxy"
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations
    ]
  }
}

resource "kubernetes_service_v1" "gitlab_ssh" {
  provider = kubernetes.main

  metadata {
    name      = "gitlab-ssh"
    namespace = kubernetes_namespace_v1.gitlab_proxy.metadata[0].name
  }

  spec {
    port {
      name        = "ssh"
      port        = 22
      target_port = 22
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_manifest" "gitlab_ssh_endpoint" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "discovery.k8s.io/v1"
    kind       = "EndpointSlice"

    metadata = {
      name      = "gitlab-ssh"
      namespace = kubernetes_namespace_v1.gitlab_proxy.metadata[0].name

      labels = {
        "kubernetes.io/service-name" = "gitlab-ssh"
      }
    }

    addressType = "IPv4"

    ports = [
      {
        name     = "ssh"
        protocol = "TCP"
        port     = 22
      }
    ]

    endpoints = [
      {
        addresses = ["10.20.100.210"]

        conditions = {
          ready = true
        }
      }
    ]
  }
}

resource "kubernetes_manifest" "gitlab_ssh_route" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "traefik.io/v1alpha1"
    kind       = "IngressRouteTCP"

    metadata = {
      name      = "gitlab-ssh"
      namespace = kubernetes_namespace_v1.gitlab_proxy.metadata[0].name
    }

    spec = {
      ingressClassName = "traefik"

      entryPoints = ["ssh"]

      routes = [
        {
          match = "HostSNI(`*`)"

          services = [
            {
              name     = kubernetes_service_v1.gitlab_ssh.metadata[0].name
              port     = 22
              nativeLB = true
            }
          ]
        }
      ]
    }
  }

  depends_on = [
    kubernetes_manifest.gitlab_ssh_endpoint
  ]
}
