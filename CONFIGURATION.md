# Configuration Guide

This guide provides detailed configuration information for multi-RHOSO deployments.

## Network Addressing Scheme

This deployment uses a scalable network addressing scheme where:
- **RHOSO Instance N** uses the `172.(16+N).X.0/24` range
- **Third octet (X)** matches the **VLAN ID** for easy identification
- **Starting at 172.17** to avoid conflicts with applications using `172.16.0.0/16`

**Address Pattern:**
```
172.[INSTANCE].[VLAN].0/24
```

**Example:**
- RHOSO 1, VLAN 20 → `172.17.20.0/24`
- RHOSO 2, VLAN 21 → `172.18.21.0/24`
- RHOSO 3, VLAN 22 → `172.19.22.0/24`

This scheme provides:
- **Scalable addressing**: Supports multiple RHOSO instances (172.17.X, 172.18.X, 172.19.X, etc.)
  - **Red Hat Support**: Up to **[5 RHOSO environments](https://docs.redhat.com/en/documentation/red_hat_openstack_services_on_openshift/18.0/html-single/deploying_multiple_rhoso_environments_on_a_single_rhocp_cluster/index)** officially supported on a single cluster with namespace separation
  - **Address space available**: 172.17.X through 172.31.X (15 possible /16 ranges within RFC 1918)
- **256 networks per instance** (X = 0-255)
- **Intuitive addressing**: Network address directly indicates both instance and VLAN
- **Conflict avoidance**: Leaves 172.16.0.0/16 free for other applications

## Instance 1 Configuration

Edit [config/rhoso1.env](config/rhoso1.env) to customize:

```bash
export NAMESPACE=rhoso1

# RHOSO 1 uses 172.17.X.0/24 range where X = VLAN ID
export NETWORK_INTERNALAPI_ADDRESS_PREFIX=172.17.20      # VLAN 20
export NETWORK_STORAGE_ADDRESS_PREFIX=172.17.21          # VLAN 21
export NETWORK_TENANT_ADDRESS_PREFIX=172.17.22           # VLAN 22
export NETWORK_STORAGEMGMT_ADDRESS_PREFIX=172.17.23      # VLAN 23
export NETWORK_DESIGNATE_ADDRESS_PREFIX=172.17.25        # VLAN 25
export NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX=172.17.26    # VLAN 26

export CTLPLANE_METALLB_POOL=192.168.122.80-192.168.122.90
export DATAPLANE_COMPUTE_IP=192.168.122.100
export DATAPLANE_COMPUTE_0_IP=192.168.122.100
export DATAPLANE_COMPUTE_0_NAME=edpm-compute-0
```

**Note:** The `DATAPLANE_COMPUTE_0_NAME` must match the hostname configured on the EDPM node. The deployment will SSH to `DATAPLANE_COMPUTE_0_IP` and expect the hostname to be `edpm-compute-0.example.com`.

## Instance 2 Configuration

Edit [config/rhoso2.env](config/rhoso2.env):

```bash
export NAMESPACE=rhoso2

# RHOSO 2 uses 172.18.X.0/24 range where X = VLAN ID
export NETWORK_INTERNALAPI_ADDRESS_PREFIX=172.18.20      # VLAN 20
export NETWORK_STORAGE_ADDRESS_PREFIX=172.18.21          # VLAN 21
export NETWORK_TENANT_ADDRESS_PREFIX=172.18.22           # VLAN 22
export NETWORK_STORAGEMGMT_ADDRESS_PREFIX=172.18.23      # VLAN 23
export NETWORK_DESIGNATE_ADDRESS_PREFIX=172.18.25        # VLAN 25
export NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX=172.18.26    # VLAN 26

export CTLPLANE_METALLB_POOL=192.168.122.110-192.168.122.120
export DATAPLANE_COMPUTE_IP=192.168.122.101
export DATAPLANE_COMPUTE_0_IP=192.168.122.101
export DATAPLANE_COMPUTE_0_NAME=edpm-compute-1
```

**Note:** Instance 2 connects to a different EDPM node (`192.168.122.101`) with hostname `edpm-compute-1.example.com`.

## Adding More Instances

To add a third instance (RHOSO 3), create `config/rhoso3.env`:

```bash
export NAMESPACE=rhoso3

# RHOSO 3 uses 172.19.X.0/24 range where X = VLAN ID
export NETWORK_INTERNALAPI_ADDRESS_PREFIX=172.19.20      # VLAN 20
export NETWORK_STORAGE_ADDRESS_PREFIX=172.19.21          # VLAN 21
export NETWORK_TENANT_ADDRESS_PREFIX=172.19.22           # VLAN 22
export NETWORK_STORAGEMGMT_ADDRESS_PREFIX=172.19.23      # VLAN 23
export NETWORK_DESIGNATE_ADDRESS_PREFIX=172.19.25        # VLAN 25
export NETWORK_DESIGNATE_EXT_ADDRESS_PREFIX=172.19.26    # VLAN 26

export CTLPLANE_METALLB_POOL=192.168.122.130-192.168.122.140
export DATAPLANE_COMPUTE_IP=192.168.122.102
export DATAPLANE_COMPUTE_0_IP=192.168.122.102
export DATAPLANE_COMPUTE_0_NAME=edpm-compute-2
```

Then deploy: `source config/rhoso3.env && make instance`

## Configuration Requirements

### MUST be unique per instance:
- `NAMESPACE` - Kubernetes namespace
- `NETWORK_*_ADDRESS_PREFIX` - IP subnet prefixes
- `CTLPLANE_METALLB_POOL` - LoadBalancer IP ranges
- `DATAPLANE_COMPUTE_IP` - EDPM node IP address
- `DATAPLANE_COMPUTE_0_IP` - EDPM node IP address (same as above)
- `DATAPLANE_COMPUTE_0_NAME` - EDPM node short hostname (without .example.com)

### MUST be the same across instances:
- `NNCP_INTERFACE` - Physical interface (e.g., enp6s0)
- `NNCP_BRIDGE` - Bridge name (ospbr)
- `NETWORK_VLAN_START` - First VLAN ID (20)

## Network Configuration Reference

### VLAN Assignments

All instances use the same VLAN IDs but different IP subnets:

| Network | VLAN ID | Instance 1 Subnet | Instance 2 Subnet | Instance 3 Subnet |
|---------|---------|-------------------|-------------------|-------------------|
| InternalAPI | 20 | 172.17.20.0/24 | 172.18.20.0/24 | 172.19.20.0/24 |
| Storage | 21 | 172.17.21.0/24 | 172.18.21.0/24 | 172.19.21.0/24 |
| Tenant | 22 | 172.17.22.0/24 | 172.18.22.0/24 | 172.19.22.0/24 |
| StorageMgmt | 23 | 172.17.23.0/24 | 172.18.23.0/24 | 172.19.23.0/24 |
| Designate | 25 | 172.17.25.0/24 | 172.18.25.0/24 | 172.19.25.0/24 |
| DesignateExt | 26 | 172.17.26.0/24 | 172.18.26.0/24 | 172.19.26.0/24 |

### MetalLB IP Pool Allocation

Each instance requires unique MetalLB IP pools:

| Instance | Ctlplane Pool | InternalAPI Pool | Storage Pool | Tenant Pool |
|----------|---------------|------------------|--------------|-------------|
| Instance 1 | 192.168.122.80-90 | 172.17.20.80-90 | 172.17.21.80-90 | 172.17.22.80-90 |
| Instance 2 | 192.168.122.110-120 | 172.18.20.80-90 | 172.18.21.80-90 | 172.18.22.80-90 |
| Instance 3 | 192.168.122.130-140 | 172.19.20.80-90 | 172.19.21.80-90 | 172.19.22.80-90 |

**Important:** Ensure MetalLB pools do not overlap between instances.

### EDPM Compute Node Requirements

Each instance requires a dedicated EDPM compute node:

| Instance | Compute Node IP | Hostname | Short Name |
|----------|----------------|----------|------------|
| Instance 1 | 192.168.122.100 | edpm-compute-0.example.com | edpm-compute-0 |
| Instance 2 | 192.168.122.101 | edpm-compute-1.example.com | edpm-compute-1 |
| Instance 3 | 192.168.122.102 | edpm-compute-2.example.com | edpm-compute-2 |

## Common Configuration Variables

These variables are defined in the main Makefile and apply to all instances:

```bash
PASSWORD=12345678              # Default password for OpenStack services
TIMEOUT=90                     # Deployment timeout in minutes
NETWORK_MTU=1500              # Network MTU size
NNCP_INTERFACE=enp6s0         # Physical network interface
NNCP_BRIDGE=ospbr             # Bridge name for VLAN interfaces
NETWORK_VLAN_START=20         # Starting VLAN ID
```

## Advanced Configuration

### Customizing Control Plane Services

You can customize which OpenStack services are deployed by modifying the control plane configuration. See [IMPLEMENTATION_DETAILS.md](IMPLEMENTATION_DETAILS.md) for more information.

### Network Performance Tuning

For production deployments, consider:
- Adjusting `NETWORK_MTU` based on your infrastructure
- Using SR-IOV or DPDK for high-performance networking
- Configuring network QoS policies

### High Availability

For HA deployments:
- Deploy multiple controller nodes
- Configure Galera cluster replication
- Use shared storage for persistent volumes

See the [Red Hat RHOSO documentation](https://docs.redhat.com/en/documentation/red_hat_openstack_services_on_openshift) for detailed HA configuration.
