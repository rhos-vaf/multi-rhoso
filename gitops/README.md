# Multi-RHOSO GitOps Complete Deployment

This directory contains a comprehensive kustomize-based deployment structure for deploying complete RHOSO instances via GitOps. It manages **everything** from NNCP to EDPM using ArgoCD sync waves with a layered approach.

## What's Included - Complete End-to-End Deployment

This structure manages the entire RHOSO deployment lifecycle using **three layers** - one shared NNCP layer (deployed once) plus **three layers per instance**:

### NNCP Layer: Shared Network Configuration (Deploy Once for All Instances)
- ✅ **NNCP** - Network Node Configuration Policy with VLAN interfaces configured for ALL instances (rhoso1, rhoso2)
- **CLUSTER-SCOPED** - Requires cluster-admin
- **Deploy this ONCE before any RHOSO instance layers**
- **Location**: `base/nncp/`
- **When adding new instances (rhoso3, rhoso4)**:
  1. Add IP address slots to `base/nncp/nncp-worker.yaml`
  2. Redeploy the nncp app

### Layer 1: Network Resources (Per Instance)
- **CLUSTER-SCOPED (metallb-system namespace)**:
  - ✅ **MetalLB** - IP Address Pools and L2 Advertisements (per instance)
- **CLUSTER-SCOPED (instance namespace)**:
  - ✅ **Namespace** - Instance namespace (rhoso1, rhoso2)
- **NAMESPACED** (in instance namespace):
  - ✅ **NAD** - Network Attachment Definitions for pod networking
  - ✅ **Secrets** - OpenStack service passwords (osp-secret)
  - ✅ **NetConfig** - OpenStack network configuration

### Layer 2: Control Plane (Per Instance)
- ✅ **OpenStackControlPlane** - Complete control plane with all OpenStack services (Wave 0)
- **NAMESPACED** - Can use namespaced ArgoCD

### Layer 3: DataPlane / EDPM (Per Instance)
- ✅ **EDPM** - Compute node deployment with Ansible automation (Waves 9-10)
- **NAMESPACED** - Can use namespaced ArgoCD
- **Must deploy AFTER Layer 2 control plane is Ready**

**Note**: The layered approach allows for flexible ArgoCD deployment strategies. Layer 0-1 require cluster-admin, while Layers 2-3 can use namespaced ArgoCD. Layer 3 MUST wait for Layer 2 control plane to reach STATUS=True before deploying.

## Directory Structure

```
multi-rhoso/
├── gitops/                             # GitOps deployment configuration (this directory)
│   ├── README.md                       # This file - deployment guide
│   ├── TROUBLESHOOTING.md              # Troubleshooting guide
│   ├── argocd-apps/                    # ArgoCD Application manifests
│   │   ├── rhoso1-cluster.yaml
│   │   ├── rhoso1-network.yaml
│   │   ├── rhoso1-controlplane.yaml
│   │   ├── rhoso1-dataplane.yaml
│   │   ├── rhoso2-cluster.yaml
│   │   ├── rhoso2-network.yaml
│   │   ├── rhoso2-controlplane.yaml
│   │   └── rhoso2-dataplane.yaml
│   └── openshift-gitops-configs/       # ArgoCD/GitOps operator configs
│
└── va/                                 # Kustomize base and overlays
    ├── base/
    │   ├── nncp/                       # NNCP Layer: Shared network config (DEPLOY ONCE)
    │   │   ├── kustomization.yaml
    │   │   └── nncp-worker.yaml        # Wave -5: Network config for ALL instances
    │   ├── network/                    # Layer 1: Per-instance network resources base
    │   │   ├── kustomization.yaml
    │   │   ├── ipaddresspool.yaml      # Wave -2: MetalLB pools template
    │   │   ├── namespace.yaml          # Wave -3: Namespace (CLUSTER-SCOPED)
    │   │   ├── netattach.yaml          # Wave -3: NAD (NAMESPACED)
    │   │   ├── osp-secret.yaml         # Wave -1: Secrets (NAMESPACED)
    │   │   └── netconfig.yaml          # Wave -1: Network config (NAMESPACED)
    │   ├── controlplane/               # Layer 2: Control plane base
    │   │   ├── kustomization.yaml
    │   │   └── openstackcontrolplane.yaml  # Wave 0: Control plane (NAMESPACED)
    │   └── dataplane/                  # Layer 3: DataPlane base
    │       ├── kustomization.yaml
    │       ├── dataplane-ssh-secret.yaml   # Wave 9: SSH keys (NAMESPACED)
    │       ├── nodeset.yaml            # Wave 10: Node definition (NAMESPACED)
    │       └── deployment.yaml         # Wave 10: Deployment trigger (NAMESPACED)
    └── overlays/
        ├── rhoso1/                     # RHOSO instance 1
        │   ├── network/                # Layer 1: Network (MetalLB, NAD, secrets, netconfig)
        │   ├── controlplane/           # Layer 2: Control plane
        │   └── dataplane/              # Layer 3: EDPM compute
        └── rhoso2/                     # RHOSO instance 2
            ├── network/                # Layer 1: Network (MetalLB, NAD, secrets, netconfig)
            ├── controlplane/           # Layer 2: Control plane
            └── dataplane/              # Layer 3: EDPM compute
```

### Deployment Layers Explained

**NNCP Layer: `base/nncp` (Deploy Once for All Instances)**
- Shared network configuration for ALL RHOSO instances
- **NNCP** (Wave -5): Network configuration with VLAN interfaces and IP addresses for all instances
- Requires cluster-admin or cluster-scoped ArgoCD
- **Deploy this ONCE before any RHOSO instances**
- **Resources have label**: `layer: nncp` (NOT instance-specific)
- **When adding new instances (rhoso3, rhoso4)**:
  1. Add IP addresses to `base/nncp/nncp-worker.yaml`
  2. Redeploy the nncp app

Each RHOSO instance (rhoso1, rhoso2) has **three layered overlays**:

**Layer 1: `{instance}/network`** (Network Resources - Per Instance)
- **CLUSTER-SCOPED (metallb-system namespace)**:
  - MetalLB IP Address Pools and L2 Advertisements (Wave -2)
- **CLUSTER-SCOPED (instance namespace)**:
  - Namespace (Wave -3)
- **NAMESPACED** (in instance namespace):
  - Network Attachment Definitions (NAD) (Wave -3)
  - Secrets (osp-secret) (Wave -1)
  - NetConfig (Wave -1)
- Deploy first (after NNCP Layer is complete)
- **Sync Waves**: -2 (MetalLB), -3 (Namespace, NAD), -1 (Secrets, NetConfig)
- **Labels**: `instance: rhoso1` or `instance: rhoso2`
- **Note**: Overlays use kustomize replacements to set instance-specific MetalLB pool names and IP ranges

**Layer 2: `{instance}/controlplane`**
- OpenStack control plane (Wave 0)
- Control plane services: Keystone, Nova, Neutron, Cinder, Glance, etc.
- **NAMESPACED** - Can use namespaced ArgoCD
- Deploy after Layer 1 is complete
- **Must reach STATUS=True before deploying Layer 3**

**Layer 3: `{instance}/dataplane`**
- EDPM compute nodes (Waves 9-10)
- DataPlaneNodeSet and DataPlaneDeployment for compute nodes
- **NAMESPACED** - Can use namespaced ArgoCD
- **MUST deploy AFTER Layer 2 control plane is Ready (STATUS=True)**
- Typically ~20-30 min after Layer 2 deployment

This layered approach allows:
- Proper namespace isolation for MetalLB resources (metallb-system) using per-resource patches
- Separation of concerns between cluster-level and namespace-level resources
- Flexible permission models (cluster-admin vs namespaced)
- Independent lifecycle management for control plane and compute nodes
- Better GitOps organization for multi-instance deployments
- Sync waves ensure proper ordering within each layer

## ArgoCD Sync Waves Explained

Resources are deployed in a specific order using ArgoCD sync waves:

| Wave | Resources | Description | Wait Time |
|------|-----------|-------------|-----------|
| **-5** | NNCP | Configure network interfaces on worker nodes | ~2-3 min |
| **-3** | Namespace, NAD | Create namespace and network attachments | ~30 sec |
| **-2** | MetalLB Pools | Configure IP address pools for LoadBalancers | ~30 sec |
| **-1** | Secrets, NetConfig | Create osp-secret and network configuration | ~1 min |
| **0** | OpenStackControlPlane | Deploy all OpenStack services | ~20-30 min |
| **9** | EDPM SSH Secret | SSH keys for compute node access | ~10 sec |
| **10** | DataPlaneNodeSet, DataPlaneDeployment | Define and deploy EDPM compute nodes | ~10-15 min |

**Total Deployment Time**: ~40-50 minutes (fully automated)

**Post-Deployment**: Nova cell host discovery required (see [Post-Deployment Tasks](#post-deployment-tasks))

## GitOps Deployment with ArgoCD

### Prerequisites

**Deployment Model**
- Three-layer deployment per instance using separate overlays (`network`, `controlplane`, `dataplane`)
- NNCP layer requires cluster-scoped ArgoCD (deploy once for all instances)
- Layer 1 (Network + MetalLB) requires cluster-scoped ArgoCD per instance
- Layers 2-3 (Control Plane, DataPlane) can use namespaced ArgoCD
- MetalLB resources correctly placed in `metallb-system` namespace with instance-specific pool names
- Allows independent control over control plane and compute deployment
- Better separation of concerns and lifecycle management

#### SSH Key Setup (Required for GitOps Deployment)

**IMPORTANT:** The GitOps deployment method requires you to manually configure SSH keys before deployment. Unlike the traditional Makefile method (which generates SSH keys automatically), GitOps deployments need pre-configured SSH keys in the secret files.

You need SSH keys for:
1. **Ansible access to EDPM nodes** - For deploying and managing compute nodes
2. **Nova live migration** - For migrating VMs between compute nodes

**Generate SSH keys:**

```bash
# 1. Generate Ansible SSH key for EDPM deployment
ssh-keygen -t rsa -b 4096 -f ~/.ssh/dataplane_key -N ''

# 2. Generate Nova migration SSH key
ssh-keygen -t ed25519 -f ~/.ssh/nova_migration_key -N ''

# 3. Deploy public keys to EDPM compute nodes
ssh-copy-id -i ~/.ssh/dataplane_key.pub root@192.168.122.100
ssh-copy-id -i ~/.ssh/dataplane_key.pub root@192.168.122.101
```

**Update secret files:**

Edit the following files and replace the placeholder values with your actual SSH keys:

1. [../va/base/dataplane/dataplane-ssh-secret.yaml](../va/base/dataplane/dataplane-ssh-secret.yaml)
   - Replace `ssh-privatekey` with contents of `~/.ssh/dataplane_key`
   - Replace `ssh-publickey` with contents of `~/.ssh/dataplane_key.pub`

2. [../va/base/dataplane/nova-migration-ssh-key.yaml](../va/base/dataplane/nova-migration-ssh-key.yaml)
   - Replace `ssh-privatekey` with contents of `~/.ssh/nova_migration_key`
   - Replace `ssh-publickey` with contents of `~/.ssh/nova_migration_key.pub`

**Security Note:** These SSH key files have been sanitized and contain placeholder values only. You MUST replace them with your own keys before deploying via GitOps.

**Why GitOps requires manual SSH key setup:**
- GitOps deployments are declarative and version-controlled
- SSH keys should not be stored in git repositories
- The traditional Makefile method can generate keys on-the-fly because it's imperative
- In production, consider using sealed secrets, External Secrets Operator, or Vault for secret management

#### ArgoCD Deployment

**OpenShift GitOps Operator**
- Deploys ArgoCD in cluster mode by default
- Has cluster-admin permissions to manage all resources
- Quick install using [gitops-tools](https://github.com/rhos-vaf/gitops-tools.git):
  ```bash
  git clone https://github.com/rhos-vaf/gitops-tools.git
  cd gitops-tools
  make install_gitops_operator        # Install OpenShift GitOps Operator
  make configure_openshift_gitops     # Configure permissions and TLS certificates
  ```
- Or install from OperatorHub UI

#### Required Permissions

**NNCP Layer (Cluster-scoped)** requires:
- `NodeNetworkConfigurationPolicy` (nmstate.io)

**Network Layer (Cluster-scoped)** requires:
- `Namespace` (core)
- `IPAddressPool`, `L2Advertisement` (metallb.io)

**Control Plane & DataPlane Layers (Namespaced)** only require:
- Permissions within the target namespace
- Can use namespaced ArgoCD installation

### ArgoCD Application Examples

**nncp Application (Deploy First - NNCP Layer)**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nncp
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/multi-rhoso.git
    targetRevision: main
    path: va/base/nncp
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
```

**rhoso1-network Application (Deploy Second - Network Layer)**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhoso1-network
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/multi-rhoso.git
    targetRevision: main
    path: va/overlays/rhoso1/network
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
```

**rhoso1-controlplane Application (Deploy Third - Layer 2)**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhoso1-controlplane
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/multi-rhoso.git
    targetRevision: main
    path: va/overlays/rhoso1/controlplane
  destination:
    server: https://kubernetes.default.svc
    namespace: rhoso1
  syncPolicy:
    automated:
      prune: false  # Prevent accidental deletion of control plane
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
```

**rhoso1-dataplane Application (Deploy Fourth - Layer 3)**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhoso1-dataplane
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/multi-rhoso.git
    targetRevision: main
    path: va/overlays/rhoso1/dataplane
  destination:
    server: https://kubernetes.default.svc
    namespace: rhoso1
  syncPolicy:
    automated:
      prune: false  # Prevent accidental deletion of compute nodes
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
```

**Note**: The overlays reference base resources using relative paths (`../../../base/`). When testing locally with `oc kustomize` or `kustomize build`, you need the `--load-restrictor=LoadRestrictionsNone` flag. ArgoCD handles this automatically when all resources are in the same git repository.

**Deployment Order**:
1. Deploy `base/nncp` FIRST (creates network infrastructure for ALL instances)
   - Wait for NNCP to be Synced and Healthy
   - Verify with: `oc get nncp`
2. Deploy `rhoso1/network` (creates namespace, MetalLB, NAD, Secrets, NetConfig)
   - Sync waves ensure proper ordering: Namespace/NAD (-3) → MetalLB (-2) → Secrets/NetConfig (-1)
   - Wait for Layer 1 to be Synced and Healthy
3. Deploy `rhoso1/controlplane` (creates OpenStack control plane)
   - ArgoCD will show as Synced when control plane resource is created
   - Monitor control plane readiness: `oc get openstackcontrolplane -n rhoso1 openstack -w`
   - **Wait for STATUS=True (~20-30 min) before proceeding to Layer 3**
4. Deploy `rhoso1/dataplane` (creates EDPM compute nodes)
   - Only deploy after control plane STATUS=True
   - DataPlane deployment takes ~10-15 min

Repeat the same pattern for rhoso2 using the `rhoso2/*` overlays (skip step 1, as NNCP is already deployed).

**Adding rhoso3, rhoso4, etc.**:
1. Edit `base/nncp/nncp-worker.yaml` to add additional IP address entries for the new instance
2. Redeploy the NNCP app to update network configuration
3. Follow steps 2-4 above for the new instance overlay

## Network Configuration

Network addressing uses a VLAN-based pattern for clean IP organization:
- **rhoso1**: `172.17.{VLAN}.0/24` (e.g., VLAN 20 → 172.17.20.0/24)
- **rhoso2**: `172.18.{VLAN}.0/24` (e.g., VLAN 20 → 172.18.20.0/24)

### rhoso1
- CtlPlane: 192.168.122.0/24 (gateway IP: 192.168.122.10)
- InternalAPI (VLAN 20): 172.17.20.0/24
- Storage (VLAN 21): 172.17.21.0/24
- Tenant (VLAN 22): 172.17.22.0/24
- StorageMgmt (VLAN 23): 172.17.23.0/24
- DesignateExt (VLAN 26): 172.17.26.0/24
- MetalLB Pool: 192.168.122.80-90
- Compute Node: 192.168.122.100 (edpm-compute-0)

### rhoso2
- CtlPlane: 192.168.122.0/24 (gateway IP: 192.168.122.20)
- InternalAPI (VLAN 20): 172.18.20.0/24
- Storage (VLAN 21): 172.18.21.0/24
- Tenant (VLAN 22): 172.18.22.0/24
- StorageMgmt (VLAN 23): 172.18.23.0/24
- DesignateExt (VLAN 26): 172.18.26.0/24
- MetalLB Pool: 192.168.122.110-120
- Compute Node: 192.168.122.101 (edpm-compute-1)

## Post-Deployment Tasks

### Nova Cell Host Discovery

After the dataplane deployment completes successfully (all Ansible jobs finish), you must run Nova cell host discovery to map compute hosts to Nova cells. This is **required** for the hypervisors to appear in `openstack hypervisor list`.

**Why this is needed:**
- The compute service registers with Nova and reports resources to Placement API
- However, Nova requires explicit host-to-cell mapping for hypervisor queries
- Without this step, `openstack hypervisor list` will return empty even though the compute service is up

**Commands:**

```bash
# For rhoso1
oc -n rhoso1 exec -it nova-cell1-conductor-0 -- nova-manage cell_v2 discover_hosts --verbose

# For rhoso2
oc -n rhoso2 exec -it nova-cell1-conductor-0 -- nova-manage cell_v2 discover_hosts --verbose
```

**Expected output:**
```
Found 2 cell mappings.
Skipping cell0 since it does not contain hosts.
Getting computes from cell 'cell1': b33ec35d-7eeb-487c-99eb-3de6f6be3a04
Checking host mapping for compute host 'edpm-compute-X.ctlplane.example.com': 2feea379-d3b9-41ac-bda8-6fabef2f455f
Creating host mapping for compute host 'edpm-compute-X.ctlplane.example.com': 2feea379-d3b9-41ac-bda8-6fabef2f455f
Found 1 unmapped computes in cell: b33ec35d-7eeb-487c-99eb-3de6f6be3a04
```

**Verify:**

```bash
# Check host mappings
oc -n rhoso1 exec -it nova-cell1-conductor-0 -- nova-manage cell_v2 list_hosts

# Verify hypervisors are now visible
oc -n rhoso1 rsh openstackclient openstack hypervisor list
```

**Expected hypervisor list output:**
```
+--------------------------------------+----------------------------+-----------------+-----------------+-------+
| ID                                   | Hypervisor Hostname        | Hypervisor Type | Host IP         | State |
+--------------------------------------+----------------------------+-----------------+-----------------+-------+
| 2feea379-d3b9-41ac-bda8-6fabef2f455f | edpm-compute-0.example.com | QEMU            | 192.168.122.100 | up    |
+--------------------------------------+----------------------------+-----------------+-----------------+-------+
```

**Automation Note:**
The traditional Makefile deployment (`make dataplane`) automatically runs host discovery. For GitOps deployments, this is a one-time manual step after initial deployment. For production, consider configuring automatic discovery by setting `discover_hosts_in_cells_interval` in nova.conf (e.g., `discover_hosts_in_cells_interval = 60` to check every 60 seconds).

## Troubleshooting

For common issues and their solutions, see the [Troubleshooting Guide](TROUBLESHOOTING.md).

## Resources

### GitOps & Automation
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Sync Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [Kustomize Documentation](https://kustomize.io/)
- [Kustomize Overlays Guide](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/#bases-and-overlays)

### OpenStack on Kubernetes
- [OpenStack K8s Operators](https://github.com/openstack-k8s-operators/install_yamls)
- [RHOSO Documentation](https://docs.redhat.com/en/documentation/red_hat_openstack_services_on_openshift)
- [Nova Cell V2 Documentation](https://docs.openstack.org/nova/latest/admin/cells.html)
- [EDPM Documentation](https://openstack-k8s-operators.github.io/edpm-ansible/)
