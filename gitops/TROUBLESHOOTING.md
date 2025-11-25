# Multi-RHOSO Troubleshooting Guide

This guide covers common issues and their solutions when deploying RHOSO instances using GitOps.

## Table of Contents

- [Label Management and ArgoCD Drift](#label-management-and-argocd-drift)
  - [Kubernetes Labels in Multi-RHOSO](#kubernetes-labels-in-multi-rhoso)
  - [ArgoCD Drift Handling](#argocd-drift-handling)
  - [Kustomize Labels vs CommonLabels](#kustomize-labels-vs-commonlabels)
- [ArgoCD Issues](#argocd-issues)
  - [SharedResourceWarning](#sharedresourcewarning)
- [Post-Deployment Issues](#post-deployment-issues)
  - [Empty Hypervisor List After Deployment](#empty-hypervisor-list-after-deployment)
- [DataPlane Issues](#dataplane-issues)
  - [DataPlane Deployment Failures](#dataplane-deployment-failures)
- [Operator Issues](#operator-issues)
  - [Operator RBAC Permission Errors](#operator-rbac-permission-errors)
- [Control Plane Issues](#control-plane-issues)
  - [Control Plane Not Reaching Ready Status](#control-plane-not-reaching-ready-status)
- [Network Configuration Issues](#network-configuration-issues)
  - [NNCP Configuration](#nncp-configuration)

## Label Management and ArgoCD Drift

### Kubernetes Labels in Multi-RHOSO

This deployment uses a combination of standard Kubernetes labels and custom tracking labels:

**Standard Kubernetes Labels** (managed by operators):
- `app.kubernetes.io/name`: Component type (e.g., `openstackdataplaneservice`)
- `app.kubernetes.io/instance`: Resource instance identifier (e.g., `repo-setup`)
- `app.kubernetes.io/part-of`: Higher-level application (operators set to `openstack-operator`)
- `app.kubernetes.io/managed-by`: Management tool (set to `kustomize`)

**Custom Tracking Labels** (for GitOps organization):
- `deployment`: Multi-RHOSO deployment identifier (`multi-rhoso`)
- `instance`: RHOSO instance identifier (`rhoso1`, `rhoso2`)
- `layer`: Deployment layer (`nncp`, `network`, `controlplane`, `dataplane`)
- `managed-by`: Kustomize tracker (`kustomize`)

### ArgoCD Drift Handling

**OpenStackDataPlaneService Resources** are managed by operators that enforce their own label values. ArgoCD Applications include `ignoreDifferences` to prevent false drift detection:

```yaml
ignoreDifferences:
  - group: dataplane.openstack.org
    kind: OpenStackDataPlaneService
    jsonPointers:
      - /metadata/labels/app.kubernetes.io~1part-of    # Operator sets to openstack-operator
      - /metadata/labels/app.kubernetes.io~1instance   # Operator sets to repo-setup
```

**Why this is needed:**
1. Kustomize applies: `app.kubernetes.io/part-of: openstack` (via commonLabels)
2. Operator reconciles and changes to: `app.kubernetes.io/part-of: openstack-operator`
3. Without `ignoreDifferences`, ArgoCD detects continuous drift
4. With `ignoreDifferences`, ArgoCD ignores operator-managed label changes

**Other resources** (NodeSet, Deployment, Secrets) keep the labels from kustomize because operators don't modify them.

### Kustomize Labels vs CommonLabels

The overlays use both `labels` and `commonLabels`:

```yaml
# Custom tracking labels (added without overwriting)
labels:
  - pairs:
      deployment: multi-rhoso
      instance: rhoso1
      layer: dataplane
      managed-by: kustomize

# Standard Kubernetes labels (applied to all resources)
commonLabels:
  app.kubernetes.io/part-of: openstack
  app.kubernetes.io/managed-by: kustomize
```

**Difference:**
- `labels`: Adds labels without overwriting existing ones
- `commonLabels`: Overwrites labels with the same key

## ArgoCD Issues

### SharedResourceWarning

**Symptom**: Warning that a resource is tracked by multiple ArgoCD Applications:
```
SharedResourceWarning: OpenStackDataPlaneService/repo-setup is part of applications rhoso1-dataplane and repo-setup
```

**Root Cause**: The `app.kubernetes.io/instance` label creates phantom Application tracking

**Solution**: Already fixed in base files - `app.kubernetes.io/instance` label is managed by operators, and `ignoreDifferences` prevents drift warnings

## Post-Deployment Issues

### Empty Hypervisor List After Deployment

**Symptom**: `openstack hypervisor list` returns empty even though:
- `openstack compute service list` shows compute service as `enabled | up`
- `openstack resource provider list` shows the compute node UUID
- Nova compute logs show successful resource reporting

**Root Cause**: Compute host not mapped to Nova cell

**Solution**: Run host discovery (see [Post-Deployment Tasks](README.md#post-deployment-tasks))

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

## DataPlane Issues

### DataPlane Deployment Failures

**Missing Secrets**:
- Ensure `libvirt-secret` and `nova-migration-ssh-key` exist in dataplane overlay resources
- Check `osp-secret` contains all required passwords (especially telemetry: `AodhPassword`, `CeilometerPassword`, `CloudKittyPassword`)

**Missing OpenStackDataPlaneService**:
- Verify `repo-setup-service.yaml` exists in dataplane overlay resources
- Confirm service is namespace-scoped (kustomize adds namespace automatically)

**RabbitMQ Connectivity Issues**:
- Check EDPM node can resolve service names: `nslookup rabbitmq-cell1.rhoso1.svc` from EDPM node
- Verify DNS configuration on EDPM nodes: `cat /etc/resolv.conf`
- Test RabbitMQ port connectivity: `nc -zv rabbitmq-cell1.rhoso1.svc 5671`
- RabbitMQ uses port **5671** (TLS), not 5672
- Restart nova_compute service if needed: `sudo systemctl restart edpm_nova_compute`

## Operator Issues

### Operator RBAC Permission Errors

**Symptom**: Operators fail to create ServiceAccounts with errors like:
```
ServiceAccount error: cannot set an ownerRef on a resource you can't delete:
RBAC: clusterrole.rbac.authorization.k8s.io "nova-operator-proxy-role" not found
```

**Root Cause**: OpenStack operators need permissions to:
1. Create ServiceAccounts with ownerReferences (requires delete permission)
2. Create standard kube-rbac-proxy ClusterRoles

**Solution**: Apply RBAC fixes for affected operators (requires cluster-admin):

```bash
# Nova operator RBAC fix
cat <<EOF | oc apply -f -
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: nova-operator-serviceaccount-manager
rules:
- apiGroups: [""]
  resources: [serviceaccounts]
  verbs: [create, delete, get, list, patch, update, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: nova-operator-serviceaccount-manager-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: nova-operator-serviceaccount-manager
subjects:
- kind: ServiceAccount
  name: nova-operator-controller-manager
  namespace: openstack-operators
EOF

# MariaDB operator RBAC fix (for Galera clusters)
cat <<EOF | oc apply -f -
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: mariadb-operator-serviceaccount-manager
rules:
- apiGroups: [""]
  resources: [serviceaccounts]
  verbs: [create, delete, get, list, patch, update, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: mariadb-operator-serviceaccount-manager-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: mariadb-operator-serviceaccount-manager
subjects:
- kind: ServiceAccount
  name: mariadb-operator-controller-manager
  namespace: openstack-operators
EOF
```

**Note**: These RBAC resources are operator-level permissions and should not be added to GitOps configuration. They should be part of the operator installation/upgrade process.

## Control Plane Issues

### Control Plane Not Reaching Ready Status

**Telemetry Issues**:
- If telemetry is enabled, ensure CloudKitty and logging configurations are complete
- Check for missing MetalLB LoadBalancer annotations on internal services

**Database Issues**:
- Verify MariaDB/Galera pods are running: `oc get pods -n rhoso1 | grep galera`
- Check database secrets exist and are correct

## Network Configuration Issues

### NNCP Configuration

**Secondary IP Addition**:
- NNCP for first instance creates VLAN interfaces with primary IPs
- Subsequent instances add secondary IPs to existing VLAN interfaces
- Verify with: `oc get nncp -o yaml | grep -A 10 "ipv4:"`

## Additional Resources

For more information, see:
- [Main README](README.md) - Overview and deployment instructions
- [ArgoCD Apps README](argocd-apps/README.md) - ArgoCD Application configuration
- [Post-Deployment Tasks](README.md#post-deployment-tasks) - Required steps after deployment
