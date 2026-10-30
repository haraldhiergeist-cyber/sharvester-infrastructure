variable "rancher_vcluster_api_vip" {
  description = "Dedicated VIP for the Rancher vCluster API"
  type        = string
  default     = "192.168.0.238"
}

data "kubernetes_service_v1" "rancher_vcluster_host" {
  provider = kubernetes.harvester

  metadata {
    name      = "rancher-vcluster"
    namespace = "rancher-vcluster"
  }
}

resource "kubernetes_service_v1" "rancher_vcluster_api" {
  provider = kubernetes.harvester

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["kube-vip.io/vipHost"]
    ]
  }

  metadata {
    name      = "rancher-vcluster-api"
    namespace = "rancher-vcluster"

    annotations = {
      "kube-vip.io/loadbalancerIPs" = var.rancher_vcluster_api_vip
    }
  }

  spec {
    type = "LoadBalancer"

    selector = data.kubernetes_service_v1.rancher_vcluster_host.spec[0].selector

    port {
      name        = "https"
      port        = 443
      target_port = data.kubernetes_service_v1.rancher_vcluster_host.spec[0].port[0].target_port
      protocol    = "TCP"
    }

    external_traffic_policy = "Cluster"
  }
}
