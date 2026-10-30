# Sharvester

OpenTofu-managed homelab infrastructure based on Harvester, Rancher and RKE2.

The repository manages the persistent infrastructure around the `main` RKE2 cluster. Golden-image creation is intentionally separated into `image-builder/` and uses its own temporary OpenTofu state.

## Architecture

The environment consists of:

- Single-node Harvester cluster: `sharvester`
- Rancher running as Harvester vCluster/add-on
- Rancher hostname: `rancher.lab.harald-hiergeist.de`
- Rancher ingress IP: `192.168.0.233`
- Downstream RKE2 cluster: `main`
- 3 control-plane/etcd nodes
- 3 worker nodes
- openSUSE Leap Micro 6.2 golden images
- kube-vip for the Kubernetes API
- MetalLB for service LoadBalancers
- RKE2 Traefik ingress
- cert-manager with IONOS Hosting DNS DNS-01 validation
- Longhorn-backed Harvester storage

## Network

Main workload network:

```text
Network:             10.20.100.0/24
Bastion / DNS:       10.20.100.1
DHCP range:          10.20.100.100-200

Kubernetes API VIP:  10.20.100.211
Reserved:            10.20.100.212

MetalLB pool:        10.20.100.213-10.20.100.220
Traefik LoadBalancer 10.20.100.213
```

Harvester VM network:

```text
harvester-public/vlan100
```

Applications are expected below:

```text
*.lab.harald-hiergeist.de
```

## RKE2 cluster

RKE2 version:

```text
v1.35.8+rke2r1
```

Control-plane pool:

```text
quantity:        3
roles:           control-plane, etcd
CPU:             2
RAM:             6 GiB
OS disk:         40 GiB
rolling update:
  maxSurge:       1
  maxUnavailable: 1
```

Worker pool:

```text
quantity:        3
role:            worker
CPU:             8
RAM:             16 GiB
OS disk:         40 GiB
Longhorn disk:   250 GiB
mount:           /var/lib/longhorn

rolling update:
  maxSurge:       0
  maxUnavailable: 1
```

`maxSurge = 0` is intentional. Each worker carries a large Longhorn data disk and the Harvester host has limited NVMe capacity. A surge rollout can otherwise exhaust schedulable storage.

## Storage layout

Two explicit Harvester/Longhorn storage tiers are used.

### Bulk storage

StorageClass:

```text
harvester-longhorn-bulk
```

Longhorn disk tag:

```text
bulk
```

Used for temporary image-building resources:

```text
openSUSE upstream image
builder root disks
```

### NVMe storage

StorageClass:

```text
harvester-longhorn-nvme
```

Longhorn disk tag:

```text
nvme
```

Used for:

```text
golden images
control-plane OS disks
worker OS disks
worker Longhorn data disks
```

The Longhorn default disk must carry the `bulk` tag and the NVMe disk must carry the `nvme` tag.

Current disk-tag verification:

```bash
kubectl --context sharvester -n longhorn-system \
  get nodes.longhorn.io sharvester -o json | jq '
    .spec.disks
    | to_entries[]
    | {
        id: .key,
        path: .value.path,
        tags: .value.tags,
        allowScheduling: .value.allowScheduling
      }
  '
```

Expected result:

```text
default disk -> ["bulk"]
NVMe disk    -> ["nvme"]
```

The `bulk` tag is currently an external prerequisite and should eventually be made part of an idempotent Harvester bootstrap procedure.

## Golden images

The production cluster currently consumes:

```text
harvester-public/leap-micro-62-rke2-controlplane
harvester-public/leap-micro-62-rke2-worker
```

Both images are 32 GiB.

The main infrastructure stack does not own the image-build process. It only references the released image IDs.

Image creation lives under:

```text
image-builder/
```

See:

```text
image-builder/README.md
```

## kube-vip

The Kubernetes API VIP is:

```text
10.20.100.211
```

kube-vip is bootstrapped as part of the Rancher `rancher2_cluster_v2.main` resource through `rke_config.additional_manifest`.

This avoids the previous chicken-and-egg problem where the Kubernetes provider needed a working API VIP before kube-vip itself could be created.

Expected state:

```bash
kubectl --context main-direct -n kube-system \
  get daemonset kube-vip-ds
```

Expected:

```text
DESIRED   CURRENT   READY
3         3         3
```

A basic VIP reachability test is:

```bash
curl -k https://10.20.100.211:6443/version
```

Without credentials, this normally returns:

```text
401 Unauthorized
```

That is sufficient to prove that the Kubernetes API is reachable through the VIP.

## kubeconfig contexts

The central kubeconfig is:

```text
~/.kube/config
```

Relevant contexts:

```text
sharvester
rancher-vcluster
main
rancher
main-direct
```

`main-direct` connects directly to:

```text
https://10.20.100.211:6443
```

It uses client certificate authentication and does not depend on the Rancher proxy.

The direct context is recreated after a cold cluster bootstrap with:

```bash
./scripts/bootstrap-main-direct.sh
```

The script:

1. reads the API VIP from OpenTofu output
2. obtains Rancher's generated kubeconfig from state
3. discovers a control-plane VM
4. reads `/etc/rancher/rke2/rke2.yaml`
5. builds a direct kubeconfig using the VIP
6. merges the `main-direct` context into `~/.kube/config`
7. validates the connection

Do not manually copy long-lived Kubernetes credentials into the repository.

## MetalLB

MetalLB runs in:

```text
metallb-system
```

Address pool:

```text
10.20.100.213-10.20.100.220
```

Traefik receives:

```text
10.20.100.213
```

On a completely fresh cluster, MetalLB must be bootstrapped in two phases because its CRDs need to exist before OpenTofu can create the corresponding custom resources.

First:

```bash
tofu apply \
  -target=kubernetes_namespace_v1.main_metallb \
  -target=helm_release.main_metallb
```

Then wait:

```bash
kubectl --context main-direct wait \
  --for=condition=Established \
  crd/ipaddresspools.metallb.io \
  crd/l2advertisements.metallb.io \
  --timeout=120s
```

After that, a normal OpenTofu apply can create the pool and L2Advertisement.

## Traefik

RKE2's Traefik installation is used.

The service is configured as a LoadBalancer and receives:

```text
10.20.100.213
```

Verification:

```bash
kubectl --context main-direct -n kube-system \
  get svc rke2-traefik
```

Expected external IP:

```text
10.20.100.213
```

## cert-manager and IONOS DNS

cert-manager runs in:

```text
cert-manager
```

The IONOS Hosting DNS webhook is used.

Webhook:

```text
cert-manager-webhook-ionos
```

Solver group:

```text
acme.fabmade.de
```

Solver name:

```text
ionos
```

IONOS Hosting DNS endpoint:

```text
https://api.hosting.ionos.com/dns/v1
```

The credentials are intentionally not stored in OpenTofu state.

Expected environment variables:

```text
IONOS_PUBLIC_PREFIX
IONOS_SECRET
```

They are stored outside the repository in:

```text
~/.config/sharvester/secrets.env
```

Permissions should be:

```bash
chmod 600 ~/.config/sharvester/secrets.env
```

The Kubernetes Secret is created idempotently with:

```bash
./scripts/bootstrap-ionos-secret.sh
```

The Secret contains:

```text
IONOS_PUBLIC_PREFIX
IONOS_SECRET
```

Do not place the IONOS credentials in `.tf`, `.tfvars` or OpenTofu state.

## Let's Encrypt

Production ClusterIssuer:

```text
letsencrypt-production
```

Verification:

```bash
kubectl --context main-direct get clusterissuer
```

Expected:

```text
NAME                     READY
letsencrypt-production   True
```

## Cold bootstrap procedure

The following sequence has been tested successfully from a completely removed `main` cluster.

### 1. Verify Harvester base infrastructure

The following must already exist:

```text
Harvester host
Rancher vCluster
VLAN/network
bulk StorageClass
NVMe StorageClass
golden images
Bastion
Rancher Harvester cloud credential prerequisites
```

Verify the disk tags:

```bash
kubectl --context sharvester -n longhorn-system \
  get nodes.longhorn.io sharvester -o json | jq '.spec.disks'
```

### 2. Build golden images if necessary

See:

```text
image-builder/README.md
```

This is not required when usable released images already exist.

### 3. Create the Rancher-managed RKE2 cluster

Plan only the core cluster:

```bash
tofu plan \
  -target=rancher2_cluster_v2.main \
  -out=/tmp/rebuild-main.plan
```

Apply:

```bash
tofu apply /tmp/rebuild-main.plan
```

This creates:

```text
rancher2_machine_config_v2.main_controlplane
rancher2_machine_config_v2.main_worker
rancher2_cluster_v2.main
```

kube-vip is included through the Rancher additional manifest.

### 4. Wait for the six VMs

```bash
kubectl --context sharvester -n default get vm
```

Expected:

```text
3 x main-controlplane-...
3 x main-worker-...
```

### 5. Verify the API VIP

```bash
curl -k https://10.20.100.211:6443/version
```

A `401 Unauthorized` response proves reachability.

### 6. Bootstrap `main-direct`

```bash
./scripts/bootstrap-main-direct.sh
```

Verify:

```bash
kubectl --context main-direct get nodes -o wide
```

Expected:

```text
3 control-plane/etcd Ready
3 worker Ready
```

### 7. Bootstrap MetalLB and cert-manager Helm releases

```bash
tofu apply \
  -target=kubernetes_namespace_v1.main_metallb \
  -target=kubernetes_namespace_v1.main_cert_manager \
  -target=helm_release.main_metallb \
  -target=helm_release.main_cert_manager \
  -target=helm_release.main_ionos_webhook
```

### 8. Wait for CRDs

```bash
kubectl --context main-direct wait \
  --for=condition=Established \
  crd/ipaddresspools.metallb.io \
  crd/l2advertisements.metallb.io \
  --timeout=120s
```

```bash
kubectl --context main-direct wait \
  --for=condition=Established \
  crd/clusterissuers.cert-manager.io \
  crd/certificates.cert-manager.io \
  --timeout=120s
```

### 9. Bootstrap IONOS Secret

```bash
./scripts/bootstrap-ionos-secret.sh
```

### 10. Complete the infrastructure

```bash
tofu plan -out=/tmp/final-main-bootstrap.plan
tofu apply /tmp/final-main-bootstrap.plan
```

### 11. Final acceptance

```bash
kubectl --context main-direct get nodes
kubectl --context main-direct -n kube-system get ds kube-vip-ds
kubectl --context main-direct -n metallb-system get pods
kubectl --context main-direct -n cert-manager get pods
kubectl --context main-direct get clusterissuer
kubectl --context main-direct get svc -A | grep LoadBalancer
```

Finally:

```bash
tofu plan
```

Expected:

```text
No changes. Your infrastructure matches the configuration.
```

This exact cold-bootstrap path has been successfully tested.

## Repository layout

```text
sharvester/
├── 00-rancher-provider.tf
├── 05-helm-main-provider.tf
├── 05-kubernetes-main-provider.tf
├── 06-rancher-vcluster-coredns.tf
├── 20-rke2-main.tf
├── 22-main-metallb.tf
├── 23-main-traefik.tf
├── 24-main-cert-manager.tf
├── 25-main-letsencrypt.tf
├── 30-outputs.tf
├── 31-main-api-outputs.tf
├── cert-manager.tf
├── cert-manager-ionos.tf
├── rancher-vcluster-cert-manager.tf
├── main.tf
├── variables.tf
├── scripts/
│   ├── bootstrap-main-direct.sh
│   └── bootstrap-ionos-secret.sh
├── templates/
├── image-builder/
│   ├── README.md
│   ├── 10-leap-micro-base-image.tf
│   ├── providers.tf
│   ├── variables.tf
│   ├── cloud-init/
│   └── scripts/
└── README.md
```

## State

The primary stack uses a local OpenTofu state.

Never commit:

```text
terraform.tfstate
terraform.tfstate.*
*.tfvars
*.auto.tfvars
*.plan
.terraform/
```

The dependency lock files should be committed:

```text
.terraform.lock.hcl
image-builder/.terraform.lock.hcl
```

State backups belong outside the repository, for example:

```text
~/backups/sharvester/
```

## Secrets

Do not commit:

```text
Rancher API tokens
IONOS credentials
private SSH keys
kubeconfig files
terraform state
tfvars containing secrets
```

Rancher authentication is supplied through:

```text
TF_VAR_rancher_token
```

IONOS credentials are supplied through:

```text
IONOS_PUBLIC_PREFIX
IONOS_SECRET
```

## Known-good verification

The environment is considered healthy when all of the following succeed:

```bash
kubectl --context main-direct get nodes
```

All six nodes must be `Ready`.

```bash
kubectl --context main-direct -n kube-system get ds kube-vip-ds
```

Must show `3/3`.

```bash
kubectl --context main-direct get clusterissuer
```

`letsencrypt-production` must show `True`.

```bash
kubectl --context main-direct get svc -A | grep LoadBalancer
```

Traefik must show:

```text
10.20.100.213
```

And finally:

```bash
tofu plan
```

must return:

```text
No changes. Your infrastructure matches the configuration.
```
