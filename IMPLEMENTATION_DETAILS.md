# Implementation Details

This document provides detailed technical information about how multi-RHOSO deployment works internally.

## NNCP Behavior

**First RHOSO Instance (any namespace name):**
- `source config/rhoso1.env && make nncp` **GENERATES** NNCP from scratch
- Automatically detects this is the first instance by checking if NNCP resource exists
- Configures VLAN interfaces with primary IPs (following 172.17.X pattern where X = VLAN ID):
  - enp6s0.20: 172.17.20.5/24 (InternalAPI - VLAN 20)
  - enp6s0.21: 172.17.21.5/24 (Storage - VLAN 21)
  - enp6s0.22: 172.17.22.5/24 (Tenant - VLAN 22)
  - enp6s0.23: 172.17.23.5/24 (StorageMgmt - VLAN 23)
  - enp6s0.25: 172.17.25.5/24 (Designate - VLAN 25)
  - enp6s0.26: 172.17.26.5/24 (DesignateExt - VLAN 26)

**Additional RHOSO Instances (any namespace name):**
- `source config/rhoso2.env && make nncp` **SKIPS** NNCP generation
- Automatically detects NNCP already exists
- **ONLY** adds secondary IPs via patching (following 172.18.X pattern where X = VLAN ID):
  - enp6s0.20: 172.18.20.5/24 (InternalAPI - secondary)
  - enp6s0.21: 172.18.21.5/24 (Storage - secondary)
  - enp6s0.22: 172.18.22.5/24 (Tenant - secondary)
  - enp6s0.23: 172.18.23.5/24 (StorageMgmt - secondary)
  - enp6s0.25: 172.18.25.5/24 (Designate - secondary)
  - enp6s0.26: 172.18.26.5/24 (DesignateExt - secondary)

**Why?** The NNCP is a **shared cluster resource**. Regenerating it would delete previous instance IPs.

**How the detection works:**
1. Wrapper Makefile checks if NNCP exists: `oc get nncp`
2. **If NNCP exists (additional instance):**
   - Runs local script: `scripts/add-nncp-secondary-ips.sh`
   - Adds secondary IPs for the new `NAMESPACE` network subnets
3. **If NNCP doesn't exist (first instance):**
   - Calls upstream install_yamls to generate NNCP with primary IPs
   - Uses vanilla upstream without modifications

This allows ANY namespace name to work correctly - the first instance will always generate NNCP, and additional instances will only add secondary IPs using our local script.

## MetalLB Configuration

Each instance uses **separate IP pools**:

| Pool | Instance 1 (172.17.X) | Instance 2 (172.18.X) |
|------|-----------|-----------|
| Ctlplane | 192.168.122.80-90 | 192.168.122.110-120 |
| InternalAPI | 172.17.20.80-90 | 172.18.20.80-90 |
| Storage | 172.17.21.80-90 | 172.18.21.80-90 |
| Tenant | 172.17.22.80-90 | 172.18.22.80-90 |
| StorageMgmt | 172.17.23.80-90 | 172.18.23.80-90 |
| Designate | 172.17.25.80-90 | 172.18.25.80-90 |
| DesignateExt | 172.17.26.80-90 | 172.18.26.80-90 |

Pools are **namespace-scoped** via `serviceAllocation.namespaces` to prevent IP conflicts.

**Addressing Pattern**: `172.[16+N].[VLAN].X` where N = instance number, VLAN = VLAN ID, X = host address

## Network Isolation

Each instance has completely isolated networks following the `172.[16+N].[VLAN].0/24` pattern:

**Instance 1 (172.17.X range):**
- InternalAPI: 172.17.20.0/24 (VLAN 20)
- Storage: 172.17.21.0/24 (VLAN 21)
- Tenant: 172.17.22.0/24 (VLAN 22)
- StorageMgmt: 172.17.23.0/24 (VLAN 23)
- Designate: 172.17.25.0/24 (VLAN 25)
- DesignateExt: 172.17.26.0/24 (VLAN 26)

**Instance 2 (172.18.X range):**
- InternalAPI: 172.18.20.0/24 (VLAN 20)
- Storage: 172.18.21.0/24 (VLAN 21)
- Tenant: 172.18.22.0/24 (VLAN 22)
- StorageMgmt: 172.18.23.0/24 (VLAN 23)
- Designate: 172.18.25.0/24 (VLAN 25)
- DesignateExt: 172.18.26.0/24 (VLAN 26)

**Key Points:**
- Same VLAN IDs across instances, different subnets
- Third octet matches VLAN ID for easy identification
- Second octet increments per instance (17, 18, 19, etc.)
- Starts at 172.17 to avoid conflicts with 172.16.0.0/16 applications
