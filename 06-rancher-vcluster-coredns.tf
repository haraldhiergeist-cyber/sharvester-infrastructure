#
# Additional DNS records required by Rancher's Harvester machine driver.
#
# The vCluster-provided CoreDNS imports:
#
#   import /etc/coredns/custom/*.server
#
# so coredns-custom is the extension point and does not modify
# the vCluster-managed "coredns" ConfigMap itself.
#

resource "kubernetes_config_map_v1" "rancher_vcluster_coredns_custom" {
  provider = kubernetes.rancher_vcluster

  metadata {
    name      = "coredns-custom"
    namespace = "kube-system"
  }

  data = {
    "rancher.server" = chomp(<<-EOT
      rancher.lab.harald-hiergeist.de:1053 {
          hosts {
              192.168.0.233 rancher.lab.harald-hiergeist.de
          }
      }
    EOT
    )

    "sharvester.server" = chomp(<<-EOT
      sharvester:1053 {
          hosts {
              192.168.0.233 sharvester
          }
      }
    EOT
    )

    "lab-harald-hiergeist.server" = chomp(<<-EOT
      lab.harald-hiergeist.de:1053 {
          forward . 192.168.0.200
      }
    EOT
    )
  }
}
