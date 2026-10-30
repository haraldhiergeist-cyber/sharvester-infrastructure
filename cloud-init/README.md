# Leap Micro Golden Image Builder

This directory contains the standalone OpenTofu pipeline used to create the openSUSE Leap Micro 6.2 golden images consumed by the Sharvester `main` RKE2 cluster.

The builder is intentionally separated from the production infrastructure state.

## Purpose

The builder creates two images:

```text
RKE2 control-plane/etcd image
RKE2 worker image with Longhorn prerequisites
```

The builder itself is temporary.

Normal production operation should not require:

```text
builder VMs
builder PVCs
upstream SUSE image
builder OpenTofu state
```

Only the released golden images need to remain in Harvester.

## Storage model

Temporary build resources use:

```text
harvester-longhorn-bulk
```

which selects the Longhorn disk tagged:

```text
bulk
```

Released golden images use:

```text
harvester-longhorn-nvme
```

which selects the Longhorn disk tagged:

```text
nvme
```

This keeps transient build storage away from the limited NVMe tier.

## Builder sizes

Control-plane builder root disk:

```text
32 GiB
```

Worker builder root disk:

```text
32 GiB
```

Released golden images are therefore also approximately:

```text
32 GiB
```

The production RKE2 nodes may use larger OS disks. The current main cluster uses:

```text
40 GiB OS disks
```

## Upstream image

Pinned openSUSE Leap Micro 6.2 image:

```text
openSUSE-Leap-Micro.x86_64-6.2-Default-qcow-Build12.9.qcow2
```

Source:

```text
https://download.opensuse.org/distribution/leap-micro/6.2/appliances/openSUSE-Leap-Micro.x86_64-6.2-Default-qcow-Build12.9.qcow2
```

The upstream image is temporary and is downloaded to the `bulk` storage tier.

## Build graph

The pipeline is:

```text
Pinned upstream qcow
        |
        v
32 GiB builder PVCs on bulk storage
        |
        v
Control-plane + worker builder VMs
        |
        v
transactional-update
        |
        v
Golden-image sanitization
        |
        v
Builder shutdown
        |
        v
Export builder PVCs
        |
        v
Golden images on NVMe
```

## Control-plane image

The control-plane image installs and prepares:

```text
qemu-guest-agent
ca-certificates
```

The transactional-update timer is disabled in the resulting image.

The image is sanitized before export:

```text
SSH host keys removed
machine-id cleared
cloud-init state cleaned
builder-specific files removed
```

## Worker image

The worker image additionally prepares the node for Longhorn:

```text
open-iscsi
nfs-client
cryptsetup
device-mapper
kernel-default
qemu-guest-agent
ca-certificates
```

The build validates:

```text
iscsiadm
mount.nfs
cryptsetup
dmsetup
iscsi_tcp kernel module
```

`iscsid.service` and `qemu-guest-agent.service` are enabled in the resulting snapshot.

The transactional-update timer is disabled so Kubernetes node updates and reboots can be orchestrated deliberately.

## Files

```text
image-builder/
├── 10-leap-micro-base-image.tf
├── providers.tf
├── variables.tf
├── cloud-init/
│   ├── controlplane-builder.yaml
│   └── worker-builder.yaml
├── scripts/
│   └── wait-for-vm-stopped.sh
├── .terraform.lock.hcl
└── README.md
```

## Providers

The builder only needs:

```text
harvester/harvester
hashicorp/kubernetes
```

The Kubernetes provider points explicitly to:

```text
context: sharvester
```

This is deliberate. The builder must not depend on whichever kubeconfig context happens to be current.

## Required kubeconfig

Expected path:

```text
~/.kube/config
```

Expected context:

```text
sharvester
```

Verification:

```bash
kubectl --context sharvester get nodes
```

## Required storage prerequisites

The main Sharvester stack owns the StorageClasses.

The builder only consumes them:

```text
harvester-longhorn-bulk
harvester-longhorn-nvme
```

Verify:

```bash
kubectl --context sharvester get storageclass \
  harvester-longhorn-bulk \
  harvester-longhorn-nvme
```

Verify Longhorn disk tags:

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

Expected:

```text
default disk -> bulk
NVMe disk    -> nvme
```

## State model

The builder does not share state with the main infrastructure stack.

The production stack references released image IDs directly.

The builder state is only needed while a build is in progress.

After a successful release:

1. released images remain in Harvester
2. released images are removed from the temporary builder state
3. builder VMs are destroyed
4. builder PVCs are destroyed
5. the upstream image is destroyed
6. temporary builder state can be archived or removed

This avoids permanently reserving storage for build resources.

## Current released images

The currently consumed images are:

```text
harvester-public/leap-micro-62-rke2-controlplane
harvester-public/leap-micro-62-rke2-worker
```

These images are currently in active production use.

Do not delete or replace them while current VM disks still reference them.

Verification:

```bash
kubectl --context sharvester -n harvester-public \
  get virtualmachineimage | grep 'leap-micro-62-rke2'
```

## Important: immutable releases

The next improvement to this builder is immutable release naming.

The current production images use fixed names:

```text
leap-micro-62-rke2-controlplane
leap-micro-62-rke2-worker
```

Do not blindly run a new build that attempts to replace these objects.

Harvester refuses deletion of an image while VM volumes still reference it, and replacing an image under the same name is therefore not a safe rollout mechanism.

Future releases should use unique names, for example:

```text
leap-micro-62-rke2-controlplane-<release>
leap-micro-62-rke2-worker-<release>
```

A release may be based on a build-input hash, for example:

```text
leap-micro-62-rke2-worker-d550e5c1398b
```

The desired workflow is:

```text
build new immutable image
        |
        v
verify image
        |
        v
update main stack image ID
        |
        v
Rancher rolls nodes
        |
        v
verify all new OS disks reference new image
        |
        v
delete old image only when unused
```

Until immutable release naming has been implemented in the OpenTofu code, treat the builder configuration as a build definition rather than something that should be applied blindly against the current production image names.

## Building a release

Before starting:

```bash
cd ~/sharvester/image-builder
```

Verify:

```bash
tofu init
tofu validate
```

Check Harvester:

```bash
kubectl --context sharvester get nodes
```

Check storage:

```bash
kubectl --context sharvester get storageclass \
  harvester-longhorn-bulk \
  harvester-longhorn-nvme
```

Before running an actual build, ensure the image resource names are unique and do not collide with production images currently in use.

Then:

```bash
tofu plan
```

Review the plan carefully.

A fresh build should create temporary resources similar to:

```text
harvester_image.leap_micro_upstream

kubernetes_persistent_volume_claim_v1.controlplane_builder_root
kubernetes_persistent_volume_claim_v1.worker_builder_root

harvester_cloudinit_secret.controlplane_builder
harvester_cloudinit_secret.worker_builder

harvester_virtualmachine.controlplane_builder
harvester_virtualmachine.worker_builder

terraform_data.controlplane_build_inputs
terraform_data.worker_build_inputs

terraform_data.controlplane_builder_complete
terraform_data.worker_builder_complete

harvester_image.leap_micro_controlplane
harvester_image.leap_micro_worker
```

Do not apply if the plan proposes destroying an image currently used by production VMs.

## Build completion

The builder VMs shut themselves down after completing the transactional image preparation.

The script:

```text
scripts/wait-for-vm-stopped.sh
```

waits for the builder VM to reach the stopped state before the corresponding PVC is exported.

The script always uses the explicit Harvester kubeconfig context.

## Verify builder placement

During a build:

```bash
kubectl --context sharvester -n default get pvc \
  -o custom-columns='NAME:.metadata.name,SIZE:.spec.resources.requests.storage,SC:.spec.storageClassName'
```

The builder PVCs should be:

```text
32Gi
```

The underlying upstream image StorageClass must select:

```text
bulk
```

## Verify golden images

After export:

```bash
kubectl --context sharvester -n harvester-public \
  get virtualmachineimage
```

Golden images should report:

```text
progress: 100
```

The generated image StorageClasses should use:

```text
diskSelector = nvme
```

## Promotion

The production stack should reference a released image by fixed immutable ID.

Example:

```hcl
locals {
  main_controlplane_image = "harvester-public/leap-micro-62-rke2-controlplane-<release>"
  main_worker_image       = "harvester-public/leap-micro-62-rke2-worker-<release>"
}
```

Then from the main project:

```bash
cd ~/sharvester
tofu plan
```

Review the resulting Rancher MachineConfig rollout before applying.

For workers:

```text
maxSurge       = 0
maxUnavailable = 1
```

must remain in place to avoid temporary storage exhaustion.

## Verify successful promotion

After rollout:

```bash
kubectl --context main-direct get nodes
```

All six nodes must be `Ready`.

Check worker OS disks:

```bash
for PVC in $(
  kubectl --context sharvester -n default get pvc -o json |
  jq -r '
    .items[]
    | select(.metadata.name | startswith("main-worker-"))
    | select(.spec.resources.requests.storage == "40Gi")
    | .metadata.name
  '
); do
  kubectl --context sharvester -n default get pvc "$PVC" -o json |
  jq -r '
    [.metadata.name,
     .spec.resources.requests.storage,
     (.metadata.annotations["harvesterhci.io/imageId"] // "<none>")]
    | @tsv
  '
done
```

Only after every current VM disk references the new release is the previous image eligible for deletion.

## Cleanup after a successful release

The goal after each build is:

```text
no builder VMs
no builder PVCs
no upstream build image
released golden images remain
```

Before removing builder state, always keep a backup:

```bash
STAMP="$(date +%Y%m%d-%H%M%S)"

cp terraform.tfstate \
  "$HOME/backups/sharvester/image-builder-${STAMP}.tfstate"
```

Never use `kubectl delete` or the Harvester UI to clean resources that are still tracked in OpenTofu state unless the corresponding state operation is deliberately handled as well.

## Safety rules

Never:

```text
replace a production image in-place
delete a golden image still referenced by VM volumes
put secrets into the builder state
use main-direct as the builder Kubernetes provider
assume harvester-longhorn-single means "non-NVMe"
```

Always:

```text
use explicit disk selectors
build on bulk
export releases to NVMe
use immutable release names
verify image references before deleting old releases
keep worker maxSurge at 0
```
