# =============================================================================
# Rancher-provisioned RKE2 guest cluster "main"
# =============================================================================

variable "main_rke2_version" {
  description = "Pinned RKE2 version for the main cluster."
  type        = string
  nullable    = false
}

variable "main_kube_vip" {
  description = "Static kube-vip address in 10.20.100.0/24, outside the Bastion DHCP range 10.20.100.100-200."
  type        = string
  nullable    = false
}

variable "main_ssh_user" {
  description = "SSH/cloud user used by the Leap Micro images."
  type        = string
  default     = "opensuse"
}

variable "main_controlplane_cpu" {
  type    = number
  default = 4
}

variable "main_controlplane_memory_gib" {
  type    = number
  default = 8
}

variable "main_worker_cpu" {
  type    = number
  default = 4
}

variable "main_worker_memory_gib" {
  type    = number
  default = 8
}

variable "main_os_disk_gib" {
  type    = number
  default = 32
}

variable "main_longhorn_data_disk_gib" {
  type    = number
  default = 150
}

locals {
  main_cluster_name       = "main"
  harvester_cluster_name  = "sharvester"
  harvester_vm_namespace  = "default"
  main_controlplane_count = 3
  main_worker_count       = 3

  main_etcd_snapshot_cron      = "0 */6 * * *"
  main_etcd_snapshot_retention = 5

  main_kube_vip_version   = "v1.2.4"
  main_kube_vip_interface = "eth0"
  main_kube_vip_address   = "10.20.100.211"

  main_controlplane_image = "harvester-public/leap-micro-62-rke2-controlplane"
  main_worker_image       = "harvester-public/leap-micro-62-rke2-worker-v2"

  main_vm_network           = "harvester-public/vlan100"
  main_target_storage_class = harvester_storageclass.nvme.name
}

# Rancher already knows Harvester as an imported cluster.
data "rancher2_cluster_v2" "sharvester" {
  name = local.harvester_cluster_name
}

# Do not depend on data.rancher2_cluster_v2.sharvester.kube_config: imported
# Harvester clusters can return that field empty. Reuse the kubeconfig that is
# already known to work with kubectl/Harvester provider on the OpenTofu VM.
resource "rancher2_cloud_credential" "sharvester" {
  name = "sharvester-main-rke2"

  harvester_credential_config {
    cluster_id         = data.rancher2_cluster_v2.sharvester.cluster_v1_id
    cluster_type       = "imported"
    kubeconfig_content = file(pathexpand(var.harvester_kubeconfig_path))
  }

  lifecycle {
    ignore_changes = [
      harvester_credential_config
    ]
  }
}

resource "rancher2_machine_config_v2" "main_controlplane" {
  # Both image resources must have been built/exported before Rancher receives
  # the machine templates.

  generate_name = "main-controlplane-"

  harvester_config {
    vm_namespace         = local.harvester_vm_namespace
    cpu_count            = tostring(var.main_controlplane_cpu)
    memory_size          = tostring(var.main_controlplane_memory_gib)
    ssh_user             = var.main_ssh_user
    reserved_memory_size = "-1"

    disk_info = jsonencode({
      disks = [
        {
          imageName = local.main_controlplane_image
          size      = var.main_os_disk_gib
          bootOrder = 1
        }
      ]
    })

    network_info = jsonencode({
      interfaces = [
        {
          networkName = local.main_vm_network
        }
      ]
    })
    user_data = <<-CLOUDINIT
      #cloud-config

      users:
        - default
        - name: harald
          groups:
            - wheel
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          lock_passwd: true
          ssh_authorized_keys:
    ${join("\n", [for key in local.main_ssh_public_keys : "        - ${key}"])}

      ssh_pwauth: false
      disable_root: true

      runcmd:
        - [ bash, -lc, 'systemctl enable --now qemu-guest-agent.service' ]
    CLOUDINIT
  }
}

resource "rancher2_machine_config_v2" "main_worker" {

  generate_name = "main-worker-"

  harvester_config {
    vm_namespace         = local.harvester_vm_namespace
    cpu_count            = tostring(var.main_worker_cpu)
    memory_size          = tostring(var.main_worker_memory_gib)
    ssh_user             = var.main_ssh_user
    reserved_memory_size = "-1"

    disk_info = jsonencode({
      disks = [
        {
          imageName = local.main_worker_image
          size      = var.main_os_disk_gib
          bootOrder = 1
        },
        {
          storageClassName = local.main_target_storage_class
          size             = var.main_longhorn_data_disk_gib
          bootOrder        = 2
        }
      ]
    })

    network_info = jsonencode({
      interfaces = [
        {
          networkName = local.main_vm_network
        }
      ]
    })

    # Golden image already contains all host packages. Per-VM cloud-init only
    # enables services and prepares the dedicated Longhorn data disk.

    user_data = <<-CLOUDINIT
      #cloud-config

      users:
        - default
        - name: harald
          groups:
            - wheel
          sudo: ALL=(ALL) NOPASSWD:ALL
          shell: /bin/bash
          lock_passwd: true
          ssh_authorized_keys:
    ${join("\n", [for key in local.main_ssh_public_keys : "        - ${key}"])}

      ssh_pwauth: false
      disable_root: true

      runcmd:
       - [ bash, -lc, 'systemctl enable --now qemu-guest-agent.service' ]
       - [ bash, -lc, 'modprobe iscsi_tcp && systemctl enable --now iscsid.service' ]
       - [ bash, -lc, 'systemctl mask --now transactional-update.timer' ]
       - [ bash, -lc, 'for i in $(seq 1 60); do test -b /dev/vdc && exit 0; sleep 1; done; echo "/dev/vdc not found" >&2; exit 1' ]
       - [ bash, -lc, 'fstype="$(blkid -s TYPE -o value /dev/vdc 2>/dev/null || true)"; label="$(blkid -s LABEL -o value /dev/vdc 2>/dev/null || true)"; if [ -z "$fstype" ]; then mkfs.ext4 -F -L longhorn-data /dev/vdc; elif [ "$fstype" != "ext4" ] || [ "$label" != "longhorn-data" ]; then echo "Unexpected filesystem on /dev/vdc: type=$fstype label=$label" >&2; exit 1; fi' ]
       - [ mkdir, -p, /var/lib/longhorn ]
       - [ bash, -lc, 'grep -q "^LABEL=longhorn-data /var/lib/longhorn " /etc/fstab || echo "LABEL=longhorn-data /var/lib/longhorn ext4 defaults 0 2" >> /etc/fstab' ]
       - [ mount, -a ]
    CLOUDINIT
  }
}

resource "rancher2_cluster_v2" "main" {
  name               = local.main_cluster_name
  kubernetes_version = var.main_rke2_version

  rke_config {

    additional_manifest = templatefile(
      "${path.module}/templates/main-kube-vip.yaml.tftpl",
      {
        kube_vip_address   = local.main_kube_vip_address
        kube_vip_interface = local.main_kube_vip_interface
        kube_vip_version   = local.main_kube_vip_version
      }
    )

    machine_pools {
      name                         = "controlplane"
      cloud_credential_secret_name = rancher2_cloud_credential.sharvester.id

      control_plane_role = true
      etcd_role          = true
      worker_role        = false
      quantity           = local.main_controlplane_count

      drain_before_delete = true
      node_drain_timeout  = 600

      rolling_update {
        max_unavailable = "1"
        max_surge       = "1"
      }

      machine_config {
        kind = rancher2_machine_config_v2.main_controlplane.kind
        name = rancher2_machine_config_v2.main_controlplane.name
      }

    }

    machine_pools {
      name                         = "worker"
      cloud_credential_secret_name = rancher2_cloud_credential.sharvester.id

      control_plane_role = false
      etcd_role          = false
      worker_role        = true
      quantity           = local.main_worker_count

      drain_before_delete = true
      node_drain_timeout  = 600

      rolling_update {
        max_unavailable = "1"
        max_surge       = "0"
      }

      machine_labels = {
        "node.longhorn.io/create-default-disk" = "true"
      }

      machine_config {
        kind = rancher2_machine_config_v2.main_worker.kind
        name = rancher2_machine_config_v2.main_worker.name
      }
    }

    machine_selector_config {
      config = yamlencode({
        "cloud-provider-name" = ""
      })
    }

    # kube-vip itself is installed as a post-bootstrap add-on. The VIP must be
    # present in the API server certificate before that happens.
    machine_global_config = yamlencode({
      "tls-san" = [var.main_kube_vip]
      "ingress-controller" = [
        "traefik"
      ]
    })

    etcd {
      snapshot_schedule_cron = local.main_etcd_snapshot_cron
      snapshot_retention     = local.main_etcd_snapshot_retention
    }

    upgrade_strategy {
      control_plane_concurrency = "1"
      worker_concurrency        = "1"
    }
  }

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

variable "main_ssh_public_key_paths" {
  type = list(string)

  default = [
    "~/.ssh/id_ed25519.pub",
    "~/.ssh/windows_id_ed25519.pub",
  ]
}

locals {
  main_ssh_public_keys = [
    for path in var.main_ssh_public_key_paths :
    trimspace(file(pathexpand(path)))
  ]
}
