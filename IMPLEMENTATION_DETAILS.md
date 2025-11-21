# Implementation Details

This document provides detailed technical information about how multi-RHOSO deployment works internally.

## NNCP Behavior

**First RHOSO Instance (any namespace name):**
- `source config/rhoso1.env && make nncp` **GENERATES** NNCP from scratch
- Automatically detects this is the first instance by checking if NNCP resource exists
- Configures VLAN interfaces with primary IPs:
  - enp6s0.20: 172.17.0.5/24 (InternalAPI)
  - enp6s0.21: 172.18.0.5/24 (Storage)
  - enp6s0.22: 172.19.0.5/24 (Tenant)
  - enp6s0.23: 172.20.0.5/24 (StorageMgmt)

**Additional RHOSO Instances (any namespace name):**
- `source config/rhoso2.env && make nncp` **SKIPS** NNCP generation
- Automatically detects NNCP already exists
- **ONLY** adds secondary IPs via patching:
  - enp6s0.20: 172.27.0.5/24 (secondary)
  - enp6s0.21: 172.29.0.5/24 (secondary)
  - enp6s0.22: 172.31.0.5/24 (secondary)
  - enp6s0.23: 172.32.0.5/24 (secondary)

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

| Pool | Instance 1 | Instance 2 |
|------|-----------|-----------|
| Ctlplane | 192.168.122.80-90 | 192.168.122.110-120 |
| InternalAPI | 172.17.0.80-90 | 172.27.0.80-90 |
| Storage | 172.18.0.80-90 | 172.29.0.80-90 |
| Tenant | 172.19.0.80-90 | 172.31.0.80-90 |

Pools are **namespace-scoped** via `serviceAllocation.namespaces` to prevent IP conflicts.

## Network Isolation

Each instance has completely isolated networks:

**Instance 1:**
- InternalAPI: 172.17.0.0/24 (VLAN 20)
- Storage: 172.18.0.0/24 (VLAN 21)
- Tenant: 172.19.0.0/24 (VLAN 22)
- StorageMgmt: 172.20.0.0/24 (VLAN 23)

**Instance 2:**
- InternalAPI: 172.27.0.0/24 (VLAN 20)
- Storage: 172.29.0.0/24 (VLAN 21)
- Tenant: 172.31.0.0/24 (VLAN 22)
- StorageMgmt: 172.32.0.0/24 (VLAN 23)

Note: Same VLAN IDs, different subnets.
