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
│  │ - Pool 1 InternalAPI: 172.17.0.80-90         │          │
│  │ - Pool 2 InternalAPI: 172.27.0.80-90         │          │
│  └──────────────────────────────────────────────┘          │
│                                                              │
│  ┌──────────────────────────────────────────────┐          │
│  │ NMState (Network Configuration)              │          │
│  │ - VLAN 20: InternalAPI (172.17/172.27)       │          │
│  │ - VLAN 21: Storage (172.18/172.29)           │          │
│  │ - VLAN 22: Tenant (172.19/172.31)            │          │
│  │ - VLAN 23: StorageMgmt (172.20/172.32)       │          │
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

Or step-by-step:

```bash
make nmstate          # Install NMState operator for network configuration
make metallb          # Install MetalLB operator as LoadBalancer service provider
make openstack        # Install OpenStack operators for control plane management
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

### Instance 1 Configuration

Edit [config/rhoso1.env](config/rhoso1.env) to customize:

```bash
export NAMESPACE=rhoso1
export NETWORK_INTERNALAPI_ADDRESS_PREFIX=172.17.0
export NETWORK_STORAGE_ADDRESS_PREFIX=172.18.0
export NETWORK_TENANT_ADDRESS_PREFIX=172.19.0
export NETWORK_STORAGEMGMT_ADDRESS_PREFIX=172.20.0
export CTLPLANE_METALLB_POOL=192.168.122.80-192.168.122.90
export DATAPLANE_COMPUTE_IP=192.168.122.100
export DATAPLANE_COMPUTE_0_IP=192.168.122.100
export DATAPLANE_COMPUTE_0_NAME=edpm-compute-0
```

**Note:** The `DATAPLANE_COMPUTE_0_NAME` must match the hostname configured on the EDPM node. The deployment will SSH to `DATAPLANE_COMPUTE_0_IP` and expect the hostname to be `edpm-compute-0.example.com`.

### Instance 2 Configuration

Edit [config/rhoso2.env](config/rhoso2.env):

```bash
export NAMESPACE=rhoso2
export NETWORK_INTERNALAPI_ADDRESS_PREFIX=172.27.0
export NETWORK_STORAGE_ADDRESS_PREFIX=172.29.0
export NETWORK_TENANT_ADDRESS_PREFIX=172.31.0
export NETWORK_STORAGEMGMT_ADDRESS_PREFIX=172.32.0
export CTLPLANE_METALLB_POOL=192.168.122.110-192.168.122.120
export DATAPLANE_COMPUTE_IP=192.168.122.101
export DATAPLANE_COMPUTE_0_IP=192.168.122.101
export DATAPLANE_COMPUTE_0_NAME=edpm-compute-1
```

**Note:** Instance 2 connects to a different EDPM node (`192.168.122.101`) with hostname `edpm-compute-1.example.com`.

### Key Configuration Requirements

**MUST be unique per instance:**
- `NAMESPACE` - Kubernetes namespace
- `NETWORK_*_ADDRESS_PREFIX` - IP subnet prefixes
- `CTLPLANE_METALLB_POOL` - LoadBalancer IP ranges
- `DATAPLANE_COMPUTE_IP` - EDPM node IP address
- `DATAPLANE_COMPUTE_0_IP` - EDPM node IP address (same as above)
- `DATAPLANE_COMPUTE_0_NAME` - EDPM node short hostname (without .example.com)

**MUST be the same across instances:**
- `NNCP_INTERFACE` - Physical interface (e.g., enp6s0)
- `NNCP_BRIDGE` - Bridge name (ospbr)
- `NETWORK_VLAN_START` - First VLAN ID (20)

## Implementation Details

For detailed technical information about NNCP behavior, MetalLB configuration, and network isolation, see [IMPLEMENTATION_DETAILS.md](IMPLEMENTATION_DETAILS.md).

## Verification

### Verify NNCP Configuration

```bash
make verify-nncp
```

Expected output:
```
NNCP Resources:
NAME         STATUS
enp6s0-crc   Available

IP Addresses on CRC Node (enp6s0.20 - InternalAPI):
    inet 172.17.0.5/24 brd 172.17.0.255 scope global enp6s0.20
    inet 172.27.0.5/24 brd 172.27.0.255 scope global secondary enp6s0.20
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
rhoso1-internalapi   172.17.0.80-172.17.0.90
...

LoadBalancer Services:
NAME                TYPE           EXTERNAL-IP      PORT(S)
rabbitmq            LoadBalancer   172.17.0.80      5671/TCP
...
```

### Verify Instance 2

```bash
source config/rhoso2.env && make verify
```

Expected output similar to instance 1, but with `rhoso2` namespace and 172.27/29/31/32 subnets.

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

**Important Notes:**
- The `edpm_deploy_instance` utility uses `oc rsh openstackclient` which operates in the **current namespace** set by `oc project`
- Always run `oc project <namespace>` before using this utility to target the correct RHOSO instance
- Each instance maintains separate OpenStack resources (images, networks, VMs, floating IPs)
- The test creates resources with generic names, so running it multiple times in the same namespace may create duplicate resources

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

### Remove Everything

```bash
make clean-all
```

⚠️ **WARNING:** This removes ALL instances and shared infrastructure. You'll need to redeploy from scratch.

## Troubleshooting

For detailed troubleshooting information, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Available Make Targets

### OpenShift Installation

| Target | Description |
|--------|-------------|
| `make openshift` | Install OpenShift (CRC) with development tools. Downloads kubectl, kustomize, oc, operator-sdk automatically |
| `make download_tools` | Download only the development tools without installing OpenShift |
| `make crc` | Deprecated alias for `make openshift` |

### Shared Infrastructure (Run Once)

| Target | Description |
|--------|-------------|
| `make infrastructure` | Deploy all shared infrastructure (runs all targets below) |
| `make nmstate` | Install NMState operator |
| `make metallb` | Install MetalLB operator |
| `make openstack` | Install OpenStack operators |
| `make openstack-init` | Initialize OpenStack operators |
| `make storage` | Create 30 persistent volumes for OpenStack |

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
| `make clean` | Remove instance (requires config sourced) |
| `make clean-all` | Remove all instances and shared infrastructure |

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
