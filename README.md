# Multi-RHOSO Deployment

Deploy multiple isolated Red Hat OpenStack Services on OpenShift (RHOSO) instances on a single OpenShift cluster with complete network isolation and namespace separation

## Overview

This project provides a simplified workflow for deploying multiple RHOSO instances using the upstream [openstack-k8s-operators/install_yamls](https://github.com/openstack-k8s-operators/install_yamls) repository. Each instance runs in its own namespace with isolated networks and dedicated compute resources.

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ OpenShift Cluster (CRC)                                     │
│                                                              │
│  ┌─────────────────┐           ┌─────────────────┐         │
│  │ rhoso1          │           │ rhoso2          │         │
│  │ namespace       │           │ namespace       │         │
│  │                 │           │                 │         │
│  │ Control Plane 1 │           │ Control Plane 2 │         │
│  │ - RabbitMQ      │           │ - RabbitMQ      │         │
│  │ - MariaDB       │           │ - MariaDB       │         │
│  │ - Nova API      │           │ - Nova API      │         │
│  │ - Neutron       │           │ - Neutron       │         │
│  │ ...             │           │ ...             │         │
│  └────────┬────────┘           └────────┬────────┘         │
│           │                             │                   │
│  ┌────────▼────────────────────────────▼────────┐          │
│  │ MetalLB (LoadBalancer IPs)                   │          │
│  │ - Pool 1: 192.168.122.80-90                  │          │
│  │ - Pool 2: 192.168.122.110-120                │          │
│  │ - Pool 1 InternalAPI: 172.17.20.80-90        │          │
│  │ - Pool 2 InternalAPI: 172.18.20.80-90        │          │
│  └──────────────────────────────────────────────┘          │
│                                                              │
│  ┌──────────────────────────────────────────────┐          │
│  │ NMState (Network Configuration)              │          │
│  │ - VLAN 20: InternalAPI (172.17.20/172.18.20) │          │
│  │ - VLAN 21: Storage (172.17.21/172.18.21)     │          │
│  │ - VLAN 22: Tenant (172.17.22/172.18.22)      │          │
│  │ - VLAN 23: StorageMgmt (172.17.23/172.18.23) │          │
│  │ - VLAN 25: Designate (172.17.25/172.18.25)   │          │
│  │ - VLAN 26: DesignateExt (172.17.26/172.18.26)│          │
│  └──────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────┘
                     │                    │
                     ▼                    ▼
          ┌──────────────────┐  ┌──────────────────┐
          │ edpm-compute-0   │  │ edpm-compute-1   │
          │ 192.168.122.100  │  │ 192.168.122.101  │
          │                  │  │                  │
          │ Connects to      │  │ Connects to      │
          │ Control Plane 1  │  │ Control Plane 2  │
          └──────────────────┘  └──────────────────┘
```

## Prerequisites

**Option A: Use existing OpenShift cluster**
- OpenShift cluster accessible (any version compatible with RHOSO)
- `oc` CLI tool installed and configured
- Cluster admin access

**Option B: Install CRC (OpenShift local cluster)**
- RHEL 9 or Fedora workstation with sufficient resources:
  - Minimum: 16 CPUs, 32GB RAM, 150GB disk
  - Recommended: 32 CPUs, 64GB RAM, 300GB disk
- Red Hat pull secret from [console.redhat.com](https://console.redhat.com/openshift/create/local)

**Common requirements for both options:**
- EDPM compute nodes prepared (see EDPM setup below)
- Network connectivity between OpenShift and EDPM nodes

### EDPM Compute Nodes Setup

You need EDPM (External Data Plane Management) compute nodes for each RHOSO instance. You can either:

**Option 1: Use existing RHEL 9.x servers**
- Ensure SSH access from OpenShift cluster
- Configure hostnames matching your deployment config

**Option 2: Create EDPM VMs using upstream devsetup (recommended for testing)**

```bash
# Navigate to devsetup directory
cd install_yamls/devsetup

# Create 2 EDPM compute VMs
EDPM_TOTAL_NODES=2 make edpm_compute

# This creates:
# - edpm-compute-0 (192.168.122.100)
# - edpm-compute-1 (192.168.122.101)
```

**Configure hostnames on EDPM nodes:**

```bash
# Using the generated SSH key from install_yamls/out/edpm/
ssh -i ~/multi-rhoso/install_yamls/out/edpm/ansibleee-ssh-key-id_rsa root@192.168.122.100 \
  "hostnamectl set-hostname edpm-compute-0.example.com"

ssh -i ~/multi-rhoso/install_yamls/out/edpm/ansibleee-ssh-key-id_rsa root@192.168.122.101 \
  "hostnamectl set-hostname edpm-compute-1.example.com"
```

**Important:**
- The SSH key is automatically generated when you run `make edpm_compute`
- The hostnames must match the `DATAPLANE_COMPUTE_0_NAME` values in your config files:
  - [config/rhoso1.env](config/rhoso1.env): `DATAPLANE_COMPUTE_0_NAME=edpm-compute-0`
  - [config/rhoso2.env](config/rhoso2.env): `DATAPLANE_COMPUTE_0_NAME=edpm-compute-1`

**SSH Key Note for Deployment Methods:**
- **Traditional Makefile deployment**: SSH keys are generated automatically during deployment
- **GitOps deployment**: You must manually configure SSH keys before deployment (see [gitops/README.md - SSH Key Setup](gitops/README.md#ssh-key-setup-required-for-gitops-deployment))

## Deployment Methods

This project supports **two deployment methods**:

### Method 1: Traditional Makefile Deployment
- Step-by-step deployment using `make` commands
- Full control over each deployment phase
- Good for understanding the deployment process
- See [Quick Start](#quick-start) below

### Method 2: GitOps Deployment with ArgoCD
- Complete automated deployment using ArgoCD sync waves
- Declarative, version-controlled configuration
- Manages entire lifecycle: NNCP → Namespace → NAD → MetalLB → Secrets → NetConfig → ControlPlane → EDPM
- Full deployment in ~40-50 minutes, completely automated
- Automatic Nova cell host discovery included
- See [gitops/README.md](gitops/README.md) for details

**Comparison:**

| Feature | Traditional (Makefile) | GitOps (ArgoCD) |
|---------|------------------------|-----------------|
| **Deployment** | Manual `make` commands | Automated sync waves |
| **Configuration** | Shell env files | Kustomize overlays |
| **Version Control** | Scripts only | Complete manifests |
| **Rollback** | Manual re-deployment | Git revert |
| **Drift Detection** | None | Automatic (ArgoCD) |
| **Multi-cluster** | Complex | Native support |
| **Production Ready** | Yes | Highly recommended |

**GitOps Quick Example:**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhoso1
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/your-org/multi-rhoso.git
    path: va/overlays/rhoso1
  destination:
    namespace: rhoso1
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

For complete GitOps documentation including sync waves, network configuration, and troubleshooting, see **[gitops/README.md](gitops/README.md)**.

---

## Quick Start

### 1. Clone This Repository

```bash
cd /home/mcarpio/CLAUDE
git clone https://github.com/rhos-vaf/multi-rhoso.git
cd multi-rhoso
```

### 2. (Optional) Install OpenShift (CRC)

If you don't have an OpenShift cluster, install CRC:

```bash
# Download your pull secret from https://console.redhat.com/openshift/create/local
# Save it to ~/pull-secret

# Install OpenShift (CRC) with default settings (32 CPUs, 64GB RAM, 300GB disk)
# This also downloads required tools (kubectl, kustomize, oc, etc.)
make openshift

# Or customize the installation
make openshift CRC_VERSION=2.41.0 PULL_SECRET=~/pull-secret CPUS=32 MEMORY=65536 DISK=300
```

**Default OpenShift configuration:**
- `CRC_VERSION=2.41.0`
- `PULL_SECRET=$(HOME)/pull-secret`
- `CPUS=32`
- `MEMORY=65536` (MB)
- `DISK=300` (GB)

**Note:**
- OpenShift (CRC) installation takes 15-30 minutes depending on your internet connection and hardware
- The `make openshift` target automatically downloads required development tools (kubectl, kustomize, oc, operator-sdk, etc.)

### 3. Deploy Shared Infrastructure (Run Once)

Deploy operators and resources shared by all RHOSO instances:

```bash
make infrastructure
```

**⏱️ Expected time:** 10-15 minutes

This will install in sequence:
1. **NMState operator** (`openshift-nmstate` namespace) - Network interface configuration and VLAN management
2. **MetalLB operator** (`metallb-system` namespace) - LoadBalancer service provider for service exposure
3. **Cert Manager operator** (`cert-manager` namespace) - Certificate management for operator webhooks
4. **OpenStack operators** (`openstack-operators` namespace) - Control plane component operators (Nova, Neutron, Cinder, etc.)
5. **Persistent volumes** - 30 local storage PVs for database and service storage

Or step-by-step:

```bash
make nmstate          # Install NMState operator
make metallb          # Install MetalLB operator
make certmanager      # Install Cert Manager operator
make openstack        # Install OpenStack operators (skips NNCP, NMState, MetalLB, Cert Manager)
make openstack-init   # Initialize OpenStack operators and create default resources
make storage          # Create 30 persistent volumes for database storage
```

### 4. Deploy First RHOSO Instance

```bash
source config/rhoso1.env && make instance
```

**⏱️ Expected time:** 20-30 minutes

**Note:** The `make instance` target automatically creates `osp-secret` with database passwords, configures DNS server settings, waits for control plane to reach "Ready" status, and runs host discovery to register compute nodes in Nova cells.

Or step-by-step:

```bash
source config/rhoso1.env && make nncp             # Generate NNCP with primary IPs on VLAN interfaces
source config/rhoso1.env && make namespace        # Create rhoso1 namespace
source config/rhoso1.env && make netattach        # Create network attachment definitions (NADs) for pod networking
source config/rhoso1.env && make metallb-config   # Configure namespace-scoped MetalLB IP address pools
source config/rhoso1.env && make controlplane     # Deploy control plane (auto-creates osp-secret + OpenStack services)
source config/rhoso1.env && make wait-controlplane # Wait for control plane to reach Ready status (up to 30 min)
source config/rhoso1.env && make dataplane        # Deploy EDPM compute node + auto-discover hosts in Nova cells
```

### 5. Deploy Second RHOSO Instance

```bash
source config/rhoso2.env && make instance
```

**⏱️ Expected time:** 20-30 minutes

**Note:** Same automatic features as instance 1 (secrets creation, DNS configuration, control plane readiness wait, and host discovery).

Or step-by-step:

```bash
source config/rhoso2.env && make nncp             # Add secondary IPs to existing NNCP (skips regeneration)
source config/rhoso2.env && make namespace        # Create rhoso2 namespace
source config/rhoso2.env && make netattach        # Create NADs with different subnet configurations
source config/rhoso2.env && make metallb-config   # Configure separate namespace-scoped IP pools for instance 2
source config/rhoso2.env && make controlplane     # Deploy separate control plane (auto-creates osp-secret + services)
source config/rhoso2.env && make wait-controlplane # Wait for second control plane to reach Ready status (up to 30 min)
source config/rhoso2.env && make dataplane        # Deploy second EDPM compute node + auto-discover hosts
```

## Configuration

For detailed configuration information including network addressing schemes, instance-specific settings, and advanced configuration options, see **[CONFIGURATION.md](CONFIGURATION.md)**.

**Quick Reference:**
- **RHOSO 1**: Uses `172.17.X.0/24` range (where X = VLAN ID)
- **RHOSO 2**: Uses `172.18.X.0/24` range (where X = VLAN ID)
- **Red Hat Support**: Up to **[5 RHOSO environments](https://docs.redhat.com/en/documentation/red_hat_openstack_services_on_openshift/18.0/html-single/deploying_multiple_rhoso_environments_on_a_single_rhocp_cluster/index)** officially supported
- **Pattern**: `172.[16+N].[VLAN].0/24` where N = instance number

Configuration files:
- [config/rhoso1.env](config/rhoso1.env) - Instance 1 configuration
- [config/rhoso2.env](config/rhoso2.env) - Instance 2 configuration

## Implementation Details

For detailed technical information about NNCP behavior, MetalLB configuration, and network isolation, see [IMPLEMENTATION_DETAILS.md](IMPLEMENTATION_DETAILS.md).

## Verification

### Verify NNCP Configuration

```bash
make verify-nncp
```

Expected output showing all VLAN interfaces and their IP addresses:
```
NNCP Resources:
NAME         STATUS
enp6s0-crc   Available

==========================================
IP Addresses on CRC Node
==========================================

VLAN 20 (InternalAPI - enp6s0.20):
    inet 172.17.20.5/24 brd 172.17.20.255 scope global enp6s0.20
    inet 172.18.20.5/24 brd 172.18.20.255 scope global secondary enp6s0.20

VLAN 21 (Storage - enp6s0.21):
    inet 172.17.21.5/24 brd 172.17.21.255 scope global enp6s0.21
    inet 172.18.21.5/24 brd 172.18.21.255 scope global secondary enp6s0.21

VLAN 22 (Tenant - enp6s0.22):
    inet 172.17.22.5/24 brd 172.17.22.255 scope global enp6s0.22
    inet 172.18.22.5/24 brd 172.18.22.255 scope global secondary enp6s0.22

VLAN 23 (StorageMgmt - enp6s0.23):
    inet 172.17.23.5/24 brd 172.17.23.255 scope global enp6s0.23
    inet 172.18.23.5/24 brd 172.18.23.255 scope global secondary enp6s0.23

VLAN 25 (Designate - enp6s0.25):
    inet 172.17.25.5/24 brd 172.17.25.255 scope global enp6s0.25
    inet 172.18.25.5/24 brd 172.18.25.255 scope global secondary enp6s0.25

VLAN 26 (DesignateExt - enp6s0.26):
    inet 172.17.26.5/24 brd 172.17.26.255 scope global enp6s0.26
    inet 172.18.26.5/24 brd 172.18.26.255 scope global secondary enp6s0.26
```

### Verify Instance 1

```bash
source config/rhoso1.env && make verify
```

Expected output:
```
Namespace:
NAME      STATUS   AGE
rhoso1    Active   30m

OpenStackControlPlane:
NAME      STATUS
rhoso1    Ready

MetalLB Pools:
rhoso1-ctlplane      192.168.122.80-192.168.122.90
rhoso1-internalapi   172.17.20.80-172.17.20.90
...

LoadBalancer Services:
NAME                TYPE           EXTERNAL-IP      PORT(S)
rabbitmq            LoadBalancer   172.17.20.80     5671/TCP
...
```

### Verify Instance 2

```bash
source config/rhoso2.env && make verify
```

Expected output similar to instance 1, but with `rhoso2` namespace and 172.18.X.0/24 subnets (where X = VLAN ID).

### Manual Verification

Check EDPM compute nodes are registered:

**Instance 1:**
```bash
oc exec -n rhoso1 openstackclient -- openstack compute service list
```

**Instance 2:**
```bash
oc exec -n rhoso2 openstackclient -- openstack compute service list
```

Expected:
```
+----+--------------+---------------------------+------+---------+-------+
| ID | Binary       | Host                      | Zone | Status  | State |
+----+--------------+---------------------------+------+---------+-------+
| 1  | nova-compute | edpm-compute-0.ctlplane   | nova | enabled | up    |
+----+--------------+---------------------------+------+---------+-------+
```

### Testing Deployments with Test VMs

After deploying your RHOSO instances, you can validate they work correctly by creating test VMs on the EDPM compute nodes using the upstream `edpm_deploy_instance` utility.

#### Using make edpm_deploy_instance with Multiple Namespaces

The `edpm_deploy_instance` target is an upstream testing utility from [install_yamls/devsetup](https://github.com/openstack-k8s-operators/install_yamls/tree/main/devsetup) that:
- Creates a CirrOS test image
- Creates test networks (private network with subnet, public network with floating IPs)
- Launches test VM instances
- Validates connectivity via floating IP ping

**To test each RHOSO instance separately**, switch the namespace context before running the test:

**Test Instance 1 (rhoso1):**
```bash
# Set namespace context
oc project rhoso1

# Create a test VM on edpm-compute-0
cd install_yamls/devsetup
make edpm_deploy_instance

# This will:
# - Create CirrOS image in rhoso1 namespace
# - Create networks and a test VM
# - Assign floating IP and ping to verify connectivity
```

**Test Instance 2 (rhoso2):**
```bash
# Switch namespace context
oc project rhoso2

# Create a test VM on edpm-compute-1
cd install_yamls/devsetup
make edpm_deploy_instance

# This creates a separate test VM in the rhoso2 namespace
```

**Create multiple test VMs:**
```bash
# Set namespace context
oc project rhoso1

# Create 3 test VMs (test_0, test_1, test_2)
cd install_yamls/devsetup
make edpm_deploy_instance NUMBER_OF_INSTANCES=3
```

## Cleanup

### Remove Instance 2

```bash
source config/rhoso2.env && make clean
```

Removes:
- `rhoso2` namespace
- MetalLB IP pools for instance 2
- Does NOT remove NNCP secondary IPs (manual cleanup required)

### Remove Instance 1

```bash
source config/rhoso1.env && make clean
```

Removes:
- `rhoso1` namespace
- MetalLB IP pools for instance 1
- Does NOT remove NNCP (manual cleanup required)

### Remove Shared Infrastructure

```bash
make clean-infrastructure
```

Removes:
- NMState operator (`openshift-nmstate` namespace)
- MetalLB operator (`metallb-system` namespace)
- Cert Manager operator (`cert-manager` and `cert-manager-operator` namespaces)
- OpenStack operators (`openstack-operators` namespace)

⚠️ **WARNING:** This removes all shared infrastructure. All instances must be removed first.

### Remove Everything

```bash
make clean-all
```

Removes:
- All RHOSO instances (namespaces matching `rhoso*` or `openstack*`)
- All shared infrastructure (calls `make clean-infrastructure`)

⚠️ **WARNING:** This removes ALL instances and shared infrastructure. You'll need to redeploy from scratch.

## Troubleshooting

For detailed troubleshooting information, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

### Common Issue: Empty Hypervisor List

If `openstack hypervisor list` returns empty even though `openstack compute service list` shows the compute service as `enabled | up`, the compute host needs to be discovered and mapped to the Nova cell:

**Symptoms:**
- Compute service shows as `up` in `openstack compute service list`
- Resource provider exists in Placement API (`openstack resource provider list` shows the compute node)
- `openstack hypervisor list` returns empty

**Root Cause:**
Nova requires explicit host-to-cell mapping. Even when the compute service registers successfully and reports resources to Placement API, it won't appear in the hypervisor list until discovered by the cell conductor.

**Solution:**
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
Getting computes from cell 'cell1': <cell-uuid>
Checking host mapping for compute host 'edpm-compute-X.ctlplane.example.com': <uuid>
Creating host mapping for compute host 'edpm-compute-X.ctlplane.example.com': <uuid>
Found 1 unmapped computes in cell: <cell-uuid>
```

**Verify:**
```bash
# Check host mappings
oc -n rhoso1 exec -it nova-cell1-conductor-0 -- nova-manage cell_v2 list_hosts

# Verify hypervisors are now visible
oc -n rhoso1 rsh openstackclient openstack hypervisor list
```

**For Production:**
Configure automatic discovery by setting `discover_hosts_in_cells_interval` in nova.conf (e.g., `discover_hosts_in_cells_interval = 60` to check every 60 seconds). The Makefile deployment automatically runs host discovery via `make dataplane`, but GitOps deployments may require manual discovery after initial deployment.

## Available Make Targets

### OpenShift Installation

| Target | Description |
|--------|-------------|
| `make openshift` | Install OpenShift (CRC) with development tools. Downloads kubectl, kustomize, oc, operator-sdk automatically |
| `make download_tools` | Download only the development tools without installing OpenShift |

### Shared Infrastructure (Run Once)

| Target | Description |
|--------|-------------|
| `make infrastructure` | Deploy all shared infrastructure (runs all targets below in sequence) |
| `make nmstate` | Install NMState operator in `openshift-nmstate` namespace |
| `make metallb` | Install MetalLB operator in `metallb-system` namespace |
| `make certmanager` | Install Cert Manager operator in `cert-manager` namespace |
| `make openstack` | Install OpenStack operators in `openstack-operators` namespace (skips NNCP, NMState, MetalLB, Cert Manager) |
| `make openstack-init` | Initialize OpenStack operators and create default OpenStack CR |
| `make storage` | Create 30 persistent volumes for OpenStack services |

### Instance Deployment (Requires config sourced)

| Target | Description |
|--------|-------------|
| `make instance` | Deploy complete RHOSO instance (runs all targets below in order) |
| `make nncp` | Configure NNCP (generates for first instance, adds secondary IPs for others) |
| `make namespace` | Create namespace |
| `make netattach` | Create network attachments |
| `make metallb-config` | Configure MetalLB IP pools |
| `make controlplane` | Deploy control plane (creates secrets + services) |
| `make wait-controlplane` | Wait for control plane to be ready (30-minute timeout) |
| `make dataplane` | Deploy data plane compute + automatic host discovery |
| `make clean-dataplane` | Delete dataplane resources only (keeps control plane) |

### Verification

| Target | Description |
|--------|-------------|
| `make verify-nncp` | Verify NNCP configuration and IP addresses |
| `make verify` | Verify instance deployment (requires config sourced) |

### Cleanup

| Target | Description |
|--------|-------------|
| `make clean` | Remove instance (requires config sourced) - deletes namespace and MetalLB pools |
| `make clean-infrastructure` | Remove all shared infrastructure (NMState, MetalLB, Cert Manager, OpenStack operators) |
| `make clean-all` | Remove all instances and shared infrastructure (confirms before proceeding) |

### Usage Examples

```bash
# Deploy first instance
source config/rhoso1.env && make instance

# Deploy second instance
source config/rhoso2.env && make instance

# Verify first instance
source config/rhoso1.env && make verify

# Clean up second instance
source config/rhoso2.env && make clean

# Get help
make help
```

## Resources

- [OpenStack K8s Operators](https://github.com/openstack-k8s-operators/install_yamls)
- [RHOSO Documentation](https://docs.redhat.com/en/documentation/red_hat_openstack_services_on_openshift)
- [MetalLB Documentation](https://metallb.universe.tf/)
- [NMState Documentation](https://nmstate.io/)
