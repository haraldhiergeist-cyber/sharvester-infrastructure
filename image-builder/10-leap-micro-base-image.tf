# =============================================================================
# Fully automated Leap Micro 6.2 golden-image pipeline
# =============================================================================
# Graph:
# upstream qcow -> builder root volumes -> builder VMs -> wait for clean shutdown
# -> export PVCs -> control-plane + worker images -> Rancher MachineConfigs

provider "kubernetes" {
  alias          = "harvester"
  config_path    = pathexpand(var.harvester_kubeconfig_path)
  config_context = var.harvester_kubeconfig_context
}

resource "kubernetes_persistent_volume_claim_v1" "controlplane_builder_root" {
  provider         = kubernetes.harvester
  wait_until_bound = true

  metadata {
    name      = "leap-micro-62-controlplane-builder-root"
    namespace = local.builder_namespace

    annotations = {
      "harvesterhci.io/imageId" = harvester_image.leap_micro_upstream.id
    }
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    volume_mode        = "Block"
    storage_class_name = harvester_image.leap_micro_upstream.volume_storage_class_name

    resources {
      requests = {
        storage = "32Gi"
      }
    }
  }

  timeouts {
    create = "20m"
  }

  lifecycle {
    replace_triggered_by = [
      terraform_data.controlplane_build_inputs,
    ]
  }
}

resource "harvester_cloudinit_secret" "controlplane_builder" {
  name      = "leap-micro-62-controlplane-builder-cloudinit"
  namespace = local.builder_namespace
  user_data = file("${path.module}/cloud-init/controlplane-builder.yaml")
}

resource "harvester_cloudinit_secret" "worker_builder" {
  name      = "leap-micro-62-worker-builder-cloudinit"
  namespace = local.builder_namespace
  user_data = file("${path.module}/cloud-init/worker-builder.yaml")
}

resource "kubernetes_persistent_volume_claim_v1" "worker_builder_root" {
  provider         = kubernetes.harvester
  wait_until_bound = true

  metadata {
    name      = "leap-micro-62-worker-builder-root"
    namespace = local.builder_namespace

    annotations = {
      "harvesterhci.io/imageId" = harvester_image.leap_micro_upstream.id
    }
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    volume_mode        = "Block"
    storage_class_name = harvester_image.leap_micro_upstream.volume_storage_class_name

    resources {
      requests = {
        storage = "32Gi"
      }
    }
  }

  timeouts {
    create = "20m"
  }

  lifecycle {
    replace_triggered_by = [
      terraform_data.worker_build_inputs,
    ]
  }
}

locals {
  leap_micro_upstream_url = "https://download.opensuse.org/distribution/leap-micro/6.2/appliances/openSUSE-Leap-Micro.x86_64-6.2-Default-qcow-Build12.9.qcow2"

  image_namespace      = "harvester-public"
  builder_namespace    = "default"
  harvester_vm_network = "harvester-public/vlan100"

  builder_storage_class = "harvester-longhorn-bulk"
  target_storage_class  = "harvester-longhorn-nvme"

  controlplane_builder_name = "leap-micro-62-controlplane-builder"
  worker_builder_name       = "leap-micro-62-worker-builder"
}

# Pinned official openSUSE Leap Micro 6.2 upstream image.
resource "harvester_image" "leap_micro_upstream" {
  name               = "leap-micro-62-upstream"
  namespace          = local.image_namespace
  display_name       = "openSUSE-Leap-Micro-6.2-upstream"
  description        = "Pinned upstream openSUSE Leap Micro 6.2 Default-qcow Build12.9 used only to build RKE2 node images"
  source_type        = "download"
  storage_class_name = local.builder_storage_class
  url                = local.leap_micro_upstream_url

  timeouts {
    create = "30m"
    update = "30m"
    delete = "10m"
  }
}

# Minimal control-plane image: current Leap Micro patches, qemu-guest-agent,
# normal public CA trust, and automatic OS rebooting disabled.
resource "harvester_virtualmachine" "controlplane_builder" {
  name      = local.controlplane_builder_name
  namespace = local.builder_namespace

  description  = "Ephemeral builder for the RKE2 control-plane Leap Micro image"
  cpu          = 2
  memory       = "4Gi"
  hostname     = local.controlplane_builder_name
  run_strategy = "RerunOnFailure"

  network_interface {
    name           = "nic-1"
    model          = "virtio"
    type           = "bridge"
    network_name   = local.harvester_vm_network
    wait_for_lease = false
  }

  lifecycle {
    ignore_changes = all

    replace_triggered_by = [
      terraform_data.controlplane_build_inputs,
    ]
  }

  disk {
    name                 = "rootdisk"
    type                 = "disk"
    bus                  = "virtio"
    boot_order           = 1
    existing_volume_name = kubernetes_persistent_volume_claim_v1.controlplane_builder_root.metadata[0].name
    auto_delete          = false
  }

  cloudinit {
    user_data_secret_name = harvester_cloudinit_secret.controlplane_builder.name
  }

  timeouts {
    create = "20m"
    update = "20m"
    delete = "10m"
  }
}

# Worker image: current patches plus Longhorn host prerequisites.
resource "harvester_virtualmachine" "worker_builder" {
  name      = local.worker_builder_name
  namespace = local.builder_namespace

  description  = "Ephemeral builder for the RKE2 Longhorn worker Leap Micro image"
  cpu          = 2
  memory       = "4Gi"
  hostname     = local.worker_builder_name
  run_strategy = "RerunOnFailure"

  network_interface {
    name           = "nic-1"
    model          = "virtio"
    type           = "bridge"
    network_name   = local.harvester_vm_network
    wait_for_lease = false
  }

  lifecycle {
    ignore_changes = all

    replace_triggered_by = [
      terraform_data.worker_build_inputs,
    ]
  }

  disk {
    name                 = "rootdisk"
    type                 = "disk"
    bus                  = "virtio"
    boot_order           = 1
    existing_volume_name = kubernetes_persistent_volume_claim_v1.worker_builder_root.metadata[0].name
    auto_delete          = false
  }

  cloudinit {
    user_data_secret_name = harvester_cloudinit_secret.worker_builder.name
  }

  timeouts {
    create = "20m"
    update = "20m"
    delete = "10m"
  }
}

# Creation of a VM resource only proves that Harvester created/started it.
# These steps wait until the guest has patched itself, rebooted into the new
# transactional snapshot, passed verification, sanitized its identity, and
# deliberately powered itself off.
resource "terraform_data" "controlplane_builder_complete" {
  triggers_replace = [harvester_virtualmachine.controlplane_builder.id]

  provisioner "local-exec" {
    command = "${path.module}/scripts/wait-for-vm-stopped.sh '${pathexpand(var.harvester_kubeconfig_path)}' '${var.harvester_kubeconfig_context}' '${local.builder_namespace}' '${local.controlplane_builder_name}' '${var.golden_image_build_timeout_seconds}'"
  }
}

resource "terraform_data" "worker_builder_complete" {
  triggers_replace = [harvester_virtualmachine.worker_builder.id]

  provisioner "local-exec" {
    command = "${path.module}/scripts/wait-for-vm-stopped.sh '${pathexpand(var.harvester_kubeconfig_path)}' '${var.harvester_kubeconfig_context}' '${local.builder_namespace}' '${local.worker_builder_name}' '${var.golden_image_build_timeout_seconds}'"
  }
}

resource "terraform_data" "controlplane_build_inputs" {
  input = {
    upstream_url       = local.leap_micro_upstream_url
    cloud_init_sha256  = filesha256("${path.module}/cloud-init/controlplane-builder.yaml")
    wait_script_sha256 = filesha256("${path.module}/scripts/wait-for-vm-stopped.sh")
  }
}

resource "terraform_data" "worker_build_inputs" {
  input = {
    upstream_url       = local.leap_micro_upstream_url
    cloud_init_sha256  = filesha256("${path.module}/cloud-init/worker-builder.yaml")
    wait_script_sha256 = filesha256("${path.module}/scripts/wait-for-vm-stopped.sh")
  }
}

# Export the stopped, sanitized builder PVCs as reusable Harvester images.
resource "harvester_image" "leap_micro_controlplane" {
  depends_on = [terraform_data.controlplane_builder_complete]

  name               = "leap-micro-62-rke2-controlplane"
  namespace          = local.image_namespace
  display_name       = "opensuse-leap-micro-6.2-rke2-controlplane"
  description        = "Automated Leap Micro 6.2 image for Rancher-provisioned RKE2 control-plane/etcd nodes"
  source_type        = "export-from-volume"
  pvc_namespace      = local.builder_namespace
  pvc_name           = kubernetes_persistent_volume_claim_v1.controlplane_builder_root.metadata[0].name
  storage_class_name = local.target_storage_class

  timeouts {
    create = "30m"
    update = "30m"
    delete = "10m"
  }
}

resource "harvester_image" "leap_micro_worker" {
  depends_on = [terraform_data.worker_builder_complete]

  name               = "leap-micro-62-rke2-worker-v2"
  namespace          = local.image_namespace
  display_name       = "opensuse-leap-micro-6.2-rke2-worker-v2"
  description        = "Automated Leap Micro 6.2 image with Longhorn host prerequisites for RKE2 workers"
  source_type        = "export-from-volume"
  pvc_namespace      = local.builder_namespace
  pvc_name           = kubernetes_persistent_volume_claim_v1.worker_builder_root.metadata[0].name
  storage_class_name = local.target_storage_class

  timeouts {
    create = "30m"
    update = "30m"
    delete = "10m"
  }
}
