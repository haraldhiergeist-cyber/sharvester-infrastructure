terraform {
  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = "1.8.2"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "3.2.1"
    }

    rancher2 = {
      source  = "rancher/rancher2"
      version = "~> 14.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }

    harbor = {
      source  = "goharbor/harbor"
      version = "3.12.5"
    }
  }
}

provider "harvester" {
  kubeconfig  = "~/.kube/config"
  kubecontext = "sharvester"
}

# Kubernetes API des Harvester-Hostclusters
provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "sharvester"
}

provider "kubernetes" {
  alias = "rancher_vcluster"

  config_path    = pathexpand("~/.kube/config")
  config_context = "rancher-vcluster"
}

provider "kubernetes" {
  alias          = "harvester"
  config_path    = pathexpand(var.harvester_kubeconfig_path)
  config_context = "sharvester"
}

provider "helm" {
  kubernetes = {
    config_path    = "~/.kube/config"
    config_context = "sharvester"
  }
}

provider "helm" {
  alias = "rancher_vcluster"

  kubernetes = {
    config_path    = pathexpand("~/.kube/config")
    config_context = "rancher-vcluster"
  }
}

resource "harvester_clusternetwork" "lab" {
  name        = "lab"
  description = "Lab network on second physical NIC"
}

resource "harvester_vlanconfig" "lab_sharvester" {
  name = "lab-sharvester"

  cluster_network_name = harvester_clusternetwork.lab.name

  uplink {
    nics = [
      "eno1"
    ]

    bond_mode   = "active-backup"
    mtu         = 1500
    bond_miimon = -1
  }

  node_selector = {
    "kubernetes.io/hostname" = "sharvester"
  }
}

resource "harvester_network" "vlan100" {
  name      = "vlan100"
  namespace = "harvester-public"

  vlan_id = 100

  route_mode           = "auto"
  route_dhcp_server_ip = ""

  cluster_network_name = harvester_clusternetwork.lab.name

  depends_on = [
    harvester_vlanconfig.lab_sharvester
  ]
}

resource "harvester_network" "untagged" {
  name      = "untagged"
  namespace = "harvester-public"

  vlan_id = 0

  route_mode           = "auto"
  route_dhcp_server_ip = ""

  cluster_network_name = "mgmt"
}

resource "kubernetes_annotations" "longhorn_not_default" {
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"

  metadata {
    name = "harvester-longhorn"
  }

  annotations = {
    "storageclass.kubernetes.io/is-default-class" = "false"
  }

  force = true
}

resource "harvester_storageclass" "single_node" {
  name        = "harvester-longhorn-single"
  description = "Longhorn storage class for single-node Harvester"

  is_default             = true
  allow_volume_expansion = true
  reclaim_policy         = "Delete"
  volume_binding_mode    = "Immediate"

  parameters = {
    migratable          = "true"
    numberOfReplicas    = "1"
    staleReplicaTimeout = "30"
  }

  depends_on = [
    kubernetes_annotations.longhorn_not_default
  ]
}

resource "harvester_image" "ubuntu2404" {
  name         = "ubuntu-2404"
  namespace    = "harvester-public"
  display_name = "ubuntu-24.04-lts"
  source_type  = "download"

  url                = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  storage_class_name = harvester_storageclass.single_node.name
}

resource "harvester_cloudinit_secret" "bastion" {
  name      = "bastion-cloudinit"
  namespace = "default"

  user_data = <<-EOF
    #cloud-config

    hostname: bastion
    manage_etc_hosts: false

    users:
      - name: harald
        shell: /bin/bash
        sudo: "ALL=(ALL) NOPASSWD:ALL"
        lock_passwd: true
        ssh_authorized_keys:
          - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJiRBenVkZy54abHbEVYu/nIPJL1uUbHqf1bxlrFGFHT haral@DESKTOP-I6L4OTM
    package_update: true

    packages:
      - qemu-guest-agent
      - dnsmasq
      - nftables

    write_files:

      - path: /etc/sysctl.d/99-bastion-router.conf
        permissions: "0644"
        content: |
          net.ipv4.ip_forward=1

      - path: /etc/nftables.conf
        permissions: "0644"
        content: |
          #!/usr/sbin/nft -f

          flush ruleset

          table inet filter {
            chain forward {
              type filter hook forward priority 0;
              policy drop;

              ct state established,related accept

              iifname "lan0" oifname "wan0" accept
              iifname "wan0" oifname "lan0" accept
            }
          }

          table ip nat {
            chain postrouting {
              type nat hook postrouting priority 100;

              ip saddr 10.20.100.0/24 oifname "wan0" masquerade
            }
          }

      - path: /etc/dnsmasq.conf
        permissions: "0644"
        content: |
          dhcp-ignore-clid
          dhcp-authoritative

          interface=lan0
          interface=wan0
          bind-interfaces

          listen-address=10.20.100.1,192.168.0.200

          # DHCP ausschließlich im Lab-Netz
          no-dhcp-interface=wan0

          dhcp-range=vlan100,10.20.100.100,10.20.100.200,12h

          # Rancher Master
          dhcp-host=6e:03:06:70:3b:0e,10.20.100.11,rancher-master1
          dhcp-host=b2:69:69:a8:07:1d,10.20.100.12,rancher-master2
          dhcp-host=4a:33:9b:2c:d0:70,10.20.100.13,rancher-master3

          # Rancher Worker
          dhcp-host=6a:ce:84:5a:50:60,10.20.100.21,rancher-worker1
          dhcp-host=ca:96:05:65:29:5c,10.20.100.22,rancher-worker2
          dhcp-host=72:6d:d0:29:fc:75,10.20.100.23,rancher-worker3

          # Main Master
          dhcp-host=02:42:ac:11:00:02,10.20.100.31,main-master1
          dhcp-host=02:42:ac:11:00:03,10.20.100.32,main-master2
          dhcp-host=02:42:ac:11:00:04,10.20.100.33,main-master3

          # Main Worker
          dhcp-host=02:42:ac:11:00:05,10.20.100.41,main-worker1
          dhcp-host=02:42:ac:11:00:06,10.20.100.42,main-worker2
          dhcp-host=02:42:ac:11:00:07,10.20.100.43,main-worker3

          dhcp-host=56:8d:6d:69:11:b1,10.20.100.51,postgres
          dhcp-host=c6:c2:d6:d0:80:e6,10.20.100.52,gitlab

          addn-hosts=/etc/hosts

          server=/fritz.box/192.168.0.2
          server=8.8.8.8
          server=1.1.1.1

          domain=lab.harald-hiergeist.de
          local=/lab.harald-hiergeist.de/
          expand-hosts

          dhcp-option=15,lab.harald-hiergeist.de
          dhcp-option=3,10.20.100.1
          dhcp-option=6,10.20.100.1

          log-queries
          log-dhcp

          dhcp-leasefile=/var/lib/misc/dnsmasq.leases

      - path: /etc/hosts
        permissions: "0644"
        content: |
          127.0.0.1 localhost


          ::1     ip6-localhost ip6-loopback
          fe00::0 ip6-localnet
          ff00::0 ip6-mcastprefix
          ff02::1 ip6-allnodes
          ff02::2 ip6-allrouters

          10.20.100.1   bastion.lab.harald-hiergeist.de

          10.20.100.11  rancher-master1.lab.harald-hiergeist.de
          10.20.100.12  rancher-master2.lab.harald-hiergeist.de
          10.20.100.13  rancher-master3.lab.harald-hiergeist.de
          10.20.100.21  rancher-worker1.lab.harald-hiergeist.de
          10.20.100.22  rancher-worker2.lab.harald-hiergeist.de
          10.20.100.23  rancher-worker3.lab.harald-hiergeist.de

          10.20.100.31  main-master1.lab.harald-hiergeist.de
          10.20.100.32  main-master2.lab.harald-hiergeist.de
          10.20.100.33  main-master3.lab.harald-hiergeist.de
          10.20.100.41  main-worker1.lab.harald-hiergeist.de
          10.20.100.42  main-worker2.lab.harald-hiergeist.de
          10.20.100.43  main-worker3.lab.harald-hiergeist.de

          10.20.100.51  postgres.lab.harald-hiergeist.de
          10.20.100.52  gitlab.lab.harald-hiergeist.de

          10.20.100.210 rancher.lab.harald-hiergeist.de

          10.20.100.213 main.lab.harald-hiergeist.de
          10.20.100.213 harbor.lab.harald-hiergeist.de
          10.20.100.213 keycloak.lab.harald-hiergeist.de
          10.20.100.213 kafka-ui.lab.harald-hiergeist.de
          10.20.100.213 redis.lab.harald-hiergeist.de
          10.20.100.213 plc-ui.lab.harald-hiergeist.de
          10.20.100.213 plc-query.lab.harald-hiergeist.de
          10.20.100.213 grafana.lab.harald-hiergeist.de
          10.20.100.213 plc-ui-quarkus.lab.harald-hiergeist.de
          10.20.100.213 plc-query-quarkus.lab.harald-hiergeist.de

    runcmd:
      - sysctl --system
      - systemctl enable --now qemu-guest-agent
      - systemctl enable --now nftables
      - nft -f /etc/nftables.conf
      - systemctl restart dnsmasq
  EOF

  network_data = <<-EOF
    version: 2

    ethernets:
      wan0:
        match:
          macaddress: "02:00:00:20:00:01"
        set-name: wan0
        addresses:
          - 192.168.0.200/24
        routes:
          - to: default
            via: 192.168.0.2
        nameservers:
          addresses:
            - 192.168.0.2

      lan0:
        match:
          macaddress: "02:00:00:20:00:02"
        set-name: lan0
        addresses:
          - 10.20.100.1/24
  EOF
}

resource "harvester_virtualmachine" "bastion" {
  name      = "bastion"
  namespace = "default"

  description = "DNS, DHCP and routing gateway for the lab network"

  cpu    = 1
  memory = "1Gi"

  hostname = "bastion"

  efi         = true
  secure_boot = false

  run_strategy = "RerunOnFailure"

  network_interface {
    name        = "wan"
    model       = "virtio"
    type        = "bridge"
    mac_address = "02:00:00:20:00:01"

    network_name = harvester_network.untagged.id
  }

  lifecycle {
    ignore_changes = [
      disk,
    ]
  }

  network_interface {
    name        = "lan"
    model       = "virtio"
    type        = "bridge"
    mac_address = "02:00:00:20:00:02"

    network_name = harvester_network.vlan100.id
  }

  disk {
    name        = "rootdisk"
    type        = "disk"
    size        = "8Gi"
    bus         = "virtio"
    boot_order  = 1
    image       = harvester_image.ubuntu2404.id
    auto_delete = true
  }

  cloudinit {
    user_data_secret_name    = harvester_cloudinit_secret.bastion.name
    network_data_secret_name = harvester_cloudinit_secret.bastion.name
  }

  depends_on = [
    harvester_network.vlan100,
    harvester_storageclass.single_node,
    harvester_image.ubuntu2404
  ]
}

resource "harvester_storageclass" "nvme" {
  name                   = "harvester-longhorn-nvme"
  description            = "Longhorn storage class for NVMe disks"
  is_default             = false
  allow_volume_expansion = true
  reclaim_policy         = "Delete"
  volume_binding_mode    = "Immediate"

  parameters = {
    migratable          = "true"
    numberOfReplicas    = "1"
    staleReplicaTimeout = "30"
    diskSelector        = "nvme"
  }
}

resource "harvester_storageclass" "bulk" {
  name = "harvester-longhorn-bulk"

  parameters = {
    diskSelector        = "bulk"
    migratable          = "true"
    numberOfReplicas    = "1"
    staleReplicaTimeout = "30"
  }
}

resource "harvester_cloudinit_secret" "vm" {
  name      = "vm-cloudinit"
  namespace = "default"

  user_data = <<-EOF
    #cloud-config
    users:
      - name: harald
        shell: /bin/bash
        sudo: "ALL=(ALL) NOPASSWD:ALL"
        lock_passwd: true
        ssh_authorized_keys:
          - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJiRBenVkZy54abHbEVYu/nIPJL1uUbHqf1bxlrFGFHT haral@DESKTOP-I6L4OTM
  EOF
}

resource "harvester_ssh_key" "harald" {
  name      = "harald"
  namespace = "default"

  public_key = trimspace(var.ssh_public_key)
}


resource "harvester_image" "ubuntu2404_nvme" {
  name      = "ubuntu-2404-nvme"
  namespace = "harvester-public"

  display_name = "ubuntu-24.04-nvme"

  source_type = "download"
  url         = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"

  storage_class_name = "harvester-longhorn-nvme"
}
