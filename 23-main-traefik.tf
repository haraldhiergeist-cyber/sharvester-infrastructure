resource "kubernetes_manifest" "main_traefik_config" {
  provider = kubernetes.main

  manifest = {
    apiVersion = "helm.cattle.io/v1"
    kind       = "HelmChartConfig"

    metadata = {
      name      = "rke2-traefik"
      namespace = "kube-system"
    }

    spec = {
      valuesContent = <<-YAML
        service:
          spec:
            type: LoadBalancer
            ipFamilyPolicy: SingleStack
            ipFamilies:
              - IPv4
          annotations:
            metallb.io/loadBalancerIPs: "10.20.100.213"
            metallb.io/address-pool: "main"

        ports:
          ssh:
            port: 2222
            exposedPort: 22
            protocol: TCP
            expose:
              default: true

        additionalArguments:
          - "--entryPoints.ssh.address=:2222/tcp"
      YAML
    }
  }
}
