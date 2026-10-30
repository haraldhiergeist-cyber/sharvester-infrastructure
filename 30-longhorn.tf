resource "helm_release" "longhorn" {
  provider = helm.main

  name             = "longhorn"
  namespace        = "longhorn-system"
  create_namespace = true

  repository = "https://charts.longhorn.io"
  chart      = "longhorn"
  version    = "1.13.0"

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  wait_for_jobs   = true
  timeout         = 900

  values = [
    yamlencode({
      persistence = {
        createStorageClass = false
      }

      defaultSettings = {
        defaultDataPath                         = "/var/lib/longhorn"
        defaultReplicaCount                     = 3
        defaultDataLocality                     = "best-effort"
        storageOverProvisioningPercentage       = 100
        storageReservedPercentageForDefaultDisk = 10

        systemManagedComponentsNodeSelector = "node-role.kubernetes.io/worker:true"
      }

      longhornManager = {
        nodeSelector = {
          "node-role.kubernetes.io/worker" = "true"
        }
      }

      longhornDriver = {
        nodeSelector = {
          "node-role.kubernetes.io/worker" = "true"
        }
      }

      longhornUI = {
        nodeSelector = {
          "node-role.kubernetes.io/worker" = "true"
        }
      }

      longhornGlobalManager = {
        nodeSelector = {
          "node-role.kubernetes.io/worker" = "true"
        }
      }
    })
  ]
}
